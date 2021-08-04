require "clear"
require "kemal"
require "./uuid"
require "./simple_config"
require "./connection"
require "./model"
require "./loki"
require "./trigger"
require "./runner"
require "./artificer"

module BitteCI
  class Server
    struct Config
      include SimpleConfig::Configuration

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

      def for_runner
        Runner::Config.new({
          "github_user_content_base_url" => github_user_content_base_url.to_s,
        }, nil)
      end
    end

    property config : BitteCI::Server::Config

    def self.start(config)
      new(config).start
    end

    def initialize(@config)
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
      halt env, status_code: 404, response: render("src/views/404.ecr", "src/views/layout.ecr")
    end

    def h(s)
      case s
      in String
        HTML.escape(s)
      in Nil
        ""
      end
    end

    def start
      control = ChannelControl.new(10)
      channels = [] of Channel(String)
      start_control(control, channels)
      start_pg_listen(config, channels)

      error 404 do
        title = "Not Found"
        render("src/views/404.ecr", "src/views/layout.ecr")
      end

      ws "/ci/api/v1/socket" do |socket|
        Connection.new(socket, control, config).run
      end

      get "/" do
        title = "Bitte CI"
        prs = PullRequest.query.to_a.sort_by { |pr| pr.created_at }
        render "src/views/index.ecr", "src/views/layout.ecr"
      end

      get "/pull_request/:id" do |env|
        pr = PullRequest.query.where { id == env.params.url["id"] }.first
        if pr
          title = "Pull Request ##{pr.number}"
          render "src/views/pull_request.ecr", "src/views/layout.ecr"
        else
          not_found
        end
      end

      get "/build/:id" do |env|
        title = "Build #{env.params.url["id"]}"
        build = Build.query.where { id == env.params.url["id"] }.first

        not_found unless build

        logs = Loki.query_range(
          config.loki_base_url,
          build.loki_id,
          build.created_at,
          build.finished_at
        )

        pr = build.pull_request
        alloc = Allocation.query
          .where { data.jsonb("Allocation.JobID") == pr.job_id }
          .to_a
          .select { |alloc|
            alloc.parsed.allocation.task_states.try &.any? { |n, state|
              state.events.any? { |event|
                event.details["fails_task"]?
              }
            }
          }
          .sort_by { |alloc| alloc.created_at }
          .last

        render "src/views/build.ecr", "src/views/layout.ecr"
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
          env.response.headers["Content-Type"] = "application/octet-stream"
          env.response.headers["Content-Disposition"] = %(attachment; filename="#{File.basename(output.path)}")
          File.read(File.join("output", output.sha256))
        else
          halt env, status_code: 404, response: "Not Found"
        end
      end

      post "/api/v1/github" do |env|
        BitteCI::Trigger.handle(config, env)
      end

      # TODO: add authentication/validation
      put "/api/v1/output" do |env|
        BitteCI::Artificer.handle(config, env)
      end
    end

    def start_pg_listen(config, channels)
      PG.connect_listen config.postgres_url, "allocations", "github", "builds" do |n|
        obj =
          case n.channel
          when "builds"
            build = Build.query.where { id == n.payload }.first
            build.send_github_status(
              user: config.github_user,
              token: config.github_token,
              target_url: config.public_url
            ) if build
            build
          when "pull_requests"
            PullRequest.query.where { id == n.payload }.first
          when "allocations"
            alloc = Allocation.query.where { id == n.payload }.first
            alloc.simplify if alloc
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
