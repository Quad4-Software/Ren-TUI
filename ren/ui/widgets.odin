// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Immediate-mode boxes lists inputs and tabs.
*/

package ui

import "core:strings"
import "core:unicode/utf8"

Rect :: struct {
	x, y, w, h: int,
}

rect_inset :: proc(r: Rect, n: int) -> Rect {
	return Rect{
		x = r.x + n,
		y = r.y + n,
		w = max(0, r.w - 2 * n),
		h = max(0, r.h - 2 * n),
	}
}

rect_split_horizontal :: proc(r: Rect, top_h: int) -> (top, bottom: Rect) {
	th := clamp(top_h, 0, r.h)
	top = Rect{r.x, r.y, r.w, th}
	bottom = Rect{r.x, r.y + th, r.w, r.h - th}
	return
}

rect_split_vertical :: proc(r: Rect, left_w: int) -> (left, right: Rect) {
	lw := clamp(left_w, 0, r.w)
	left = Rect{r.x, r.y, lw, r.h}
	right = Rect{r.x + lw, r.y, r.w - lw, r.h}
	return
}

draw_box :: proc(buf: ^Buffer, r: Rect, title: string, focused: bool) {
	if r.w < 2 || r.h < 2 {
		return
	}
	t := theme()
	fg := t.border
	if focused {
		fg = t.accent
	}
	bg := t.bg
	tl, tr, bl, br, h, v := caps_border()

	buffer_put(buf, r.x, r.y, tl, fg, bg)
	buffer_put(buf, r.x + r.w - 1, r.y, tr, fg, bg)
	buffer_put(buf, r.x, r.y + r.h - 1, bl, fg, bg)
	buffer_put(buf, r.x + r.w - 1, r.y + r.h - 1, br, fg, bg)
	buffer_hline(buf, r.x + 1, r.y, r.w - 2, h, fg, bg)
	buffer_hline(buf, r.x + 1, r.y + r.h - 1, r.w - 2, h, fg, bg)
	buffer_vline(buf, r.x, r.y + 1, r.h - 2, v, fg, bg)
	buffer_vline(buf, r.x + r.w - 1, r.y + 1, r.h - 2, v, fg, bg)

	if title != "" && r.w > 4 {
		label := title
		max_len := r.w - 4
		if len(label) > max_len {
			label = label[:max_len]
		}
		tx := r.x + 2
		title_fg := t.title if focused else t.muted
		buffer_text(buf, tx, r.y, label, title_fg, bg, {.Bold} if focused else {})
	}
}

draw_tabs :: proc(buf: ^Buffer, r: Rect, labels: []string, active: int) {
	t := theme()
	buffer_fill_rect(buf, r.x, r.y, r.w, r.h, ' ', t.fg, t.status_bg)
	x := r.x + 1
	for label, i in labels {
		fg := t.tab_idle
		style: Style
		if i == active {
			fg = t.tab_active
			style = {.Bold}
		}
		text := fmt_tab(label, i == active)
		buffer_text(buf, x, r.y, text, fg, t.status_bg, style)
		x += len(text) + 2
		if x >= r.x + r.w {
			break
		}
	}
}

@(private)
fmt_tab :: proc(label: string, active: bool) -> string {
	if active {
		return label
	}
	return label
}

draw_status :: proc(buf: ^Buffer, r: Rect, left, right: string) {
	t := theme()
	buffer_fill_rect(buf, r.x, r.y, r.w, r.h, ' ', t.status_fg, t.status_bg)
	left_shown := truncate_runes(left, max(0, r.w - 2))
	buffer_text(buf, r.x + 1, r.y, left_shown, t.status_fg, t.status_bg)
	if right == "" {
		return
	}
	right_cols := status_right_cols(r.w, strings.rune_count(left_shown))
	if right_cols <= 0 {
		return
	}
	right_shown := truncate_runes(right, right_cols)
	rx := r.x + r.w - strings.rune_count(right_shown) - 1
	if rx <= r.x + strings.rune_count(left_shown) {
		return
	}
	buffer_text(buf, rx, r.y, right_shown, t.muted, t.status_bg)
}

List_State :: struct {
	items:    [dynamic]string,
	selected: int,
	scroll:   int,
}

list_init :: proc(l: ^List_State) {
	l^ = {}
	l.items = make([dynamic]string)
}

list_destroy :: proc(l: ^List_State) {
	for s in l.items {
		delete(s)
	}
	delete(l.items)
	l^ = {}
}

list_clear :: proc(l: ^List_State) {
	for s in l.items {
		delete(s)
	}
	clear(&l.items)
}

list_push :: proc(l: ^List_State, item: string) {
	append(&l.items, strings.clone(item))
}

list_move :: proc(l: ^List_State, delta: int, visible: int) {
	n := len(l.items)
	if n == 0 {
		l.selected = 0
		l.scroll = 0
		return
	}
	l.selected = clamp(l.selected + delta, 0, n - 1)
	list_ensure_visible(l, visible)
}

list_click :: proc(l: ^List_State, row: int, visible: int) {
	n := len(l.items)
	if n == 0 {
		return
	}
	idx := l.scroll + row
	if idx < 0 || idx >= n {
		return
	}
	l.selected = idx
	list_ensure_visible(l, visible)
}

