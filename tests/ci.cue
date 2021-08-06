package ci

ci: steps: {
	hello: {
		command: ["bash", "-c", "hello -t > /alloc/hello; hello -t"]
		outputs: ["/alloc/hello"]
	}
	bye: {
		after: ["hello"]
		command: ["bash", "-c", "hello -g goodbye > /local/bye; hello -g goodbye"]
		outputs: ["/local/bye"]
	}
}

#step: flakes: "git://127.0.0.1:7070/": ["bash", "hello"]
