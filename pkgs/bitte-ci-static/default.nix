{ crystal, lib, linkFarm, fetchFromGitHub, src, pkg-config, pkgsStatic, pkgsMusl
, zlib, libssh2, openssl, pcre }:
let
  pname = "bitte-ci";
  version = "0.1.0";
  name = "${pname}-${version}";
  crystalLib = linkFarm "crystal-lib" (lib.mapAttrsToList (name: value: {
    inherit name;
    path = fetchFromGitHub value;
  }) (import ../../shards.nix));
in pkgsMusl.clang10Stdenv.mkDerivation {
  inherit pname version;
  inherit src;

  LLVM_CONFIG = "${pkgsMusl.llvm_10}/bin/llvm-config";

  buildInputs = with pkgsStatic; [
    libevent.dev
    pcre.dev
    bdwgc
    libyaml
    gmp
    zlib
    file
    libgit2-static
    libssh2
  ];

  nativeBuildInputs = [ pkg-config crystal ];

  buildPhase = ''
    ln -s ${crystalLib} lib
    mkdir -p $out/bin
    crystal build ./src/bitte_ci.cr \
      -o $out/bin/bitte-ci \
      --static \
      --debug \
      --release \
      --verbose \
      --threads "$NIX_BUILD_CORES" \
      --link-flags "-L${pkgsStatic.bdwgc}/lib -L${pkgsStatic.libssh2}/lib"
  '';

  installPhase = ":";
}
