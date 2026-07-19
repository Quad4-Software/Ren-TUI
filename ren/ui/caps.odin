// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Terminal capability detection and forced UI modes.
Caps live on Loop. Standalone tests use a package fallback.
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

_standalone_caps: Caps

caps_ptr :: proc() -> ^Caps {
	if _active != nil {
		return &_active.caps
	}
	return &_standalone_caps
}

caps_get :: proc() -> Caps {
	return caps_ptr()^
}

caps_init :: proc(preferred := "") {
	c := caps_ptr()
	c^ = Caps{
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
		c.name = "full"
		c.mode = .Truecolor
		return
	case "256", "ansi256":
		c.mode = .Ansi256
		c.ascii = false
		c.alt_screen = true
		c.cursor_ctl = true
		c.name = "256"
		return
	case "compat", "basic", "16":
		apply_compat()
		return
	case "dumb", "plain", "ascii":
		apply_dumb()
		return
	}

	if os.get_env("NO_COLOR", context.temp_allocator) != "" {
		c.mode = .None
		c.ascii = true
		c.mouse = false
		c.name = "nocolor"
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
		c.ascii = true
	}

	if strings.contains(term, "linux") {
		c.mode = .Ansi16
		c.ascii = true
		c.alt_screen = false
		c.cursor_ctl = true
		c.name = "compat"
		return
	}

	if strings.contains(term, "vt100") || strings.contains(term, "vt102") {
		apply_compat()
		c.alt_screen = false
		c.mouse = false
		return
	}

	truecolor := colorterm == "truecolor" || colorterm == "24bit" ||
		strings.contains(term, "truecolor") || strings.contains(term, "direct") ||
		strings.contains(term, "alacritty") || strings.contains(term, "kitty") ||
		strings.contains(term, "foot") || strings.contains(term, "wezterm")

	if truecolor && c.mode != .None {
		c.mode = .Truecolor
		c.name = "full" if !c.ascii else "compat"
		return
	}

	if strings.contains(term, "256color") || strings.contains(term, "xterm") ||
	   strings.contains(term, "screen") || strings.contains(term, "tmux") ||
	   strings.contains(term, "rxvt") {
		if c.mode == .None {
			c.name = "nocolor"
			return
		}
		c.mode = .Ansi256
		c.name = "256"
		return
	}

	if c.mode == .None {
		c.name = "nocolor"
		return
	}
	c.mode = .Ansi16
	c.ascii = true
	c.name = "compat"
}

@(private)
apply_compat :: proc() {
	c := caps_ptr()
	c.mode = .Ansi16
	c.ascii = true
	c.alt_screen = true
	c.cursor_ctl = true
	c.name = "compat"
}

@(private)
apply_dumb :: proc() {
	c := caps_ptr()
	c.mode = .None
	c.ascii = true
	c.alt_screen = false
	c.cursor_ctl = false
	c.mouse = false
	c.name = "dumb"
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
	if caps_ptr().ascii {
		return '+', '+', '+', '+', '-', '|'
	}
	return '┌', '┐', '└', '┘', '─', '│'
}

caps_cursor_glyph :: proc() -> rune {
	if caps_ptr().ascii {
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
	if ch < 0x20 || ch == 0x7f || (ch >= 0x80 && ch <= 0x9f) {
		return ' '
	}
	if !caps_ptr().ascii {
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
