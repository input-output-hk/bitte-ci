{ repo, branches ? [ ], pullRequests ? { }, extraInputs ? { }, flake ? false
, srcOpt ? "" }:

let
  inherit (builtins)
    attrNames fromJSON listToAttrs readFile toFile toJSON typeOf
    unsafeDiscardStringContext;
  optionalString = cond: string: if cond then string else "";
  nameValuePair = name: value: { inherit name value; };

  genAttrs = names: f: listToAttrs (map (n: nameValuePair n (f n)) names);

  mapAttrs' = f: set:
    listToAttrs (map (attr: f attr set.${attr}) (attrNames set));

  importJSON = path: fromJSON (readFile path);

  pullRequests' = if typeOf pullRequests == "attrs" then
    pullRequests
  else
    importJSON pullRequests;

  mkJobset = if flake then mkFlakeJobset else mkLegacyJobset;
  mkFlakeJobset = ref: description: {
    inherit description;

    enabled = 1;
    hidden = false;
    type = 1;
    flake = "${repo}?ref=${ref}";
    checkinterval = 30;
    schedulingshares = 100;
    enableemail = true;
    emailoverride = "";
    keepnr = 3;
  };

  mkLegacyJobset = ref: description: {
    inherit description;

    enabled = 1;
    hidden = false;
    nixexprinput = "src";
    nixexprpath = "release.nix";
    checkinterval = 30;
    schedulingshares = 100;
    enableemail = true;
    emailoverride = "";
    keepnr = 3;

    inputs = {
      src = {
        type = "git";
        value = "${repo} ${ref}" + (optionalString (srcOpt != "") " ${srcOpt}");
        emailresponsible = true;
      };

      supportedSystems = {
        type = "nix";
        value = ''[ "x86_64-linux" "x86_64-darwin" ]'';
        emailresponsible = false;
      };
    } // extraInputs;
  };

  mkBranchJobset = branch: mkJobset branch "${branch} branch";

  mkPRJobset = prNumber:
    { title, head, ... }:
    nameValuePair "pr-${prNumber}"
    (mkJobset "refs/pull/${prNumber}/head" title);

  branchJobsets = genAttrs branches mkBranchJobset;
  prJobsets = mapAttrs' mkPRJobset pullRequests';
  jobsets = branchJobsets // prJobsets;

in {
  jobsets = derivation {
    name = "spec.json";
    system = "x86_64-linux";
    builder = "/bin/sh";
    args = [
      (toFile "spec-builder.sh" ''
        while read -r; do echo "$REPLY"; done <<EOF > $out
        ${toJSON jobsets}
        EOF
      '')
    ];
  };
}