list_ensure_visible :: proc(l: ^List_State, visible: int) {
	n := len(l.items)
	if n == 0 {
		l.scroll = 0
		return
	}
	if l.selected < l.scroll {
		l.scroll = l.selected
	}
	if l.selected >= l.scroll + visible {
		l.scroll = l.selected - visible + 1
	}
	if l.scroll < 0 {
		l.scroll = 0
	}
	max_scroll := max(0, n - visible)
	if l.scroll > max_scroll {
		l.scroll = max_scroll
	}
}

draw_list :: proc(buf: ^Buffer, r: Rect, l: ^List_State) {
	t := theme()
	inner := rect_inset(r, 0)
	visible := inner.h
	for row in 0 ..< visible {
		idx := l.scroll + row
		y := inner.y + row
		buffer_fill_rect(buf, inner.x, y, inner.w, 1, ' ', t.fg, t.bg)
		if idx < 0 || idx >= len(l.items) {
			continue
		}
		selected := idx == l.selected
		fg := t.highlight_fg if selected else t.fg
		bg := t.highlight_bg if selected else t.bg
		style: Style = {.Bold} if selected else {}
		prefix := "> " if selected else "  "
		line := strings.concatenate({prefix, l.items[idx]}, context.temp_allocator)
		line = truncate_runes(line, inner.w)
		buffer_text(buf, inner.x, y, line, fg, bg, style)
	}
}

truncate_runes :: proc(s: string, max_cols: int) -> string {
	if max_cols <= 0 {
		return ""
	}
	n := 0
	for _, i in s {
		if n >= max_cols {
			return s[:i]
		}
		n += 1
	}
	return s
}

Input_State :: struct {
	text:     strings.Builder,
	cursor:   int,
	password: bool,
}

input_init :: proc(i: ^Input_State) {
	i^ = {}
	strings.builder_init(&i.text)
}

input_destroy :: proc(i: ^Input_State) {
	strings.builder_destroy(&i.text)
	i^ = {}
}

input_clear :: proc(i: ^Input_State) {
	strings.builder_reset(&i.text)
	i.cursor = 0
}

input_value :: proc(i: ^Input_State) -> string {
	return strings.to_string(i.text)
}

input_handle :: proc(i: ^Input_State, ev: Event) -> bool {
	#partial switch ev.kind {
	case .Rune:
		s := strings.to_string(i.text)
		rune_bytes := utf8.rune_size(ev.ch)
		if i.cursor >= len(s) {
			strings.write_rune(&i.text, ev.ch)
		} else {
			left := s[:i.cursor]
			right := s[i.cursor:]
			strings.builder_reset(&i.text)
			strings.write_string(&i.text, left)
			strings.write_rune(&i.text, ev.ch)
			strings.write_string(&i.text, right)
		}
		i.cursor += rune_bytes
		return true
	case .Backspace:
		s := strings.to_string(i.text)
		if i.cursor > 0 && len(s) > 0 {
			_, size := utf8.decode_last_rune(s[:i.cursor])
			if size < 1 {
				size = 1
			}
			left := s[:i.cursor - size]
			right := s[i.cursor:]
			strings.builder_reset(&i.text)
			strings.write_string(&i.text, left)
			strings.write_string(&i.text, right)
			i.cursor -= size
		}
		return true
	case .Left:
		s := strings.to_string(i.text)
		if i.cursor > 0 {
			_, size := utf8.decode_last_rune(s[:i.cursor])
			if size < 1 {
				size = 1
			}
			i.cursor -= size
		}
		return true
	case .Right:
		s := strings.to_string(i.text)
		if i.cursor < len(s) {
			_, size := utf8.decode_rune(s[i.cursor:])
			if size < 1 {
				size = 1
			}
			i.cursor += size
		}
		return true
	case .Home:
		i.cursor = 0
		return true
	case .End:
		i.cursor = len(strings.to_string(i.text))
		return true
	case .Ctrl_U:
		input_clear(i)
		return true
	}
	return false
}

draw_input :: proc(buf: ^Buffer, r: Rect, i: ^Input_State, label: string, focused: bool) {
	t := theme()
	bg := t.input_bg
	fg := t.fg
	draw_box(buf, r, label, focused)
	inner := rect_inset(r, 1)
	if inner.h < 1 || inner.w < 1 {
		return
	}
	buffer_fill_rect(buf, inner.x, inner.y, inner.w, 1, ' ', fg, bg)
	val := input_value(i)
	shown := val
	if i.password {
		shown = strings.repeat("*", len(val), context.temp_allocator)
	}
	visible := max(1, inner.w - 1)
	scroll := 0
	if i.cursor >= visible {
		scroll = i.cursor - visible + 1
	}
	if scroll > len(shown) {
		scroll = len(shown)
	}
	if scroll > 0 {
		shown = shown[scroll:]
	}
	if len(shown) > visible {
		shown = shown[:visible]
	}
	buffer_text(buf, inner.x, inner.y, shown, fg, bg)
	if focused {
		cx := inner.x + clamp(i.cursor - scroll, 0, visible - 1)
		buffer_put(buf, cx, inner.y, caps_cursor_glyph(), t.accent, bg)
	}
}

draw_text_block :: proc(buf: ^Buffer, r: Rect, lines: []string, scroll: int) {
	t := theme()
	for row in 0 ..< r.h {
		y := r.y + row
		buffer_fill_rect(buf, r.x, y, r.w, 1, ' ', t.fg, t.bg)
		idx := scroll + row
		if idx < 0 || idx >= len(lines) {
			continue
		}
		line := lines[idx]
		if len(line) > r.w {
			line = line[:r.w]
		}
		buffer_text(buf, r.x, y, line, t.fg, t.bg)
	}
}
