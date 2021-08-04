require "./simple_config"
require "log"

module BitteCI
  def self.parse_options(name, config_class)
    return if ENV["BITTE_CI_SPEC"]?

    flags = {} of String => String
    config_file = "bitte_ci.json" if File.file?("bitte_ci.json")

    op = OptionParser.new do |parser|
      parser.banner = "Usage: bitte-ci-#{name}"

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

      config_class.option_parser(parser, flags)
    end

    op.parse

    ::Log.builder.bind "clear.*", Log::Severity::Debug, Log::IOBackend.new
    ::Log.for(name).info { "Starting" }
    yield(config_class.new(flags, config_file))
  rescue e : OptionParser::MissingOption
    STDERR.puts e
    exit 1
  end
end
