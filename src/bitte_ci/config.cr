require "uri"

module BitteCI
  class Config
    annotation Option
    end

    @[Option(help: "Base URL under which this server is reachable e.g. http://example.com")]
    property public_url : URI

    @[Option(help: "PostgreSQL URL e.g. postgres://postgres@127.0.0.1:54321/bitte_ci")]
    property postgres_url : URI

    @[Option(help: "Base URL e.g. http://127.0.0.1:3100")]
    property loki_base_url : URI = URI.parse("http://127.0.0.1:4646")

    @[Option(help: "Base URL e.g. http://127.0.0.1:4646")]
    property nomad_base_url : URI

    @[Option(help: "Path to the bitte-ci-frontend directory")]
    property frontend_path : String

    @[Option(help: "Base URL e.g. https://raw.githubusercontent.com")]
    property github_user_content_base_url : URI

    @[Option(help: "The user for setting Github status")]
    property github_user : String

    @[Option(help: "The token for setting Github status")]
    property github_token : String

    @[Option(help: "Read the GitHub token from this file")]
    property github_token_file : Path?

    @[Option(help: "The secret set in your GitHub webhook")]
    property github_hook_secret : String

    @[Option(help: "Read the GitHub hook secret from this file")]
    property github_hook_secret_file : Path?

    @[Option(help: "Flake to use for promtail")]
    property promtail_flake : URI = URI.parse("github:NixOS/nixpkgs/nixos-21.05#grafana-loki")

    @[Option(help: "Nomad token used for job submission")]
    property nomad_token : String

    @[Option(help: "Read the Nomad token from this file")]
    property nomad_token_file : Path?

    @[Option(help: "CA cert used for talking with Nomad when using HTTPS")]
    property nomad_ssl_ca : String?

    @[Option(help: "Key used for talking with Nomad when using HTTPS")]
    property nomad_ssl_key : String?

    @[Option(help: "Cert used for talking with Nomad when using HTTPS")]
    property nomad_ssl_cert : String?

    def initialize(hash : Hash(String, String))
      {% for ivar in @type.instance_vars %}
        env = "BITTE_CI_{{ivar.id}}".upcase
        value = hash[{{ivar.id.stringify}}]? || ENV[env]?

        {% if ivar.has_default_value? %}
          value ||= {{ ivar.default_value }}
        {% end %}

        {% unless ivar.type.nilable? %}
          if value.nil?
            flag = "--{{ivar.id}}".tr("_", "-")
            raise "Missing config for {{ivar.id}}, please pass it as #{flag} or set environment variable #{env}"
          end
        {% end %}

        @{{ivar.id}} = convert(value, {{ivar.type}})
      {% end %}
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

    def self.generate_flags(parser, config)
      {% for ivar in @type.instance_vars %}
        {% ann = ivar.annotation(BitteCI::Config::Option) %}
        key = {{ ivar.id.stringify }}
        flag = key.tr("_", "-")

        parser.on "--#{flag}=VALUE", {{ann[:help]}} do |value|
          config[{{ivar.id.stringify}}] = value
        end
      {% end %}
    end

    def self.configure
      config = Hash(String, String).new
      yield(config)
      post_process(config)
      new(config)
    end

    def self.post_process(config)
      %w[github_hook_secret github_token nomad_token].each do |key|
        key_file = "#{key}_file"
        if !config[key]? && config[key_file]?
          config[key] = File.read(config[key_file]).strip
        end
      end
    end
  end

  enum Cmd
    None
    Serve
    Migrate
    Queue
    Listen
  end
end
