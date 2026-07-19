// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Paint micron documents into the TUI cell buffer.
*/

package app

import "ren:micron"
import "ren:ui"

style_to_ui :: proc(st: micron.Style, fallback_fg, fallback_bg: ui.Color) -> (fg, bg: ui.Color, us: ui.Style) {
	fg = rgb_to_ui(micron.color_to_rgb(st.fg, ui_to_rgb(fallback_fg)))
	bg = rgb_to_ui(micron.color_to_rgb(st.bg, ui_to_rgb(fallback_bg)))
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

ui_to_rgb :: proc(c: ui.Color) -> micron.Rgb {
	return micron.Rgb{r = c.r, g = c.g, b = c.b}
}

rgb_to_ui :: proc(c: micron.Rgb) -> ui.Color {
	return ui.Color{r = c.r, g = c.g, b = c.b}
}

paint_doc :: proc(
	buf: ^ui.Buffer,
	r: ui.Rect,
	doc: micron.Doc,
	scroll: int,
	focus_link: int,
	hits: ^[dynamic]micron.Link_Hit,
) {
	if hits != nil {
		clear(hits)
	}
	t := ui.theme()
	page_fg := rgb_to_ui(micron.color_to_rgb(doc.page_fg, ui_to_rgb(t.fg)))
	page_bg := rgb_to_ui(micron.color_to_rgb(doc.page_bg, ui_to_rgb(t.bg)))
	if doc.page_bg == "" || doc.page_bg == "default" {
		page_bg = t.bg
	}
	if doc.page_fg == "" {
		page_fg = t.fg
	}

	link_i := micron.link_index_before_line(doc, scroll)
	for row in 0 ..< r.h {
		y := r.y + row
		idx := scroll + row
		ui.buffer_fill_rect(buf, r.x, y, r.w, 1, ' ', page_fg, page_bg)
		if idx < 0 || idx >= len(doc.lines) {
			continue
		}
		line := doc.lines[idx]
		indent := min(line.depth, 8) * 2
		content_w := micron.line_plain_width(line)
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
					append(hits, micron.Link_Hit{
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

paint_lines :: proc(buf: ^ui.Buffer, r: ui.Rect, lines: []micron.Line, scroll: int) {
	doc: micron.Doc
	doc.lines = make([dynamic]micron.Line, 0, len(lines), context.temp_allocator)
	for line in lines {
		append(&doc.lines, line)
	}
	paint_doc(buf, r, doc, scroll, -1, nil)
}
