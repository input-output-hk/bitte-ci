{ pkgs, ... }: {
  config.services = {
    loki = let
      config = builtins.toFile "loki.json" (builtins.toJSON {
        auth_enabled = false;
        ingester = {
          chunk_idle_period = "5m";
          chunk_retain_period = "30s";
          lifecycler = {
            address = "127.0.0.1";
            final_sleep = "0s";
            ring = {
              kvstore = { store = "inmemory"; };
              replication_factor = 1;
            };
          };
        };
        limits_config = {
          enforce_metric_name = false;
          ingestion_burst_size_mb = 160;
          ingestion_rate_mb = 160;
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };
        schema_config = {
          configs = [{
            from = "2020-05-15";
            index = {
              period = "168h";
              prefix = "index_";
            };
            object_store = "filesystem";
            schema = "v11";
            store = "boltdb";
          }];
        };
        server = { http_listen_port = 3100; };
        storage_config = {
          boltdb = { directory = "/var/lib/loki/index"; };
          filesystem = { directory = "/var/lib/loki/chunks"; };
        };
        table_manager = {
          retention_deletes_enabled = true;
          retention_period = "350d";
        };
      });
    in {
      service.useHostStore = true;
      service.command =
        [ "${pkgs.grafana-loki}/bin/loki" "--config.file=${./loki.json}" ];
      service.ports = [ "3100:3100" ];
    };

    reproxy = let
      config = builtins.toFile "reproxy.yml" (builtins.toJSON {
        default = [
          {
            route = "^/loki/api/v1/query_range";
            dest = "http://127.0.0.1:3100/loki/api/v1/query_range";
          }
          {
            route = "^/loki/api/v1/label/(.+)/values";
            dest = "http://127.0.0.1:3100/loki/api/v1/label/$1/values";
          }
          {
            route = "^/ci/api/v1/(.*)";
            dest = "http://127.0.0.1:9494/ci/api/v1/$1";
          }
          {
            route = "^/(.*)";
            dest = "http://127.0.0.1:3000/$1";
          }
        ];
      });
    in {
      service.useHostStore = true;
      service.command = [
        "${pkgs.reproxy}/bin/reproxy"
        "--listen"
        "0.0.0.0:3120"
        "--file.enabled"
        "--file.name=${config}"
        "--error.enabled"
        "--logger.enabled"
        "--logger.stdout"
      ];
      service.network_mode = "host";
    };

    trigger = {
      service.useHostStore = true;
      service.command = [
        "${pkgs.trigger}/bin/trigger"
        "--config"
        (builtins.toFile "trigger.yml" pkgs.triggerConfig)
      ];

      service.environment = { TRIGGER_LOG = "debug"; };
      service.ports = [ "3132:3130" ];
    };

    postgres = let
      hba = pkgs.writeText "pg_hba.conf" ''
        local all all trust
        host all all 0.0.0.0/0 trust
      '';
      ident = pkgs.writeText "pg_ident.conf" "";
      pgconf = pkgs.writeText "postgresql.conf" ''
        hba_file = '${hba}'
        ident_file = '${ident}'
        log_destination = 'stderr'
        log_line_prefix = '[%p] '
        unix_socket_directories = '/run/postgresql'
        listen_addresses = '0.0.0.0'
        max_locks_per_transaction = 1024
      '';
    in {
      service.useHostStore = true;
      service.command = [
        (pkgs.writeShellScript "entrypoint" ''
          set -exuo pipefail

          echo postgres:x:71:71:postgres user:/:/bin/sh >> /etc/passwd
          echo postgres:x:71:postgres >> /etc/group

          # fix for popen failure: Cannot allocate memory
          mkdir -p /bin
          ln -sfn ${pkgs.bashInteractive}/bin/bash /bin/sh

          mkdir -p "$PGDATA"
          chmod -R 0777 "$PGDATA"
          chown -R postgres:postgres "$PGDATA"

          if [ ! -s "$PGDATA/PG_VERSION" ]; then
            su - postgres -c "${pkgs.postgresql}/bin/initdb -D '$PGDATA'"
          fi

          ln -sfn ${pgconf} "$PGDATA/postgresql.conf"
          exec su - postgres -c "${pkgs.postgresql}/bin/postgres -D '$PGDATA'"
        '')
      ];

      service.environment = {
        PATH = pkgs.lib.makeBinPath (with pkgs; [
          busybox
          coreutils
          findutils
          gnugrep
          gnused
          postgresql
          strace
          bashInteractive
        ]);
        PGDATA = "/run/postgresql";
        LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
      };
      # service.network_mode = "host";
      service.ports = [ "5432:5432" ];
    };
  };
}
