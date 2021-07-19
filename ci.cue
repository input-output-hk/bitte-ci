package ci

ci: steps: [
	{
		label: "Hello World!"
		flakes: "github:NixOS/nixpkgs/nixos-21.05": ["bash", "hello"]
		cpu:    100
		memory: 32
		enable: pull_request.base.ref == "master"

		_cmd: """
			hello -t > /local/greeting
			"""
		command: ["/bin/bash", "-c", _cmd]
		artifacts: ["/local/greeting"]
	},
]

isMaster: pull_request.base.ref == "master"

// some default values
#step: enable: bool | *isMaster
