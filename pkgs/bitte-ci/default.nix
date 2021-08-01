{ clang10Stdenv, linkFarm, lib, fetchFromGitHub, src, gmp, openssl, pkg-config
, crystal, llvm_10, pcre, libevent, libyaml, zlib, file, libgit2 }:
let
  pname = "bitte-ci";
  version = "0.1.0";
  name = "${pname}-${version}";
  crystalLib = linkFarm "crystal-lib" (lib.mapAttrsToList (name: value: {
    inherit name;
    path = fetchFromGitHub value;
  }) (import ../../shards.nix));
in clang10Stdenv.mkDerivation {
  inherit pname version;
  inherit src;

  LLVM_CONFIG = "${llvm_10}/bin/llvm-config";

  buildInputs = [ gmp openssl pcre libevent libyaml zlib file libgit2 ];

  nativeBuildInputs = [ pkg-config crystal ];

  buildPhase = ''
    ln -s ${crystalLib} lib
    mkdir -p $out/bin
    crystal build ./src/bitte_ci.cr \
      -o $out/bin/bitte-ci \
      --progress \
      --debug \
      --verbose \
      --threads "$NIX_BUILD_CORES"
  '';

  installPhase = ":";
}
