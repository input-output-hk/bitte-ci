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
        {% raise "Annotation for Option #{ivar.id} missing" unless ann %}
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

          {% if ivar.type.nilable? %}
            if %value.nil?
              @{{ivar.id}} = nil
            else
              @{{ivar.id}} = show_detailed_error({{ivar.stringify}}, %value.inspect) {
                %value.to_simple_option(
                  {{ivar.type.union_types.reject { |t| t == Nil }.join(" | ").id}}
                )
              }
            end
          {% else %}
            if %value.nil?
              raise(::SimpleConfig::Error.missing_flag(
                %hash_key,
                {{ann[:short]}},
                {{ann[:long]}} || {{ivar.id.tr("_", "-").stringify}},
                %env_key
              ))
            else
              case %value
              when {{ivar.type}}
                @{{ivar.id}} = %value
              else
                @{{ivar.id}} = show_detailed_error({{ivar.stringify}}, %value.inspect) {
                  %value.to_simple_option(
                    {{ivar.type}}
                  )
                }
              end
            end
          {% end %}
        {% end %}
      {% end %}
    end

    private def show_detailed_error(name, insp)
      yield
    rescue e : ArgumentError
      raise "While parsing the option #{name}, value was #{insp}: #{e.inspect}"
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
          %default_value = {{ ivar.default_value }}
          %help =
            if %default_value
              {{ann[:help]}} + " (default: #{%default_value})"
            else
              {{ann[:help]}}
            end

          if %short && %long
            parser.on "-#{%short}=VALUE", "--#{%long}=VALUE", %help do |value|
              config[{{ivar.id.stringify}}] = value
            end
          elsif %short
            parser.on "-#{%short}=VALUE", %help do |value|
              config[{{ivar.id.stringify}}] = value
            end
          elsif %long
            parser.on "--#{%long}=VALUE", %help do |value|
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
    def self.missing_flag(key : String, short : Char?, long : String?, env : String?)
      notice = ["Missing value for the option '#{key}'."]
      notice << "Please set it one of these ways:"
      notice << "in your config file with: '#{key}'"
      notice << "cli flag: '-#{short}'" if short
      notice << "cli flag: '--#{long}'" if long
      notice << "environment variable: '#{env}'" if env
      OptionParser::MissingOption.new(notice.join("\n"))
    end
  end
end

class URI
  def to_simple_option(k : URI.class)
    self
  end
end

class String
  def to_simple_option(k : Int64.class)
    to_i64
  end

  def to_simple_option(k : Array(String).class)
    if self[0]? == '['
      Array(String).from_json(self)
    else
      split(',')
    end
  end

  def to_simple_option(k : String.class)
    self
  end

  def to_simple_option(k : URI.class)
    URI.parse(self)
  end

  def to_simple_option(k : UInt64.class)
    to_u64
  end

  def to_simple_option(k : UUID.class)
    UUID.new(self)
  end

  def to_simple_option(k : Hash(String, String).class)
    if self[0]? == '{'
      Hash(String, String).from_json(self)
    else
      split(' ').map { |pair| pair.split("=") }.to_h
    end
  end
end
