// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

#+build windows

package ui

import "core:os"
import "core:strings"

import "ren:constants"

Stderr_Plat :: struct {}

display_handle: rawptr

display_write_plat :: proc(data: []u8) -> bool {
	if len(data) == 0 {
		return true
	}
	n, err := os.write(os.stdout, data)
	return err == nil && n == len(data)
}

stderr_redirect_start_plat :: proc(r: ^Stderr_Redirect, log_path: string) -> bool {
	r^ = {}
	if log_path == "" {
		return false
	}
	if override := os.get_env(constants.ENV_KEEP_STDERR, context.temp_allocator); override == "1" || override == "true" {
		return false
	}
	// Windows console redirect is best-effort via keeping stderr visible.
	// Librns noise may still appear unless REN_KEEP_STDERR is unset and a
	// future CRT freopen path is added. Preserve display on stdout.
	_ = strings.clone(log_path)
	return false
}

stderr_redirect_stop_plat :: proc(r: ^Stderr_Redirect) {
	if r.log_path != "" {
		delete(r.log_path)
	}
	r^ = {}
}
