# Bitte CI

A CI built for [Bitte](https://github.com/input-output-hk/bitte), but usable with any Nomad cluster.

## Adding a project

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

For development, you can start PostgreSQL and Loki using `arion up`.
Nomad requires elevated permissions, so start it separately with:

    ❯ sudo nomad agent -dev -config agent.hcl

Then run the bitte-ci listener and server:

    ❯ bitte-ci server
    ❯ bitte-ci listen

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


In order to handle ease secrets handling, Bitte CI also supports loading
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
