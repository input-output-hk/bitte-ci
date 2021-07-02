{ crystal, openssl, gmp, makeWrapper, lib, src, cue }:
crystal.buildCrystalPackage {
  pname = "bitte-ci";
  version = "0.1.0";
  format = "crystal";
  inherit src;
  buildInputs = [ openssl gmp ];
  nativeBuildInputs = [ makeWrapper ];
  shardsFile = ../../shards.nix;
  crystalBinaries.bitte-ci = {
    src = "src/bitte_ci.cr";
    options = [ "--debug" "--progress" ];
  };

  postInstall = ''
    wrapProgram $out/bin/bitte-ci --prefix PATH : '${lib.makeBinPath [ cue ]}'
  '';
}
