require "json"
require "uri"
require "option_parser"

module SimpleConfig
  module Configuration
    def initialize(hash : Hash(String, String), file : String?)
      json = load_json(file)
      prepare_secrets(hash, json)

      # TODO: remove duplication, make sure you keep this in sync with
      # reload_config
      {% for ivar in @type.instance_vars %}
        {% ann = ivar.annotation(@type.constant("Option")) %}
        {% if ann %}
          %hash_key = {{ivar.id.stringify}}
          %env_key = {{ann[:env]}} || {{ivar.id.upcase.stringify}}

          %value = hash[%hash_key]?
          %value = json[%hash_key]? if %value.nil?
          %value = ENV[%env_key]? if %value.nil? && %env_key
          %value = {{ivar.default_value}} if %value.nil?

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
                {{@type.id}},
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
                  ).not_nil!
                }
              end
            end
          {% end %}
        {% end %}
      {% end %}
    end

    def load_json(file)
      if file
        JSON.parse(File.read(file))
      else
        JSON::Any.new({} of String => JSON::Any)
      end
    end

    def reload(log, hash : Hash(String, String), file : String?)
      json = load_json(file)
      prepare_secrets(hash, json)
      reload_config(log, hash, json)
    end

    def prepare_secrets(hash, json)
      {% for ivar in @type.instance_vars %}
        {% ann = ivar.annotation(@type.constant("Option")) %}
        {% raise "Annotation for Option #{ivar} missing" unless ann %}
        {% if ann && ann[:secret] %}
          %file_key = "{{ivar}}_file"
          %file_env_key = "{{ann[:env]}}_FILE" || %file_key.upcase
          %file = hash[%file_key]?
          %file = json[%file_key]?.try(&.as_s) if %file.nil?
          %file = ENV[%file_env_key]? if %file.nil? && %file_env_key
          hash[{{ivar.stringify}}] = File.read(%file).strip unless %file.nil?
        {% end %}
      {% end %}
    end

    # TODO: remove duplication, make sure you keep this in sync with initialize
    # We can safely ignore changes to env variable and flags, so we only
    # consider changes to the config file(s).
    def reload_config(log, hash, json)
      {% for ivar in @type.instance_vars %}
        {% ann = ivar.annotation(@type.constant("Option")) %}
        {% if ann %}
          %old = @{{ivar.id}}

          %value = hash[{{ivar.id.stringify}}]?
          %value = json[{{ivar.id.stringify}}]?.try(&.as_s) if %value.nil?

          {% if ivar.type.nilable? %}
            @{{ivar.id}} = unless %value.nil?
              show_detailed_error({{ivar.stringify}}, %value.inspect) {
                %type = {{ivar.type.union_types.reject { |t| t == Nil }.join(" | ").id}}
                %value.to_simple_option(%type)
              }
            end
          {% else %}
            @{{ivar.id}} =
              case %value
              when Nil
                %old
              when {{ivar.type}}
                %value
              else
                show_detailed_error({{ivar.stringify}}, %value.inspect) {
                  %value.to_simple_option({{ivar.type}})
                }
              end
          {% end %}

          if %old != @{{ivar.id}}
            {% if ann[:secret] %}
              log.info { "Reloaded config {{ivar.id}}: <redacted> => <redacted>" }
            {% else %}
              log.info { "Reloaded config {{ivar.id}}: #{%old} => #{@{{ivar.id}}}" }
            {% end %}
          end
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
    def option_parser(command, parser, config)
      parser.banner = "Usage: bitte-ci #{command}"

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
            parser.on "--#{%long}-file=VALUE", %help do |value|
              config["{{ivar}}_file"] = value
            end
          end
        {% end %}
      {% end %}
    end
  end

  class Error < ::Exception
    def self.missing_flag(type, key : String, short : Char?, long : String?, env : String?)
      notice = ["Missing value for the #{type} option '#{key}'."]
      notice << "Please set it one of these ways:"
      notice << "in your config file with: '#{key}'"
      notice << "cli flag: '-#{short}'" if short
      notice << "cli flag: '--#{long}'" if long
      notice << "environment variable: '#{env}'" if env
      OptionParser::MissingOption.new(notice.join("\n"))
    end
  end
end

struct JSON::Any
  def to_simple_option(k : String.class) : String
    as_s? || raise ArgumentError.new("Couldn't parse #{inspect} as #{k}")
  end

  def to_simple_option(k : Array(String).class) : Array(String)
    as_a?.try &.map(&.as_s) || raise ArgumentError.new("Couldn't parse #{inspect} as #{k}")
  end

  def to_simple_option(k : Hash(String, String).class) : Hash(String, String)
    as_h?.try &.transform_values(&.as_s) || raise ArgumentError.new("Couldn't parse #{inspect} as #{k}")
  end

  def to_simple_option(k : UInt64.class) : UInt64
    as_i64?.try &.to_u64 || raise ArgumentError.new("Couldn't parse #{inspect} as #{k}")
  end

  def to_simple_option(k : URI.class) : URI
    s = as_s? || raise ArgumentError.new("Couldn't parse #{inspect} as #{k}")
    (URI.parse(s) if s) || raise ArgumentError.new("Couldn't parse #{inspect} as #{k}")
  end

  def to_simple_option(k : UUID.class) : UUID
    s = as_s? || raise ArgumentError.new("Couldn't parse #{inspect} as #{k}")
    (UUID.new(s) if s) || raise ArgumentError.new("Couldn't parse #{inspect} as #{k}")
  end

  def to_simple_option(k : Int64.class) : Int64
    as_i64? || raise ArgumentError.new("Couldn't parse #{inspect} as #{k}")
  end

  def to_simple_option(k : Int32.class) : Int32
    as_i? || raise ArgumentError.new("Couldn't parse #{inspect} as #{k}")
  end
end

class URI
  def to_simple_option(k : URI.class) : URI
    self
  end
end

class String
  def to_simple_option(k : Int32.class) : Int32
    to_i32
  end

  def to_simple_option(k : UInt32.class) : UInt32
    to_u32
  end

  def to_simple_option(k : Int64.class) : Int64
    to_i64
  end

  def to_simple_option(k : Array(String).class) : Array(String)
    if self[0]? == '['
      Array(String).from_json(self)
    else
      split(',')
    end
  end

  def to_simple_option(k : String.class) : String
    self
  end

  def to_simple_option(k : URI.class) : URI
    URI.parse(self)
  end

  def to_simple_option(k : UInt64.class) : UInt64
    to_u64
  end

  def to_simple_option(k : UUID.class) : UUID
    UUID.new(self)
  end

  def to_simple_option(k : Hash(String, String).class) : Hash(String, String)
    if self[0]? == '{'
      Hash(String, String).from_json(self)
    else
      split(' ').map(&.split("=")).to_h
    end
  end
end
