package ci

ci: steps: [
	{
		label: "crystal spec"
		flakes: "github:NixOS/nixpkgs/nixos-21.05": ["crystal"]
		command: ["/bin/crystal", "spec"]
		enable: pull_request.base.ref == "master"
	},
]

isMaster: pull_request.base.ref == "master"

// some default values
#step: enable: bool | *isMaster
