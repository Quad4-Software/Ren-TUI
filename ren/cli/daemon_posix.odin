// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
POSIX process detach for -d/--daemon.
*/

#+build linux, darwin, freebsd, openbsd, netbsd
package cli

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"

import "ren:constants"

// Detach from the controlling terminal. Parent process exits 0 on success.
// Child redirects stdio to log_path (append) or /dev/null.
daemonize :: proc(log_path: string) -> (ok: bool, err: string) {
	pid := posix.fork()
	if pid < 0 {
		return false, "fork failed"
	}
	if pid > 0 {
		os.exit(0)
	}

	if posix.setsid() < 0 {
		return false, "setsid failed"
	}

	pid = posix.fork()
	if pid < 0 {
		return false, "second fork failed"
	}
	if pid > 0 {
		os.exit(0)
	}

	_ = posix.umask({})
	_ = posix.chdir("/")

	null_fd := posix.open("/dev/null", {.RDWR}, {})
	if null_fd >= 0 {
		_ = posix.dup2(null_fd, posix.STDIN_FILENO)
		if null_fd > posix.STDERR_FILENO {
			_ = posix.close(null_fd)
		}
	}

	log_fd: posix.FD = -1
	if log_path != "" {
		path_c := strings.clone_to_cstring(log_path, context.temp_allocator)
		log_fd = posix.open(path_c, {.WRONLY, .CREAT, .APPEND}, {.IRUSR, .IWUSR})
	}
	if log_fd < 0 {
		log_fd = posix.open("/dev/null", {.WRONLY}, {})
	}
	if log_fd >= 0 {
		_ = posix.dup2(log_fd, posix.STDOUT_FILENO)
		_ = posix.dup2(log_fd, posix.STDERR_FILENO)
		if log_fd > posix.STDERR_FILENO {
			_ = posix.close(log_fd)
		}
	}
	return true, ""
}

daemon_pid_path :: proc(data_dir: string, allocator := context.allocator) -> string {
	return fmt.aprintf("%s/%s", data_dir, constants.DAEMON_PID_FILE, allocator = allocator)
}

daemon_log_path :: proc(data_dir: string, allocator := context.allocator) -> string {
	return fmt.aprintf("%s/%s", data_dir, constants.DAEMON_LOG_FILE, allocator = allocator)
}

daemon_write_pid :: proc(path: string) -> bool {
	pid := int(posix.getpid())
	text := fmt.tprintf("%d\n", pid)
	return os.write_entire_file(path, transmute([]u8)text) == nil
}

daemon_remove_pid :: proc(path: string) {
	_ = os.remove(path)
}

daemon_read_pid :: proc(path: string) -> (pid: int, ok: bool) {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return 0, false
	}
	s := strings.trim_space(string(data))
	n: int
	for i in 0 ..< len(s) {
		c := s[i]
		if c < '0' || c > '9' {
			break
		}
		n = n * 10 + int(c - '0')
	}
	if n <= 0 {
		return 0, false
	}
	return n, true
}

// True when a process with this pid exists (kill with signal 0).
daemon_pid_alive :: proc(pid: int) -> bool {
	if pid <= 0 {
		return false
	}
	return posix.kill(posix.pid_t(pid), posix.Signal(0)) == .OK
}

daemon_already_running :: proc(pid_path: string) -> (running: bool, pid: int) {
	existing, ok := daemon_read_pid(pid_path)
	if !ok {
		return false, 0
	}
	if daemon_pid_alive(existing) {
		return true, existing
	}
	daemon_remove_pid(pid_path)
	return false, 0
}

@(private)
daemon_stop_requested: bool

daemon_install_stop_signals :: proc() {
	daemon_stop_requested = false
	_ = posix.signal(.SIGTERM, daemon_stop_handler)
	_ = posix.signal(.SIGINT, daemon_stop_handler)
	_ = posix.signal(.SIGHUP, daemon_stop_handler)
}

daemon_stop_handler :: proc "c" (_: posix.Signal) {
	daemon_stop_requested = true
}

daemon_should_stop :: proc() -> bool {
	return daemon_stop_requested
}