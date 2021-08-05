package ci

import ("list")

#types: {
	ci_steps_key: =~"^[a-z_]+$"
	flake:        =~"^[A-Za-z_-][A-Za-z0-9_-]*$"
	lifecycle:    *null | "prestart" | "poststart" | "poststop"
	output:       =~"^/(alloc|local)/.*$"
}

#step: close({
	label: string
	flakes: [string]: [#types.flake, ...#types.flake] & list.MinItems(1)
	command: string | (list.MinItems(1) & [...string])
	enable:  *true | false
	vault:   *false | true
	cpu:     *100 | uint & >=100
	memory:  *40 | uint & >=64
	outputs: [...#types.output] | *[]
	env: [string]: string
	term_timeout: *1800 | int & >60
	kill_timeout: *2100 | int & >term_timeout
	after: [...#types.ci_steps_key]

	lifecycle: #types.lifecycle

	if lifecycle == null {
		sidecar: null
	}
	if lifecycle != null {
		sidecar: *false | true
	}
})

ci: close({
	version: 1
	steps:   close({
		[_key=#types.ci_steps_key]: {
			label: *_key | string
		} & #step
	})
})
