require "json"
require "http/client"
require "./uuid"
require "./job_config"

Second = 1_000_000_000u64
Minute = Second * 60

module BitteCI
  class Runner
    @ci_cue : String
    @job_config : JobConfig
    @raw : String

    def self.run(input : IO | String, config : Config)
      raw = case input
            in IO
              input.gets_to_end
            in String
              input
            end
      Log.info { "received PR" }
      Log.info { raw }
      hook = GithubHook.from_json(raw)
      new(hook.pull_request, raw, config).run
    end

    def initialize(@pr : GithubHook::PullRequest, @raw : String, @config : Config)
      @ci_cue = fetch_ci_cue
      @job_config = export_job_config
    end

    def run
      @job_config.ci.steps.each do |step|
        Log.info &.emit("Queue Job", step: step.to_json)
        NomadJob.new(pr: @pr, raw: @raw, job_config: @job_config, config: @config, step: step).queue!
      end
    end

    def export_job_config
      pr_tmp_json = File.tempname("pr", ".json")
      pr_tmp_cue = File.tempname("pr", ".cue")
      pr_tmp_schema = File.tempname("schema", ".cue")
      pr_tmp_ci = File.tempname("ci", ".cue")

      File.write(pr_tmp_json, @raw)
      File.write(pr_tmp_schema, {{ read_file "cue/schema.cue" }}) # this is read at compile time
      File.write(pr_tmp_ci, @ci_cue)

      pr_cue_mem = IO::Memory.new
      status = Process.run("cue", output: STDOUT, error: STDERR,
        args: ["import", "json", "-p", "ci", "-o", pr_tmp_cue, pr_tmp_json])
      raise "Failed to import JSON to CUE. Exited with: #{status.exit_status}" unless status.success?

      mem = IO::Memory.new
      status = Process.run("cue", output: mem, error: STDERR,
        args: ["export", pr_tmp_schema, pr_tmp_cue, pr_tmp_ci])
      raise "Failed to export CUE to JSON. Exited with: #{status.exit_status}" unless status.success?

      Log.info { "Exported CUE" }

      JobConfig.from_json(mem.to_s)
    ensure
      [pr_tmp_cue, pr_tmp_json, pr_tmp_schema, pr_tmp_ci].each do |file|
        File.delete file if file && File.file?(file)
      end
    end

    def fetch_ci_cue
      full_name = @pr.base.repo.full_name
      sha = @pr.base.sha
      ci_cue_url = @config.github_user_content_base_url.dup
      ci_cue_url.path = "/#{full_name}/#{sha}/ci.cue"

      res = HTTP::Client.get(ci_cue_url)

      case res.status
      when HTTP::Status::OK
        res.body
      else
        raise "HTTP Error while trying to GET ci.cue from #{ci_cue_url} : #{res.status.to_i} #{res.status_message}"
      end
    end
  end

  class GithubHook
    include JSON::Serializable

    property pull_request : PullRequest

    class PullRequest
      include JSON::Serializable

      property id : UInt64
      property number : UInt64
      property base : Base
      property head : Base
      property statuses_url : String
    end

    class Base
      include JSON::Serializable

      property repo : Repo
      property sha : String
      property label : String
      property ref : String
    end

    class Repo
      include JSON::Serializable

      property full_name : String
      property clone_url : String
    end
  end

  class NomadJobPost
    include JSON::Serializable

    @[JSON::Field(key: "EvalCreateIndex")]
    property eval_create_index : UInt64

    @[JSON::Field(key: "EvalID")]
    property eval_id : UUID

    @[JSON::Field(key: "Index")]
    property index : UInt64

    @[JSON::Field(key: "JobModifyIndex")]
    property job_modify_index : UInt64

    @[JSON::Field(key: "KnownLeader")]
    property known_leader : Bool

    @[JSON::Field(key: "LastContact")]
    property last_contact : UInt64

    @[JSON::Field(key: "Warnings")]
    property warnings : String
  end

  class NomadJob
    def initialize(@pr : GithubHook::PullRequest, @raw : String, @job_config : JobConfig, @config : Config, @step : JobConfig::Step)
      @loki_id = UUID.random
    end

    def queue!
      post = post_job!

      pp! post

      DB.open(@config.postgres_url) do |db|
        db.transaction do
          db.exec <<-SQL, @pr.id, @raw
            INSERT INTO pull_requests (id, data) VALUES ($1, $2)
            ON CONFLICT (id) DO UPDATE SET data = $2;
          SQL

          db.exec "SELECT pg_notify($1, $2)", "pull_requests", @pr.id

          db.exec <<-SQL, post.eval_id, @pr.id, @loki_id, Time.utc, "pending"
            INSERT INTO builds
            (id, pr_id, loki_id, created_at, build_status)
            VALUES
            ($1, $2, $3, $4, $5);
          SQL

          db.exec "SELECT pg_notify($1, $2)", "builds", post.eval_id
        end
      end
    end

    def post_job!
      Log.info { "Submitting job to Nomad" }
      rendered = {Job: job}

      nomad_url = @config.nomad_base_url.dup
      nomad_url.path = "/v1/jobs"

      res = HTTP::Client.post(
        nomad_url,
        body: rendered.to_json,
        headers: HTTP::Headers{
          "X-Nomad-Token" => [@config.nomad_token],
        }
      )

      case res.status
      when HTTP::Status::OK
        NomadJobPost.from_json(res.body)
      else
        raise "HTTP Error while trying to POST nomad job to #{nomad_url} : #{res.status.to_i} #{res.status_message}"
      end
    end

    def group_name
      "#{@pr.base.repo.full_name}##{@pr.number}:#{@pr.head.sha}"
    end

    def job
      {
        Namespace:   nil,
        ID:          "bitte-ci",
        Name:        "bitte-ci",
        Type:        "batch",
        Priority:    @step.priority,
        Datacenters: @step.datacenters,
        TaskGroups:  [
          {
            Name:  group_name,
            Count: 1,
            Env:   {
              "PATH"          => "/bin",
              "SSL_CERT_FILE" => "/etc/ssl/certs/ca-bundle.crt",
              "SHA"           => @pr.head.sha,
              "CLONE_URL"     => @pr.head.repo.clone_url,
              "LABEL"         => @pr.head.label,
              "REF"           => @pr.head.ref,
              "FULL_NAME"     => @pr.base.repo.full_name,
            },
            Tasks: [
              runner, promtail,
            ],
            ReschedulePolicy: {
              Attempts:      3,
              DelayFunction: "exponential",
              Delay:         Second * 10,
              Interval:      Minute * 1,
              MaxDelay:      Minute * 10,
              Unlimited:     false,
            },
            EphemeralDisk: {
              SizeMB:  1024,
              Migrate: true,
              Sticky:  true,
            },
            Networks: [{Mode: "host"}],
          },
        ],
      }
    end

    def runner
      {
        Name:   "runner",
        Driver: "exec",
        Config: {
          flake:   @step.flake,
          command: "/bin/bash",
          args:    ["/local/runner.sh"] + [@step.command].flatten,
        },
        Env: {
          "PATH" => "/bin",
        },
        KillSignal: "SIGINT",
        Resources:  {
          CPU:      @step.cpu,
          MemoryMB: @step.memory,
        },
        RestartPolicy: {
          Interval: Second * 60,
          Attempts: 5,
          Delay:    Second * 60,
          Mode:     "delay",
        },
        ShutdownDelay: 0,
        Leader:        true,
        Templates:     [
          {
            DestPath:     "local/runner.sh",
            EmbeddedTmpl: runner_template,
          },
          {
            DestPath:     "local/pr.json",
            EmbeddedTmpl: @pr.to_json,
          },
        ],
        Vault: if @step.vault
          {
            ChangeMode: "noop",
            Env:        true,
            Policies:   ["nomad-cluster"],
          }
        end,
      }
    end

    def promtail
      {
        Name:   "promtail",
        Driver: "exec",
        Config: {
          flake:   @config.promtail_flake,
          command: "/bin/promtail",
          args:    ["-config.file", "local/config.yaml"],
        },
        KillSignal: "SIGINT",
        Resources:  {
          CPU:      100,
          MemoryMB: 100,
        },
        ShutdownDelay: Second * 10,
        Leader:        false,
        Templates:     [
          {
            DestPath:     "local/config.yaml",
            EmbeddedTmpl: promtail_config,
          },
        ],
      }
    end

    def runner_template
      <<-RUNNER
      set -exuo pipefail

      dir="/local/$FULL_NAME"

      if [ ! -d "$dir" ]; then
        mkdir -p "$(dirname "$dir")"

        git clone "$CLONE_URL" "$dir"
        git -C "$dir" checkout "$SHA"
      fi

      cd "$dir"

      exec "$@"
      RUNNER
    end

    def promtail_config
      <<-PROMTAIL
      server:
        http_listen_port: 0
        grpc_listen_port: 0
      positions:
        filename: /local/positions.yaml
      client:
        url: http://127.0.0.1:3100/loki/api/v1/push
      scrape_configs:
      - job_name: '#{@loki_id}'
        pipeline_stages: null
        static_configs:
        - labels:
            nomad_alloc_id: '{{ env "NOMAD_ALLOC_ID" }}'
            nomad_alloc_index: '{{ env "NOMAD_ALLOC_INDEX" }}'
            nomad_alloc_name: '{{ env "NOMAD_ALLOC_NAME" }}'
            nomad_dc: '{{ env "NOMAD_DC" }}'
            nomad_group_name: '{{ env "NOMAD_GROUP_NAME" }}'
            nomad_job_id: '{{ env "NOMAD_JOB_ID" }}'
            nomad_job_name: '{{ env "NOMAD_JOB_NAME" }}'
            nomad_job_parent_id: '{{ env "NOMAD_JOB_PARENT_ID" }}'
            nomad_namespace: '{{ env "NOMAD_NAMESPACE" }}'
            nomad_region: '{{ env "NOMAD_REGION" }}'
            bitte_ci_id: '#{@loki_id}'
            __path__: /alloc/logs/*.std*.[0-9]*
      PROMTAIL
    end
  end
end
