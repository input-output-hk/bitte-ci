package ci

ci: {
	version: 1
	steps: {
		hello: {
			command: ["bash", "-c", "hello -t > /alloc/hello; hello -t"]
			outputs: ["/alloc/hello"]
		}
	}
}

// we can reference any values from the PR to control whether this PR
// should be built.
#isMaster: pull_request.base.ref == "master"
#isAdmin:  sender.login == "manveru"

// some default values
#step: enable: bool | *(#isMaster && #isAdmin)
#step: flakes: "github:NixOS/nixpkgs": ["bash", "hello"]
