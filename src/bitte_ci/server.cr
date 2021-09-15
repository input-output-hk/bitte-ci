require "clear"
require "kemal"
require "markd"

require "./artificer"
require "./connection"
require "./loki"
require "./model"
require "./runner"
require "./simple_config"
require "./trigger"
require "./uuid"

module BitteCI
  class Server
    struct Config
      include SimpleConfig::Configuration

      def self.help
        "Start the webserver"
      end

      def self.command
        "serve"
      end

      @[Option(help: "Port to bind to")]
      property port : Int32 = 9494

      @[Option(help: "Host to bind to")]
      property host : String = "127.0.0.1"

      @[Option(help: "The user for setting Github status")]
      property github_user : String

      @[Option(secret: true, help: "The token for setting Github status")]
      property github_token : String

      @[Option(help: "Base URL under which this server is reachable e.g. http://example.com")]
      property public_url : URI

      @[Option(help: "Base URL e.g. http://127.0.0.1:3100")]
      property loki_base_url = URI.parse("http://127.0.0.1:4646")

      @[Option(secret: true, help: "The secret set in your GitHub webhook")]
      property github_hook_secret : String

      @[Option(help: "Base URL e.g. https://raw.githubusercontent.com")]
      property github_user_content_base_url : URI

      @[Option(secret: true, help: "PostgreSQL URL e.g. postgres://postgres@127.0.0.1:54321/bitte_ci")]
      property postgres_url : URI

      @[Option(help: "Base URL e.g. http://127.0.0.1:4646")]
      property nomad_base_url = URI.parse("http://127.0.0.1:4646")

      @[Option(help: "CA cert used for talking with Nomad when using HTTPS")]
      property nomad_ssl_ca : String?

      @[Option(help: "Key used for talking with Nomad when using HTTPS")]
      property nomad_ssl_key : String?

      @[Option(help: "Cert used for talking with Nomad when using HTTPS")]
      property nomad_ssl_cert : String?

      @[Option(help: "Nomad datacenters to run the jobs in (comma separated)")]
      property nomad_datacenters : Array(String)

      @[Option(secret: true, help: "Nomad token used for job submission")]
      property nomad_token : String

      @[Option(secret: true, help: "HMAC secret used for verifying output uploads")]
      property artifact_secret : String

      @[Option(help: "Directory used for storign output uploads (will be created if it doesn't exist)")]
      property artifact_dir : String

      @[Option(help: "Build runner dependencies from this flake")]
      property runner_flake = URI.parse("github:input-output-hk/bitte-ci")

      @[Option(help: "Specify a ci.cue file to use instad of fetching it from the base repo head")]
      property ci_cue : String?

      def for_runner
        Runner::Config.new({
          "github_user_content_base_url" => github_user_content_base_url,
          "github_user"                  => github_user,
          "github_token"                 => github_token,
          "nomad_base_url"               => nomad_base_url,
          "nomad_datacenters"            => nomad_datacenters.to_json,
          "nomad_ssl_ca"                 => nomad_ssl_ca,
          "nomad_ssl_key"                => nomad_ssl_key,
          "nomad_ssl_cert"               => nomad_ssl_cert,
          "runner_flake"                 => runner_flake,
          "loki_base_url"                => loki_base_url,
          "nomad_token"                  => nomad_token,
          "postgres_url"                 => postgres_url,
          "ci_cue"                       => ci_cue,
          "public_url"                   => public_url,
          "artifact_secret"              => artifact_secret,
        }.compact.transform_values &.to_s, nil)
      end

      def run(log)
        Server.new(log, self).run
      end
    end

    property config : BitteCI::Server::Config
    property log : Log

    def initialize(@log, @config : Config)
    end

    def jsonb_resolve(a, b)
      Clear::SQL::JSONB.jsonb_resolve(a, b)
    end

    def json(env, **rest)
      env.response.content_type = "application/json"
      rest.to_json
    end

    macro not_found
      title = "Not Found"
      halt env, status_code: 404, response: lrender("404")
    end

    def h(event : Listener::AllocationPayload::Allocation::TaskStates::Event)
      if event.details.empty?
        h event.display_message
      else
        h "#{event.display_message} #{event.details.pretty_inspect}"
      end
    end

    def h(s : String)
      HTML.escape(s)
    end

    def h(n : Nil)
      ""
    end

    def h(n : UUID)
      n.to_s
    end

    macro lrender(tmpl)
      render "src/views/{{tmpl.id}}.ecr", "src/views/layout.ecr"
    end

    def run
      Clear::SQL.init(config.postgres_url.to_s)

      control = ChannelControl.new(10)
      channels = [] of Channel(String)
      start_control(control, channels)
      start_pg_listen(config, channels)

      error 404 do
        title = "Not Found"
        lrender "404"
      end

      ws "/ci/api/v1/socket" do |socket|
        Connection.new(socket, control, config).run
      end

      get "/" do
        title = "Bitte CI"
        # ameba:disable Lint/UselessAssign
        prs = PullRequest.query.to_a.sort_by(&.created_at)
        lrender "index"
      end

      get "/about" do
        markdown = Markd.to_html({{ read_file "README.md" }})

        # ameba:disable Lint/UselessAssign
        content = <<-HTML
          <div class="about container">
            #{markdown}
          </div>
        HTML
        title = "About"
        render "src/views/layout.ecr"
      end

      get "/nodes" do |env|
        nodes = Node.query.map(&.parsed.node)
        title = "Nodes"
        lrender "nodes"
      end

      get "/jobs" do |env|
        jobs = Job.query.map(&.parsed.job)
        title = "Jobs"
        lrender "jobs"
      end

      get "/allocations" do |env|
        allocs = Allocation.query.map(&.parsed.allocation)
        title = "Allocations"
        lrender "allocations"
      end

      get "/pull_request/:id" do |env|
        pr = PullRequest.query.where { id == env.params.url["id"] }.first
        if pr
          title = "Pull Request ##{pr.number}"
          lrender "pull_request"
        else
          not_found
        end
      end

      get "/build/:id" do |env|
        title = "Build #{env.params.url["id"]}"
        build = Build.query.where { id == env.params.url["id"] }.first

        not_found unless build

        # ameba:disable Lint/UselessAssign
        logs = Loki.query_range(
          config.loki_base_url,
          build.loki_id,
          build.created_at,
          build.finished_at
        )

        pr = build.pull_request

        alloc = Allocation.query
          .where { data.jsonb("Allocation.JobID") == pr.job_id }
          .order_by(:created_at, :desc)
          .first

        not_found unless alloc

        # ameba:disable Lint/UselessAssign
        outputs = alloc.outputs
          .select(:id, :size, :created_at, :path, :mime, :sha256).to_a

        # ameba:disable Lint/UselessAssign
        failing_alloc = alloc
          .parsed
          .allocation
          .task_states
          .try &.any? { |n, state|
            state.events.any? { |event|
              event.details["fails_task"]?
            }
          }

        lrender "build"
      end

      get "/api/v1/build" do |env|
        json env, builds: Build.query.order_by(:created_at, :desc).limit(10).to_a
      end

      get "/api/v1/build/:id" do |env|
        json env, build: Build.query.where { id == env.params.url["id"] }.first
      end

      get "/api/v1/organization" do |env|
        logins = PullRequest.query
          .select(login: jsonb_resolve("data", "organization.login"))
          .to_a(fetch_columns: true)
          .map { |row| row["login"] }
        json env, organizations: logins
      end

      get "/api/v1/organization/:id" do |env|
        organization = PullRequest.query
          .where { data.jsonb("organization.login") == env.params.url["id"] }
          .select(organization: jsonb_resolve("data", "organization"))
          .first(fetch_columns: true)
        json env, organization: organization["organization"] if organization
      end

      get "/api/v1/pull_request" do |env|
        json env, pull_requests: PullRequest.query
          .order_by(:created_at, :desc)
          .limit(10)
          .to_a
      end

      get "/api/v1/pull_request/:id" do |env|
        json env, pull_request: PullRequest.query.where { id == env.params.url["id"] }.first
      end

      get "/api/v1/allocation" do |env|
        json env, allocations: Allocation.query.order_by(:created_at, :desc).limit(10).to_a
      end

      get "/api/v1/allocation/:id" do |env|
        json env, allocation: Allocation.query.where { id == env.params.url["id"] }.first
      end

      get "/api/v1/output/:id" do |env|
        output = Output.query.where { var("id") == env.params.url["id"] }.first
        if output
          env.response.headers["Content-Type"] = output.mime
          env.response.headers["Content-Disposition"] = %(attachment; filename="#{File.basename(output.path)}")
          File.read(File.join(config.artifact_dir, output.sha256[0..5], output.sha256))
        else
          halt env, status_code: 404, response: "Not Found"
        end
      end

      post "/api/v1/github" do |env|
        BitteCI::Trigger.handle(config, env)
      end

      put "/api/v1/output" do |env|
        BitteCI::Artificer.handle(config, env)
      end

      Kemal.config.port = config.port
      Kemal.config.host_binding = config.host
      Kemal.run
    end

    def start_pg_listen(config, channels)
      PG.connect_listen config.postgres_url, "allocations", "github", "builds" do |n|
        obj =
          case n.channel
          when "builds"
            Build.query.where { id == n.payload }.first
          when "pull_requests"
            PullRequest.query.where { id == n.payload }.first
          when "allocations"
            if alloc = Allocation.query.where { id == n.payload }.first
              pp! alloc.try(&.id)
              alloc.send_github_status(
                user: config.github_user,
                token: config.github_token,
                target_url: config.public_url,
              )
              alloc.simplify
            end
          end

        channels.each { |c| c.send({"type" => n.channel, "value" => obj}.to_json) } if obj
      end
    end

    def start_control(control, channels)
      # Synchronize access to `channel`
      spawn do
        loop do
          next unless msg = control.receive?

          op, chan = msg

          case op
          in ChannelOp::Subscribe
            channels.push(chan) unless channels.includes?(chan)
          in ChannelOp::Unsubscribe
            channels.delete(chan)
            chan.close
          end
        end
      end
    end
  end
end
