// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

#+build darwin

/*
Darwin termios raw mode and TIOCGWINSZ.
*/

package ui

import "core:c"
import "core:sys/posix"

Winsize :: struct {
	row:    u16,
	col:    u16,
	xpixel: u16,
	ypixel: u16,
}

Term_Plat :: struct {
	orig: posix.termios,
}

TIOCGWINSZ_DARWIN :: 0x40087468

foreign import libc "system:System.framework"

foreign libc {
	ioctl :: proc(fd: c.int, request: c.ulong, #c_vararg args: ..any) -> c.int ---
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
	ws: Winsize
	ret := ioctl(c.int(display_fd), TIOCGWINSZ_DARWIN, &ws)
	if ret == 0 && ws.col > 0 && ws.row > 0 {
		return int(ws.col), int(ws.row), true
	}
	return 0, 0, false
}
