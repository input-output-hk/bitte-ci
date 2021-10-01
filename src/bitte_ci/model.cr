require "clear"
require "./uuid"
require "./line"
require "./github_hook"

Clear.enum BuildStatus, "pending", "running", "complete", "failed"

class PullRequest
  include Clear::Model

  primary_key type: :bigint
  column data : JSON::Any

  has_many builds : Build, foreign_key: "pr_id"

  @parsed : ::BitteCI::GithubHook::PullRequest?

  # TODO: Optimize this (see https://github.com/anykeyh/clear/issues/95 )!
  def parsed
    @parsed ||=
      ::BitteCI::GithubHook::PullRequest.from_json(pull_request.to_json)
  end

  def job_id
    "#{base["repo"]["full_name"]}##{number}-#{sha}"
  end

  # TODO: whittle down the data we actually want to send
  def simplify
    {id: id, data: data, builds: builds.order_by(:created_at, :desc).map(&.simplify)}
  end

  def pull_request
    data.dig("pull_request")
  end

  def base
    data.dig("pull_request", "base")
  end

  def head
    data.dig("pull_request", "head")
  end

  def ref
    data.dig("pull_request", "head", "ref").as_s
  end

  def head_repo_url
    data.dig("pull_request", "head", "repo", "html_url").as_s
  end

  def sha
    data.dig("pull_request", "head", "sha").as_s
  end

  def title
    data.dig("pull_request", "title").as_s
  end

  def user_login
    data.dig("pull_request", "user", "login").as_s
  end

  def user_url
    data.dig("pull_request", "user", "html_url").as_s
  end

  def base_url
    data.dig("pull_request", "base", "repo", "html_url").as_s
  end

  def base_name
    data.dig("pull_request", "base", "repo", "name").as_s
  end

  def number
    data.dig("pull_request", "number").as_i64
  end

  def org_avatar
    data.dig("organization", "avatar_url").as_s
  end

  def url
    data.dig("pull_request", "html_url").as_s
  end

  def created_at
    Time.parse_rfc3339(data.dig("pull_request", "created_at").as_s)
  end

  def created_at_relative
    span = Time.utc - created_at

    if span.total_days > 1
      "#{span.total_days.round(1)} days ago"
    elsif span.total_hours > 1
      "#{span.total_hours.round(1)} hours ago"
    elsif span.total_minutes > 1
      "#{span.total_minutes.round(1)} minutes ago"
    else
      "#{span.total_seconds.round(1)} seconds ago"
    end
  end

  def branch_url
    "#{head_repo_url}/tree/#{ref}"
  end

  def org_url
    "https://github.com/#{data["organization"]["login"]}"
  end

  def commit_url
    "#{head_repo_url}/commits/#{sha}"
  end

  def sha_short
    sha[0..7]
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
  column failed : Bool

  belongs_to pull_request : PullRequest, foreign_key: "pr_id", foreign_key_type: Int64
  has_many jobs : Job, foreign_key: "build_id"

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

  def url
    "/build/#{id}"
  end

  def statuses_url
    URI.parse(pull_request.data["pull_request"]["statuses_url"].as_s)
  end

  @parsed : ::BitteCI::GithubHook::PullRequest?

  # TODO: Optimize this (see https://github.com/anykeyh/clear/issues/95 )!
  def parsed
    @parsed ||=
      ::BitteCI::GithubHook::PullRequest.from_json(pull_request.to_json)
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
  column data : JSON::Any

  has_many outputs : Output, foreign_key: "alloc_id"
  belongs_to pull_request : PullRequest, foreign_key: "pr_id", foreign_key_type: Int64
  belongs_to job : Job, foreign_key: "job_id", foreign_key_type: UUID

  @parsed : ::BitteCI::Listener::AllocationPayload::Allocation?

  # TODO: Optimize this (see https://github.com/anykeyh/clear/issues/95 )!
  def parsed
    @parsed ||=
      ::BitteCI::Listener::AllocationPayload::Allocation.from_json(data.to_json)
  end

  def simplify
    outputs = Output.query.where { alloc_id == id }.select(:id, :size, :created_at, :alloc_id, :path, :mime).to_a
    {
      client_status: client_status,
      created_at:    created_at,
      eval_id:       eval_id,
      id:            id,
      index:         index,
      outputs:       outputs,
      updated_at:    updated_at,
    }
  end

  def statuses_url
    URI.parse(pull_request.data["pull_request"]["statuses_url"].as_s)
  end

  def status_to_state : String
    case client_status
    when BuildStatus::Pending, BuildStatus::Running
      "pending"
    when BuildStatus::Complete
      "success"
    else
      "failure"
    end
  end

  # TODO: only send status if something changed
  def send_github_status(user : String, token : String, target_url : URI)
    alloc = parsed
    pr = pull_request.parsed

    common = {
      user:       user,
      token:      token,
      state:      status_to_state,
      target_url: target_url,
    }

    description = "pending"

    case client_status
    when BuildStatus::Pending, BuildStatus::Running
      description = "builds pending"
    when BuildStatus::Complete
      description = "builds succeeded"
      alloc.task_states.try &.each do |name, state|
        next if state.failed

        pr.send_status(
          **common,
          description: "build succeeded",
          context: "Bitte CI - #{name}"
        )
      end
    else
      description = "builds failed"

      alloc.task_states.try &.each do |name, state|
        next unless state.failed

        pr.send_status(
          **common,
          description: "build failed",
          context: "Bitte CI - #{name}"
        )
      end
    end

    pr.send_status(
      **common,
      description: description,
      context: "Bitte CI"
    )
  end
