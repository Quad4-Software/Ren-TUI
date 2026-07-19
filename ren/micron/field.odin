// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Micron field span parser (display-only widgets).
*/

package micron

import "core:strconv"
import "core:strings"

parse_field :: proc(line: string, start: int, style: Style, allocator := context.allocator) -> (skip: int, span: Span, ok: bool) {
	if start < 0 || start >= len(line) || line[start] != '<' {
		return 0, {}, false
	}
	field_start := start + 1
	bt_rel := strings.index_byte(line[field_start:], '`')
	if bt_rel < 0 {
		return 0, {}, false
	}
	bt := field_start + bt_rel
	field_content := line[field_start:bt]
	name := field_content
	value := ""
	masked := false
	kind_label := "text"
	width := 24

	if before, after, cut_ok := cut_once(field_content, '|'); cut_ok {
		flags := before
		rest := after
		name = rest
		if next := strings.index_byte(rest, '|'); next >= 0 {
			name = rest[:next]
			rest = rest[next + 1:]
			value = rest
			if before2, after2, cut2 := cut_once(rest, '|'); cut2 {
				value = before2
				_ = after2
			}
		}
		if strings.contains(flags, "^") {
			kind_label = "radio"
			flags = strip_byte(flags, '^')
		} else if strings.contains(flags, "?") {
			kind_label = "check"
			flags = strip_byte(flags, '?')
		} else if strings.contains(flags, "!") {
			masked = true
			flags = strip_byte(flags, '!')
		}
		if flags != "" {
			if w, wok := strconv.parse_int(flags); wok && w > 0 {
				if w > 64 {
					w = 64
				}
				width = w
			}
		}
	}

	end_rel := strings.index_byte(line[bt + 1:], '>')
	if end_rel < 0 {
		return 0, {}, false
	}
	end := bt + 1 + end_rel
	data := line[bt + 1:end]
	label := name if name != "" else data
	disp: string
	switch kind_label {
	case "check", "radio":
		disp = strings.concatenate({"[ ] ", label}, allocator)
	case:
		shown := value if value != "" else data
		if masked {
			n := min(width, max(1, len(shown)))
			stars, _ := strings.repeat("*", n, context.temp_allocator)
			shown = stars
		}
		if len(shown) > width {
			shown = shown[:width]
		}
		disp = strings.concatenate({"[", label, "=", shown, "]"}, allocator)
	}
	text := sanitize_text_runes(disp, allocator)
	delete(disp)
	return end - start + 1, Span{
		kind = .Field,
		text = text,
		style = style,
	}, true
}
