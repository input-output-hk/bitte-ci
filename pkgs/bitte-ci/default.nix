{ clang10Stdenv, linkFarm, lib, fetchFromGitHub, src, gmp, openssl, pkg-config
, crystal, llvm_10, pcre, libevent, libyaml, zlib, file, libgit2, libssh2, bdwgc
, removeReferencesTo, static ? false }:
let
  pname = "bitte-ci";
  version = "0.1.0";
  name = "${pname}-${version}";

  crystalLib = linkFarm "crystal-lib" (lib.mapAttrsToList (name: value: {
    inherit name;
    path = fetchFromGitHub value;
  }) (import ../../shards.nix));

  crystalBuildFlags = if static then [ "--static" "--release" ] else [ ];
in clang10Stdenv.mkDerivation {
  inherit pname version;
  inherit src;

  LLVM_CONFIG = "${llvm_10}/bin/llvm-config";

  buildInputs = [ gmp openssl pcre libevent libyaml zlib file libgit2 libssh2 ];

  nativeBuildInputs = [ removeReferencesTo pkg-config crystal ];

  buildPhase = ''
    ln -s ${crystalLib} lib
    mkdir -p $out/bin
    crystal build ./src/bitte_ci.cr \
      -o $out/bin/bitte-ci \
      --link-flags "-L${bdwgc}/lib" \
      ${builtins.concatStringsSep " " crystalBuildFlags}
    remove-references-to -t ${crystal} $out/bin/*
  '';

  installPhase = ":";
}
