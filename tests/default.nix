{ pkgs, inputs, ... }: {
  test-bitte-ci = pkgs.callPackage ./ci.nix { inherit inputs; };
  test-bitte-cacert = pkgs.callPackage ./cacert.nix { inherit inputs; };
}
