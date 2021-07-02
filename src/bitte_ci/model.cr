require "clear"
require "./uuid"

Clear.enum BuildStatus, "pending", "running", "complete", "failed"

class PullRequest
  include Clear::Model

  primary_key type: :bigint
  column data : JSON::Any

  # belongs_to project : Project, foreign_key: "project_id", foreign_key_type: UUID

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
      target_url:  target_url.dup.tap { |url| url.path = "/job/#{id}" },
      description: description[0..138],
      context:     "Bitte CI",
    }

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
      raise "HTTP Error while trying to POST github status to #{uri} : #{res.status.to_i} #{res.status_message}"
    end
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
end

class Migration1
  include Clear::Migration

  def change(direction)
    create_enum :build_status_type, BuildStatus

    create_table :allocations, id: :uuid do |t|
      t.column :client_status, :string, null: false
      t.column :created_at, :timestamptz, null: false
      t.column :updated_at, :timestamptz, null: false
      t.column :index, :bigint, null: false
      t.column :eval_id, :uuid, null: false
    end

    # create_table :projects, id: :uuid do |t|
    #   t.column :name, :string, null: false, unique: true
    #   t.column :created_at, :timestamptz, null: false
    #   t.column :updated_at, :timestamptz
    #   t.index ["created_at"]
    #   t.index ["updated_at"]
    # end

    create_table :pull_requests, id: :bigserial do |t|
      t.column :data, :jsonb, null: false
      # t.references to: "projects", name: "project_id", type: "uuid", null: false, on_delete: :cascade
    end

    create_table :builds, id: :uuid do |t|
      t.column :build_status, :build_status_type
      t.column :created_at, :timestamptz, null: false
      t.column :updated_at, :timestamptz
      t.column :finished_at, :timestamptz
      t.column :loki_id, :uuid, null: false
      t.references to: "pull_requests", name: "pr_id", type: "bigserial", null: false, on_delete: :cascade
      t.index ["created_at"]
      t.index ["updated_at"]
      t.index ["finished_at"]
    end
  end
end
