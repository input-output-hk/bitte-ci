{ pkgs, lib, config, ... }:
let cfg = config.services.bitte-ci;
in {
  options = {
    services.bitte-ci = {
      enable = lib.mkEnableOption "Enable Bitte CI";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.bitte-ci;
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9494;
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
      };

      publicUrl = lib.mkOption { type = lib.types.str; };

      postgresUrl = lib.mkOption { type = lib.types.str; };

      nomadUrl = lib.mkOption { type = lib.types.str; };

      lokiUrl = lib.mkOption { type = lib.types.str; };

      nomadTokenFile = lib.mkOption { type = lib.types.str; };

      nomadSslCa = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      nomadSslKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      nomadSslCert = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      nomadDatacenters =
        lib.mkOption { type = lib.types.listOf lib.types.str; };

      githubHookSecretFile = lib.mkOption { type = lib.types.str; };

      githubTokenFile = lib.mkOption { type = lib.types.str; };

      githubUser = lib.mkOption { type = lib.types.str; };

      githubUserContentUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://raw.githubusercontent.com";
      };

      runnerFlake = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      artifactSecretFile = lib.mkOption { type = lib.types.str; };

      artifactDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/bitte-ci-server/artifacts";
      };

      _configJson = lib.mkOption {
        type = lib.types.path;
        default = builtins.toFile "config.json" (builtins.toJSON {
          host = cfg.host;
          port = cfg.port;
          public_url = cfg.publicUrl;
          postgres_url = cfg.postgresUrl;
          github_user_content_base_url = cfg.githubUserContentUrl;
          github_hook_secret_file = cfg.githubHookSecretFile;
          nomad_base_url = cfg.nomadUrl;
          loki_base_url = cfg.lokiUrl;
          github_token_file = cfg.githubTokenFile;
          github_user = cfg.githubUser;
          nomad_token_file = cfg.nomadTokenFile;
          nomad_datacenters = cfg.nomadDatacenters;
          runner_flake = cfg.runnerFlake;
          artifact_secret_file = cfg.artifactSecretFile;
          artifact_dir = cfg.artifactDir;
        });
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.bitte-ci-server = {
      description = "Basic server and frontend for the Bitte CI";
      after =
        [ "bitte-ci-migrate.service" "loki.service" "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ cue ];

      # environment.KEMAL_ENV = "production";

      serviceConfig = {
        ExecStart =
          "${cfg.package.server}/bin/bitte-ci-server -c ${cfg._configJson}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    systemd.services.bitte-ci-listener = {
      description = "Listen to Nomad events and update CI status";
      after = [
        "bitte-ci-migrate.service"
        "bitte-ci-server.service"
        "nomad.service"
        "postgresql.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart =
          "${cfg.package.listen}/bin/bitte-ci-listen -c ${cfg._configJson}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    systemd.services.bitte-ci-migrate = {
      description = "Migrate the Bitte CI database";
      after = [ "postgresql.service" ];
      wantedBy = [
        "bitte-ci-listener.service"
        "bitte-ci-server.service"
        "multi-user.target"
      ];
      script = "";

      serviceConfig = {
        ExecStart =
          "${cfg.package.migrate}/bin/bitte-ci-migrate -c ${cfg._configJson}";
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
