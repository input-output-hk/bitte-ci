require "clear"
require "./uuid"

Clear.enum BuildStatus, "pending", "running", "complete", "failed"

class PullRequest
  include Clear::Model

  primary_key type: :bigint
  column data : JSON::Any

  has_many builds : Build, foreign_key: "pr_id"

  # TODO: whittle down the data we actually want to send
  def simplify
    {id: id, data: data, builds: builds.order_by(:created_at, :desc).map(&.simplify)}
  end
end

class Build
  include Clear::Model

  primary_key type: :uuid
  column build_status : BuildStatus
  column created_at : Time
  column updated_at : Time?
  column finished_at : Time?
  column loki_id : UUID

  belongs_to pull_request : PullRequest, foreign_key: "pr_id", foreign_key_type: Int64

  def simplify
    {
      id:           id,
      pr_id:        pr_id,
      build_status: build_status,
      created_at:   created_at,
      updated_at:   updated_at,
      finished_at:  finished_at,
    }
  end

  def step_to_state
    case build_status
    when BuildStatus::Pending, BuildStatus::Running
      "pending"
    when BuildStatus::Complete
      "success"
    when BuildStatus::Failed
      "failure"
    end
  end

  def statuses_url
    URI.parse(pull_request.data["pull_request"]["statuses_url"].as_s)
  end

  # TODO: only send status if something changed
  def send_github_status(user : String, token : String, target_url : URI)
    description = "Nothing here yet..."

    body = {
      state:       step_to_state,
      target_url:  target_url.dup.tap { |url| url.path = "/build/#{id}" },
      description: description[0..138],
      context:     "Bitte CI",
    }

    Log.info &.emit("sending github status",
      state: body[:state],
      target_url: body[:target_url].to_s,
      description: body[:description])

    uri = statuses_url
    client = HTTP::Client.new(uri)
    client.basic_auth user, token
    res = client.post(
      uri.path,
      headers: HTTP::Headers{
        "Accept" => "application/vnd.github.v3+json",
      },
      body: body.to_json,
    )

    case res.status
    when HTTP::Status::CREATED
      res
    else
      Log.error {
        "HTTP Error while trying to POST github status to #{uri} : #{res.status.to_i} #{res.status_message}"
      }
    end
  rescue e : Socket::ConnectError
    Log.error &.emit(e.inspect, url: statuses_url.to_s)
  end
end

class Allocation
  include Clear::Model

  primary_key type: :uuid
  column created_at : Time
  column updated_at : Time
  column client_status : String
  column index : Int64
  column eval_id : UUID

  has_many outputs : Output, foreign_key: "alloc_id"

  def simplify
    outputs = Output.query.where { alloc_id == id }.select(:id, :size, :created_at, :alloc_id, :path, :mime).to_a
    {
      created_at:    created_at,
      updated_at:    updated_at,
      client_status: client_status,
      index:         index,
      eval_id:       eval_id,
      outputs:       outputs,
    }
  end
end

class Output
  include Clear::Model

  primary_key type: :uuid
  column data : Bytes
  column size : UInt64
  column created_at : Time
  column alloc_id : UUID
  column path : String
  column mime : String

  belongs_to allocation : Build, foreign_key: "alloc_id", foreign_key_type: UUID

  def inspect
    {id: id, created_at: created_at, alloc_id: alloc_id, size: size.humanize, path: path, mime: mime}.inspect
  end
end

# Convert from bytea column to Crystal's Bytes
class Clear::Model::Converter::BytesConverter
  def self.to_column(x : String | Bytes | Nil) : Bytes?
    case x
    in String
      x.to_slice
    in Bytes
      x
    in Nil
      nil
    end
  end

  def self.to_column(x)
    raise Clear::ErrorMessages.converter_error(x.class.name, "Bytes")
  end

  def self.to_db(x : Bytes?)
    x
  end
end

Clear::Model::Converter.add_converter("Bytes", Clear::Model::Converter::BytesConverter)
