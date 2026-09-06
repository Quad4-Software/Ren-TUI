// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Micron page editor for local pages under data_dir/pages. Splits the Page
tab into a source pane over a rendered preview pane.
*/

package app

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "ren:micron"
import "ren:ui"

// A page is editable when it came from a local disk path (data_dir/pages or
// downloads), not from a remote node fetch.
page_is_local :: proc(a: ^App) -> bool {
	return a.page_disk != ""
}

page_edit_reset :: proc(a: ^App) {
	for &l in a.page_edit_lines {
		ui.input_destroy(&l)
	}
	clear(&a.page_edit_lines)
	a.page_editing = false
	a.page_edit_focus = 0
	a.page_edit_sel = 0
	a.page_edit_scroll = 0
	a.page_prev_scroll = 0
	a.page_naming = false
	if a.page_edit_doc_ok {
		micron.doc_destroy(&a.page_edit_doc)
		a.page_edit_doc_ok = false
	}
}

page_edit_text :: proc(a: ^App, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	for &l, i in a.page_edit_lines {
		if i > 0 {
			strings.write_byte(&b, '\n')
		}
		strings.write_string(&b, ui.input_value(&l))
	}
	return strings.to_string(b)
}

// Rebuild the live preview doc from the current editor lines.
page_edit_rebuild :: proc(a: ^App) {
	text := page_edit_text(a)
	if a.page_edit_doc_ok {
		micron.doc_destroy(&a.page_edit_doc)
		a.page_edit_doc_ok = false
	}
	a.page_edit_doc = micron.parse(text)
	a.page_edit_doc_ok = true
	mark_dirty(a)
}

page_edit_try_start :: proc(a: ^App) {
	if !page_is_local(a) {
		set_status(a, "edit needs a local page (open via search or N for new)", STATUS_HOLD)
		return
	}
	page_edit_reset(a)
	lines := strings.split_lines(a.page_source, context.temp_allocator)
	if len(lines) == 0 {
		l: ui.Input_State
		ui.input_init(&l)
		append(&a.page_edit_lines, l)
	}
	for text in lines {
		l: ui.Input_State
		ui.input_init(&l)
		strings.write_string(&l.text, text)
		l.cursor = 0
		append(&a.page_edit_lines, l)
	}
	a.page_editing = true
	a.page_view_raw = false
	page_edit_rebuild(a)
	set_status(a, "edit mode  Ctrl+S save  Tab preview  Esc done", STATUS_HOLD)
}

page_edit_exit :: proc(a: ^App) {
	page_edit_reset(a)
	set_status(a, "edit closed", STATUS_HOLD)
}

// Ensure the selected editor line is inside the source pane viewport.
page_edit_ensure_visible :: proc(a: ^App) {
	visible := max(1, a.page_edit_src_rect.h)
	if a.page_edit_sel < a.page_edit_scroll {
		a.page_edit_scroll = a.page_edit_sel
	}
	if a.page_edit_sel >= a.page_edit_scroll + visible {
		a.page_edit_scroll = a.page_edit_sel - visible + 1
	}
	max_scroll := max(0, len(a.page_edit_lines) - visible)
	a.page_edit_scroll = clamp(a.page_edit_scroll, 0, max_scroll)
}

page_edit_move :: proc(a: ^App, delta: int) {
	n := len(a.page_edit_lines)
	if n == 0 {
		return
	}
	prev := a.page_edit_sel
	a.page_edit_sel = clamp(a.page_edit_sel + delta, 0, n - 1)
	if a.page_edit_sel != prev {
		// Keep the column close to where the cursor was on the old line.
		cur := &a.page_edit_lines[a.page_edit_sel]
		old := a.page_edit_lines[prev]
		col := min(old.cursor, len(ui.input_value(cur)))
		cur.cursor = col
	}
	page_edit_ensure_visible(a)
}

