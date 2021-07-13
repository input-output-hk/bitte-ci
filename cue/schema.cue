package ci

import ("list")

#step: {
	label:   string
	flakes: [string]: [string, ...string] & list.MinItems(1)
	command: string | (list.MinItems(1) & [...string])
	enable:  *true | false
	vault: *false | true
	cpu: *100 | uint
	memory: *300 | uint
}

ci: {
	version: 1
	steps: [...#step]
}
