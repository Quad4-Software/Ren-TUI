// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Raw terminal mode alt screen and ANSI present.
Platform entry points live in term_posix.odin / term_windows.odin.
*/

package ui

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

Term :: struct {
	raw:      bool,
	width:    int,
	height:   int,
	out:      strings.Builder,
	prev:     Buffer,
	has_prev: bool,
	plat:     Term_Plat,
}

term_init :: proc(t: ^Term, preferred_color := "", enable_mouse := true) -> bool {
	caps_init(preferred_color)
	if !enable_mouse {
		caps_ptr().mouse = false
	}
	t^ = {}
	strings.builder_init(&t.out)
	if !term_plat_enter_raw(t) {
		return false
	}
	t.raw = true
	c := caps_ptr()
	if c.alt_screen {
		term_enter_alt(t)
	} else {
		strings.write_string(&t.out, "\x1b[2J\x1b[H")
		term_flush(t)
	}
	if c.cursor_ctl {
		term_hide_cursor(t)
	}
	if c.mouse {
		strings.write_string(&t.out, "\x1b[?1000h\x1b[?1002h\x1b[?1006h")
		term_flush(t)
	}
	term_query_size(t)
	return true
}

term_close :: proc(t: ^Term) {
	c := caps_ptr()
	if t.raw {
		if c.mouse {
			strings.write_string(&t.out, "\x1b[?1006l\x1b[?1002l\x1b[?1000l")
			term_flush(t)
		}
		if c.cursor_ctl {
			term_show_cursor(t)
		}
		if c.alt_screen {
			term_leave_alt(t)
		} else {
			strings.write_string(&t.out, "\x1b[0m\x1b[2J\x1b[H")
			term_flush(t)
		}
		term_plat_leave_raw(t)
		t.raw = false
	}
	if t.has_prev {
		buffer_destroy(&t.prev)
		t.has_prev = false
	}
	strings.builder_destroy(&t.out)
}

term_enter_alt :: proc(t: ^Term) {
	strings.write_string(&t.out, "\x1b[?1049h\x1b[2J\x1b[H")
	term_flush(t)
}

term_leave_alt :: proc(t: ^Term) {
	strings.write_string(&t.out, "\x1b[?1049l")
	term_flush(t)
}

term_hide_cursor :: proc(t: ^Term) {
	strings.write_string(&t.out, "\x1b[?25l")
	term_flush(t)
}

term_show_cursor :: proc(t: ^Term) {
	strings.write_string(&t.out, "\x1b[?25h")
	term_flush(t)
}

term_query_size :: proc(t: ^Term) {
	w, h, ok := term_plat_winsize()
	if ok && w > 0 && h > 0 {
		t.width = w
		t.height = h
		return
	}
	t.width = parse_int_env("COLUMNS", 80)
	t.height = parse_int_env("LINES", 24)
}

term_flush :: proc(t: ^Term) {
	s := strings.to_string(t.out)
	if len(s) > 0 {
		_ = display_write(transmute([]u8)s)
		strings.builder_reset(&t.out)
	}
}

@(private)
write_sgr :: proc(b: ^strings.Builder, fg, bg: Color, style: Style) {
	switch caps_ptr().mode {
	case .None:
		strings.write_string(b, "\x1b[0m")
		if .Bold in style {
			strings.write_string(b, "\x1b[1m")
		}
		if .Reverse in style {
			strings.write_string(b, "\x1b[7m")
		}
		return
	case .Ansi16:
		strings.write_string(b, "\x1b[0")
		if .Bold in style {
			strings.write_string(b, ";1")
		}
		if .Dim in style {
			strings.write_string(b, ";2")
		}
		if .Underline in style {
			strings.write_string(b, ";4")
		}
		if .Reverse in style {
			strings.write_string(b, ";7")
		}
		fi := color_to_ansi16(fg)
		bi := color_to_ansi16(bg)
		if fi < 8 {
			fmt.sbprintf(b, ";%d", 30 + fi)
		} else {
			fmt.sbprintf(b, ";%d", 90 + (fi - 8))
		}
		if bi < 8 {
			fmt.sbprintf(b, ";%d", 40 + bi)
		} else {
			fmt.sbprintf(b, ";%d", 100 + (bi - 8))
		}
		strings.write_string(b, "m")
		return
	case .Ansi256:
		strings.write_string(b, "\x1b[0")
		if .Bold in style {
			strings.write_string(b, ";1")
		}
		if .Dim in style {
			strings.write_string(b, ";2")
		}
		if .Underline in style {
			strings.write_string(b, ";4")
		}
		if .Reverse in style {
			strings.write_string(b, ";7")
		}
		fmt.sbprintf(b, ";38;5;%d", color_to_ansi256(fg))
		fmt.sbprintf(b, ";48;5;%d", color_to_ansi256(bg))
		strings.write_string(b, "m")
		return
	case .Truecolor:
	}
	strings.write_string(b, "\x1b[0")
	if .Bold in style {
		strings.write_string(b, ";1")
	}
	if .Dim in style {
		strings.write_string(b, ";2")
	}
	if .Underline in style {
		strings.write_string(b, ";4")
	}
	if .Reverse in style {
		strings.write_string(b, ";7")
	}
	fmt.sbprintf(b, ";38;2;%d;%d;%d", fg.r, fg.g, fg.b)
	fmt.sbprintf(b, ";48;2;%d;%d;%d", bg.r, bg.g, bg.b)
	strings.write_string(b, "m")
}

