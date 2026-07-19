// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Wrap micron document lines into visual rows for a given column width.
*/

package micron

import "core:strings"
import "core:unicode/utf8"

Layout_Seg :: struct {
	text:       string,
	style:      Style,
	kind:       Span_Kind,
	url:        string,
	link_i:     int,
	field_i:    int,
	field_spec: string,
}

Layout_Row :: struct {
	src_line: int,
	indent:   int,
	segs:     [dynamic]Layout_Seg,
}

layout_rows_destroy :: proc(rows: ^[dynamic]Layout_Row) {
	for &row in rows {
		delete(row.segs)
	}
	delete(rows^)
	rows^ = {}
}

layout_doc :: proc(doc: Doc, width: int, allocator := context.allocator) -> [dynamic]Layout_Row {
	rows := make([dynamic]Layout_Row, 0, len(doc.lines), allocator)
	w := max(1, width)
	link_i := 0
	field_i := 0
	for line_i in 0 ..< len(doc.lines) {
		line := doc.lines[line_i]
		indent := min(line.depth, 8) * 2
		content_w := max(1, w - indent)
		layout_wrap_line(&rows, line, line_i, indent, content_w, &link_i, &field_i, allocator)
	}
	return rows
}

layout_row_count :: proc(doc: Doc, width: int) -> int {
	rows := layout_doc(doc, width, context.temp_allocator)
	return len(rows)
}

layout_first_row_for_link :: proc(doc: Doc, width: int, link_focus: int) -> int {
	if link_focus < 0 {
		return 0
	}
	rows := layout_doc(doc, width, context.temp_allocator)
	for i in 0 ..< len(rows) {
		for seg in rows[i].segs {
			if seg.link_i == link_focus {
				return i
			}
		}
	}
	return 0
}

layout_first_row_for_field :: proc(doc: Doc, width: int, field_focus: int) -> int {
	if field_focus < 0 {
		return 0
	}
	rows := layout_doc(doc, width, context.temp_allocator)
	for i in 0 ..< len(rows) {
		for seg in rows[i].segs {
			if seg.field_i == field_focus {
				return i
			}
		}
	}
	return 0
}

layout_row_width :: proc(row: Layout_Row) -> int {
	n := row.indent
	for seg in row.segs {
		n += strings.rune_count(seg.text)
	}
	return n
}

@(private)
layout_wrap_line :: proc(
	rows: ^[dynamic]Layout_Row,
	line: Line,
	line_i: int,
	indent: int,
	content_w: int,
	link_i: ^int,
	field_i: ^int,
	allocator := context.allocator,
) {
	start_len := len(rows^)
	row := layout_new_row(line_i, indent, allocator)
	col := 0

	commit :: proc(rows: ^[dynamic]Layout_Row, row: ^Layout_Row, line_i, indent: int, allocator := context.allocator) {
		append(rows, row^)
		row^ = layout_new_row(line_i, indent, allocator)
	}

	if len(line.spans) == 0 {
		append(rows, row)
		return
	}

	for span in line.spans {
		span_link := -1
		if span.kind == .Link || span.kind == .Partial {
			span_link = link_i^
			link_i^ += 1
		}
		span_field := -1
		if span.kind == .Field {
			span_field = field_i^
			field_i^ += 1
		}

		if span.kind == .HR {
			for col < content_w {
				remain := content_w - col
				piece := strings.repeat("-", remain, allocator)
				append(&row.segs, Layout_Seg{
					text = piece,
					style = span.style,
					kind = .HR,
					url = "",
					link_i = -1,
					field_i = -1,
					field_spec = "",
				})
				col = content_w
			}
			commit(rows, &row, line_i, indent, allocator)
			col = 0
			continue
		}

		text := span.text
		for len(text) > 0 {
			remain := content_w - col
			if remain <= 0 {
				commit(rows, &row, line_i, indent, allocator)
				col = 0
				remain = content_w
			}

			if col == 0 && len(row.segs) == 0 {
				text = trim_leading_spaces(text)
				if len(text) == 0 {
					break
				}
			}

			r0, _ := utf8.decode_rune_in_string(text)
			if r0 == ' ' || r0 == '\t' {
				ws, ws_bytes := next_spaces(text)
				ws_cols := strings.rune_count(ws)
				if ws_cols > remain {
					commit(rows, &row, line_i, indent, allocator)
					col = 0
					text = text[ws_bytes:]
					continue
				}
				append(&row.segs, Layout_Seg{
					text = text[:ws_bytes],
					style = span.style,
					kind = span.kind,
					url = span.url,
					link_i = span_link,
					field_i = span_field,
					field_spec = span.field_spec,
				})
				col += ws_cols
				text = text[ws_bytes:]
				continue
			}

			word, word_bytes, rest := next_word(text)
			word_cols := strings.rune_count(word)
			if word_cols <= remain {
				append(&row.segs, Layout_Seg{
					text = text[:word_bytes],
					style = span.style,
					kind = span.kind,
					url = span.url,
					link_i = span_link,
					field_i = span_field,
					field_spec = span.field_spec,
				})
				col += word_cols
				text = rest
				continue
			}

			if col > 0 {
				commit(rows, &row, line_i, indent, allocator)
				col = 0
				continue
			}

			piece := take_runes(word, remain)
			piece_bytes := len(piece)
			append(&row.segs, Layout_Seg{
				text = text[:piece_bytes],
				style = span.style,
				kind = span.kind,
				url = span.url,
				link_i = span_link,
				field_i = span_field,
				field_spec = span.field_spec,
			})
			text = text[piece_bytes:]
			commit(rows, &row, line_i, indent, allocator)
			col = 0
		}
	}

	if len(row.segs) > 0 {
		append(rows, row)
	} else {
		delete(row.segs)
		if len(rows^) == start_len {
			append(rows, layout_new_row(line_i, indent, allocator))
		}
	}
}

@(private)
layout_new_row :: proc(line_i, indent: int, allocator := context.allocator) -> Layout_Row {
	return Layout_Row{
		src_line = line_i,
		indent = indent,
		segs = make([dynamic]Layout_Seg, 0, 4, allocator),
	}
}

@(private)
trim_leading_spaces :: proc(s: string) -> string {
	i := 0
	for i < len(s) {
		r, size := utf8.decode_rune_in_string(s[i:])
		if r != ' ' && r != '\t' {
			break
		}
		i += size
	}
	return s[i:]
}

@(private)
next_word :: proc(s: string) -> (word: string, bytes: int, rest: string) {
	i := 0
	for i < len(s) {
		r, size := utf8.decode_rune_in_string(s[i:])
		if r == ' ' || r == '\t' {
			break
		}
		i += size
	}
	return s[:i], i, s[i:]
}

@(private)
next_spaces :: proc(s: string) -> (spaces: string, bytes: int) {
	i := 0
	for i < len(s) {
		r, size := utf8.decode_rune_in_string(s[i:])
		if r != ' ' && r != '\t' {
			break
		}
		i += size
	}
	return s[:i], i
}

@(private)
take_runes :: proc(s: string, n: int) -> string {
	if n <= 0 || len(s) == 0 {
		return ""
	}
	i := 0
	count := 0
	for i < len(s) && count < n {
		_, size := utf8.decode_rune_in_string(s[i:])
		i += size
		count += 1
	}
	return s[:i]
}
