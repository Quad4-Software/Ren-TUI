// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Windows stub for -d/--daemon.
*/

#+build windows
package cli

import "core:fmt"

import "ren:constants"

daemonize :: proc(log_path: string) -> (ok: bool, err: string) {
	_ = log_path
	return false, "daemon mode requires POSIX"
}

daemon_pid_path :: proc(data_dir: string, allocator := context.allocator) -> string {
	return fmt.aprintf("%s/%s", data_dir, constants.DAEMON_PID_FILE, allocator = allocator)
}

daemon_log_path :: proc(data_dir: string, allocator := context.allocator) -> string {
	return fmt.aprintf("%s/%s", data_dir, constants.DAEMON_LOG_FILE, allocator = allocator)
}

daemon_write_pid :: proc(path: string) -> bool {
	_ = path
	return false
}

daemon_remove_pid :: proc(path: string) {
	_ = path
}

daemon_read_pid :: proc(path: string) -> (pid: int, ok: bool) {
	_ = path
	return 0, false
}

daemon_pid_alive :: proc(pid: int) -> bool {
	_ = pid
	return false
}

daemon_already_running :: proc(pid_path: string) -> (running: bool, pid: int) {
	_ = pid_path
	return false, 0
}

daemon_install_stop_signals :: proc() {}

daemon_should_stop :: proc() -> bool {
	return true
}
