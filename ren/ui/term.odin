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
		caps.mouse = false
	}
	t^ = {}
	strings.builder_init(&t.out)
	if !term_plat_enter_raw(t) {
		return false
	}
	t.raw = true
	if caps.alt_screen {
		term_enter_alt(t)
	} else {
		strings.write_string(&t.out, "\x1b[2J\x1b[H")
		term_flush(t)
	}
	if caps.cursor_ctl {
		term_hide_cursor(t)
	}
	if caps.mouse {
		strings.write_string(&t.out, "\x1b[?1000h\x1b[?1002h\x1b[?1006h")
		term_flush(t)
	}
	term_query_size(t)
	return true
}

term_close :: proc(t: ^Term) {
	if t.raw {
		if caps.mouse {
			strings.write_string(&t.out, "\x1b[?1006l\x1b[?1002l\x1b[?1000l")
			term_flush(t)
		}
		if caps.cursor_ctl {
			term_show_cursor(t)
		}
		if caps.alt_screen {
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
	switch caps.mode {
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

term_present :: proc(t: ^Term, buf: ^Buffer) {
	term_query_size(t)
	if buf.width != t.width || buf.height != t.height {
		buffer_resize(buf, t.width, t.height)
	}

	strings.builder_reset(&t.out)
	strings.write_string(&t.out, "\x1b[H")

	last_fg := Color{255, 255, 255}
	last_bg := Color{0, 0, 0}
	last_style: Style
	first := true

	for y in 0 ..< buf.height {
		for x in 0 ..< buf.width {
			cell := buf.cells[y * buf.width + x]
			if first || cell.fg != last_fg || cell.bg != last_bg || cell.style != last_style {
				write_sgr(&t.out, cell.fg, cell.bg, cell.style)
				last_fg = cell.fg
				last_bg = cell.bg
				last_style = cell.style
				first = false
			}
			ch := sanitize_rune(cell.ch)
			strings.write_rune(&t.out, ch)
		}
		if y + 1 < buf.height {
			strings.write_string(&t.out, "\r\n")
		}
	}
	strings.write_string(&t.out, "\x1b[0m")
	term_flush(t)

	if t.has_prev {
		buffer_destroy(&t.prev)
	}
	t.prev = buffer_create(buf.width, buf.height)
	copy(t.prev.cells, buf.cells)
	t.has_prev = true
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
