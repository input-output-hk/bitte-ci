require "kemal"
require "json"
require "clear"
require "option_parser"
require "./bitte_ci/*"

# TODO: use config for all
config = BitteCI::Config.new(
  public_url: URI.parse(ENV["BITTE_CI_PUBLIC_URL"]? || "http://127.0.0.1:9292"),
  db_url: URI.parse(ENV["BITTE_CI_DB_URL"]? || "postgres://postgres@127.0.0.1/bitte_ci"),
  loki_url: URI.parse(ENV["BITTE_CI_LOKI_URL"]? || "http://127.0.0.1:3120"),
  nomad_url: URI.parse(ENV["BITTE_CI_NOMAD_URL"]? || "http://127.0.0.1:4646"),
  frontend_path: ENV["BITTE_CI_FRONTEND_DIR"]? || "result",
  githubusercontent_url: URI.parse(ENV["BITTE_CI_GITHUBUSERCONTENT_URL"]? || "https://raw.githubusercontent.com")
)

action = BitteCI::Cmd::None

op = OptionParser.parse do |parser|
  parser.banner = "Usage: bitte-ci server"

  parser.on "-h", "--help", "Show this help" do
    puts parser
    exit
  end

  parser.on "--db-url=VALUE", "PostgreSQL URL" do |value|
    config.db_url = URI.parse(value)
  end

  parser.on "--loki-url=VALUE", "Loki URL" do |value|
    config.loki_url = URI.parse(value)
  end

  parser.on "--frontend-path=VALUE", "Path to the frontend directory" do |value|
    config.frontend_path = value
  end

  parser.on "--githubusercontent-url=VALUE", "Domain to fetch ci.cue from" do |value|
    config.githubusercontent_url = URI.parse(value)
  end

  parser.on "--nomad-url=VALUE", "Domain that nomad runs on" do |value|
    config.nomad_url = URI.parse(value)
  end

  parser.on "--server", "Start the webserver" do
    action = BitteCI::Cmd::Serve
  end

  parser.on "--migrate", "Migrate the DB" do
    action = BitteCI::Cmd::Migrate
  end

  parser.on "--queue", "queue the PR piped into stdin or passed as argument" do
    action = BitteCI::Cmd::Queue
  end

  parser.on "--listen", "Start nomad event listener" do
    action = BitteCI::Cmd::Listen
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

  class Config
    property public_url : URI
    property db_url : URI
    property loki_url : URI
    property nomad_url : URI
    property githubusercontent_url : URI
    property frontend_path : String

    def initialize(
      @public_url : URI,
      @db_url : URI,
      @loki_url : URI,
      @nomad_url : URI,
      @githubusercontent_url : URI,
      @frontend_path : String
    )
    end
  end
end

puts "starting #{action}"

case action
in BitteCI::Cmd::Queue
  arg = ARGV[0]? ? File.read(ARGV[0]) : STDIN
  BitteCI::Runner.run(arg, config)
in BitteCI::Cmd::Migrate
  Clear::SQL.init(config.db_url.to_s)
  Clear::Migration::Manager.instance.apply_all
in BitteCI::Cmd::Serve
  Clear::SQL.init(config.db_url.to_s)
  BitteCI.start(
    config: config,
    github_user: ENV["GITHUB_USER"],
    github_token: ENV["GITHUB_TOKEN"],
  )
  Kemal.run port: 9494
in BitteCI::Cmd::Listen
  BitteCI::NomadEvents.listen(config)
in BitteCI::Cmd::None
  puts op
end
