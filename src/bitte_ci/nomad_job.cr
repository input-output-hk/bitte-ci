module BitteCI
  class NomadJob
    struct Config
      getter nomad_datacenters, nomad_base_url, nomad_ssl_ca, nomad_ssl_cert,
        nomad_ssl_key, runner_flake, loki_base_url, nomad_token, postgres_url,
        public_url, artifact_secret, github_user, github_token

      def initialize(
        @nomad_datacenters : Array(String),
        @nomad_base_url : URI,
        @nomad_ssl_ca : String?,
        @nomad_ssl_key : String?,
        @nomad_ssl_cert : String?,
        @runner_flake : URI,
        @loki_base_url : URI,
        @nomad_token : String,
        @postgres_url : URI,
        @public_url : URI,
        @artifact_secret : String,
        @github_user : String,
        @github_token : String
      )
      end
    end

    def initialize(
      @pr : GithubHook::PullRequest,
      @raw : String,
      @job_config : JobConfig,
      @config : NomadJob::Config,
      @groups : Array(Array(String))
    )
      @loki_id = UUID.random
    end

    def queue!
      post = post_job!

      Log.debug &.emit("NomadJob#queue!", post: post.inspect)

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

      nomad_url = @config.nomad_base_url.dup
      nomad_url.path = "/v1/jobs"

      # json = rendered.to_json
      # Process.run("iogo",
      #   args: ["json2hcl"],
      #   input: IO::Memory.new(json),
      #   output: STDOUT,
      #   error: STDERR
      # )

      res = HTTP::Client.post(
        nomad_url,
        tls: (ssl_context if nomad_url.scheme == "https"),
        body: rendered.to_json,
        headers: headers,
      )

      case res.status
      when HTTP::Status::OK
        NomadJobPost.from_json(res.body)
      else
        raise "HTTP Error while trying to POST nomad job to #{nomad_url} : #{res.status.to_i} #{res.status_message}"
      end
    end

    def ssl_context
      OpenSSL::SSL::Context::Client.from_hash({
        "ca"   => @config.nomad_ssl_ca,
        "cert" => @config.nomad_ssl_cert,
        "key"  => @config.nomad_ssl_key,
      })
    end

    def headers
      HTTP::Headers{
        "X-Nomad-Token" => [@config.nomad_token],
      }
    end

    def rendered
      {Job: job}
    end

    def job_id
      UUID.random
    end

    def job_name
      "#{@pr.base.repo.full_name}##{@pr.number}-#{@pr.head.sha}"
    end

    def task_group_name
      job_name
    end

    def job
      {
        Namespace:   nil,
        ID:          job_id,
        Name:        job_name,
        Type:        "batch",
        Priority:    40,
        Datacenters: @config.nomad_datacenters,
        TaskGroups:  task_groups,
        Meta:        {
          pull_request_id: @pr.id.to_s,
        },
      }
    end

    def task_groups
      @groups.map do |group|
        {
          Name:                      (group - ["prepare"]).join(" "),
          Count:                     1,
          Tasks:                     tasks(group),
          StopAfterClientDisconnect: Minute * 10,
          Networks:                  [{Mode: "host"}],

          ReschedulePolicy: {
            Attempts:      3,
            DelayFunction: "exponential",
            Delay:         Second * 10,
            Interval:      Minute * 1,
            MaxDelay:      Minute * 10,
            Unlimited:     false,
          },
          Restart: {
            Attempts: 1,
            Mode:     "fail",
          },
          EphemeralDisk: {
            SizeMB:  2 * 1024,
            Migrate: false,
            Sticky:  false,
          },
        }
      end
    end

    def tasks(group)
      group.map do |name|
        step_config = @job_config.ci.steps[name]
        Task.new(@pr, name, step_config, @config, @loki_id)
      end
    end

    class Task
      def initialize(
        @pr : GithubHook::PullRequest,
        @name : String,
        @config : JobConfig::Step,
        @job_config : Config,
        @loki_id : UUID
      )
      end

      # combine the required dependencies for the runner.sh with
      def dependencies
        deps = %w[bash cacert command].map { |a| "#{@job_config.runner_flake}##{a}" }
        original = @config.flakes.flat_map { |k, vs| vs.map { |v| "#{k}##{v}" } }
        (deps + original).uniq
      end

      def definition
        command = [@config.command].flatten
        args = command.size > 1 ? command[1..-1] : [] of String

        obfuscate = [@job_config.github_token]

        {
          Name:   @name,
          Driver: "exec",

          Config: {
            flake_deps: dependencies,
            command:    "/bin/bitte-ci-command",
            args:       [
              "--name", @name,
              "--command", command[0],
              "--args", args.to_json,
              "--obfuscate", obfuscate.to_json,
              "--loki-base-url", @job_config.loki_base_url.to_s,
              "--public-url", @job_config.public_url.to_s,
              "--after", @config.after.to_json,
              "--outputs", @config.outputs.to_json,
              "--bitte-ci-id", @loki_id,
              "--artifact-secret", @job_config.artifact_secret,
            ],
          },

          Env: {
            "PATH"          => "/bin",
            "SSL_CERT_FILE" => "/current-alloc/etc/ssl/certs/ca-bundle.crt",
            "SHA"           => @pr.head.sha,
            "CLONE_URL"     => @pr.head.repo.clone_url,
            "PR_NUMBER"     => @pr.number.to_s,
            "LABEL"         => @pr.head.label,
            "REF"           => @pr.head.ref,
            "FULL_NAME"     => @pr.base.repo.full_name,
            "GITHUB_USER"   => @job_config.github_user,
            "GITHUB_TOKEN"  => @job_config.github_token,
            # "GIT_TRACE"        => "2",
            # "GIT_CURL_VERBOSE" => "2",
          }.merge(@config.env),

          ShutdownDelay: 0,
          KillSignal:    "SIGTERM",

          Resources: {
            CPU:      @config.cpu,
            MemoryMB: @config.memory,
          },

          RestartPolicy: {
            Interval: Second * 60,
            Attempts: 5,
            Delay:    Second * 60,
            Mode:     "delay",
          },

          Templates: [
            {
              DestPath:     "local/pr.json",
              EmbeddedTmpl: @pr.to_json,
            },
          ],

          Vault: if @config.vault
            {
              ChangeMode: "noop",
              Env:        true,
              Policies:   ["nomad-cluster"],
            }
          end,

          Lifecycle: {Hook: @config.lifecycle},
          Sidecar:   @config.sidecar,
        }
      end

      def to_json(b)
        definition.to_json(b)
      end
    end
  end
end
