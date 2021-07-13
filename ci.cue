package ci

ci: steps: [
	{
		label: "crystal spec"
		flakes: "github:NixOS/nixpkgs/nixos-21.05": [
			"crystal", "shards", "gmp", "pkg-config", "openssl",
		]
		cpu:    5000
		memory: 1024
		enable: pull_request.base.ref == "master"

		_cmd: """
			shards
			crystal spec
			"""
		command: ["/bin/bash", "-c", _cmd]
	},
]

isMaster: pull_request.base.ref == "master"

// some default values
#step: enable: bool | *isMaster
