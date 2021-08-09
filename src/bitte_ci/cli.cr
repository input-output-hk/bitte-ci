require "./simple_config"
require "log"

module BitteCI
  def self.parse_options(*commands)
    return if ENV["BITTE_CI_SPEC"]?

    flags = {} of String => String
    config_file = "bitte_ci.json" if File.file?("bitte_ci.json")
    chosen = nil

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

      parser.on "-h", "--help", "Show this help" do
        puts parser
        exit
      end

      parser.on "-c=FILE", "--config=FILE", "Read config from the given file (default is ./bitte_ci.json)" do |value|
        config_file = value
      end

      commands.each do |config_type|
        parser.on config_type.command, config_type.help do
          chosen = config_type
          config_type.option_parser(config_type.command, parser, flags)
        end
      end
    end

    if commands.size == 1
      ARGV.unshift commands.first.command
    end

    argv = ARGV.dup
    op.parse(ARGV)

    if chosen
      run(argv, op, flags, config_file, chosen.not_nil!)
    else
      puts op
      exit 1
    end
  rescue e : OptionParser::MissingOption
    STDERR.puts e
    exit 1
  end

  def self.run(argv, parser : OptionParser, flags : Hash(String, String), config_file : String?, config_type)
    log = ::Log.for(config_type.command)

    config = config_type.new(flags, config_file)

    Signal::HUP.trap do
      log.info { "Received HUP, reloading configuration" }
      flags.clear
      parser.parse(argv.dup)
      config.reload(log, flags, config_file)
    end

    config.run(log)
  end
end
