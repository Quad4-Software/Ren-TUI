// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Micron field span parser (NomadNet-compatible form widgets).
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
	kind := Field_Kind.Text
	width := 24
	prechecked := false

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
				prechecked = after2 == "*"
			}
		}
		if strings.contains(flags, "^") {
			kind = .Radio
			flags = strip_byte(flags, '^')
		} else if strings.contains(flags, "?") {
			kind = .Checkbox
			flags = strip_byte(flags, '?')
		} else if strings.contains(flags, "!") {
			masked = true
			flags = strip_byte(flags, '!')
		}
		if flags != "" {
			if w, wok := strconv.parse_int(flags); wok && w > 0 {
				if w > 256 {
					w = 256
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

	field_name := strings.clone(name, allocator)
	field_label := ""
	field_value := ""
	switch kind {
	case .Checkbox, .Radio:
		field_value = strings.clone(value if value != "" else data, allocator)
		field_label = strings.clone(data if data != "" else name, allocator)
	case .Text, .None:
		field_value = strings.clone(data if data != "" else value, allocator)
		field_label = strings.clone(name if name != "" else data, allocator)
	}

	disp := field_display_text(kind, field_label, field_value, width, masked, prechecked, allocator)
	text := sanitize_text_runes(disp, allocator)
	delete(disp)
	return end - start + 1, Span{
		kind = .Field,
		text = text,
		style = style,
		field_kind = kind,
		field_name = field_name,
		field_value = field_value,
		field_label = field_label,
		field_width = width,
		field_masked = masked,
		field_prechecked = prechecked,
	}, true
}

field_display_text :: proc(
	kind: Field_Kind,
	label, value: string,
	width: int,
	masked: bool,
	checked: bool,
	allocator := context.allocator,
) -> string {
	switch kind {
	case .Checkbox, .Radio:
		mark := "[x] " if checked else "[ ] "
		lab := label if label != "" else value
		return strings.concatenate({mark, lab}, allocator)
	case .Text, .None:
		shown := value
		if masked {
			n := min(max(1, width), max(1, len(shown)))
			if len(shown) == 0 {
				n = min(width, 1)
			}
			stars, _ := strings.repeat("*", n, context.temp_allocator)
			shown = stars
		}
		w := max(1, width)
		if len(shown) > w {
			shown = shown[:w]
		}
		lab := label if label != "" else "field"
		return strings.concatenate({"[", lab, "=", shown, "]"}, allocator)
	}
	return strings.clone("", allocator)
}
