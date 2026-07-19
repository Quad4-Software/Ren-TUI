// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Terminal capability detection and forced UI modes.
*/

package ui

import "core:os"
import "core:strings"

import "ren:constants"

Color_Mode :: enum {
	None,
	Ansi16,
	Ansi256,
	Truecolor,
}

Caps :: struct {
	mode:       Color_Mode,
	ascii:      bool,
	alt_screen: bool,
	cursor_ctl: bool,
	mouse:      bool,
	name:       string,
}

caps: Caps

caps_init :: proc(preferred := "") {
	caps = Caps{
		mode = .Truecolor,
		ascii = false,
		alt_screen = true,
		cursor_ctl = true,
		mouse = true,
		name = "full",
	}

	force := strings.to_lower(preferred, context.temp_allocator)
	if force == "" {
		force = strings.to_lower(os.get_env(constants.ENV_UI, context.temp_allocator), context.temp_allocator)
	}
	switch force {
	case "full", "modern", "truecolor", "24":
		caps.name = "full"
		caps.mode = .Truecolor
		return
	case "256", "ansi256":
		caps.mode = .Ansi256
		caps.ascii = false
		caps.alt_screen = true
		caps.cursor_ctl = true
		caps.name = "256"
		return
	case "compat", "basic", "16":
		apply_compat()
		return
	case "dumb", "plain", "ascii":
		apply_dumb()
		return
	}

	if os.get_env("NO_COLOR", context.temp_allocator) != "" {
		caps.mode = .None
		caps.ascii = true
		caps.mouse = false
		caps.name = "nocolor"
		return
	}

	term := strings.to_lower(os.get_env("TERM", context.temp_allocator), context.temp_allocator)
	colorterm := strings.to_lower(os.get_env("COLORTERM", context.temp_allocator), context.temp_allocator)
	utf8 := locale_is_utf8()

	if term == "" || term == "dumb" || term == "unknown" {
		apply_dumb()
		return
	}

	if !utf8 {
		caps.ascii = true
	}

	if strings.contains(term, "linux") {
		caps.mode = .Ansi16
		caps.ascii = true
		caps.alt_screen = false
		caps.cursor_ctl = true
		caps.name = "compat"
		return
	}

	if strings.contains(term, "vt100") || strings.contains(term, "vt102") {
		apply_compat()
		caps.alt_screen = false
		caps.mouse = false
		return
	}

	truecolor := colorterm == "truecolor" || colorterm == "24bit" ||
		strings.contains(term, "truecolor") || strings.contains(term, "direct") ||
		strings.contains(term, "alacritty") || strings.contains(term, "kitty") ||
		strings.contains(term, "foot") || strings.contains(term, "wezterm")

	if truecolor && caps.mode != .None {
		caps.mode = .Truecolor
		caps.name = "full" if !caps.ascii else "compat"
		return
	}

	if strings.contains(term, "256color") || strings.contains(term, "xterm") ||
	   strings.contains(term, "screen") || strings.contains(term, "tmux") ||
	   strings.contains(term, "rxvt") {
		if caps.mode == .None {
			caps.name = "nocolor"
			return
		}
		// NomadNet default target: UTF-8 + at least 256 colors
		caps.mode = .Ansi256
		caps.name = "256"
		return
	}

	if caps.mode == .None {
		caps.name = "nocolor"
		return
	}
	caps.mode = .Ansi16
	caps.ascii = true
	caps.name = "compat"
}

@(private)
apply_compat :: proc() {
	caps.mode = .Ansi16
	caps.ascii = true
	caps.alt_screen = true
	caps.cursor_ctl = true
	caps.name = "compat"
}

@(private)
apply_dumb :: proc() {
	caps.mode = .None
	caps.ascii = true
	caps.alt_screen = false
	caps.cursor_ctl = false
	caps.mouse = false
	caps.name = "dumb"
}

color_to_ansi256 :: proc(c: Color) -> int {
	if c.r == c.g && c.g == c.b {
		if c.r < 8 {
			return 16
		}
		if c.r > 248 {
			return 231
		}
		return 232 + int((int(c.r) - 8) * 24 / 247)
	}
	r := (int(c.r) * 5) / 255
	g := (int(c.g) * 5) / 255
	b := (int(c.b) * 5) / 255
	return 16 + 36 * r + 6 * g + b
}

locale_is_utf8 :: proc() -> bool {
	for key in ([]string{"LC_ALL", "LC_CTYPE", "LANG"}) {
		v := strings.to_lower(os.get_env(key, context.temp_allocator), context.temp_allocator)
		if v == "" {
			continue
		}
		return strings.contains(v, "utf-8") || strings.contains(v, "utf8")
	}
	return true
}

caps_border :: proc() -> (tl, tr, bl, br, h, v: rune) {
	if caps.ascii {
		return '+', '+', '+', '+', '-', '|'
	}
	return '┌', '┐', '└', '┘', '─', '│'
}

caps_cursor_glyph :: proc() -> rune {
	if caps.ascii {
		return '_'
	}
	return '▌'
}

color_to_ansi16 :: proc(c: Color) -> int {
	bright := int(c.r) + int(c.g) + int(c.b) >= 360
	r := c.r >= 128
	g := c.g >= 128
	b := c.b >= 128
	idx := 0
	if r { idx |= 1 }
	if g { idx |= 2 }
	if b { idx |= 4 }
	if bright && idx != 0 {
		idx |= 8
	} else if bright && idx == 0 {
		idx = 7
	}
	if !bright && idx == 7 {
		idx = 8
	}
	return idx
}

sanitize_rune :: proc(ch: rune) -> rune {
	// Never emit C0, DEL, or C1 controls into the terminal stream.
	if ch < 0x20 || ch == 0x7f || (ch >= 0x80 && ch <= 0x9f) {
		return ' '
	}
	if !caps.ascii {
		return ch
	}
	switch ch {
	case '┌', '┐', '└', '┘', '┼', '├', '┤', '┬', '┴':
		return '+'
	case '─', '━', '┄', '┅':
		return '-'
	case '│', '┃', '┆', '┇':
		return '|'
	case '▌', '▐', '█', '▀', '▄', '■', '▪':
		return '#'
	case '•', '·':
		return '*'
	case '→', '⇒':
		return '>'
	case '←', '⇐':
		return '<'
	case '…':
		return '.'
	}
	if ch > 0x7e {
		return '?'
	}
	return ch
}
