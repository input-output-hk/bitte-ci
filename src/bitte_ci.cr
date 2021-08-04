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
    Command
    Prepare
  end

  def self.parse_options
    action = BitteCI::Cmd::None

    flags = {} of String => String
    config_file = "bitte_ci.json" if File.file?("bitte_ci.json")

    op = OptionParser.new do |parser|
      parser.banner = "Usage: bitte-ci"

      parser.invalid_option do |opt|
        puts parser
        puts
        STDERR.puts "Option invalid: #{opt}"
        parser.stop
        exit 1
      end

      parser.missing_option do |opt|
        puts parser
        puts
        STDERR.puts "Option missing: #{opt}"
        parser.stop
        exit 1
      end

      parser.on "server", "Start the webserver" do
        parser.banner = "Usage: bitte-ci"
        action = BitteCI::Cmd::Serve
        BitteCI::Server::Config.option_parser(parser, flags)
      end

      parser.on "migrate", "Migrate the DB" do
        parser.banner = "Usage: bitte-ci migrate"
        action = BitteCI::Cmd::Migrate
        BitteCI::Migrator::Config.option_parser(parser, flags)
      end

      parser.on "queue", "queue the PR piped into stdin or passed as argument" do
        parser.banner = "Usage: bitte-ci queue"
        action = BitteCI::Cmd::Queue
        BitteCI::Runner::Config.option_parser(parser, flags)
      end

      parser.on "listen", "Start nomad event listener" do
        parser.banner = "Usage: bitte-ci listen"
        action = BitteCI::Cmd::Listen
        BitteCI::Listener::Config.option_parser(parser, flags)
      end

      parser.on "command", "Executor for steps within Nomad" do
        parser.banner = "Usage: bitte-ci command"
        action = BitteCI::Cmd::Command
        BitteCI::Commander::Config.option_parser(parser, flags)
      end

      parser.on "prepare", "Prepare the repository in /alloc" do
        parser.banner = "Usage: bitte-ci prepare"
        action = BitteCI::Cmd::Prepare
        BitteCI::Preparator::Config.option_parser(parser, flags)
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
      ::Log.builder.bind "clear.*", Log::Severity::Debug, Log::IOBackend.new
      Log.info { "Starting server" }
      server_config = BitteCI::Server::Config.new(flags, config_file)
      Clear::SQL.init(server_config.postgres_url.to_s)
      BitteCI::Server.start(server_config)
      Kemal.run port: 9494
    in BitteCI::Cmd::Migrate
      BitteCI::Migrator.run(BitteCI::Migrator::Config.new(flags, config_file))
    in BitteCI::Cmd::Queue
      Log.info { "Adding PR to job queue" }
      arg = ARGV[0]? ? File.read(ARGV[0]) : STDIN
      BitteCI::Runner.run(arg, BitteCI::Runner::Config.new(flags, config_file))
    in BitteCI::Cmd::Listen
      Log.info { "Starting Nomad event listener" }
      BitteCI::Listener.listen(BitteCI::Listener::Config.new(flags, config_file))
    in BitteCI::Cmd::Command
      BitteCI::Commander.run(BitteCI::Commander::Config.new(flags, config_file))
    in BitteCI::Cmd::Prepare
      BitteCI::Preparator.run(BitteCI::Preparator::Config.new(flags, config_file))
    in BitteCI::Cmd::None
      puts op
      exit 1
    end
  rescue e : OptionParser::MissingOption
    STDERR.puts e
    exit 1
  end
end

unless ENV["BITTE_CI_SPEC"]?
  BitteCI.parse_options
end
