{
  description = "Test";
  inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05"; };
  outputs = { self, nixpkgs }:
    let pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      packages.x86_64-linux = {
        grafana-loki = pkgs.grafana-loki;
        hello = pkgs.hello;
      };
    };
}
