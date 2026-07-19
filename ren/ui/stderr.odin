// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Quiet librns/runtime stdio during TUI. UI writes go to the real terminal.
*/

package ui

Stderr_Redirect :: struct {
	active:   bool,
	log_path: string,
	plat:     Stderr_Plat,
}

display_write :: proc(data: []u8) -> bool {
	return display_write_plat(data)
}

stderr_redirect_start :: proc(r: ^Stderr_Redirect, log_path: string) -> bool {
	return stderr_redirect_start_plat(r, log_path)
}

stderr_redirect_stop :: proc(r: ^Stderr_Redirect) {
	stderr_redirect_stop_plat(r)
}
