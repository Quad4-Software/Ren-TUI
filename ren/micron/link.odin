// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Micron link span parser: `[label`url] or `[label`url`fields].
*/

package micron

import "core:strings"

parse_link :: proc(line: string, start: int, style: Style, allocator := context.allocator) -> (skip: int, span: Span, ok: bool) {
	if start < 0 || start >= len(line) || line[start] != '[' {
		return 0, {}, false
	}
	end_rel := strings.index_byte(line[start + 1:], ']')
	if end_rel < 0 {
		return 0, {}, false
	}
	end := start + 1 + end_rel
	link_data := line[start + 1:end]
	label := ""
	url := ""
	fields := ""
	before, after, cut_ok := cut_once(link_data, '`')
	if !cut_ok {
		url = link_data
	} else {
		label = before
		rest := after
		before2, after2, cut2 := cut_once(rest, '`')
		if !cut2 {
			url = rest
		} else {
			url = before2
			fields = after2
		}
	}
	if url == "" {
		return 0, {}, false
	}
	if label == "" {
		label = url
	}

	req := parse_request_spec(fields, context.temp_allocator)
	dest := url
	if !request_data_empty(req) {
		suffix := format_request_suffix(req, context.temp_allocator)
		if suffix != "" {
			dest = strings.concatenate({url, "`", suffix}, context.temp_allocator)
		}
	}
	formatted := format_nomadnetwork_url(dest, allocator)
	field_spec := ""
	if trim_ascii_spaces(fields) != "" {
		field_spec = strings.clone(fields, allocator)
	}
	return end - start + 1, Span{
		kind = .Link,
		text = sanitize_text_runes(label, allocator),
		url = formatted,
		style = style,
		field_spec = field_spec,
	}, true
}

format_request_suffix :: proc(r: Request_Data, allocator := context.allocator) -> string {
	if request_data_empty(r) {
		return ""
	}
	parts := make([dynamic]string, 0, len(r.vars) + len(r.fields), context.temp_allocator)
	for p in r.vars {
		append(&parts, strings.concatenate({p.key, "=", p.value}, context.temp_allocator))
	}
	for p in r.fields {
		append(&parts, strings.concatenate({"field.", p.key, "=", p.value}, context.temp_allocator))
	}
	return strings.join(parts[:], "|", allocator)
}
