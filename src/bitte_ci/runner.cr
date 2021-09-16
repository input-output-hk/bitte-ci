require "json"
require "yaml"
require "http/client"
require "pg"
require "./uuid"
require "./job_config"
require "./simple_config"
require "./github_hook"
require "./nomad_job"
require "./graph"
require "./model"

Second = 1_000_000_000u64
Minute = Second * 60

module BitteCI
  class Runner
    struct Config
      include SimpleConfig::Configuration

      def self.help
        "queue the PR piped into stdin or passed as argument"
      end

      def self.command
        "queue"
      end

      @[Option(help: "Base URL e.g. https://raw.githubusercontent.com")]
      property github_user_content_base_url : URI = URI.parse("https://raw.githubusercontent.com")

      @[Option(help: "The user for setting Github status")]
      property github_user : String

      @[Option(secret: true, help: "The token for setting Github status")]
      property github_token : String

      @[Option(help: "Base URL e.g. http://127.0.0.1:4646")]
      property nomad_base_url = URI.parse("http://127.0.0.1:4646")

      @[Option(help: "Nomad datacenters to run the jobs in (comma separated)")]
      property nomad_datacenters : Array(String)

      @[Option(help: "CA cert used for talking with Nomad when using HTTPS")]
      property nomad_ssl_ca : String?

      @[Option(help: "Key used for talking with Nomad when using HTTPS")]
      property nomad_ssl_key : String?

      @[Option(help: "Cert used for talking with Nomad when using HTTPS")]
      property nomad_ssl_cert : String?

      @[Option(help: "Build runner dependencies from this flake")]
      property runner_flake : URI = URI.parse("github:input-output-hk/bitte-ci")

      @[Option(help: "Base URL e.g. http://127.0.0.1:3100")]
      property loki_base_url = URI.parse("http://127.0.0.1:4646")

      @[Option(secret: true, help: "Nomad token used for job submission")]
      property nomad_token : String

      @[Option(secret: true, help: "PostgreSQL URL e.g. postgres://postgres@127.0.0.1:54321/bitte_ci")]
      property postgres_url : URI

      @[Option(help: "Specify a ci.cue file to use instad of fetching it from the base repo head")]
      property ci_cue : String?

      @[Option(help: "URL to reach the bitte-ci server for output uploads")]
      property public_url : URI

      @[Option(secret: true, help: "HMAC secret used for verifying output uploads")]
      property artifact_secret : String

      def for_nomad_job
        NomadJob::Config.new(
          nomad_datacenters: nomad_datacenters.dup,
          nomad_base_url: nomad_base_url.dup,
          nomad_ssl_ca: nomad_ssl_ca,
          nomad_ssl_cert: nomad_ssl_cert,
          nomad_ssl_key: nomad_ssl_key,
          runner_flake: runner_flake,
          loki_base_url: loki_base_url,
          nomad_token: nomad_token,
          postgres_url: postgres_url,
          public_url: public_url,
          artifact_secret: artifact_secret,
          github_user: github_user,
          github_token: github_token,
        )
      end

      def run(log)
        arg = ARGV[0]? ? File.read(ARGV[0]) : STDIN
        Runner.run(log, self, arg)
      end
    end

    property log : Log
    property ci_cue : String
    property job_config : JobConfig
    property raw : String

    def self.run(log : Log, config : Config, input : IO | String)
      raw = case input
            in IO
              input.gets_to_end
            in String
              input
            end
      log.info { "received PR" }
      log.info { raw }
      hook = GithubHook.from_json(raw)
      new(log, hook.pull_request, raw, config).run
    end

    def initialize(@log : Log, @pr : GithubHook::PullRequest, @raw : String, @config : Config)
      @ci_cue = fetch_ci_cue
      @job_config = export_job_config
    end

    def run
      Clear::SQL.init(@config.postgres_url.to_s)

      @log.info &.emit("Generating Job", step: @job_config.to_json)

      DB.open(@config.postgres_url.to_s) do |db|
        db.transaction do
          db.exec <<-SQL, @pr.id, @pr.to_json
            INSERT INTO pull_requests (id, data) VALUES ($1, $2)
            ON CONFLICT (id) DO UPDATE SET data = $2;
          SQL

          # This for some reason ignores the where clause
          # ::PullRequest.query
          #   .where { var("id") == @pr.id }
          #   .find_or_create(id: @pr.id, data: @pr.to_json)
        end
      end

      @job_config.ci.steps.each do |_key, step|
        step.after = ["prepare"] if step.after.empty?
      end

      @job_config.ci.steps["prepare"] = JobConfig::Step.new(
        label: "Git checkout to /alloc/repo",
        flakes: {@config.runner_flake.to_s => ["prepare-static"]},
        command: ["bitte-ci-prepare"],
        enable: true,
        vault: false,
        cpu: 3000u32,
        memory: 3u32 * 1024,
        lifecycle: "prestart",
        sidecar: false,
      )

      groups = calculate_graph
      run_graph(groups)
    end

    def calculate_graph
      graph = Graph::Directed.new

      vertices = {} of String => Graph::Node

      @job_config.ci.steps.each do |key, _step|
        vertices[key] = graph.add_vertex(key)
      end

      @job_config.ci.steps.each do |key, step|
        step.after.each do |after|
          graph.add_edge(vertices[after], vertices[key], 1)
        end
      end

      dijkstras = Graph::Dijkstras.new(graph, vertices["prepare"])

      @job_config.ci.steps.compact_map { |key, _step|
        next if key == "prepare"
        dijkstras.shortest_path(vertices["prepare"], vertices[key])
      }
    end

    def run_graph(groups)
      if @job_config.ci.enabled_steps.size <= 1
        @log.info &.emit("Skip Job because steps are empty")
        return
      else
        @log.info &.emit("Queue Job", step: @job_config.to_json)
      end

      NomadJob.new(
        pr: @pr,
        raw: @raw,
        job_config: @job_config,
        config: @config.for_nomad_job,
        groups: groups,
      ).queue!
    end

    def export_job_config
      pr_tmp_json = File.tempname("pr", ".json")
      pr_tmp_cue = File.tempname("pr", ".cue")
      pr_tmp_schema = File.tempname("schema", ".cue")
      pr_tmp_ci = File.tempname("ci", ".cue")

      File.write(pr_tmp_json, @raw)
      File.write(pr_tmp_schema, {{ read_file "cue/schema.cue" }}) # this is read at compile time
      File.write(pr_tmp_ci, @ci_cue)

      status = Process.run("cue", output: STDOUT, error: STDERR,
        args: ["import", "json", "-p", "ci", "-o", pr_tmp_cue, pr_tmp_json])
      raise "Failed to import JSON to CUE. Exited with: #{status.exit_status}" unless status.success?

      mem = IO::Memory.new
      status = Process.run("cue", output: mem, error: STDERR,
        args: ["export", pr_tmp_schema, pr_tmp_cue, pr_tmp_ci])
      raise "Failed to export CUE to JSON. Exited with: #{status.exit_status}" unless status.success?

      @log.info { "Exported CUE" }

      JobConfig.from_json(mem.to_s)
    ensure
      [pr_tmp_cue, pr_tmp_json, pr_tmp_schema, pr_tmp_ci].each do |file|
        File.delete file if file && File.file?(file)
      end
    end

    def fetch_ci_cue
      if config_ci_cue = @config.ci_cue
        return File.read(config_ci_cue)
      end

      full_name = @pr.base.repo.full_name
      sha = @pr.base.sha
      content_url = @config.github_user_content_base_url.dup
      path = "/#{full_name}/#{sha}/ci.cue"

      client = HTTP::Client.new(content_url)
      client.basic_auth @config.github_user, @config.github_token

      res = client.get(path)

      case res.status
      when HTTP::Status::OK
        res.body
      else
        raise "HTTP Error while trying to GET ci.cue from #{content_url}#{path} : #{res.status.to_i} #{res.status_message}"
      end
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
end
