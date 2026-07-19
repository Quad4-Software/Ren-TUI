// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Entry point for the Ren TUI client.
*/

package main

import "core:fmt"
import "core:os"

import "ren:app"
import "ren:cli"
import "ren:crash"
import "ren:store"

main :: proc() {
	crash.install()
	context.assertion_failure_proc = crash.assertion_failure

	opts, err := cli.parse_args(os.args[1:], false)
	if err != "" {
		fmt.eprintf("ren-tui: %s\n", err)
		cli.print_help_tui()
		cli.options_destroy(&opts)
		crash.close()
		os.exit(2)
	}

	cfg := store.config_default()
	cli.apply_to_config(&cfg, &opts)

	code := 0
	if handled, c := cli.run_utility_actions(&cfg, &opts); handled {
		code = c
	} else {
		code = app.run(&opts)
	}

	store.config_destroy_strings(&cfg)
	cli.options_destroy(&opts)
	crash.close()
	os.exit(code)
}
