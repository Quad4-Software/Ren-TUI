// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

#+build freebsd, openbsd, netbsd

/*
BSD termios raw mode. Window size falls back to COLUMNS/LINES env.
*/

package ui

import "core:sys/posix"

Term_Plat :: struct {
	orig: posix.termios,
}

term_plat_enter_raw :: proc(t: ^Term) -> bool {
	if posix.tcgetattr(posix.STDIN_FILENO, &t.plat.orig) != .OK {
		return false
	}
	raw := t.plat.orig
	raw.c_lflag -= {.ECHO, .ICANON, .ISIG, .IEXTEN}
	raw.c_iflag -= {.IXON, .ICRNL, .BRKINT, .INPCK, .ISTRIP}
	raw.c_oflag -= {.OPOST}
	raw.c_cc[.VMIN] = 0
	raw.c_cc[.VTIME] = 1
	if posix.tcsetattr(posix.STDIN_FILENO, .TCSANOW, &raw) != .OK {
		return false
	}
	return true
}

term_plat_leave_raw :: proc(t: ^Term) {
	_ = posix.tcsetattr(posix.STDIN_FILENO, .TCSANOW, &t.plat.orig)
}

term_plat_winsize :: proc() -> (w, h: int, ok: bool) {
	return 0, 0, false
}
