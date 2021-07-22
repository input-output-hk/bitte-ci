# Bitte CI

A CI built for [Bitte](https://github.com/input-output-hk/bitte), but usable with any Nomad cluster.

## Dependencies

Bitte CI depends on some external services:

* PostgreSQL
* Nomad
* Loki

## Development

Building can be done using Nix:

    nix build

Or Crystal:

    crystal build ./src/bitte_ci.cr -o bitte-ci

For development, you can start PostgreSQL and Loki using `arion up`.
Nomad requires elevated permissions, so start it separately with:

    sudo nomad agent -dev -config agent.hcl

## WebSocket API

You can communicate with the Websocket based API at the path: `/ci/api/v1/socket`.
This is intended to be consumed by the web frontend, but can be useful for
scripting purposes as well.

Due to the sometimes large messages, it's recommended to provide ample buffer
space for the responses.

Currently implemented are:

### Monitoring pull requests

    echo '{"channel": "pull_requests"}' \
      | websocat -B 1000000 ws://0.0.0.0:9494/ci/api/v1/socket

### Monitoring a pull request

    echo '{"channel": "pull_request", "id": 1234}' \
      | websocat -B 1000000 ws://0.0.0.0:9494/ci/api/v1/socket

### Monitoring a build

    echo '{"channel": "build", "uuid": "87671204-5181-46fd-97b7-29b341a684b3"}' \
      | websocat -B 1000000 ws://0.0.0.0:9494/ci/api/v1/socket
