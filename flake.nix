{
  description = "Flake for Bitte CI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";
    bitte.url = "github:input-output-hk/bitte/nix-driver-with-profiles";
    arion.url = "github:hercules-ci/arion";
    bitte-ci-frontend.url = "github:input-output-hk/bitte-ci-frontend";
  };

  outputs = { self, ... }@inputs:
    let
      overlay = final: prev: {
        nomad = inputs.bitte.legacyPackages.${prev.system}.nomad;

        bitte-ci = prev.callPackage ./pkgs/bitte-ci {
          src = prev.lib.sourceFilesBySuffices ./. [
            ".cr"
            ".lock"
            ".yml"
            ".cue"
            ".fixture"
          ];
        };

        bitte-ci-frontend =
          inputs.bitte-ci-frontend.defaultPackage.${prev.system};

        arion = inputs.arion.defaultPackage.${prev.system};

        reproxy = prev.callPackage ./pkgs/reproxy { };

        ngrok = prev.callPackage ./pkgs/ngrok { };

        tests = final.callPackage ./tests { inherit inputs; };

        project = inputs.arion.lib.build {
          modules = [ ./arion-compose.nix ];
          pkgs = final;
        };
      };

      pkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
        overlays = [ overlay ];
      };
    in {
      nixosModules.bitte-ci = import ./modules/bitte-ci.nix;

      legacyPackages.x86_64-linux = pkgs;

      packages.x86_64-linux.bitte-ci = pkgs.bitte-ci;

      defaultPackage.x86_64-linux = self.packages.x86_64-linux.bitte-ci;

      devShell.x86_64-linux = pkgs.mkShell {
        DOCKER_HOST = "unix:///run/podman/podman.sock";

        # requires https://github.com/NixOS/nix/pull/4983
        # BITTE_CI_POSTGRES_URL = "postgres://postgres@127.0.0.1/bitte_ci";

        FRONTEND_PATH = pkgs.bitte-ci-frontend;

        shellHook = ''
          export GITHUB_TOKEN="$(awk '/github.com/ {print $6;exit}' ~/.netrc)"
        '';

        buildInputs = with pkgs; [
          pkgs.arion
          websocat
          grafana-loki
          nomad
          reproxy
          ngrok
          kcov

          inputs.bitte.packages.x86_64-linux.cue

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
