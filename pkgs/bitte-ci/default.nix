{ lib, callPackage, pkgsStatic, pkgsMusl, symlinkJoin }:
let
  commandNames =
    [ "bitte-ci" "command" "listen" "migrate" "prepare" "queue" "server" ];

  mkBitte = name: main:
    callPackage ./package.nix { extraArgs = { inherit main name; }; };

  mkBitteStatic = name: main:
    callPackage ./package.nix {
      inherit (pkgsMusl) clang10Stdenv llvm_10;
      inherit (pkgsStatic)
        gmp openssl pcre libevent libyaml zlib file libgit2 libssh2 bdwgc;
      extraArgs = {
        inherit main name;
        static = true;
      };
    };

  static = builtins.listToAttrs (map (name: {
    name = "${name}-static";
    value = mkBitteStatic name "src/bitte_ci/cli/${name}.cr";
  }) commandNames);

  dynamic = builtins.listToAttrs (map (name: {
    inherit name;
    value = mkBitte name "src/bitte_ci/cli/${name}.cr";
  }) commandNames);

  compilations = {
    static-all = symlinkJoin {
      name = "bitte-ci-all";
      paths = builtins.attrValues static;
    };

    dynamic-all = symlinkJoin {
      name = "bitte-ci-all";
      paths = builtins.attrValues dynamic;
    };
  };
in static // dynamic // compilations
