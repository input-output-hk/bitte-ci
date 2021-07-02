package ci

import ("list")

#step: {
	label:   string
	flake:   string
	command: string | (list.MinItems(1) & [...string])
	enable:  *true | false
	datacenters: *["dc1"] | (list.MinItems(1) & [...string])
	vault: *false | true
}

ci: {
	version: 1
	steps: [...#step]
}
