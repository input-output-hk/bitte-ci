{ stdenv, oldCrystal, src }:
stdenv.mkDerivation rec {
  pname = "crystal";
  version = "1.1.1";

  inherit src;

  passthru.buildCrystalPackage = oldCrystal.buildCrystalPackage;

  installPhase = ''
    mkdir -p $out
    cp -r bin lib share $out
  '';
}

