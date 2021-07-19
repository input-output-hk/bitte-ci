require "json"
require "uri"
require "option_parser"

module SimpleConfig
  module Configuration
    def initialize(hash : Hash(String, String), file : String?)
      json =
        if file
          JSON.parse(File.read(file))
        else
          JSON::Any.new({} of String => JSON::Any)
        end

      {% for ivar in @type.instance_vars %}
        {% ann = ivar.annotation(@type.constant("Option")) %}
        {% if ann && ann[:secret] %}
          %file_key = "{{ivar}}_file"
          %file_env_key = "{{ann[:env]}}_FILE" || %file_key.upcase
          %file = hash[%file_key]?
          %file = json[%file_key]?.try(&.as_s) if %file.nil?
          %file = ENV[%file_env_key]? if %file.nil? && %file_env_key
          hash[{{ivar.id.stringify}}] = File.read(%file) unless %file.nil?
        {% end %}
      {% end %}

      {% for ivar in @type.instance_vars %}
        {% ann = ivar.annotation(@type.constant("Option")) %}
        {% if ann %}
          %hash_key = {{ivar.id.stringify}}
          %env_key = {{ann[:env]}} || {{ivar.id.upcase.stringify}}

          %value = hash[%hash_key]?
          %value = json[%hash_key]?.try(&.as_s) if %value.nil?
          %value = ENV[%env_key]? if %value.nil? && %env_key
          %value = {{ ivar.default_value }} if %value.nil?

          {% unless ivar.type.nilable? %}
            if %value.nil?
              raise(::SimpleConfig::Error.missing_flag(
                %hash_key,
                {{ann[:short]}},
                {{ann[:long]}} || {{ivar.id.tr("_", "-").stringify}},
                %env_key
              ))
            end
          {% end %}

          @{{ivar.id}} = convert(%value, {{ivar.type}})
        {% end %}
      {% end %}
    end

    def convert(value : String, kind : Array(String).class)
      value.split(',')
    end

    def convert(value : String | Nil, kind : (String | Nil).class)
      value if value
    end

    def convert(value : String, kind : URI.class)
      URI.parse(value)
    end

    def convert(value : URI, kind : URI.class)
      value
    end

    def convert(value : String, kind : String.class)
      value
    end

    def convert(value : String | Nil, kind : (Path | Nil).class)
      Path.new(value) if value
    end

    macro included
      extend SimpleConfig::OptionParserFlags

      annotation Option
      end

      def self.configure
        hash = {} of String => String
        yield(hash)
        new(hash, nil)
      end
    end
  end

  module OptionParserFlags
    def option_parser(parser, config)
      {% for ivar in @type.instance_vars %}
        {% ann = ivar.annotation(@type.constant("Option")) %}
        {% if ann %}
          %secret = {{ann[:secret]}}
          %short = {{ann[:short]}}
          %long = {{ann[:long]}} || {{ivar.id.tr("_", "-").stringify}}

          if %short && %long
            parser.on "-#{%short}=VALUE", "--#{%long}=VALUE", {{ann[:help]}} do |value|
              config[{{ivar.id.stringify}}] = value
            end
          elsif %short
            parser.on "-#{%short}=VALUE", {{ann[:help]}} do |value|
              config[{{ivar.id.stringify}}] = value
            end
          elsif %long
            parser.on "--#{%long}=VALUE", {{ann[:help]}} do |value|
              config[{{ivar.id.stringify}}] = value
            end
          end

          if %secret
            parser.on "--#{%long}-file=VALUE", {{ann[:help]}} do |value|
              config["{{ivar}}_file"] = value
            end
          end
        {% end %}
      {% end %}
    end
  end

  class Error < ::Exception
    class MissingOption < Error; end

    def self.missing_flag(key : String, short : Char?, long : String?, env : String?)
      notice = ["Missing value for the option '#{key}'. Please set it one of these ways:"]
      notice << "in your config file with: '#{key}'"
      notice << "cli flag: '-#{short}'" if short
      notice << "cli flag: '--#{long}'" if long
      notice << "environment variable: '#{env}'" if env
      Error::MissingOption.new(notice.join("\n"))
    end
  end
end
