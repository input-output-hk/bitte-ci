{ src, rust-nix }:
rust-nix.buildPackage {
  name = "trigger";
  version = "1.1.2";
  inherit src;
  root = ./.;
}
