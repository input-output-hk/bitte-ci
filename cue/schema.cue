package ci

import ("list")

#step: {
	label:   string
	flake:   string
	command: string | (list.MinItems(1) & [...string])
	enable:  *true | false
	datacenters: *["dc1"] | (list.MinItems(1) & [...string])
	vault: *false | true
	cpu: *100 | uint
	memory: *300 | uint
}

ci: {
	version: 1
	steps: [...#step]
}
