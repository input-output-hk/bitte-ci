{ pkgs, lib, config, ... }:
let cfg = config.services.bitte-ci;
in {
  options = {
    services.bitte-ci = {
      enable = lib.mkEnableOption "Enable Bitte CI";

      publicUrl = lib.mkOption { type = lib.types.str; };

      postgresUrl = lib.mkOption { type = lib.types.str; };

      nomadUrl = lib.mkOption { type = lib.types.str; };

      lokiUrl = lib.mkOption { type = lib.types.str; };

      frontendPath = lib.mkOption {
        type = lib.types.path;
        default = pkgs.bitte-ci-frontend;
      };

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
    };
  };

  config = lib.mkIf cfg.enable (let
    toFlags = f: builtins.toString (lib.cli.toGNUCommandLine { } f);

    flags = {
      public-url = cfg.publicUrl;
      postgres-url = cfg.postgresUrl;
      frontend-path = builtins.toString cfg.frontendPath;
      github-user-content-base-url = cfg.githubUserContentUrl;
      github-hook-secret-file = cfg.githubHookSecretFile;
      nomad-base-url = cfg.nomadUrl;
      loki-base-url = cfg.lokiUrl;
      github-token-file = cfg.githubTokenFile;
      github-user = cfg.githubUser;
      nomad-token-file = cfg.nomadTokenFile;
      nomad-datacenters = lib.concatStringsSep "," cfg.nomadDatacenters;
      runner-flake = cfg.runnerFlake;
    };

    certs = lib.optionalAttrs (cfg.nomadSslCa != null) {
      nomad-ssl-ca = cfg.nomadSslCa;
      nomad-ssl-key = cfg.nomadSslKey;
      nomad-ssl-cert = cfg.nomadSslCert;
    };

    listenFlags = toFlags ({
      inherit (flags) postgres-url nomad-base-url nomad-token-file public-url;
    } // certs);

    serverFlags = toFlags ({
      inherit (flags)
        postgres-url public-url github-user github-token-file frontend-path
        loki-base-url github-hook-secret-file github-user-content-base-url
        nomad-base-url nomad-token-file runner-flake nomad-datacenters;
    } // certs);

    migrateFlags = toFlags { inherit (flags) postgres-url; };
  in {
    systemd.services.bitte-ci-server = {
      description = "Basic server and frontend for the Bitte CI";
      after =
        [ "bitte-ci-migrate.service" "loki.service" "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ bitte-ci ];
      script = ''
        exec bitte-ci server ${serverFlags}
      '';

      serviceConfig = {
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
      path = with pkgs; [ bitte-ci ];
      script = ''
        exec bitte-ci listen ${listenFlags}
      '';

      serviceConfig = {
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
      path = with pkgs; [ bitte-ci ];
      script = ''
        exec bitte-ci migrate ${migrateFlags}
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  });
}
