{ id, msgs ? { } }:
let
  task = name:
    { when ? { ... }: { } }@args:
    givenScript:
    let
      evaluated = when msgs;
      ok = builtins.all (a: a) (builtins.attrValues evaluated);
    in if ok then
      derivation rec {
        inherit id name;
        script = builtins.toFile "script.sh" givenScript;
        system = "x86_64-linux";
        result = builtins.concatStringsSep "." [
          id
          name
          (builtins.hashString outputHashAlgo script)
        ];
        outputHashAlgo = "sha256";
        outputHashMode = "flat";
        outputHash = builtins.hashString outputHashAlgo result;
        builder = ./builder.sh;
      }
    else {
      when = evaluated;
    };
in {
  ping = task "ping" {
    when = { manager-confirmation ? false, coverage ? 0, ... }: {
      "manager confirmed" = manager-confirmation;
      "code coverage over 75" = coverage > 75;
    };
  } ''
    lift send $uuid ping
  '';

  pong = task "pong" {
    when = { ping ? false, manager-confirmation ? false, ... }: {
      "ping succeeded" = ping;
      "manager gave ok" = manager-confirmation;
    };
  } ''
    echo running pong
  '';
}
