{ pullRequests }:

import ./make-jobsets.nix {
  inherit pullRequests;
  flake = true;
  repo = "github:input-output-hk/bitte-ci";
  branches = [ "main" ];
}
