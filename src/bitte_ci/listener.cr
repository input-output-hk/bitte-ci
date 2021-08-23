require "http/client"
require "json"
require "db"
require "pg"
require "./uuid"
require "./simple_config"
require "./line"

module BitteCI
  class Listener
    struct Config
      include SimpleConfig::Configuration

      def self.help
        "Start nomad event listener"
      end

      def self.command
        "listen"
      end

      @[Option(help: "PostgreSQL URL e.g. postgres://postgres@127.0.0.1:54321/bitte_ci")]
      property postgres_url : URI

      @[Option(help: "Base URL e.g. http://127.0.0.1:4646")]
      property nomad_base_url = URI.parse("http://127.0.0.1:4646")

      @[Option(secret: true, help: "Nomad token used for job submission")]
      property nomad_token : String

      @[Option(help: "CA cert used for talking with Nomad when using HTTPS")]
      property nomad_ssl_ca : String?

      @[Option(help: "Key used for talking with Nomad when using HTTPS")]
      property nomad_ssl_key : String?

      @[Option(help: "Cert used for talking with Nomad when using HTTPS")]
      property nomad_ssl_cert : String?

      @[Option(help: "Base URL under which this server is reachable e.g. http://example.com")]
      property public_url : URI

      def run(log)
        Listener.new(log, self).run
      end
    end

    property log : Log
    property config : Config

    def initialize(@log, @config); end

    # TODO: refactor to use Clear
    def run
      DB.open(config.postgres_url.to_s) do |db|
        index = 0i64

        db.query "SELECT COALESCE(MAX(index), 0) from allocations;" do |rs|
          rs.each do
            index = rs.read(Int64) + 1
          end
        end

        nomad_url = config.nomad_base_url.dup
        nomad_url.path = "/v1/event/stream"
        nomad_url.query = URI::Params.new({
          "topic" => ["Allocation"],
          "index" => [index.to_s],
        }).to_s

        headers = HTTP::Headers{
          "X-Nomad-Token" => [config.nomad_token],
        }

        context = ssl_context(config) if nomad_url.scheme == "https"

        loop do
          HTTP::Client.get(nomad_url, headers: headers, tls: context) do |res|
            res.body_io.each_line { |line| handle_line(db, line) }
          end
        end
      end
    end

    def handle_line(db, line)
      return if line == "{}"
      return if line "subscription closed by server, client should resubscribe"
      j = Line.from_json(line)
      j.events.each do |event|
        next unless event.is_a?(Allocation)

        db.transaction do
          id = event.payload.allocation.id
          eval_id = event.payload.allocation.eval_id
          status = event.payload.allocation.client_status

          log.info { "Updating allocation #{id} with #{status}" }

          db.exec <<-SQL, id, eval_id, j.index, status, event.payload.to_json
            INSERT INTO allocations
              (id, eval_id, index, client_status, data, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
            ON CONFLICT (id) DO
              UPDATE SET index = $3, updated_at = NOW(), client_status = $4, data = $5;
          SQL

          db.exec "SELECT pg_notify($1, $2)", "allocations", id

          case status
          when "failed", "complete"
            db.exec <<-SQL, eval_id, status
              UPDATE builds
                SET build_status = $2, updated_at = NOW(), finished_at = NOW()
                WHERE id = $1 AND build_status != $2;
            SQL
          else
            db.exec <<-SQL, eval_id, status
              UPDATE builds
                SET build_status = $2, updated_at = NOW()
                WHERE id = $1 AND build_status != $2;
            SQL
          end

          db.exec "SELECT pg_notify($1, $2)", "builds", eval_id
        end
      end
    rescue e : JSON::ParseException
      log.error &.emit("Couldn't parse line, stored as line.json", error: e.inspect)
      File.write("line.json", line)
    end

    def ssl_context(config)
      OpenSSL::SSL::Context::Client.from_hash({
        "ca"   => config.nomad_ssl_ca,
        "cert" => config.nomad_ssl_cert,
        "key"  => config.nomad_ssl_key,
      })
    end
  end
end
