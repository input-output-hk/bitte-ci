{ id, msgs ? { } }:
let
  hash = task: msg: builtins.hashString "sha256" "${id}.${task}.${msg}";

  pp = v: builtins.trace (builtins.toJSON v) v;

  task = name:
    { when ? null }@args:
    script:
    let
      when = args.when or ({ ... }: { });
      evaluated = when msgs;
      ok = builtins.all (a: a) (builtins.attrValues (pp evaluated));
    in if ok then
      derivation {
        system = "x86_64-linux";
        name = name;
        outputHashAlgo = "sha256";
        outputHashMode = "recursive";
        outputHash = hash name "___OK___";
        builder = ./builder.sh;
        inherit script;
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
    curl -X POST https://deployer.com/deploy/baz
    echo task_id_baz_OK > $out
  '';
}
