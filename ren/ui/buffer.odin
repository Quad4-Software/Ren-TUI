// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Retained cell buffer the UI paints into each frame.
*/

package ui

Style :: bit_set[Style_Bit]
Style_Bit :: enum {
	Bold,
	Dim,
	Underline,
	Reverse,
}

Cell :: struct {
	ch:    rune,
	fg:    Color,
	bg:    Color,
	style: Style,
}

Buffer :: struct {
	width:  int,
	height: int,
	cells:  []Cell,
}

buffer_create :: proc(width, height: int, allocator := context.allocator) -> Buffer {
	w := max(width, 1)
	h := max(height, 1)
	cells := make([]Cell, w * h, allocator)
	t := theme()
	for &c in cells {
		c = Cell{ch = ' ', fg = t.fg, bg = t.bg, style = {}}
	}
	return Buffer{width = w, height = h, cells = cells}
}

buffer_destroy :: proc(b: ^Buffer) {
	delete(b.cells)
	b^ = {}
}

buffer_resize :: proc(b: ^Buffer, width, height: int, allocator := context.allocator) {
	if b.width == width && b.height == height {
		return
	}
	buffer_destroy(b)
	b^ = buffer_create(width, height, allocator)
}

buffer_clear :: proc(b: ^Buffer, bg: Color, fg: Color) {
	for &c in b.cells {
		c = Cell{ch = ' ', fg = fg, bg = bg, style = {}}
	}
}

buffer_at :: proc(b: ^Buffer, x, y: int) -> ^Cell {
	if x < 0 || y < 0 || x >= b.width || y >= b.height {
		return nil
	}
	return &b.cells[y * b.width + x]
}

buffer_put :: proc(b: ^Buffer, x, y: int, ch: rune, fg, bg: Color, style: Style = {}) {
	cell := buffer_at(b, x, y)
	if cell == nil {
		return
	}
	cell.ch = sanitize_cell_rune(ch)
	cell.fg = fg
	cell.bg = bg
	cell.style = style
}

// Strip controls before they reach the present path.
sanitize_cell_rune :: proc(ch: rune) -> rune {
	if ch < 0x20 || ch == 0x7f || (ch >= 0x80 && ch <= 0x9f) {
		return ' '
	}
	return ch
}

buffer_text :: proc(b: ^Buffer, x, y: int, text: string, fg, bg: Color, style: Style = {}) {
	cx := x
	for r in text {
		if r == '\n' {
			break
		}
		buffer_put(b, cx, y, r, fg, bg, style)
		cx += 1
		if cx >= b.width {
			break
		}
	}
}

buffer_fill_rect :: proc(b: ^Buffer, x, y, w, h: int, ch: rune, fg, bg: Color) {
	for row in 0 ..< h {
		for col in 0 ..< w {
			buffer_put(b, x + col, y + row, ch, fg, bg)
		}
	}
}

buffer_hline :: proc(b: ^Buffer, x, y, w: int, ch: rune, fg, bg: Color) {
	for i in 0 ..< w {
		buffer_put(b, x + i, y, ch, fg, bg)
	}
}

buffer_vline :: proc(b: ^Buffer, x, y, h: int, ch: rune, fg, bg: Color) {
	for i in 0 ..< h {
		buffer_put(b, x, y + i, ch, fg, bg)
	}
}
