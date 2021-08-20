{
  description = "Flake for Bitte CI";

  nixConfig.build-users-group = "";
  nixConfig.extra-experimental-features = "nix-command flakes ca-references";
  nixConfig.extra-substituters = "https://hydra.iohk.io";
  nixConfig.extra-trusted-public-keys =
    "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";
    arion.url = "github:hercules-ci/arion";
    inclusive.url = "github:input-output-hk/nix-inclusive";
    bitte.url = "github:input-output-hk/bitte";

    # requires this PR https://github.com/NixOS/nix/pull/5082
    nix.url = "github:NixOS/nix";
    devshell.url = "github:numtide/devshell";

    nomad-src = {
      url = "github:input-output-hk/nomad/release-1.1.2";
      flake = false;
    };

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
      overlay = final: prev: {
        bitte-ci = final.callPackage ./pkgs/bitte-ci { };

        nix = inputs.nix.packages.${prev.system}.nix;

        inclusive = inputs.inclusive.lib.inclusive;

        inherit (inputs.bitte.packages.${prev.system}) cue nomad;

        libgit2 = final.callPackage ./pkgs/libgit2 {
          inherit (prev.darwin.apple_sdk.frameworks) Security;
        };

        crystal = final.callPackage ./pkgs/crystal {
          oldCrystal = prev.crystal;
          src = inputs.crystal-src;
        };

        bdwgc = final.callPackage ./pkgs/bdwgc {
          src = inputs.bdwgc-src;
          libatomic_ops = inputs.libatomic_ops;
        };

        tests = final.callPackage ./tests { inherit inputs; };

        arion = inputs.arion.defaultPackage.${prev.system};

        reproxy = prev.callPackage ./pkgs/reproxy { };

        ngrok = prev.callPackage ./pkgs/ngrok { };

        project = inputs.arion.lib.build {
          modules = [ ./arion-compose.nix ];
          pkgs = final;
        };
      };

      pkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
        overlays = [ overlay inputs.devshell.overlay ];
      };
    in {
      inherit inputs;

      nixosModules.bitte-ci = import ./modules/bitte-ci.nix;

      packages.x86_64-linux = {
        # just for development
        inherit (pkgs)
          nix crystal libgit2 bdwgc tests arion reproxy ngrok project cacert
          bash;
      } // pkgs.bitte-ci;

      legacyPackages.x86_64-linux = pkgs;

      defaultPackage.x86_64-linux = self.packages.x86_64-linux.bitte-ci;

      hydraJobs = {
        build-command-static.x86_64-linux = self.packages.x86_64-linux.command-static;
        build-prepare-static.x86_64-linux = self.packages.x86_64-linux.prepare-static;
        build-cacert.x86_64-linux = self.packages.x86_64-linux.cacert; # this nixpkgs' version
      };


      devShell.x86_64-linux = let
        withCategory = category: attrset: attrset // { inherit category; };
        main = withCategory "main";
        maintenance = withCategory "maintenance";
        run = withCategory "run";
      in pkgs.devshell.mkShell {
        name = "bitte-ci";
        env = [
          {
            name = "CRYSTAL_LIBRARY_PATH";
            value = pkgs.lib.makeLibraryPath (with pkgs; [
              gmp
              openssl
              pcre
              libevent
              libyaml
              zlib
              file
              libgit2
              libssh2
            ]);
          }
          {
            name = "PKG_CONFIG_PATH";
            value = builtins.concatStringsSep ":"
              (map (path: "${path}/lib/pkgconfig")
                pkgs.bitte-ci.bitte-ci.buildInputs);
          }
          {
            name = "LLVM_CONFIG";
            value = "${pkgs.llvm_10}/bin/llvm-config";
          }
          {
            name = "DOCKER_HOST";
            eval =
              "$([[ -S /run/podman/podman.sock ]] && echo 'unix:///run/podman/podman.sock' || echo 'unix:///run/docker.sock')";
          }
          {
            name = "GITHUB_TOKEN";
            eval = "$(awk '/github.com/ {print $6;exit}' ~/.netrc)";
          }
          # bitte-ci cofig evironment
          # TODO: prefix with BITTE_CI_
          {
            name = "PUBLIC_URL";
            value = "http://127.0.0.1:9494";
          }
          {
            name = "POSTGRES_URL";
            value = "postgres://postgres@127.0.0.1:5432/bitte_ci";
          }
          {
            name = "NOMAD_BASE_URL";
            value = "http://127.0.0.1:4646";
          }
          {
            name = "LOKI_BASE_URL";
            value = "http://127.0.0.1:3100";
          }
          {
            name = "NOMAD_DATACENTERS";
            value = "dc1";
          }
          {
            name = "GITHUB_USER_CONTENT_BASE_URL";
            value = "https://raw.githubusercontent.com";
          }
          {
            name = "NOMAD_TOKEN";
            value = "snakeoil";
          }
          {
            name = "ARTIFACT_SECRET";
            value = "snakeoil";
          }
          {
            name = "ARTIFACT_DIR";
            eval = "$(mkdir -p $DEVSHELL_ROOT/.artifacts && echo '.artifacts')";
          }
        ];

        # tempfix: remove when merged https://github.com/numtide/devshell/pull/123
        devshell.startup.load_profiles = pkgs.lib.mkForce
          (pkgs.lib.noDepEntry ''
            # PATH is devshell's exorbitant privilege:
            # fence against its' pollution
            _PATH=''${PATH}
            # Load installed profiles
            for file in "$DEVSHELL_DIR/etc/profile.d/"*.sh; do
              # If that folder doesn't exist, bash loves to return the whole glob
              [[ -f "$file" ]] && source "$file"
            done
            # Exert exorbitant privilege and leave no trace
            export PATH=''${_PATH}
            unset _PATH
          '');

        commands = [
          {
            name = "fmt";
            help = "Fix Nix formatting";
            command = "fd . -e nix $DEVSHELL_ROOT -X nixfmt";
          }
          {
            name = "evalnix";
            help = "Check Nix parsing";
            command =
              "fd --extension nix --exec nix-instantiate --parse --quiet {} >/dev/null";
          }
          (main {
            package = pkgs.crystal; # TODO: missing meta.description
          })
          (main { package = pkgs.crystal2nix; })
          (main { package = pkgs.cue; })
          (main { package = pkgs.arion; })
          (maintenance {
            name = "deps";
            help = "Do stuff with deps(?)"; # TODO
            command = "${./scripts/deps_new.cr}";
          })
          (run {
            name = "launch-services";
            help = "Run the docker services like postgres";
            command = ''
              trap "arion -f $DEVSHELL_ROOT/arion-compose.nix -p $DEVSHELL_ROOT/arion-pkgs.nix down" SIGINT
              arion -f $DEVSHELL_ROOT/arion-compose.nix -p $DEVSHELL_ROOT/arion-pkgs.nix up
            '';
          })
          (run {
            name = "launch-nomad";
            help = "Launch nomad (will run sudo)";
            command =
              "sudo -E --preserve-env=PATH ${pkgs.nomad}/bin/nomad agent -dev -config $DEVSHELL_ROOT/agent.hcl";
          })
        ];

        packages = with pkgs;
          [
            arion
            websocat
            grafana-loki
            nomad
            reproxy
            ngrok
            kcov

            pkg-config
            fd
            clang_10

            nixfmt
            nix
          ] ++ pkgs.bitte-ci.bitte-ci.buildInputs;
      };
    };
}
