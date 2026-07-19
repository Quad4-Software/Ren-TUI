// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
CLI flag parsing tests including -d/--daemon.
*/

package tests

import "core:testing"

import "ren:cli"

@(test)
test_cli_daemon_flag :: proc(t: ^testing.T) {
	opts, err := cli.parse_args([]string{"-d"}, false)
	defer cli.options_destroy(&opts)
	testing.expect_value(t, err, "")
	testing.expect(t, opts.daemon)

	opts2, err2 := cli.parse_args([]string{"--daemon"}, false)
	defer cli.options_destroy(&opts2)
	testing.expect_value(t, err2, "")
	testing.expect(t, opts2.daemon)

	opts3, err3 := cli.parse_args([]string{"--deamon"}, false)
	defer cli.options_destroy(&opts3)
	testing.expect_value(t, err3, "")
	testing.expect(t, opts3.daemon)

	_, err4 := cli.parse_args([]string{"-d"}, true)
	testing.expect(t, err4 != "")
}

@(test)
test_cli_daemon_paths :: proc(t: ^testing.T) {
	pid := cli.daemon_pid_path("/tmp/ren-test")
	defer delete(pid)
	log := cli.daemon_log_path("/tmp/ren-test")
	defer delete(log)
	testing.expect_value(t, pid, "/tmp/ren-test/ren-tui.pid")
	testing.expect_value(t, log, "/tmp/ren-test/daemon.log")
}