end

class Output
  include Clear::Model

  primary_key type: :uuid
  column sha256 : String
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

class Job
  include Clear::Model

  primary_key type: :uuid
  column created_at : Time
  column updated_at : Time
  column data : JSON::Any

  belongs_to build : Build, foreign_key: "alloc_id", foreign_key_type: UUID
  has_many job_groups : JobGroup, foreign_key: "task_id"
  has_many evaluations : Evaluation, foreign_key: "job_id"

  @parsed : ::BitteCI::Listener::Job::JobPayload::Job?

  # TODO: Optimize this (see https://github.com/anykeyh/clear/issues/95 )!
  def parsed
    @parsed ||=
      ::BitteCI::Listener::Job::JobPayload::Job.from_json(data.to_json)
  end
end

class Evaluation
  include Clear::Model

  primary_key type: :uuid
  column job_id : String
  column status : String
  column created_at : Time
  column updated_at : Time
end

class JobGroup
  include Clear::Model

  primary_key type: :uuid
  column created_at : Time
  column updated_at : Time

  belongs_to job : Job, foreign_key: "job_id", foreign_key_type: UUID
  has_many tasks : Task, foreign_key: "job_group_id"
end

class Task
  include Clear::Model

  primary_key type: :uuid
  column created_at : Time
  column updated_at : Time
  column status : BuildStatus

  belongs_to job_group : JobGroup, foreign_key: "job_group_id", foreign_key_type: UUID
  has_many stdout : LogLine, foreign_key: "task_id"
  has_many stderr : LogLine, foreign_key: "task_id"
end

Clear.enum LogLineType, "stdout", "stderr"

class LogLine
  include Clear::Model

  primary_key type: :uuid
  column created_at : Time
  column data : String
  column type : LogLineType

  belongs_to task : Task, foreign_key: "task_id", foreign_key_type: UUID
end

class Node
  include Clear::Model

  primary_key type: :uuid
  column created_at : Time
  column updated_at : Time
  column data : JSON::Any

  @parsed : ::BitteCI::Listener::Node::NodePayload::Node?

  # TODO: Optimize this (see https://github.com/anykeyh/clear/issues/95 )!
  def parsed
    @parsed ||=
      ::BitteCI::Listener::Node::NodePayload::Node.from_json(data.to_json)
  end
end
