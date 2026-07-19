// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Micron layout helpers for document link maps and widths.
*/

package micron

import "core:strings"

line_plain_width :: proc(line: Line) -> int {
	n := 0
	if line.depth > 0 {
		n += min(line.depth, 8) * 2
	}
	for span in line.spans {
		n += strings.rune_count(span.text)
	}
	return n
}

doc_link_count :: proc(doc: Doc) -> int {
	n := 0
	for line in doc.lines {
		for span in line.spans {
			if span.kind == .Link || span.kind == .Partial {
				n += 1
			}
		}
	}
	return n
}

link_index_before_line :: proc(doc: Doc, line_idx: int) -> int {
	n := 0
	limit := min(line_idx, len(doc.lines))
	for i in 0 ..< limit {
		for span in doc.lines[i].spans {
			if span.kind == .Link || span.kind == .Partial {
				n += 1
			}
		}
	}
	return n
}
