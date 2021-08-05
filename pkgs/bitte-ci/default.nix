{ lib, callPackage, pkgsStatic, pkgsMusl }:
let
  cmds = [ "bitte-ci" "command" "listen" "migrate" "prepare" "queue" "server" ];

  mkBitte = name: main:
    callPackage ./package.nix {
      extraArgs = { inherit main name bitteCiPackages; };
    };

  mkBitteStatic = name: main:
    callPackage ./package.nix {
      inherit (pkgsMusl) clang10Stdenv llvm_10;
      inherit (pkgsStatic)
        gmp openssl pcre libevent libyaml zlib file libgit2 libssh2 bdwgc;
      extraArgs = {
        inherit main name bitteCiPackages;
        static = true;
      };
    };

  bitteCiPackages = with builtins;
    listToAttrs (concatLists (map (name: [
      {
        name = "${name}-static";
        value = mkBitteStatic name "src/bitte_ci/cli/${name}.cr";
      }
      {
        inherit name;
        value = mkBitte name "src/bitte_ci/cli/${name}.cr";
      }
    ]) cmds));
in callPackage ./package.nix { extraArgs = { inherit bitteCiPackages; }; }