term_invalidate :: proc(t: ^Term) {
	t.has_prev = false
}

term_present :: proc(t: ^Term, buf: ^Buffer) {
	term_query_size(t)
	if buf.width != t.width || buf.height != t.height {
		buffer_resize(buf, t.width, t.height)
	}

	use_diff := t.has_prev && t.prev.width == buf.width && t.prev.height == buf.height

	strings.builder_reset(&t.out)
	if !use_diff {
		strings.write_string(&t.out, "\x1b[H")
	}

	last_fg := Color{255, 255, 255}
	last_bg := Color{0, 0, 0}
	last_style: Style
	sgr_valid := false
	cursor_x := -1
	cursor_y := -1

	for y in 0 ..< buf.height {
		for x in 0 ..< buf.width {
			idx := y * buf.width + x
			cell := buf.cells[idx]
			if cell.ch == CELL_WIDE_CONT {
				continue
			}
			if use_diff {
				prev := t.prev.cells[idx]
				if cell.ch == prev.ch && cell.fg == prev.fg && cell.bg == prev.bg && cell.style == prev.style {
					continue
				}
				if cursor_x != x || cursor_y != y {
					fmt.sbprintf(&t.out, "\x1b[%d;%dH", y + 1, x + 1)
					cursor_x = x
					cursor_y = y
					sgr_valid = false
				}
			}
			if !sgr_valid || cell.fg != last_fg || cell.bg != last_bg || cell.style != last_style {
				write_sgr(&t.out, cell.fg, cell.bg, cell.style)
				last_fg = cell.fg
				last_bg = cell.bg
				last_style = cell.style
				sgr_valid = true
			}
			ch := sanitize_rune(cell.ch)
			strings.write_rune(&t.out, ch)
			w := max(1, rune_cols(ch))
			cursor_x = x + w
			cursor_y = y
			if cursor_x >= buf.width {
				cursor_x = 0
				cursor_y = y + 1
			}
		}
		if !use_diff && y + 1 < buf.height {
			strings.write_string(&t.out, "\r\n")
			cursor_x = 0
			cursor_y = y + 1
		}
	}
	strings.write_string(&t.out, "\x1b[0m")
	term_flush(t)

	if !t.has_prev || t.prev.width != buf.width || t.prev.height != buf.height {
		if t.has_prev {
			buffer_destroy(&t.prev)
		}
		t.prev = buffer_create(buf.width, buf.height)
		t.has_prev = true
	}
	copy(t.prev.cells, buf.cells)
}

// Build present output into a builder for tests. Does not write to the terminal.
term_present_to_builder :: proc(t: ^Term, buf: ^Buffer, out: ^strings.Builder, want_diff: bool) {
	diff := want_diff && t.has_prev && t.prev.width == buf.width && t.prev.height == buf.height
	strings.builder_reset(out)
	if !diff {
		strings.write_string(out, "\x1b[H")
	}
	last_fg := Color{255, 255, 255}
	last_bg := Color{0, 0, 0}
	last_style: Style
	sgr_valid := false
	cursor_x := -1
	cursor_y := -1
	for y in 0 ..< buf.height {
		for x in 0 ..< buf.width {
			idx := y * buf.width + x
			cell := buf.cells[idx]
			if cell.ch == CELL_WIDE_CONT {
				continue
			}
			if diff {
				prev := t.prev.cells[idx]
				if cell.ch == prev.ch && cell.fg == prev.fg && cell.bg == prev.bg && cell.style == prev.style {
					continue
				}
				if cursor_x != x || cursor_y != y {
					fmt.sbprintf(out, "\x1b[%d;%dH", y + 1, x + 1)
					cursor_x = x
					cursor_y = y
					sgr_valid = false
				}
			}
			if !sgr_valid || cell.fg != last_fg || cell.bg != last_bg || cell.style != last_style {
				write_sgr(out, cell.fg, cell.bg, cell.style)
				last_fg = cell.fg
				last_bg = cell.bg
				last_style = cell.style
				sgr_valid = true
			}
			ch := sanitize_rune(cell.ch)
			strings.write_rune(out, ch)
			w := max(1, rune_cols(ch))
			cursor_x = x + w
			cursor_y = y
			if cursor_x >= buf.width {
				cursor_x = 0
				cursor_y = y + 1
			}
		}
		if !diff && y + 1 < buf.height {
			strings.write_string(out, "\r\n")
		}
	}
	strings.write_string(out, "\x1b[0m")
}

term_read_byte :: proc() -> (b: u8, ok: bool) {
	buf: [1]u8
	n, err := os.read(os.stdin, buf[:])
	if err != nil || n <= 0 {
		return 0, false
	}
	return buf[0], true
}

parse_int_env :: proc(name: string, fallback: int) -> int {
	v, ok := os.lookup_env(name, context.temp_allocator)
	if !ok {
		return fallback
	}
	n, n_ok := strconv.parse_int(v)
	if !n_ok {
		return fallback
	}
	return n
}
