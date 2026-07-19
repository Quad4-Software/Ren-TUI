// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

#+build linux, darwin, freebsd, openbsd, netbsd

package ui

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sys/posix"

import "ren:constants"

Stderr_Plat :: struct {
	saved_out: posix.FD,
	saved_err: posix.FD,
}

// Real terminal fd for presents and clipboard. Defaults to stdout.
display_fd: posix.FD = posix.STDOUT_FILENO

display_write_plat :: proc(data: []u8) -> bool {
	if len(data) == 0 {
		return true
	}
	n := posix.write(display_fd, raw_data(data), len(data))
	return n == len(data)
}

stderr_redirect_start_plat :: proc(r: ^Stderr_Redirect, log_path: string) -> bool {
	r^ = {}
	display_fd = posix.STDOUT_FILENO
	if log_path == "" {
		return false
	}
	if override := os.get_env(constants.ENV_KEEP_STDERR, context.temp_allocator); override == "1" || override == "true" {
		return false
	}

	dir := filepath.dir(log_path)
	_ = os.make_directory_all(dir)

	path_c := strings.clone_to_cstring(log_path, context.temp_allocator)
	fd := posix.open(path_c, {.WRONLY, .CREAT, .APPEND}, {.IRUSR, .IWUSR})
	if fd < 0 {
		return false
	}

	saved_out := posix.dup(posix.STDOUT_FILENO)
	saved_err := posix.dup(posix.STDERR_FILENO)
	if saved_out < 0 || saved_err < 0 {
		if saved_out >= 0 {
			_ = posix.close(saved_out)
		}
		if saved_err >= 0 {
			_ = posix.close(saved_err)
		}
		_ = posix.close(fd)
		return false
	}

	if posix.dup2(fd, posix.STDOUT_FILENO) < 0 || posix.dup2(fd, posix.STDERR_FILENO) < 0 {
		_ = posix.dup2(saved_out, posix.STDOUT_FILENO)
		_ = posix.dup2(saved_err, posix.STDERR_FILENO)
		_ = posix.close(fd)
		_ = posix.close(saved_out)
		_ = posix.close(saved_err)
		return false
	}
	_ = posix.close(fd)

	r.active = true
	r.plat.saved_out = saved_out
	r.plat.saved_err = saved_err
	r.log_path = strings.clone(log_path)
	display_fd = saved_out
	return true
}

stderr_redirect_stop_plat :: proc(r: ^Stderr_Redirect) {
	if !r.active {
		display_fd = posix.STDOUT_FILENO
		return
	}
	_ = posix.dup2(r.plat.saved_out, posix.STDOUT_FILENO)
	_ = posix.dup2(r.plat.saved_err, posix.STDERR_FILENO)
	_ = posix.close(r.plat.saved_out)
	_ = posix.close(r.plat.saved_err)
	delete(r.log_path)
	r^ = {}
	display_fd = posix.STDOUT_FILENO
}
