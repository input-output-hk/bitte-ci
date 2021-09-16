require "http/client"
require "json"
require "db"
require "pg"
require "./uuid"
require "./simple_config"
require "./line"
require "./model"

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

      @[Option(help: "Index to start listening from (comes from db by default)")]
      property index : UInt64?

      def run(log)
        Listener.new(log, self).run
      end
    end

    property log : Log
    property config : Config

    def initialize(@log, @config); end

    # TODO: refactor to use Clear
    def run
      Clear::SQL.init(config.postgres_url.to_s)

      DB.open(config.postgres_url.to_s) do |db|
        index = 0u64

        if config.index
          index = config.index.not_nil!
        else
          db.query "SELECT COALESCE(MAX(index), 0) from allocations;" do |rs|
            rs.each do
              index = rs.read(Int64)
            end
          end
        end

        nomad_url = config.nomad_base_url.dup
        nomad_url.path = "/v1/event/stream"
        nomad_url.query = URI::Params.new({
          "topic" => ["Job", "Allocation", "Deployment", "Evaluation"],
          "index" => [(index + 1).to_s],
        }).to_s

        headers = HTTP::Headers{
          "X-Nomad-Token" => [config.nomad_token],
        }

        context = ssl_context(config) if nomad_url.scheme == "https"

        loop do
          listen(db, nomad_url, headers, context)
          sleep 1
        end
      end
    end

    def listen(db, nomad_url, headers, context)
      HTTP::Client.get(nomad_url, headers: headers, tls: context) do |res|
        res.body_io.each_line { |line| handle_line(db, line) }
      end
    rescue e : IO::EOFError | Socket::ConnectError
      log.error &.emit("Connection to Nomad lost", error: e.inspect)
    end

    def handle_line(db, line)
      raise "Possibly invalid Nomad token" if line == "Permission denied"
      return if line == "{}"
      return unless line.starts_with?("{")

      j = Line.from_json(line)
      j.events.each do |event|
        case event
        when Allocation
          handle_allocation(db, event, j.index)
        when Evaluation
          handle_evaluation(db, event, j.index)
        when Job
          handle_job(db, event, j.index)
        when Node
          handle_node(db, event, j.index)
        else
          log.error &.emit("Couldn't parse line, stored as line_unknown.json")
          File.write("line_unknown.json", line)
        end
      end
    rescue e : JSON::ParseException | ArgumentError | IO::EOFError | Socket::ConnectError
      log.error &.emit("Couldn't parse line, stored as line_error.json", error: e.inspect)
      File.write("line_error.json", line)
    end

    def ssl_context(config)
      OpenSSL::SSL::Context::Client.from_hash({
        "ca"   => config.nomad_ssl_ca,
        "cert" => config.nomad_ssl_cert,
        "key"  => config.nomad_ssl_key,
      })
    end

    def handle_node(db, event : Node, index)
      node = event.payload.node
      File.write("node_event.json", node.to_json)

      db.transaction do
        log.info { "Updating node #{node.id}" }

        db.exec <<-SQL, node.id, event.payload.to_json
          INSERT INTO nodes
            (id, created_at, updated_at, data) VALUES ($1, NOW(), NOW(), $2)
          ON CONFLICT (id) DO
            UPDATE SET data = $2, updated_at = NOW()
        SQL
      end
    end

    def handle_evaluation(db, event : Evaluation, index)
      eval = event.payload.evaluation
      File.write("evaluation_event.json", eval.to_json)

      db.transaction do
        log.info { "Updating evaluation #{eval.id} with #{eval.status}" }

        db.exec <<-SQL, eval.id, eval.job_id, eval.status, eval.create_time, eval.modify_time
          INSERT INTO evaluations
            (id, job_id, status, created_at, updated_at) VALUES ($1, $2, $3, $4, $5)
          ON CONFLICT (id) DO
            UPDATE SET status = $3, updated_at = $5
        SQL
      end
    end

    def handle_job(db, event : Job, index)
      job = event.payload.job
      File.write("evaluation_event.json", job.to_json)

      db.transaction do
        log.info { "Updating job #{job.id}" }

        db.exec <<-SQL, job.id, job.submit_time, event.payload.to_json
          INSERT INTO jobs
            (id, created_at, updated_at, data) VALUES ($1, $2, NOW(), $3)
          ON CONFLICT (id) DO
            UPDATE SET data = $3, updated_at = NOW()
        SQL
      end
    end

    def handle_allocation(db, event : Allocation, index)
      alloc = event.payload.allocation

      File.write("allocation_event.json", alloc.to_json)

      db.transaction do
        log.info { "Updating allocation #{alloc.id} with #{alloc.client_status}" }

        old_alloc = ::Allocation.query.where { var("id") == alloc.id }.first

        if old_alloc
          update_allocation(db, event, index, old_alloc)
        else
          create_allocation(db, event, index)
        end

        update_builds(db, alloc)
      end
    end

    private def parse_uuid(s : String) : UUID?
      UUID.new(s)
    rescue e : ArgumentError
    end

    def update_builds(db : DB::Database, alloc : AllocationPayload::Allocation)
      case alloc.client_status
      when "failed", "complete"
        db.exec <<-SQL, alloc.eval_id, alloc.client_status
          UPDATE builds
            SET build_status = $2, updated_at = NOW(), finished_at = NOW()
            WHERE id = $1 AND build_status != $2;
        SQL
      else
        db.exec <<-SQL, alloc.eval_id, alloc.client_status
          UPDATE builds
            SET build_status = $2, updated_at = NOW()
            WHERE id = $1 AND build_status != $2;
        SQL
      end

      db.exec "SELECT pg_notify($1, $2)", "builds", alloc.eval_id
    end

    def update_allocation(db : DB::Database, event : Allocation, index : UInt64, old_alloc : ::Allocation)
      alloc = event.payload.allocation
      changed = false

      old_alloc.parsed.allocation.task_states.try &.each do |old_name, old_state|
        alloc.task_states.try &.each do |new_name, new_state|
          next if old_name != new_name
          next if new_state.failed == old_state.failed && new_state.state == old_state.state

          changed = true
        end
      end

      old_alloc.update(
        index: index.to_i64,
        updated_at: Time.utc,
        client_status: alloc.client_status,
        data: JSON.parse(event.payload.to_json),
      )

      db.exec("SELECT pg_notify($1, $2)", "allocations", alloc.id) if changed
    end

    def create_allocation(db : DB::Database, event : Allocation, index : UInt64)
      pr_id = job_id_to_pr_id(db, alloc.job_id)
      return unless pr_id

      alloc = event.payload.allocation

      new_alloc = ::Allocation.create(
        id: alloc.id,
        eval_id: alloc.eval_id,
        job_id: alloc.job_id,
        pr_id: job_id_to_pr_id(db, alloc.job_id),
        index: index,
        client_status: alloc.client_status,
        data: event.payload.to_json
      )

      db.exec "SELECT pg_notify($1, $2)", "allocations", alloc.id
    end

    def job_id_to_pr_id(db : DB::Database, job_id : String) : Int64?
      pr_id = nil

      db.query "SELECT (data->'Job'->'Meta'->>'pull_request_id')::bigint from jobs WHERE id = $1;", job_id do |rs|
        rs.each do
          pr_id = rs.read(Int64)
        end
      end

      pr_id
    rescue e : PQ::PQError
      log.error &.emit("Couldn't get PR for job id", job_id: job_id, error: e.inspect)
      nil
    end
  end
end
