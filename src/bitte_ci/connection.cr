require "kemal"

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
    @socket : HTTP::WebSocket
    @control : ChannelControl
    @channel : Channel(String)

    def initialize(@socket, @control)
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

        case msg.channel
        in MsgChannel::PullRequests
          @socket.send(on_pull_requests.to_json)
        in MsgChannel::PullRequest
          @socket.send(on_pull_request(msg.id).to_json)
        in MsgChannel::Build
          @socket.send(on_build(msg.uuid).to_json)
        end
      end
    end

    def on_build(id : Nil)
    end

    def on_build(id : UUID)
      build = Build.query.where { var("id") == id }.first
      {type: "build", build: build.simplify} if build
    end

    def on_pull_requests
      ordering = "(data#>>'{pull_request, created_at}')::timestamptz"
      prs = PullRequest.query.order_by(ordering, :desc).limit(100).map do |pr|
        pr.simplify
      end

      {type: "pull_requests", value: prs}
    end

    def on_pull_request(id : Nil)
    end

    def on_pull_request(id : Int64)
      pr = PullRequest.query.where { var("id") == id }.first
      {type: "pull_request", value: pr.simplify} if pr
    end

    def on_build(id : Nil)
    end

    def on_build(id : UUID)
      build = Build.query.where { var("id") == id }.first
      return unless build

      query = URI::Params.new(
        {
          "direction" => ["FORWARD"],
          "query"     => [%({bitte_ci_id="#{build.loki_id}"})],
          "start"     => [((Time.utc - 24.hours).to_unix_ms * 1000000).to_s],
          "end"       => [(Time.utc.to_unix_ms * 1000000).to_s],
        }
      )

      res = HTTP::Client.get("http://127.0.0.1:3120/loki/api/v1/query_range?" + query.to_s)

      dec = LokiQueryRange.from_json(res.body)

      logs = Hash(UUID, Array(NamedTuple(time: Time, line: String))).new

      dec.data.result.each do |result|
        next if result.stream["filename"] =~ /promtail\./
        pp! result.stream
        id = UUID.new(result.stream["nomad_alloc_id"])
        pp! id

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
      pp! e
      pp! res.body if res
      sleep 1
    end
  end

  def self.start(github_user : String, github_token : String)
    control = ChannelControl.new(10)
    channels = [] of Channel(String)
    start_control(control, channels)

    PG.connect_listen OPTIONS[:db_url], "allocations", "github", "builds" do |n|
      obj =
        case n.channel
        when "builds"
          build = Build.query.where { id == n.payload }.first
          pp! build.send_github_status(user: github_user, token: github_token) if build
          build
        when "pull_requests"
          PullRequest.query.where { id == n.payload }.first
        when "allocations"
          Allocation.query.where { id == n.payload }.first
        end

      channels.each { |c| c.send({"type" => n.channel, "value" => obj}.to_json) } if obj
    end

    ws "/ci/api/v1/socket" do |socket|
      Connection.new(socket, control).run
    end
  end

  def self.start_control(control, channels)
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