// Split the current line at the cursor, moving the tail to a new line.
page_edit_split_line :: proc(a: ^App) {
	if a.page_edit_sel < 0 || a.page_edit_sel >= len(a.page_edit_lines) {
		return
	}
	cur := &a.page_edit_lines[a.page_edit_sel]
	s := ui.input_value(cur)
	c := clamp(cur.cursor, 0, len(s))
	right := strings.clone(s[c:])
	nl: ui.Input_State
	ui.input_init(&nl)
	strings.write_string(&nl.text, right)
	delete(right)
	strings.builder_reset(&cur.text)
	strings.write_string(&cur.text, s[:c])
	inject_at(&a.page_edit_lines, a.page_edit_sel + 1, nl)
	a.page_edit_sel += 1
	page_edit_ensure_visible(a)
	page_edit_rebuild(a)
}

// Merge the current line into the previous one (Backspace at column 0).
page_edit_join_prev :: proc(a: ^App) {
	if a.page_edit_sel <= 0 || a.page_edit_sel >= len(a.page_edit_lines) {
		return
	}
	cur := a.page_edit_lines[a.page_edit_sel]
	prev := &a.page_edit_lines[a.page_edit_sel - 1]
	prev.cursor = len(ui.input_value(prev))
	strings.write_string(&prev.text, ui.input_value(&cur))
	ui.input_destroy(&cur)
	ordered_remove(&a.page_edit_lines, a.page_edit_sel)
	a.page_edit_sel -= 1
	page_edit_ensure_visible(a)
	page_edit_rebuild(a)
}

// Merge the next line into the current one (Delete at end of line).
page_edit_join_next :: proc(a: ^App) {
	if a.page_edit_sel < 0 || a.page_edit_sel + 1 >= len(a.page_edit_lines) {
		return
	}
	cur := &a.page_edit_lines[a.page_edit_sel]
	if cur.cursor < len(ui.input_value(cur)) {
		return
	}
	next := a.page_edit_lines[a.page_edit_sel + 1]
	strings.write_string(&cur.text, ui.input_value(&next))
	ui.input_destroy(&next)
	ordered_remove(&a.page_edit_lines, a.page_edit_sel + 1)
	page_edit_rebuild(a)
}

page_edit_save :: proc(a: ^App) {
	if a.page_disk == "" {
		set_status(a, "no local page path", STATUS_HOLD)
		return
	}
	text := page_edit_text(a)
	if os.write_entire_file(a.page_disk, transmute([]u8)text) != nil {
		set_status(a, "page save failed", STATUS_HOLD)
		return
	}
	// Keep the rendered view in sync with what landed on disk.
	delete(a.page_source)
	a.page_source = strings.clone(text)
	micron.doc_destroy(&a.page_doc)
	a.page_doc = micron.parse(a.page_source)
	a.page_link_focus = 0 if a.page_doc.link_count > 0 else -1
	clear(&a.page_hits)
	page_form_init_from_doc(a)
	set_status(a, fmt.tprintf("saved %s", a.page_disk), STATUS_HOLD)
	mark_dirty(a)
}

