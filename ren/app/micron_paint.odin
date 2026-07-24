// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Paint micron documents into the TUI cell buffer with word wrap.
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
	focus_field: int,
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

	rows := micron.layout_doc(doc, r.w, context.temp_allocator)
	for row in 0 ..< r.h {
		y := r.y + row
		idx := scroll + row
		ui.buffer_fill_rect(buf, r.x, y, r.w, 1, ' ', page_fg, page_bg)
		if idx < 0 || idx >= len(rows) {
			continue
		}
		layout_row := rows[idx]
		src := doc.lines[layout_row.src_line] if layout_row.src_line >= 0 && layout_row.src_line < len(doc.lines) else micron.Line{}
		content_w := micron.layout_row_width(layout_row)
		x := r.x
		switch src.align {
		case .Left:
			x = r.x
		case .Center:
			x = r.x + max(0, (r.w - content_w) / 2)
		case .Right:
			x = r.x + max(0, r.w - content_w)
		}
		x += layout_row.indent
		for seg in layout_row.segs {
			fg, bg, us := style_to_ui(seg.style, page_fg, page_bg)
			is_link := seg.kind == .Link || seg.kind == .Partial
			is_field := seg.kind == .Field
			if is_link {
				us += {.Underline}
				if focus_link >= 0 && seg.link_i == focus_link {
					us += {.Reverse}
					fg = t.highlight_fg
				} else {
					fg = t.title
				}
			}
			if is_field {
				if focus_field >= 0 && seg.field_i == focus_field {
					us += {.Reverse}
					fg = t.highlight_fg
				} else {
					fg = t.ok
				}
			}
			if seg.kind == .HR {
				fg = t.muted
			}
			start_x := x
			for raw in seg.text {
				ch := raw
				if x >= r.x + r.w {
					break
				}
				w := ui.rune_cols(ch)
				if w <= 0 {
					if ch < 0x20 || ch == 0x7f || (ch >= 0x80 && ch <= 0x9f) {
						w = 1
						ch = ' '
					} else {
						continue
					}
				}
				if x + w > r.x + r.w {
					break
				}
				ui.buffer_put(buf, x, y, ch, fg, bg, us)
				for i in 1 ..< w {
					ui.buffer_put(buf, x + i, y, ui.CELL_WIDE_CONT, fg, bg, us)
				}
				x += w
			}
			if hits != nil && x > start_x {
				if is_link && seg.url != "" {
					append(hits, micron.Link_Hit{
						line_idx = idx,
						x0 = start_x,
						x1 = x,
						url = seg.url,
						field_spec = seg.field_spec,
						field_i = -1,
					})
				} else if is_field && seg.field_i >= 0 {
					append(hits, micron.Link_Hit{
						line_idx = idx,
						x0 = start_x,
						x1 = x,
						url = "",
						field_spec = "",
						field_i = seg.field_i,
					})
				}
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
	paint_doc(buf, r, doc, scroll, -1, -1, nil)
}
