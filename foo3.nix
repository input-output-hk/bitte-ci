{ id, inputs ? { } }:
let
  pp = v: builtins.trace (builtins.toJSON v) v;

  inherit ((builtins.getFlake (toString ./.)).packages.x86_64-linux)
    liftbridge-cli;

  task = name:
    { when ? { ... }: { }, success ? { ${name} = true; }
    , failure ? { ${name} = false; }, ... }@args:
    givenScript:
    let
      evaluated = when inputs;
      ok = builtins.all (a: a) (builtins.attrValues evaluated);
    in if ok then
      derivation rec {
        inherit id name;
        passAsFile = [ "script" ];
        script = givenScript;
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
      inputs = builtins.attrNames (builtins.functionArgs when);
      when = evaluated;
    };

  length = o:
    {
      list = builtins.length o;
      set = builtins.length (builtins.attrNames o);
    }.${builtins.typeOf o};
in {
  ping = task "ping" {
    when = { manager-confirmation ? false, coverage ? 0, ... }: {
      "code coverage over 75" = coverage > 75;
    };
  } ''
    ${liftbridge-cli}/bin/main p -s brain -c -m '{"ping": true}'
  '';

  approval-qa = task "approval-qa" {
    when = { approvals ? { }, ... }: {
      "got 2/3 approvals already" = (length approvals) < 2;
    };
  } ''
    echo QA approval
  '';

  pong = task "pong" {
    when = { ping ? false, approvals ? { }, ... }: { "ping succeeded" = ping; };
  } ''
    echo running pong
  '';
}
