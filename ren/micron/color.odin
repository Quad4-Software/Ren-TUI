// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Micron color tokens to RGB.
*/

package micron

import "core:math"
import "core:strconv"

Rgb :: struct {
	r, g, b: u8,
}

is_hex_byte :: proc(b: u8) -> bool {
	return (b >= '0' && b <= '9') || (b >= 'a' && b <= 'f') || (b >= 'A' && b <= 'F')
}

is_hex3 :: proc(s: string) -> bool {
	if len(s) != 3 {
		return false
	}
	for i in 0 ..< 3 {
		if !is_hex_byte(s[i]) {
			return false
		}
	}
	return true
}

is_hex6 :: proc(s: string) -> bool {
	if len(s) != 6 {
		return false
	}
	for i in 0 ..< 6 {
		if !is_hex_byte(s[i]) {
			return false
		}
	}
	return true
}

micron_color_token :: proc(c: string) -> bool {
	if c == "" || c == "default" {
		return false
	}
	if is_hex3(c) || is_hex6(c) {
		return true
	}
	return len(c) == 3 && c[0] == 'g'
}

hex_nibble :: proc(b: u8) -> u8 {
	switch b {
	case '0' ..= '9':
		return b - '0'
	case 'a' ..= 'f':
		return b - 'a' + 10
	case 'A' ..= 'F':
		return b - 'A' + 10
	}
	return 0
}

expand_hex3 :: proc(s: string) -> Rgb {
	r := hex_nibble(s[0])
	g := hex_nibble(s[1])
	b := hex_nibble(s[2])
	return Rgb{r = r * 17, g = g * 17, b = b * 17}
}

parse_hex6 :: proc(s: string) -> Rgb {
	return Rgb{
		r = hex_nibble(s[0]) << 4 | hex_nibble(s[1]),
		g = hex_nibble(s[2]) << 4 | hex_nibble(s[3]),
		b = hex_nibble(s[4]) << 4 | hex_nibble(s[5]),
	}
}

color_to_rgb :: proc(c: string, fallback: Rgb) -> Rgb {
	if !micron_color_token(c) {
		return fallback
	}
	if is_hex3(c) {
		return expand_hex3(c)
	}
	if is_hex6(c) {
		return parse_hex6(c)
	}
	if len(c) == 3 && c[0] == 'g' {
		v, ok := strconv.parse_int(c[1:])
		if !ok || v < 0 {
			v = 50
		}
		if v > 99 {
			v = 99
		}
		h := u8(math.floor(f64(v) * 2.55))
		return Rgb{r = h, g = h, b = h}
	}
	return fallback
}

heading_style :: proc(level: int, dark: bool) -> Style {
	if dark {
		switch level {
		case 1:
			return Style{fg = "222", bg = "bbb"}
		case 2:
			return Style{fg = "111", bg = "999"}
		case 3:
			return Style{fg = "000", bg = "777"}
		}
		return Style{fg = "ddd", bg = "default"}
	}
	switch level {
	case 1:
		return Style{fg = "000", bg = "777"}
	case 2:
		return Style{fg = "111", bg = "aaa"}
	case 3:
		return Style{fg = "222", bg = "ccc"}
	}
	return Style{fg = "222", bg = "default"}
}

plain_defaults :: proc(dark: bool) -> (fg, bg: string) {
	if dark {
		return "ddd", "default"
	}
	return "222", "default"
}
