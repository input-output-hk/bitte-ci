package ci

import ("list")

#types: {
	// This identifier is used across a number of systems, so the name
	// needs to be kept simple.
	ci_steps_key: =~"^[a-z_]+$"

	// any valid Nix identifier is a valid flake attribute.
	flake: =~"^[a-zA-Z_][a-zA-Z0-9_'-]*$"

	// https://www.nomadproject.io/docs/job-specification/lifecycle
	lifecycle: *null | "prestart" | "poststart" | "poststop"

	// We only allow output from these two directories at this time.
	output: =~"^/(alloc|local)/.*$"
}

#step: close({
	// Usually identical to the step key name.
	label: string

	// A struct of flake URLs to Nix attribute names.
	flakes: [string]: [#types.flake, ...#types.flake] & list.MinItems(1)

	// This command will be executed in the step.
	command: string | (list.MinItems(1) & [...string])

	// Whether this step should be executed.
	enable: *true | false

	// Obtain a Vault token in the VAULT_TOKEN environment variable.
	vault: *false | true

	// Reserve that many Mhz for this step. Exceeding this value for
	// too long may lead to step termination.
	cpu: *100 | uint & >=100

	// Reserved memory for the step. Exceeding this value will result
	// in OOM and step termination.
	memory: *40 | uint & >=64

	// Globs of paths that should be saved when the step finishes.
	outputs: [...#types.output] | *[]

	// Set some environment variables.
	env: [string]: string

	// Wait this amount of seconds to send the command a TERM signal.
	term_timeout: *1800 | int & >60

	// Wait this amount of seconds to send the command a KILL signal.
	kill_timeout: *2100 | int & >term_timeout

	// Wait for completion of steps in this list before executing this
	// step. The wait time doesn't count against the timeouts.
	after: [...#types.ci_steps_key]

	// https://www.nomadproject.io/docs/job-specification/lifecycle
	lifecycle: #types.lifecycle

	if lifecycle == null {
		sidecar: null
	}
	if lifecycle != null {
		// You may specify whether your task is a sidecar when a
		// lifecycle is set. Enable this if you want the step to restart
		// until all other steps are finished when it terminates.
		// Useful for example to start a database or other services
		// needed for your environment.
		sidecar: *false | true
	}
})

ci: close({
	// We only support version 1 right now. May be used in future for
	// backwards compatibility.
	version: uint & <2
	steps:   close({
		[_key=#types.ci_steps_key]: {
			label: *_key | string
		} & #step
	})
})
