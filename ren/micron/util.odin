// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Micron helpers shared by parsers.
*/

package micron

import "core:strings"

cut_once :: proc(s: string, sep: u8) -> (before, after: string, ok: bool) {
	i := strings.index_byte(s, sep)
	if i < 0 {
		return s, "", false
	}
	return s[:i], s[i + 1:], true
}

strip_byte :: proc(s: string, b: u8, allocator := context.temp_allocator) -> string {
	n := 0
	for i in 0 ..< len(s) {
		if s[i] != b {
			n += 1
		}
	}
	if n == len(s) {
		return s
	}
	out := make([]u8, n, allocator)
	j := 0
	for i in 0 ..< len(s) {
		if s[i] != b {
			out[j] = s[i]
			j += 1
		}
	}
	return string(out)
}

trim_ascii_spaces :: proc(s: string) -> string {
	i := 0
	for i < len(s) && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r') {
		i += 1
	}
	j := len(s)
	for j > i && (s[j - 1] == ' ' || s[j - 1] == '\t' || s[j - 1] == '\r') {
		j -= 1
	}
	return s[i:j]
}

is_literal_toggle_line :: proc(line: string) -> bool {
	i := 0
	for i < len(line) && (line[i] == ' ' || line[i] == '\t' || line[i] == '\r') {
		i += 1
	}
	if i + 2 > len(line) || line[i] != '`' || line[i + 1] != '=' {
		return false
	}
	j := i + 2
	for j < len(line) {
		c := line[j]
		if c != ' ' && c != '\t' && c != '\r' {
			return false
		}
		j += 1
	}
	return true
}

state_style :: proc(s: ^Parse_State) -> Style {
	return Style{
		fg = s.fg,
		bg = s.bg,
		bold = s.formatting.bold,
		underline = s.formatting.underline,
		italic = s.formatting.italic,
	}
}

apply_style_to_state :: proc(st: Style, s: ^Parse_State) {
	s.fg = st.fg
	s.bg = st.bg
	s.formatting.bold = st.bold
	s.formatting.underline = st.underline
	s.formatting.italic = st.italic
}

clone_limited :: proc(text: string, max_len: int, allocator := context.allocator) -> string {
	t := text
	if max_len > 0 && len(t) > max_len {
		t = t[:max_len]
	}
	return strings.clone(t, allocator)
}

sanitize_text_runes :: proc(text: string, allocator := context.allocator) -> string {
	needs := false
	for r in text {
		if r < 0x20 || r == 0x7f || (r >= 0x80 && r <= 0x9f) {
			needs = true
			break
		}
	}
	if !needs {
		return strings.clone(text, allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator = allocator)
	for r in text {
		ch := r
		if ch < 0x20 || ch == 0x7f || (ch >= 0x80 && ch <= 0x9f) {
			if ch == '\t' {
				ch = ' '
			} else {
				continue
			}
		}
		strings.write_rune(&b, ch)
	}
	return strings.to_string(b)
}