// All key events while the editor owns the Page tab. focus 0 edits source,
// focus 1 scrolls the preview pane.
page_edit_handle :: proc(a: ^App, ev: ui.Event) {
	#partial switch ev.kind {
	case .Esc:
		page_edit_exit(a)
		return
	case .Ctrl_S:
		page_edit_save(a)
		return
	case .Tab, .Backtab:
		a.page_edit_focus = 1 - a.page_edit_focus
		return
	}
	if a.page_edit_focus == 1 {
		max_scroll := page_edit_preview_max_scroll(a)
		#partial switch ev.kind {
		case .Up:
			a.page_prev_scroll = max(0, a.page_prev_scroll - 1)
		case .Down:
			a.page_prev_scroll = min(max_scroll, a.page_prev_scroll + 1)
		case .Page_Up:
			a.page_prev_scroll = max(0, a.page_prev_scroll - max(1, a.page_edit_prev_rect.h))
		case .Page_Down:
			a.page_prev_scroll = min(max_scroll, a.page_prev_scroll + max(1, a.page_edit_prev_rect.h))
		}
		return
	}
	changed := false
	#partial switch ev.kind {
	case .Enter:
		page_edit_split_line(a)
		return
	case .Backspace:
		if a.page_edit_sel < len(a.page_edit_lines) &&
		   a.page_edit_lines[a.page_edit_sel].cursor == 0 {
			page_edit_join_prev(a)
			return
		}
		changed = page_edit_line_input(a, ev)
	case .Delete:
		page_edit_join_next(a)
		return
	case .Up:
		page_edit_move(a, -1)
	case .Down:
		page_edit_move(a, 1)
	case .Page_Up:
		a.page_edit_scroll = max(0, a.page_edit_scroll - max(1, a.page_edit_src_rect.h))
	case .Page_Down:
		a.page_edit_scroll += max(1, a.page_edit_src_rect.h)
		page_edit_ensure_visible(a)
	case .Home, .End, .Left, .Right, .Ctrl_U, .Rune:
		changed = page_edit_line_input(a, ev)
	}
	if changed {
		page_edit_rebuild(a)
	}
	mark_dirty(a)
}

page_edit_line_input :: proc(a: ^App, ev: ui.Event) -> bool {
	if a.page_edit_sel < 0 || a.page_edit_sel >= len(a.page_edit_lines) {
		return false
	}
	return ui.input_handle(&a.page_edit_lines[a.page_edit_sel], ev)
}

page_edit_preview_max_scroll :: proc(a: ^App) -> int {
	if !a.page_edit_doc_ok {
		return 0
	}
	w := max(1, a.page_edit_prev_rect.w)
	rows := micron.layout_row_count(a.page_edit_doc, w)
	return max(0, rows - max(1, a.page_edit_prev_rect.h))
}

// Filename prompt for a brand new page under data_dir/pages.
page_new_start :: proc(a: ^App) {
	ui.input_clear(&a.page_new_name)
	a.page_naming = true
	set_status(a, "new page name  Enter create  Esc cancel", STATUS_HOLD)
}

page_new_name_ok :: proc(name: string) -> bool {
	if name == "" || strings.contains(name, "..") {
		return false
	}
	for i in 0 ..< len(name) {
		switch name[i] {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '.', '_', '-', '~':
		case:
			return false
		}
	}
	return true
}

page_new_apply :: proc(a: ^App) {
	name := strings.trim_space(ui.input_value(&a.page_new_name))
	a.page_naming = false
	ui.input_clear(&a.page_new_name)
	if !page_new_name_ok(name) {
		set_status(a, "bad page name (letters digits . _ - ~)", STATUS_HOLD)
		return
	}
	if !strings.has_suffix(strings.to_lower(name, context.temp_allocator), ".mu") {
		name = strings.concatenate({name, ".mu"}, context.temp_allocator)
	}
	pages_dir, _ := filepath.join({a.cfg.data_dir, "pages"}, context.temp_allocator)
	if os.make_directory_all(pages_dir) != nil && !os.exists(pages_dir) {
		set_status(a, "cannot create pages dir", STATUS_HOLD)
		return
	}
	disk, _ := filepath.join({pages_dir, name}, context.allocator)
	defer delete(disk)
	if !os.exists(disk) {
		content := fmt.tprintf("> %s\n\n`! New page. Edit and Ctrl+S to save.", name)
		if os.write_entire_file(disk, transmute([]u8)content) != nil {
			set_status(a, "cannot write page file", STATUS_HOLD)
			return
		}
	}
	req := strings.concatenate({"/page/", name}, context.temp_allocator)
	page_open_local_file(a, disk, req)
	page_edit_try_start(a)
}
