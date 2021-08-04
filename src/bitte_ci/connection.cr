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
        Log.info { result.inspect }
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
end
