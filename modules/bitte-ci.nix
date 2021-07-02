{ pkgs, lib, config, ... }:
let cfg = config.services.bitte-ci;
in {
  options = {
    services.bitte-ci = {
      enable = lib.mkEnableOption "Enable Bitte CI";

      dbUrl = lib.mkOption { type = lib.types.str; };

      nomadUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:4646";
      };

      frontendPath = lib.mkOption {
        type = lib.types.path;
        default = pkgs.bitte-ci-frontend;
      };

      githubusercontentUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://raw.githubusercontent.com";
      };
    };
  };

  config = lib.mkIf cfg.enable (let
    flags = builtins.toString (lib.cli.toGNUCommandLine { } {
      db-url = cfg.dbUrl;
      frontend-path = builtins.toString cfg.frontendPath;
      githubusercontent-url = cfg.githubusercontentUrl;
      nomad-url = cfg.nomadUrl;
    });
  in {
    systemd.services.bitte-ci-server = {
      description = "Basic server and frontend for the Bitte CI";
      after =
        [ "bitte-ci-migrate.service" "loki.service" "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ bitte-ci ];
      environment = {
        GITHUB_USER = "dummy";
        GITHUB_TOKEN = "dummy";
      };
      script = ''
        exec bitte-ci --server ${flags}
      '';
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
      path = with pkgs; [ bitte-ci ];
      script = ''
        exec bitte-ci --listen ${flags}
      '';
    };

    systemd.services.bitte-ci-migrate = {
      description = "Migrate the Bitte CI database";
      after = [ "postgresql.service" ];
      wantedBy = [
        "bitte-ci-listener.service"
        "bitte-ci-server.service"
        "multi-user.target"
      ];
      path = with pkgs; [ bitte-ci ];
      script = ''
        exec bitte-ci --migrate ${flags}
      '';
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
    };
  });
}
