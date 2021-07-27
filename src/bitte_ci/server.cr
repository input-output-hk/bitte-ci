require "kemal"
require "./uuid"
require "./simple_config"

module BitteCI
  class LokiQueryRange
    include JSON::Serializable

    property status : String
    property data : LokiQueryRangeData
  end

  class LokiQueryRangeData
    include JSON::Serializable

    property result : Array(LokiQueryRangeDataResult)
  end

  class LokiQueryRangeDataResult
    include JSON::Serializable

    property stream : Hash(String, String)
    property values : Array(Array(String))
  end

  enum ChannelOp
    Subscribe
    Unsubscribe
  end

  enum MsgChannel
    PullRequests
    PullRequest
    Allocation
    Build
  end

  class Msg
    include JSON::Serializable

    property channel : MsgChannel
    property uuid : UUID?
    property id : Int64?
  end

  alias ChannelControlMessage = Tuple(ChannelOp, Channel(String))
  alias ChannelControl = Channel(ChannelControlMessage)

  class Connection
    @channel : Channel(String)

    def initialize(@socket : HTTP::WebSocket, @control : ChannelControl, @config : Server::Config)
      @channel = Channel(String).new
    end

    def run
      spawn do
        @control.send({ChannelOp::Subscribe, @channel})

        while obj = @channel.receive?
          @socket.send(obj)
        end
      end

      @socket.on_close do
        @control.send({ChannelOp::Unsubscribe, @channel})
      end

      @socket.on_message do |body|
        msg = Msg.from_json(body)
        id = msg.id
        uuid = msg.uuid

        case msg.channel
        in MsgChannel::PullRequests
          @socket.send(on_pull_requests.to_json)
        in MsgChannel::PullRequest
          respond(id) { |i| on_pull_request(i) }
        in MsgChannel::Build
          respond(msg.uuid) { |i| on_build(i) }
        in MsgChannel::Allocation
          respond(msg.uuid) { |i| on_alloc(i) }
        end
      end
    end

    def respond(arg)
      obj =
        if arg
          yield(arg)
        else
          {error: "argument missing"}
        end
      @socket.send(obj.to_json)
    end

    def on_alloc(id : UUID)
      alloc = Allocation.query.where { var("id") == id }.first
      {type: "allocation", value: alloc.simplify} if alloc
    end

    def on_build(id : UUID)
      build = Build.query.where { var("id") == id }.first
      {type: "build", value: build.simplify} if build
    end

    def on_pull_requests
      ordering = "(data#>>'{pull_request, created_at}')::timestamptz"
      prs = PullRequest.query.order_by(ordering, :desc).limit(100).map do |pr|
        pr.simplify
      end

      {type: "pull_requests", value: prs}
    end

    def on_pull_request(id : Int64)
      pr = PullRequest.query.where { var("id") == id }.first
      {type: "pull_request", value: pr.simplify} if pr
    end

    def on_build(id : UUID)
      build = Build.query.where { var("id") == id }.first
      return unless build

      # nomad_alloc = get_nomad_alloc(build.id)
      # path=/v1/client/allocation/89f9a5ac-ef2a-dff8-253c-2b2fa0509fa1/stats

      query = URI::Params.new(
        {
          "direction" => ["FORWARD"],
          "query"     => [%({bitte_ci_id="#{build.loki_id}"})],
          "start"     => [((build.created_at).to_unix_ms * 1000000).to_s],
          "end"       => [((build.finished_at || Time.utc).to_unix_ms * 1000000).to_s],
        }
      )

      url = @config.loki_base_url.dup
      url.path = "/loki/api/v1/query_range"
      url.query = query.to_s

      Log.info { "querying #{url}" }

      res = HTTP::Client.get(url)

      dec = LokiQueryRange.from_json(res.body)

      logs = Hash(UUID, Array(NamedTuple(time: Time, line: String))).new

      dec.data.result.each do |result|
        next if result.stream["filename"] =~ /promtail\./
        id = UUID.new(result.stream["nomad_alloc_id"])

        current = logs[id]?
        current ||= Array(NamedTuple(time: Time, line: String)).new

        result.values.each do |line|
          time, text = line[0], line[1]
          current << {time: Time.unix_ms((time.to_i64 / 1000000).to_i64), line: text}
        end

        logs[id] = current
      end

      {type: "build", value: {build: build.simplify, logs: logs}}
    rescue e : JSON::ParseException
      Log.error &.emit(e.inspect, url: url.to_s, body: res.body) if res
      sleep 1
    end
  end

  class Server
    struct Config
      include SimpleConfig::Configuration

      @[Option(help: "The user for setting Github status")]
      property github_user : String

      @[Option(secret: true, help: "The token for setting Github status")]
      property github_token : String

      @[Option(help: "Path to the bitte-ci-frontend directory")]
      property frontend_path : String

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

      property runner_config : Runner::Config?

      def for_runner
        @runner_config ||= Runner::Config.new({
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

    def start
      control = ChannelControl.new(10)
      channels = [] of Channel(String)
      start_control(control, channels)

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
            {allocation: alloc.simplify} if alloc
          end

        channels.each { |c| c.send({"type" => n.channel, "value" => obj}.to_json) } if obj
      end

      ws "/ci/api/v1/socket" do |socket|
        Connection.new(socket, control, config).run
      end

      frontend_path = File.expand_path(config.frontend_path, home: true)

      public_folder frontend_path
      index_html = File.read(File.join(frontend_path, "index.html"))

      get "/" do
        index_html
      end

      get "/api/v1/output/:id" do |env|
        output = Output.query.where { var("id") == env.params.url["id"] }.first
        if output
          env.response.headers["Content-Type"] = "application/octet-stream"
          env.response.headers["Content-Disposition"] = %(attachment; filename="#{File.basename(output.path)}")
          output.data
        else
          halt env, status_code: 404, response: "Not Found"
        end
      end

      post "/api/v1/github" do |env|
        BitteCI::Trigger.handle(config, env)
      end

      %w[pull_requests pull_request build allocation].each do |sub|
        get "/#{sub}/*" do
          index_html
        end
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
