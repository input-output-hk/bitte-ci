require "http/client"
require "json"
require "db"
require "pg"

db_url = ENV["DB_URL"]? || "postgres://postgres@127.0.0.1/bitte_ci"

DB.open(db_url) do |db|
  HTTP::Client.get("http://127.0.0.1:4646/v1/event/stream") do |res|
    res.body_io.each_line do |line|
      next if line == "{}"
      j = Line.from_json(line)
      j.events.each do |event|
        case event
        when Allocation
          db.transaction do
            group = event.payload.allocation.task_group
            step = event.payload.allocation.client_status
            db.exec "UPDATE events SET step = $1, updated_at = $2 WHERE (id = $3);",
              step,
              Time.utc,
              group
            db.exec "SELECT pg_notify($1, $2)", "allocation_updated", group
          end
        end
      end
    end
  end
end

class Line
  include JSON::Serializable

  @[JSON::Field(key: "Index")]
  property index : UInt64

  @[JSON::Field(key: "Events")]
  property events : Array(Event)
end

abstract class Event
  include JSON::Serializable

  use_json_discriminator "Topic", {
    Allocation: Allocation,
    Evaluation: Evaluation,
    Plan:       Plan,
    Job:        Job,
  }

  @[JSON::Field(key: "Topic")]
  property topic : String

  @[JSON::Field(key: "Namespace")]
  property namespace : String
end

class Plan < Event
end

class Job < Event
end

class Allocation < Event
  @[JSON::Field(key: "Payload")]
  property payload : AllocationPayload
end

class Evaluation < Event
end

class AllocationPayload
  include JSON::Serializable

  @[JSON::Field(key: "Allocation")]
  property allocation : AllocationPayloadAllocation
end

class AllocationPayloadAllocation
  include JSON::Serializable

  @[JSON::Field(key: "ClientStatus")]
  property client_status : String

  @[JSON::Field(key: "TaskGroup")]
  property task_group : String
end
