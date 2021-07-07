require "kemal"
require "json"
require "clear"
require "option_parser"
require "./bitte_ci/*"

def parse_options
  action = BitteCI::Cmd::None

  final_config = BitteCI::Config.configure do |config|
    OptionParser.parse do |parser|
      parser.banner = "Usage: bitte-ci server"

      parser.on "server", "Start the webserver" do
        action = BitteCI::Cmd::Serve
      end

      parser.on "migrate", "Migrate the DB" do
        action = BitteCI::Cmd::Migrate
      end

      parser.on "queue", "queue the PR piped into stdin or passed as argument" do
        action = BitteCI::Cmd::Queue
      end

      parser.on "listen", "Start nomad event listener" do
        action = BitteCI::Cmd::Listen
      end

      parser.on "-h", "--help", "Show this help" do
        puts parser
        exit
      end

      BitteCI::Config.generate_flags(parser, config)
    end
  end

  return {action, final_config}
end

unless ENV["BITTE_CI_SPEC"]?
  action, config = parse_options

  case action
  in BitteCI::Cmd::Serve
    Log.info { "Starting server" }
    Clear::SQL.init(config.postgres_url.to_s)
    BitteCI.start(config: config)
    Kemal.run port: 9494
  in BitteCI::Cmd::Migrate
    Log.info { "Starting migration" }
    Clear::SQL.init(config.postgres_url.to_s)
    Clear::Migration::Manager.instance.apply_all
    Log.info { "Migration successful" }
  in BitteCI::Cmd::Queue
    Log.info { "Adding PR to job queue" }
    arg = ARGV[0]? ? File.read(ARGV[0]) : STDIN
    BitteCI::Runner.run(arg, config)
  in BitteCI::Cmd::Listen
    Log.info { "Starting Nomad event listener" }
    BitteCI::NomadEvents.listen(config)
  in BitteCI::Cmd::None
    raise "Please specify an action: server | migrate | queue | listen"
  end
end
