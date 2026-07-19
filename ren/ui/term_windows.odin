// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

#+build windows

/*
Win32 console VT mode and window size.
*/

package ui

import win32 "core:sys/windows"

Term_Plat :: struct {
	in_mode:  win32.DWORD,
	out_mode: win32.DWORD,
	have_in:  bool,
	have_out: bool,
}

term_plat_enter_raw :: proc(t: ^Term) -> bool {
	hin := win32.GetStdHandle(win32.STD_INPUT_HANDLE)
	hout := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)
	if hin == win32.INVALID_HANDLE_VALUE || hout == win32.INVALID_HANDLE_VALUE {
		return false
	}

	in_mode: win32.DWORD
	out_mode: win32.DWORD
	if win32.GetConsoleMode(hin, &in_mode) {
		t.plat.in_mode = in_mode
		t.plat.have_in = true
		mode := in_mode
		mode &= ~(win32.ENABLE_ECHO_INPUT | win32.ENABLE_LINE_INPUT | win32.ENABLE_PROCESSED_INPUT)
		mode |= win32.ENABLE_VIRTUAL_TERMINAL_INPUT
		_ = win32.SetConsoleMode(hin, mode)
	}
	if win32.GetConsoleMode(hout, &out_mode) {
		t.plat.out_mode = out_mode
		t.plat.have_out = true
		mode := out_mode
		mode |= win32.ENABLE_VIRTUAL_TERMINAL_PROCESSING | win32.ENABLE_PROCESSED_OUTPUT
		_ = win32.SetConsoleMode(hout, mode)
	}
	display_handle = rawptr(hout)
	return true
}

term_plat_leave_raw :: proc(t: ^Term) {
	hin := win32.GetStdHandle(win32.STD_INPUT_HANDLE)
	hout := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)
	if t.plat.have_in && hin != win32.INVALID_HANDLE_VALUE {
		_ = win32.SetConsoleMode(hin, t.plat.in_mode)
	}
	if t.plat.have_out && hout != win32.INVALID_HANDLE_VALUE {
		_ = win32.SetConsoleMode(hout, t.plat.out_mode)
	}
}

term_plat_winsize :: proc() -> (w, h: int, ok: bool) {
	hout := win32.HANDLE(display_handle)
	if hout == nil || hout == win32.INVALID_HANDLE_VALUE {
		hout = win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)
	}
	info: win32.CONSOLE_SCREEN_BUFFER_INFO
	if !win32.GetConsoleScreenBufferInfo(hout, &info) {
		return 0, 0, false
	}
	cols := int(info.srWindow.Right - info.srWindow.Left + 1)
	rows := int(info.srWindow.Bottom - info.srWindow.Top + 1)
	if cols <= 0 || rows <= 0 {
		return 0, 0, false
	}
	return cols, rows, true
}
