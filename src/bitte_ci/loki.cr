require "http/client"
require "log"
require "uri"
require "./time"

module BitteCI
  class Loki
    struct Value
      property time : Time
      property text : String
      property labels : Hash(String, String)

      def initialize(@time, @text, @labels); end

      def to_json(b)
        [@time.to_unix_ns.to_s, @text].to_json(b)
      end
    end

    @loki_base_url : URI
    @labels : Hash(String, String) = {} of String => String
    @obfuscate : Regex

    def self.new(loki_base_url)
      new(loki_base_url, {} of String => String)
    end

    def initialize(@loki_base_url, @labels, obfuscate)
      @inbox = Channel(Value).new
      @timer = Channel(Time).new(0)
      @done = Channel(Nil).new
      @stopping = false
      @log = ::Log.for("Loki")
      @obfuscate = Regex.union(obfuscate)
    end

    def start
      spawn { time_loop }
      spawn { push_loop }
    end

    def run(&block)
      start
      result = yield
    ensure
      stop
      result
    end

    def stop
      return if @stopping
      @log.info { "stopping Loki exporter" }
      @inbox.close
      @timer.close
      @stopping = true
      @done.receive
    end

    private def socket(name)
      left, right = UNIXSocket.pair
      right.sync = true
      spawn { right.each_line { |line| log(line, {"pipe" => name}) } }
      left
    end

    def sh(cmd, args, chdir)
      Process.new(
        cmd,
        args: args,
        chdir: chdir,
        input: Process::Redirect::Close,
        output: socket("stdout"),
        error: socket("stderr"),
      )
    end

    # Ensure we send logs at least every 10 seconds, even if the size is below 1MB
    def time_loop
      loop do
        sleep 10
        @timer.send Time.utc
      end
    rescue e : Channel::ClosedError
      @log.error &.emit("time_loop", error: e.to_s)
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
      @log.error &.emit("collect", error: e.to_s) unless @stopping
    ensure
      push(collected) if collected
    end

    def push(collected : Array(Value))
      return if collected.empty?
      @log.debug &.emit("push", collected: collected.size)

      grouped = collected.group_by do |coll|
        coll.labels
      end

      streams = [] of NamedTuple(stream: Hash(String, String), values: Array(Value))
      grouped.each do |labels, values|
        streams << {stream: labels, values: values.sort_by &.time}
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
        @log.debug &.emit("push", response: res.inspect)
      when HTTP::Status::IM_A_TEAPOT
        @log.info { "Kettle boiling over!" }
      else
        @log.error &.emit("push", response: res.inspect)
      end
    ensure
      @done.send nil if @stopping
    end

    def log(text : String, labels : Hash(String, String) = @labels)
      text = text.gsub(@obfuscate, "******")
      merged_labels = @labels.merge(labels)
      @log.debug &.emit(text: text, labels: merged_labels)
      @log.info { text }
      @inbox.send Value.new(Time.utc, text, merged_labels)
    rescue e : Channel::ClosedError
      @log.error &.emit("log", error: e.to_s) unless @stopping
    end

    def self.query_range(loki_base_url, loki_id, from : Time, to : Time?)
      query_range(
        loki_base_url,
        from: from,
        to: to || Time.utc,
        query: %({bitte_ci_id="#{loki_id}"}),
      )
    end

    class LogCliLine
      include JSON::Serializable
      property labels : Hash(String, String)
      property line : String
      property timestamp : Time
    end

    def self.query_range(loki_base_url : URI, from : Time, to : Time, query : String)
      reader, writer = IO.pipe
      args = [
        "--addr", loki_base_url.to_s,
        "query",
        "--forward",
        "--from", Time::Format::ISO_8601_DATE_TIME.format(from),
        "--to", Time::Format::ISO_8601_DATE_TIME.format(to),
        "--include-label", "bitte_ci_step",
        "--include-label", "pipe",
        "--batch", "5000",
        "--limit", "1000000",
        "--output", "jsonl",
        "--timezone", "UTC",
        query,
      ]

      logs = Hash(String, Array(LogCliLine)).new

      Process.run("logcli", args: args, output: writer, error: STDERR) do |_process|
        spawn do
          reader.each_line do |line|
            log = LogCliLine.from_json(line)
            (logs[log.labels["bitte_ci_step"]] ||= Array(LogCliLine).new) << log
          end
        end
        pp! :process_done
      end

      writer.close
      pp! :writer_done

      logs
    end
  end
end
