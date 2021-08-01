require "uri"

module BitteCI
  class Loki
    struct Value
      property time : Time
      property text : String
      property labels : Hash(String, String)

      def initialize(@time, @text, @labels); end

      def to_json(b)
        [((1000000000u128 * @time.to_unix) + @time.nanosecond).to_s, @text].to_json(b)
      end
    end

    @loki_base_url : URI
    @labels : Hash(String, String) = {} of String => String

    def self.new(loki_base_url)
      new(loki_base_url, {} of String => String)
    end

    def initialize(@loki_base_url, @labels)
      @inbox = Channel(Value).new
      @timer = Channel(Time).new(0)
      @done = Channel(Nil).new
      @stopping = false
    end

    def start
      spawn { time_loop }
      spawn { push_loop }
    end

    def start(&block)
      start
      yield
    ensure
      stop
    end

    def stop
      Log.info &.emit("Loki#stop")
      @inbox.close
      @timer.close
      @stopping = true
      @done.receive
    end

    private def socket(name)
      left, right = UNIXSocket.pair
      right.sync = true
      labels = @labels.merge({"pipe" => name})
      spawn { right.each_line { |line| log(line, labels) } }
      left
    end

    def sh(cmd, args)
      Process.run(
        cmd,
        args: args,
        input: Process::Redirect::Close,
        output: socket("stdout"),
        error: socket("stderr")
      )
    end

    def sh(cmd, args)
      Process.run(
        cmd,
        args: args,
        input: Process::Redirect::Close,
        output: socket("stdout"),
        error: socket("stderr"),
      ) { |p| yield(p) }
    end

    # Ensure we send logs at least every 10 seconds, even if the size is below 1MB
    def time_loop
      loop do
        sleep 10
        @timer.send Time.utc
      end
    rescue e : Channel::ClosedError
      Log.error &.emit("Loki#time_loop", error: e.to_s)
    end

    def push_loop
      loop do
        collect
      end
    end

    def collect
      collected = [] of Value
      size = 0

      while value = Channel.receive_first(@timer, @inbox)
        case value
        in Value
          collected << value
          size += value.text.bytesize
          break if size > 1e+6 # Send if we have more than 1MB already
        in Time
          break
        end
      end
    rescue e : Channel::ClosedError
      Log.error &.emit("Loki#collect", error: e.to_s) unless @stopping
    ensure
      push(collected) if collected
    end

    def push(collected : Array(Value))
      return if collected.empty?
      Log.info &.emit("loki#push", collected: collected.size)

      grouped = collected.group_by do |coll|
        coll.labels
      end

      streams = [] of NamedTuple(stream: Hash(String, String), values: Array(Value))
      grouped.each do |labels, values|
        streams << {stream: labels, values: values}
      end

      uri = @loki_base_url.dup
      uri.path = "/loki/api/v1/push"

      client = HTTP::Client.new(uri)
      client.compress = true
      res = client.post(
        uri.path,
        HTTP::Headers{"Content-Type" => ["application/json"]},
        {streams: streams}.to_json,
      )

      case res.status
      when HTTP::Status::NO_CONTENT
      when HTTP::Status::IM_A_TEAPOT
        Log.info { "Kettle boiling over!" }
      else
        Log.error &.emit("Loki#push", response: res.inspect)
      end
    ensure
      @done.send nil if @stopping
    end

    def log(text : String, labels : Hash(String, String))
      Log.info &.emit("loki#log", text: text, labels: labels)
      @inbox.send Value.new(Time.utc, text, labels)
    rescue e : Channel::ClosedError
      Log.error &.emit("Loki#log", error: e.to_s) unless @stopping
    end
  end
end
