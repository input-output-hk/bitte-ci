# Bitte CI

A CI built for [Bitte](https://github.com/input-output-hk/bitte),
but potentially usable with any [Nomad](https://www.nomadproject.io/) cluster.

This is basically a translator from GitHub PRs into Nomad jobs. It also comes
with a built-in UI to keep track of the deployed jobs and view logs.
Additionally the status of the PR will be updated.

The runtime sandbox environment of a job can be declaratively specified using
[Nix](https://nixos.org/) and its unstable
[flakes](https://nixos.wiki/wiki/Flakes) feature.

We strive to make life better for all developers, even if they don't know Nix,
so the only thing you have to specify are the packages you would like to have
in your environment.

## Adding a project

### ci.cue

Configuration for a project is specified using [CUE](https://cuelang.org/).
The type definitions can be found in 
[schema.cue](https://github.com/input-output-hk/bitte-ci/blob/main/cue/schema.cue).

A minimal example could be:

```
ci: {
  version: 1

  steps: hello: {
    command: ["bash", "-c", "hello -t"]
    flakes: "github:NixOS/nixpkgs/nixos-21.05": ["bash", "hello"]
  }
}
```

This will provide you with an environment that includes
[Bash](https://www.gnu.org/software/bash/) and
[Hello](https://www.gnu.org/software/hello/manual/)

You can find a list of currently more than 80k packages included in
[nixpkgs](https://github.com/NixOS/nixpkgs) at
[NixOS Search](https://search.nixos.org/packages).

### GitHub hook

Projects are added automatically when Bitte CI receives a pull request from GitHub with the correct secret.

These settings are required:

![2021-08-06_18-02](https://user-images.githubusercontent.com/3507/128539489-d635e87f-8ced-4786-9e15-a5c4ac92fd7b.png)

Also make sure to send pushes and PRs:

![2021-08-06_18-03](https://user-images.githubusercontent.com/3507/128539509-893bfe29-4a9b-4c64-8b21-d553fa723bd5.png)

## Dependencies

Bitte CI depends on some external services:

* PostgreSQL
* Nomad
* Loki

## Build

Building can be done using Nix:

    ❯ nix build

Or Crystal:

    ❯ shards build

## Develop
For development, you can enter the devshell:

    ❯ nix develop

Start PostgreSQL and Loki.
Nomad requires elevated permissions, so start it separately.

    [bitte-ci] ❯ lauch-services # arion up
    [bitte-ci] ❯ lauch-nomad # sudo nomad agent -dev -config agent.hcl

Then, after `nix build`, run the bitte-ci listener and server:

    ❯ ./result/bin/bitte-ci serve
    ❯ ./result/bin/bitte-ci listen

## Configuration

You can configure Bitte CI in a lot of ways. Each subcommand is
self-documenting and lists all the options it requires to function.

Of note is that each CLI flag can also be set via a config file or an
environment variable.

Consider the following equivalent examples:

    ❯ bitte-ci server --nomad-token c5c69215-887f-4adb-936b-ed8120e78ae8

    ❯ NOMAD_TOKEN=c5c69215-887f-4adb-936b-ed8120e78ae8 bitte-ci server

    ❯ cat bitte_ci.json
    {
      "nomad_token": "c5c69215-887f-4adb-936b-ed8120e78ae8"
    }
    ❯ bitte-ci server


In order to ease secrets handling, Bitte CI also supports loading
sensitive options from files.
This is in particular important when you want to rotate your secrets without
restarting the server.

So you can for example do the following and send a HUP signal to the server, it
will read the file again and use the new token in future requests:

    ❯ bitte-ci server --nomad-token-file my.token &
    ❯ uuidgen > my.token
    ❯ pkill -HUP -f bitte-ci
    INFO - Received HUP
    INFO - Reloading configuration
    INFO - Reloaded config nomad_token: <redacted> => <redacted>

## Setup

Ideally it's as simple as importing the NixOS module in `modules/bitte-ci.nix`.
It is available via `github:input-output-hk/bitte-ci#nixosModules.bitte-ci` if
you use flakes.

## REST API

* `GET /api/v1/allocation/:id`: Get information about this allocation
* `GET /api/v1/allocation`: List the 10 latest allocations
* `GET /api/v1/build/:id`: build for the given ID
* `GET /api/v1/build`: latest 10 builds
* `GET /api/v1/organization`: List all organizations that have submitted PRs
* `GET /api/v1/organization/:login`: Show information about this organization
* `GET /api/v1/output/:id`: Download the given output
* `GET /api/v1/pull_request/:id`: Get information about this PR
* `GET /api/v1/pull_request`: List the last 10 PRs
* `POST /api/v1/github` This endpoint recevies GitHub WebHooks.
* `PUT /api/v1/output`: Upload an output (called from the artificer in each Nomad task)
