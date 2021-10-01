{ clang10Stdenv, linkFarm, lib, fetchFromGitHub, gmp, openssl, pkg-config
, crystal, llvm_10, pcre, libevent, libyaml, zlib, file, libgit2, libssh2, bdwgc
, removeReferencesTo, callPackage, inclusive, extraArgs }:
let
  pname = if extraArgs.name == "bitte-ci" then
    "bitte-ci"
  else
    "bitte-ci-${extraArgs.name}";

  version = builtins.elemAt (builtins.match ".*version: (([[:digit:]]+\\.?)+).*"
    (builtins.readFile ../../shard.yml)) 0;

  name = "${pname}-${version}";

  crystalLib = linkFarm "crystal-lib" (lib.mapAttrsToList (name: value: {
    inherit name;
    path = fetchFromGitHub value;
  }) (import ../../shards.nix));

  crystalBuildFlags =
    if extraArgs.static or false then [ "--static" "--release" ] else [ ];

  mkSrc = paths: inclusive ../.. paths;

  src = mkSrc (import (./. + "/input_${extraArgs.name}.nix"));
in clang10Stdenv.mkDerivation {
  inherit pname version src;

  LLVM_CONFIG = "${llvm_10}/bin/llvm-config";

  buildInputs = [ gmp openssl pcre libevent libyaml zlib file libgit2 libssh2 ];

  nativeBuildInputs = [ removeReferencesTo pkg-config crystal ];

  buildPhase = ''
    ln -s ${crystalLib} lib
    mkdir -p $out/bin

    mkdir -p .cache/crystal
    export CRYSTAL_CACHE_DIR=.cache/crystal

    crystal build --verbose ${extraArgs.main} \
      -o "$out/bin/${pname}" \
      --link-flags "-L${bdwgc}/lib" \
      ${builtins.concatStringsSep " " crystalBuildFlags}

    remove-references-to -t ${crystal} $out/bin/*
  '';

  installPhase = ":";
}
