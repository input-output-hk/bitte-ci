{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";
    bitte.url = "github:input-output-hk/bitte";
    rust = {
      url = "github:input-output-hk/rust.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    trigger-source = {
      url = "github:RedL0tus/trigger";
      flake = false;
    };
    arion.url = "github:hercules-ci/arion";
  };

  outputs = { self, nixpkgs, rust, bitte, trigger-source, arion }@inputs:
    let
      overlay = final: prev: {
        nomad = bitte.legacyPackages.x86_64-linux.nomad;

        bitte-ci-env = prev.symlinkJoin {
          name = "bitte-ci-env";
          paths = with prev; [ bashInteractive cacert coreutils gitMinimal ];
        };

        bitte-ci = prev.callPackage ./pkgs/bitte-ci {};

        arion = arion.defaultPackage.x86_64-linux;

        trigger = prev.callPackage ./pkgs/trigger { src = trigger-source; };

        reproxy = prev.callPackage ./pkgs/reproxy { };

        ngrok = prev.callPackage ./pkgs/ngrok { };

        triggerConfig = builtins.toJSON {
          settings = {
            host = "0.0.0.0:3132";
            secret = "oos0kahquaiNaiciz8MaeHohNgaejien";
            print_commands = false;
            capture_output = false;
            exit_on_error = false;
            kotomei = false;
          };

          events = {
            common = ''
              set -euo pipefail

              PAYLOAD='{payload}'

              function field {
                echo $(echo "$PAYLOAD" | jq $1 | tr -d '"')
              }

              SENDER="$(field .sender.login)"
              SENDER_ID="$(field .sender.id)"
            '';

            pull_request = ''
              echo "$PAYLOAD" | ${final.crystal}/bin/crystal run ./run.cr
            '';

            all = ''
              echo "This command will be executed in all the events, the current event is {event}"
            '';

            push = ''
              echo "User '$SENDER' with ID '$SENDER_ID' pushed to this repository"
            '';

            ping = ''
              echo "User '$SENDER' with ID '$SENDER_ID' pinged to this repository"
            '';

            watch = ''
              ACTION=$(field .action)
              echo "GitHub user '$SENDER' with ID '$SENDER_ID' $ACTION watching this repository"
            '';

            "else" = ''
              echo "'$SENDER' with ID '$SENDER_ID' sent {event} event"
            '';
          };
        };

        project = arion.lib.build { modules = [ ./arion-compose.nix ]; pkgs = final; };
      };

      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ rust.overlay overlay ];
      };
    in {
      legacyPackages.x86_64-linux = pkgs;

      packages.x86_64-linux.bitte-ci = pkgs.bitte-ci;

      defaultPackage.x86_64-linux = self.packages.x86_64-linux.bitte-ci;

      devShell.x86_64-linux = pkgs.mkShell {
        DOCKER_HOST = "unix:///run/podman/podman.sock";

        buildInputs = with pkgs; [
          pkgs.arion
          websocat
          grafana-loki
          nomad
          reproxy
          ngrok
          trigger

          crystal
          shards
          crystal2nix
          openssl
          pkg-config
          gmp
        ];
      };
    };
}
