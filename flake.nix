{
  description = "Flake for Bitte CI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";
    bitte.url = "github:input-output-hk/bitte/nix-driver-with-profiles";
    arion.url = "github:hercules-ci/arion";
    bitte-ci-frontend.url = "github:input-output-hk/bitte-ci-frontend";

    crystal-src = {
      url =
        "https://github.com/crystal-lang/crystal/releases/download/1.1.1/crystal-1.1.1-1-linux-x86_64.tar.gz";
      flake = false;
    };

    libatomic_ops = {
      url =
        "https://github.com/ivmai/libatomic_ops/releases/download/v7.6.10/libatomic_ops-7.6.10.tar.gz";
      flake = false;
    };

    bdwgc-src = {
      url =
        "https://github.com/ivmai/bdwgc/releases/download/v8.0.4/gc-8.0.4.tar.gz";
      flake = false;
    };
  };

  outputs = { self, ... }@inputs:
    let
      overlay = final: prev:
        let
          src = prev.lib.sourceFilesBySuffices ./. [
            ".cr"
            ".lock"
            ".yml"
            ".cue"
            ".fixture"
          ];
        in {
          nomad = inputs.bitte.legacyPackages.${prev.system}.nomad;

          http-parser-static = prev.callPackage ./pkgs/http-parser { };

          libgit2 = final.callPackage ./pkgs/libgit2 {
            inherit (prev.darwin.apple_sdk.frameworks) Security;
          };

          bitte-ci = prev.callPackage ./pkgs/bitte-ci { inherit src; };

          bitte-ci-static = final.callPackage ./pkgs/bitte-ci {
            inherit src;
            inherit (prev.pkgsMusl) clang10Stdenv llvm_10;
            inherit (prev.pkgsStatic)
              gmp openssl pcre libevent libyaml zlib file libgit2 libssh2 bdwgc;
            static = true;
          };

          bitte-ci-frontend =
            inputs.bitte-ci-frontend.defaultPackage.${prev.system};

          crystal = final.callPackage ./pkgs/crystal {
            oldCrystal = prev.crystal;
            src = inputs.crystal-src;
          };

          bdwgc = final.callPackage ./pkgs/bdwgc {
            src = inputs.bdwgc-src;
            libatomic_ops = inputs.libatomic_ops;
          };

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
      packages.x86_64-linux.bitte-ci-prepare = pkgs.bitte-ci-prepare;
      packages.x86_64-linux.bitte-ci-static = pkgs.bitte-ci-static;

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
          gmp.dev
          pcre
          libevent
          libyaml
          zlib
          file
          libgit2
          libssh2
        ];
      };
    };
}
