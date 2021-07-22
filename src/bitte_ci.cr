require "kemal"
require "json"
require "clear"
require "option_parser"
require "./bitte_ci/*"

module BitteCI
  enum Cmd
    None
    Serve
    Migrate
    Queue
    Listen
    Artifice
  end

  def self.parse_options
    action = BitteCI::Cmd::None

    server_flags = {} of String => String
    queue_flags = {} of String => String
    migrate_flags = {} of String => String
    listen_flags = {} of String => String
    artifice_flags = {} of String => String

    config_file = "bitte_ci.json" if File.file?("bitte_ci.json")

    op = OptionParser.new do |parser|
      parser.banner = "Usage: bitte-ci server"

      parser.on "server", "Start the webserver" do
        action = BitteCI::Cmd::Serve
        BitteCI::Server::Config.option_parser(parser, server_flags)
      end

      parser.on "migrate", "Migrate the DB" do
        action = BitteCI::Cmd::Migrate
        BitteCI::Migrator::Config.option_parser(parser, migrate_flags)
      end

      parser.on "queue", "queue the PR piped into stdin or passed as argument" do
        action = BitteCI::Cmd::Queue
        BitteCI::Runner::Config.option_parser(parser, queue_flags)
      end

      parser.on "listen", "Start nomad event listener" do
        action = BitteCI::Cmd::Listen
        BitteCI::Listener::Config.option_parser(parser, listen_flags)
      end

      parser.on "artifice", "Store artifacts from an allocation" do
        action = BitteCI::Cmd::Artifice
        BitteCI::Artificer::Config.option_parser(parser, artifice_flags)
      end

      parser.on "-h", "--help", "Show this help" do
        puts parser
        exit
      end

      parser.on "-c=FILE", "--config=FILE", "Read config from the given file (default is ./bitte_ci.json)" do |value|
        config_file = value
      end
    end

    op.parse

    case action
    in BitteCI::Cmd::Serve
      Log.info { "Starting server" }
      server_config = BitteCI::Server::Config.new(server_flags, config_file)
      Clear::SQL.init(server_config.postgres_url.to_s)
      BitteCI::Server.start(server_config)
      Kemal.run port: 9494
    in BitteCI::Cmd::Migrate
      BitteCI::Migrator.run(BitteCI::Migrator::Config.new(migrate_flags, config_file))
    in BitteCI::Cmd::Queue
      Log.info { "Adding PR to job queue" }
      arg = ARGV[0]? ? File.read(ARGV[0]) : STDIN
      BitteCI::Runner.run(arg, BitteCI::Runner::Config.new(queue_flags, config_file))
    in BitteCI::Cmd::Listen
      Log.info { "Starting Nomad event listener" }
      BitteCI::Listener.listen(BitteCI::Listener::Config.new(listen_flags, config_file))
    in BitteCI::Cmd::Artifice
      Log.info { "Starting artificer" }
      BitteCI::Artificer.run(BitteCI::Artificer::Config.new(artifice_flags, config_file))
    in BitteCI::Cmd::None
      puts op
      exit 1
    end
  end
end

unless ENV["BITTE_CI_SPEC"]?
  BitteCI.parse_options
end
