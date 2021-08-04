require "clear"
require "./model"
require "./simple_config"

module BitteCI
  class Migrator
    struct Config
      include SimpleConfig::Configuration

      @[Option(help: "PostgreSQL URL e.g. postgres://postgres@127.0.0.1:54321/bitte_ci")]
      property postgres_url : URI

      @[Option(help: "migrate down this version number")]
      property down : Int64?
    end

    def self.run(config)
      Log.info { "Starting migration" }
      Clear::SQL.init(config.postgres_url.to_s)

      if down = config.down
        Log.info { "Migrating down version #{down}" }
        Clear::Migration::Manager.instance.down(down)
      else
        Log.info { "Migrating to latest version" }
        Clear::Migration::Manager.instance.apply_all
      end

      Log.info { "Migration successful" }
    end
  end
end

class Migration1
  include Clear::Migration

  def change(direction)
    create_enum :build_status_type, BuildStatus

    create_table :allocations, id: :uuid do |t|
      t.column :client_status, :string, null: false
      t.column :created_at, :timestamptz, null: false
      t.column :updated_at, :timestamptz, null: false
      t.column :index, :bigint, null: false
      t.column :eval_id, :uuid, null: false
    end

    create_table :pull_requests, id: :bigserial do |t|
      t.column :data, :jsonb, null: false
    end

    create_table :builds, id: :uuid do |t|
      t.column :build_status, :build_status_type
      t.column :created_at, :timestamptz, null: false
      t.column :updated_at, :timestamptz
      t.column :finished_at, :timestamptz
      t.column :loki_id, :uuid, null: false
      t.references to: "pull_requests", name: "pr_id", type: "bigserial", null: false, on_delete: :cascade
      t.index ["created_at"]
      t.index ["updated_at"]
      t.index ["finished_at"]
    end
  end
end

class Migration2
  include Clear::Migration

  def change(direction)
    create_table :outputs, id: :uuid do |t|
      t.column :path, :string, null: false
      t.column :data, :bytea, null: false
      t.column :size, :bigint, null: false
      t.column :created_at, :timestamptz, null: false
      t.column :mime, :string, null: false
      t.references to: "allocations", name: "alloc_id", type: "uuid", null: false, on_delete: :cascade
    end
  end
end

class Migration3
  include Clear::Migration

  def change(direction)
    drop_column "outputs", "data", "bytea"
    add_column "outputs", "sha256", "text", nullable: false
  end
end

class Migration4
  include Clear::Migration

  def change(direction)
    add_column "allocations", "data", "jsonb"
  end
end
