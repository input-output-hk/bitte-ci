require "./simple_config"

module BitteCI
  class Migrator
    struct Config
      include SimpleConfig::Configuration

      @[Option(help: "PostgreSQL URL e.g. postgres://postgres@127.0.0.1:54321/bitte_ci")]
      property postgres_url : URI
    end

    def self.run(config)
      Log.info { "Starting migration" }
      Clear::SQL.init(migrate_config.postgres_url.to_s)
      Clear::Migration::Manager.instance.apply_all
      Log.info { "Migration successful" }
    end
  end
end
