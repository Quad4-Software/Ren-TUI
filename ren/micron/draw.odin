// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Render Micron documents into the TUI cell buffer with link hit maps.
*/

package micron

import "core:strings"

import "ren:ui"

style_to_ui :: proc(st: Style, fallback_fg, fallback_bg: ui.Color) -> (fg, bg: ui.Color, us: ui.Style) {
	fg = color_to_rgb(st.fg, fallback_fg)
	bg = color_to_rgb(st.bg, fallback_bg)
	if st.bg == "" || st.bg == "default" {
		bg = fallback_bg
	}
	if st.fg == "" || st.fg == "default" {
		fg = fallback_fg
	}
	us = {}
	if st.bold {
		us += {.Bold}
	}
	if st.underline {
		us += {.Underline}
	}
	if st.italic {
		us += {.Dim}
	}
	return
}

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

draw_doc :: proc(
	buf: ^ui.Buffer,
	r: ui.Rect,
	doc: Doc,
	scroll: int,
	focus_link: int,
	hits: ^[dynamic]Link_Hit,
) {
	if hits != nil {
		clear(hits)
	}
	t := ui.theme()
	page_fg := color_to_rgb(doc.page_fg, t.fg)
	page_bg := color_to_rgb(doc.page_bg, t.bg)
	if doc.page_bg == "" || doc.page_bg == "default" {
		page_bg = t.bg
	}
	if doc.page_fg == "" {
		page_fg = t.fg
	}

	link_i := link_index_before_line(doc, scroll)
	for row in 0 ..< r.h {
		y := r.y + row
		idx := scroll + row
		ui.buffer_fill_rect(buf, r.x, y, r.w, 1, ' ', page_fg, page_bg)
		if idx < 0 || idx >= len(doc.lines) {
			continue
		}
		line := doc.lines[idx]
		indent := min(line.depth, 8) * 2
		content_w := line_plain_width(line)
		x := r.x
		switch line.align {
		case .Left:
			x = r.x
		case .Center:
			x = r.x + max(0, (r.w - content_w) / 2)
		case .Right:
			x = r.x + max(0, r.w - content_w)
		}
		x += indent
		for span in line.spans {
			fg, bg, us := style_to_ui(span.style, page_fg, page_bg)
			text := span.text
			is_link := span.kind == .Link || span.kind == .Partial
			if is_link {
				us += {.Underline}
				if focus_link == link_i {
					us += {.Reverse}
					fg = t.highlight_fg
				} else {
					fg = t.title
				}
			}
			if span.kind == .HR {
				fg = t.muted
			}
			start_x := x
			for ch in text {
				if x >= r.x + r.w {
					break
				}
				ui.buffer_put(buf, x, y, ch, fg, bg, us)
				x += 1
			}
			if is_link {
				if hits != nil && span.url != "" {
					append(hits, Link_Hit{
						line_idx = idx,
						x0 = start_x,
						x1 = x,
						url = span.url,
					})
				}
				link_i += 1
			}
			if x >= r.x + r.w {
				break
			}
		}
	}
}

draw_lines :: proc(buf: ^ui.Buffer, r: ui.Rect, lines: []Line, scroll: int) {
	doc: Doc
	doc.lines = make([dynamic]Line, 0, len(lines), context.temp_allocator)
	for line in lines {
		append(&doc.lines, line)
	}
	draw_doc(buf, r, doc, scroll, -1, nil)
}
