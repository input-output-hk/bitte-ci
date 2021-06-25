{ crystal, openssl, gmp }:
crystal.buildCrystalPackage {
  pname = "bitte-ci";
  version = "0.1.0";
  format = "shards";
  src = ../../.;
  buildInputs = [ openssl gmp ];
  shardsFile = ../../shards.nix;
  crystalBinaries.bitte-ci.src = "src/bitte_ci.cr";
}
