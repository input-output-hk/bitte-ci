require "kemal"
require "json"
require "db"
require "pg"

db_url = "postgres://postgres@127.0.0.1/bitte_ci"

channels = [] of Channel(Job)

GITHUB_USER  = ENV["GITHUB_USER"]
GITHUB_TOKEN = ENV["GITHUB_TOKEN"]

class Job
  include JSON::Serializable

  property id : UUID
  property created_at : Time
  property updated_at : Time
  property step : String
  property link : String
  property avatar : String
  property login : String
  property sender_url : String
  property head_label : String
  property head_ref : String
  property status_url : String

  def initialize(rs : PG::ResultSet)
    @id = rs.read(UUID)
    @created_at = rs.read(Time)
    @updated_at = rs.read(Time)
    @step = rs.read(String)
    @link = rs.read(String)
    @avatar = rs.read(String)
    @login = rs.read(String)
    @sender_url = rs.read(String)
    @head_label = rs.read(String)
    @head_ref = rs.read(String)
    @status_url = rs.read(String)
  end

  def target_url
    "http://127.0.0.1:3120/job/#{id}"
  end

  def step_to_state
    case step
    when "received", "pending", "queued", "running"
      "pending"
    when "complete"
      "success"
    when "failed"
      "failure"
    else
      pp! "Unknown step: #{step}"
      "error"
    end
  end

  def send_github_status
    description = "Nothing here yet..."
    body = {
      state:       step_to_state,
      target_url:  target_url,
      description: description[0..138],
      context:     "Bitte CI",
    }

    uri = URI.parse(status_url)
    client = HTTP::Client.new(uri)
    client.basic_auth GITHUB_USER, GITHUB_TOKEN
    response = client.post(
      uri.path,
      headers: HTTP::Headers{
        "Accept" => "application/vnd.github.v3+json",
      },
      body: body.to_json,
    )

    if response.status != HTTP::Status::CREATED
      pp! response
    end
  end
end

PG.connect_listen db_url, "events" do |n|
  job = Job.from_json(n.payload)
  job.send_github_status
  channels.each do |channel|
    channel.send job
  end
end

class Msg
  include JSON::Serializable

  property channel : String
  property uuid : UUID?
end

struct UUID
  def self.new(pull : JSON::PullParser)
    new pull.read_string
  end

  def to_json(builder : JSON::Builder)
    builder.string to_s
  end
end

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

DB.open(db_url) do |db|
  db.exec <<-SQL
    CREATE TABLE IF NOT EXISTS events (
      id UUID PRIMARY KEY,
      created_at TIMESTAMP WITH TIME ZONE NOT NULL,
      updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
      step TEXT NOT NULL,
      payload JSON NOT NULL
    );
  SQL

  db.exec <<-SQL
    CREATE OR REPLACE FUNCTION table_update_notify() RETURNS trigger AS $BODY$
    DECLARE
      rec RECORD;
    BEGIN
      CASE TG_OP
      WHEN 'INSERT', 'UPDATE' THEN
        rec := NEW;
      WHEN 'DELETE', 'TRUNCATE' THEN
        rec := OLD;
      ELSE
        RAISE EXCEPTION 'Unknown TG_OP: "%"', TG_OP;
      END CASE;
      PERFORM pg_notify('events', json_build_object(
        'op', TG_OP,
        'table', TG_TABLE_NAME,
        'created_at', to_json(rec.created_at),
        'updated_at', to_json(rec.updated_at),
        'step',       to_json(rec.step),
        'id',         to_json(rec.id),
        'link',       to_json(rec.payload#>>'{pull_request, _links, html, href}'),
        'avatar',     to_json(rec.payload#>>'{sender, avatar_url}'),
        'login',      to_json(rec.payload#>>'{sender, login}'),
        'sender_url', to_json(rec.payload#>>'{sender, html_url}'),
        'head_label', to_json(rec.payload#>>'{pull_request, head, label}'),
        'head_ref',   to_json(rec.payload#>>'{pull_request, head, ref}'),
        'status_url', to_json(rec.payload#>>'{pull_request, statuses_url}')
      )::text);
      RETURN NEW;
    END;
    $BODY$ LANGUAGE plpgsql VOLATILE COST 100;
  SQL

  db.transaction do
    db.exec "DROP TRIGGER IF EXISTS mytable_notify on events;"
    db.exec "DROP TRIGGER IF EXISTS events_notify on events;"

    db.exec <<-SQL
      CREATE TRIGGER events_notify
      AFTER INSERT OR UPDATE OR DELETE
      ON events
      FOR EACH ROW EXECUTE PROCEDURE table_update_notify();
    SQL
  end

  get "/" do
    "Hello World!"
  end

  ws "/ci/api/v1/socket" do |socket|
    channel = Channel(Job).new
    channels.push channel

    fiber = spawn do
      while value = channel.receive?
        socket.send({type: "job", event: value}.to_json)
      end
    end

    socket.on_message do |message|
      msg = Msg.from_json(message)

      case msg.channel
      when "logs"
        pp! :logs
        query = URI::Params.new(
          {
            "direction" => ["FORWARD"],
            "query"     => [%({nomad_group_name="#{msg.uuid}"})],
            "start"     => [((Time.utc - 24.hours).to_unix_ms * 1000000).to_s],
            "end"       => [(Time.utc.to_unix_ms * 1000000).to_s],
          }
        )

        res = HTTP::Client.get("http://127.0.0.1:3120/loki/api/v1/query_range?" + query.to_s)

        begin
          dec = LokiQueryRange.from_json(res.body)
          dec.data.result.each do |result|
            pp! result
            next if result.stream["filename"] =~ /promtail\./
            processed = result.values.map do |line|
              time, text = line[0], line[1]
              [Time.unix_ms((time.to_i64 / 1000000).to_i64), text]
            end
            socket.send({type: "logs", logs: processed}.to_json)
          end
        rescue e : JSON::ParseException
          pp! e
          pp! res.body
          sleep 1
        end
      when "jobs"
        recent_jobs = <<-SQL
          SELECT
            id,
            created_at,
            updated_at,
            step,
            payload#>>'{pull_request, _links, html, href}',
            payload#>>'{sender, avatar_url}',
            payload#>>'{sender, login}',
            payload#>>'{sender, html_url}',
            payload#>>'{pull_request, head, label}',
            payload#>>'{pull_request, head, ref}',
            payload#>>'{pull_request, statuses_url}'
          FROM events
          WHERE (created_at >= $1) AND (created_at <= $2)
          ORDER BY updated_at DESC
        SQL

        jobs = [] of Job

        db.query(recent_jobs, Time.utc - 24.hours, Time.utc) do |rs|
          rs.each do
            jobs.push(Job.new(rs))
          end
        end

        socket.send({type: "jobs", jobs: jobs}.to_json)
      end
    end

    socket.on_close do
      channels.delete channel
      channel.close
    end
  end

  Kemal.run port: 9494
end
