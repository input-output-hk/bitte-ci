{ pkgs, inputs, ... }:
pkgs.nixosTest {
  name = "cacert";

  nodes.ci = {
    environment.systemPackages = with pkgs; [ bat tree strace ];

    system.extraDependencies = with pkgs; [ pkgs.cacert ];

    environment.sessionVariables.NIXPKGS = toString pkgs.path;

    networking.useDHCP = false;

    nix = {
      package = pkgs.nixUnstable;
      registry.nixpkgs.flake = inputs.nixpkgs;
      extraOptions = ''
        experimental-features = nix-command flakes
        show-trace = true
        log-lines = 100
      '';
    };
  };

  testScript = let
    script = pkgs.writeShellScript "test.sh" ''
      set -exuo pipefail

      nix -L build path:$NIXPKGS#cacert
    '';
  in ''
    start_all()
    ci.systemctl("is-system-running --wait")
    ci.log(ci.succeed("${script}"))
  '';
}
