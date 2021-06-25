require "kemal"
require "json"
require "clear"
require "./bitte_ci/*"
require "option_parser"

OPTIONS = {
  :db_url => ENV["DB_URL"]? || "postgres://postgres@127.0.0.1/bitte_ci",
}
action = BitteCI::Cmd::None

op = OptionParser.parse do |parser|
  parser.banner = "Usage: bitte-ci server"

  parser.on "-h", "--help", "Show this help" do
    puts parser
    exit
  end

  parser.on "--db=VALUE", "PostgreSQL URL" do |value|
    OPTIONS[:db_url] = value
  end

  parser.on "-s", "--server", "Start the webserver" do
    action = BitteCI::Cmd::Serve
  end

  parser.on "-m", "--migrate", "Migrate the DB" do
    action = BitteCI::Cmd::Migrate
  end

  parser.on "-q", "--queue", "queue the PR piped into stdin" do
    action = BitteCI::Cmd::Queue
  end

  parser.on "-l", "--listen", "Start nomad event listener" do
    action = BitteCI::Cmd::Queue
  end
end

module BitteCI
  enum Cmd
    None
    Serve
    Migrate
    Queue
    Listen
  end
end

case action
in BitteCI::Cmd::Queue
  job_template = {{ read_file("#{__DIR__}/../job.hcl") }}
  BitteCI::Runner.queue(job_template, JSON.parse(STDIN))
in BitteCI::Cmd::Migrate
  Clear::SQL.init(OPTIONS[:db_url])
  Clear::Migration::Manager.instance.apply_all
in BitteCI::Cmd::Serve
  Clear::SQL.init(OPTIONS[:db_url])
  BitteCI.start(
    github_user: ENV["GITHUB_USER"],
    github_token: ENV["GITHUB_TOKEN"],
  )
  Kemal.run port: 9494
in BitteCI::Cmd::Listen
  loki_url = URI.parse("http://127.0.0.1:4646/v1/event/stream")
  BitteCI::NomadEvents.listen(db_url: OPTIONS[:db_url], loki_url: loki_url)
in BitteCI::Cmd::None
  puts op
end
