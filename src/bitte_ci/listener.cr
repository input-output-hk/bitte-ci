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
        discover(db)

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

        loop do
          listen(db, nomad_url)
          sleep 1
        end
      end
    end

    def context
      ssl_context(config) if config.nomad_base_url.scheme == "https"
    end

    def ssl_context(config)
      OpenSSL::SSL::Context::Client.from_hash({
        "ca"   => config.nomad_ssl_ca,
        "cert" => config.nomad_ssl_cert,
        "key"  => config.nomad_ssl_key,
      })
    end

    def headers
      HTTP::Headers{
        "X-Nomad-Token" => [config.nomad_token],
      }
    end

    def discover(db)
      nodes_url = config.nomad_base_url.dup
      nodes_url.path = "/v1/nodes"
      HTTP::Client.get(nodes_url, headers: headers, tls: context) do |res|
        discover_apply(db, res)
      end
    end

    def discover_apply(db, response)
      Array(NamedTuple(ID: String)).from_json(response.body_io).each do |n|
        node_url = config.nomad_base_url.dup.tap(&.path=("/v1/node/#{n[:ID]}"))
        discover_handle(db, node_url)
      end
    rescue e : JSON::ParseException
      log.error &.emit("Couldn't parse response, stored as discover_apply_error.json", error: e.inspect)
      File.write("discover_apply_error.json", response.body_io)
    end

    def discover_handle(db, node_url)
      HTTP::Client.get(node_url, headers: headers, tls: context) do |node_res|
        begin
          handle_node db, Node::NodePayload::Node.from_json(node_res.body_io)
        rescue e : JSON::ParseException
          log.error &.emit("Couldn't parse response, stored as discover_error.json", error: e.inspect)
          File.write("discover_error.json", node_res.body_io)
        end
      end
    end

    def listen(db, nomad_url)
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
          handle_allocation(db, event.payload.allocation, j.index)
        when Evaluation
          handle_evaluation(db, event.payload.evaluation)
        when Job
          handle_job(db, event.payload.job)
        when Node
          handle_node(db, event.payload.node)
        else
          log.error &.emit("Couldn't parse line, stored as line_unknown.json")
          File.write("line_unknown.json", line)
        end
      end
    rescue e : JSON::ParseException | ArgumentError | IO::EOFError | Socket::ConnectError
      log.error &.emit("Couldn't parse line, stored as line_error.json", error: e.inspect)
      File.write("line_error.json", line)
    end

    def handle_node(db, node : Node::NodePayload::Node)
      log.info { "Handling node #{node.id}" }
      File.write("node_event.json", node.to_json)

      db.transaction do
        log.info { "Updating node #{node.id}" }

        db.exec <<-SQL, node.id, node.to_json
          INSERT INTO nodes
            (id, created_at, updated_at, data) VALUES ($1, NOW(), NOW(), $2)
          ON CONFLICT (id) DO
            UPDATE SET data = $2, updated_at = NOW()
        SQL
      end
    end

    def handle_evaluation(db, eval : Evaluation::EvaluationPayload::Evaluation)
      log.info { "Handling evaluation #{eval.id}" }
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

    def handle_job(db, job : Job::JobPayload::Job)
      log.info { "Handling job #{job.id}" }
      File.write("evaluation_event.json", job.to_json)

      return unless parse_uuid(job.id)

      db.transaction do
        log.info { "Updating job #{job.id}" }

        db.exec <<-SQL, job.id, job.submit_time, job.to_json
          INSERT INTO jobs
            (id, created_at, updated_at, data) VALUES ($1, $2, NOW(), $3)
          ON CONFLICT (id) DO
            UPDATE SET data = $3, updated_at = NOW()
        SQL
      end
    end

    def handle_allocation(db, alloc : AllocationPayload::Allocation, index)
      log.info { "Handling allocation #{alloc.id}" }
      File.write("allocation_event.json", alloc.to_json)

      db.transaction do
        old_alloc = ::Allocation.query.where { var("id") == alloc.id }.first

        if old_alloc
          update_allocation(db, alloc, index, old_alloc)
        else
          create_allocation(db, alloc, index)
        end

        update_builds(db, alloc)
      end
    end

    private def parse_uuid(s : String) : UUID?
      UUID.new(s)
    rescue e : ArgumentError
    end

    def update_builds(db : DB::Database, alloc : AllocationPayload::Allocation)
      log.info { "Update build for alloc: #{alloc.id}" }
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

    def update_allocation(db : DB::Database, alloc : AllocationPayload::Allocation, index : UInt64, old_alloc : ::Allocation)
      log.info { "Update allocation #{alloc.id}" }
      changed = false

      old_alloc.parsed.task_states.try &.each do |old_name, old_state|
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
        data: JSON.parse(alloc.to_json),
      )

      db.exec("SELECT pg_notify($1, $2)", "allocations", alloc.id) if changed
    end

    def create_allocation(db : DB::Database, alloc : AllocationPayload::Allocation, index : UInt64)
      pr_id = job_id_to_pr_id(db, alloc.job_id)
      log.info { "Create allocation #{alloc.id} PR: #{pr_id}" }
      return unless pr_id

      ::Allocation.create!(
        id: alloc.id,
        eval_id: alloc.eval_id,
        job_id: alloc.job_id,
        pr_id: pr_id,
        index: index,
        client_status: alloc.client_status,
        data: alloc.to_json,
        created_at: alloc.create_time,
        updated_at: alloc.modify_time,
      )

      db.exec "SELECT pg_notify($1, $2)", "allocations", alloc.id
    end

    def job_id_to_pr_id(db : DB::Database, job_id : String) : Int64?
      pr_id = nil

      db.query "SELECT (data->'Meta'->>'pull_request_id')::bigint from jobs WHERE id = $1;", job_id do |rs|
        rs.each do
          pr_id = rs.read(Int64)
        end
      end

      pr_id
    rescue e : PQ::PQError
      log.error &.emit("Couldn't get PR for job id", job_id: job_id, error: e.inspect)
      nil
    end

    def self.print_line_events(line)
      j = Line.from_json(line)
      j.events.each do |event|
        case event
        in Allocation
          pp! event.topic
        in Evaluation
          pp! event.topic
        in Job
          pp! event.topic, event.payload.job.id
        in Node
          pp! event.topic
        in Event
          pp! event.topic
        end
      end
    end
  end
end
