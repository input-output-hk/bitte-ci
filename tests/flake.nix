{
  description = "Test";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";
  inputs.bitte-ci.url = "path:/bitte-ci";
  outputs = { self, nixpkgs, ... }@inputs:
    let
      overlay = final: prev: {
        inherit (inputs.bitte-ci.packages.x86_64-linux)
          command-static prepare prepare-static;
      };

      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ overlay ];
      };
    in { legacyPackages.x86_64-linux = pkgs; };
}
