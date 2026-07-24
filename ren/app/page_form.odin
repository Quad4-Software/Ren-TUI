// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Page form state for micron fields and submit links.
*/

package app

import "core:strings"

import "ren:micron"
import "ren:ui"

page_form_clear :: proc(a: ^App) {
	for &f in a.page_form {
		delete(f.name)
		delete(f.value)
		delete(f.label)
	}
	clear(&a.page_form)
	a.page_field_focus = -1
}

page_form_init_from_doc :: proc(a: ^App) {
	page_form_clear(a)
	if a.page_form == nil {
		a.page_form = make([dynamic]Page_Form_Input)
	}
	for line in a.page_doc.lines {
		for span in line.spans {
			if span.kind != .Field {
				continue
			}
			append(&a.page_form, Page_Form_Input{
				kind = span.field_kind,
				name = strings.clone(span.field_name),
				value = strings.clone(span.field_value),
				label = strings.clone(span.field_label),
				checked = span.field_prechecked,
				width = span.field_width if span.field_width > 0 else 24,
				masked = span.field_masked,
			})
		}
	}
	page_form_sync_spans(a)
	if len(a.page_form) > 0 && a.page_link_focus < 0 {
		a.page_field_focus = 0
	}
}

page_form_sync_spans :: proc(a: ^App) {
	fi := 0
	for &line in a.page_doc.lines {
		for &span in line.spans {
			if span.kind != .Field {
				continue
			}
			if fi >= len(a.page_form) {
				return
			}
			f := a.page_form[fi]
			disp := micron.field_display_text(
				f.kind,
				f.label,
				f.value,
				f.width,
				f.masked,
				f.checked,
				context.temp_allocator,
			)
			delete(span.text)
			span.text = strings.clone(disp)
			fi += 1
		}
	}
}

page_form_as_micron_inputs :: proc(a: ^App, allocator := context.temp_allocator) -> []micron.Form_Field_Input {
	out := make([]micron.Form_Field_Input, len(a.page_form), allocator)
	for f, i in a.page_form {
		out[i] = micron.Form_Field_Input{
			kind = f.kind,
			name = f.name,
			value = f.value,
			checked = f.checked,
		}
	}
	return out
}

page_merge_form_request :: proc(a: ^App, req: ^micron.Request_Data, field_spec: string) {
	if req == nil || field_spec == "" {
		return
	}
	// NomadNet Browser.handle_link applies name=value as var_* before form fields.
	micron.merge_link_var_spec(req, field_spec)
	inputs := page_form_as_micron_inputs(a)
	all := micron.collect_form_fields(inputs)
	defer micron.form_fields_map_destroy(&all)
	micron.merge_form_fields_into_request(req, all, field_spec)
}

page_doc_field_count :: proc(doc: micron.Doc) -> int {
	n := 0
	for line in doc.lines {
		for span in line.spans {
			if span.kind == .Field {
				n += 1
			}
		}
	}
	return n
}

page_focus_total :: proc(a: ^App) -> int {
	return micron.doc_link_count(a.page_doc) + len(a.page_form)
}

// Unified cycle: links then fields in document paint order approximates link_i then field_i.
// Focus encoding: [0 .. link_count) = links, [link_count ..) = fields.
page_cycle_focus :: proc(a: ^App, delta: int) {
	links := micron.doc_link_count(a.page_doc)
	fields := len(a.page_form)
	total := links + fields
	if total <= 0 {
		a.page_link_focus = -1
		a.page_field_focus = -1
		return
	}
	cur := 0
	if a.page_link_focus >= 0 {
		cur = a.page_link_focus
	} else if a.page_field_focus >= 0 {
		cur = links + a.page_field_focus
	} else {
		cur = 0 if delta >= 0 else total - 1
		page_set_focus_index(a, cur)
		ensure_page_focus_visible(a)
		return
	}
	cur = (cur + delta % total + total) % total
	page_set_focus_index(a, cur)
	ensure_page_focus_visible(a)
}

page_set_focus_index :: proc(a: ^App, idx: int) {
	links := micron.doc_link_count(a.page_doc)
	if idx < links {
		a.page_link_focus = idx
		a.page_field_focus = -1
		return
	}
	a.page_link_focus = -1
	a.page_field_focus = idx - links
}

page_activate_focused :: proc(a: ^App) {
	if a.page_view_raw {
		return
	}
	if a.page_field_focus >= 0 && a.page_field_focus < len(a.page_form) {
		page_toggle_focused_field(a)
		return
	}
	page_activate_focused_link(a)
}

page_toggle_focused_field :: proc(a: ^App) {
	if a.page_field_focus < 0 || a.page_field_focus >= len(a.page_form) {
		return
	}
	f := &a.page_form[a.page_field_focus]
	switch f.kind {
	case .Checkbox:
		f.checked = !f.checked
		page_form_sync_spans(a)
		mark_dirty(a)
	case .Radio:
		name := f.name
		val := f.value
		for &other in a.page_form {
			if other.kind == .Radio && other.name == name {
				other.checked = other.value == val
			}
		}
		page_form_sync_spans(a)
		mark_dirty(a)
	case .Text, .None:
	}
}

page_field_edit_rune :: proc(a: ^App, ev: ui.Event) -> bool {
	if a.page_field_focus < 0 || a.page_field_focus >= len(a.page_form) {
		return false
	}
	f := &a.page_form[a.page_field_focus]
	if f.kind != .Text && f.kind != .None {
		return false
	}
	tmp: ui.Input_State
	ui.input_init(&tmp)
	defer ui.input_destroy(&tmp)
	strings.write_string(&tmp.text, f.value)
	tmp.cursor = len(f.value)
	if !ui.input_handle(&tmp, ev) {
		return false
	}
	val := ui.input_value(&tmp)
	w := f.width if f.width > 0 else 24
	val = ui.truncate_runes(val, w)
	delete(f.value)
	f.value = strings.clone(val)
	page_form_sync_spans(a)
	mark_dirty(a)
	return true
}

ensure_page_focus_visible :: proc(a: ^App) {
	if a.page_link_focus >= 0 {
		ensure_page_link_visible(a)
		return
	}
	if a.page_field_focus < 0 {
		return
	}
	w := max(1, a.detail_rect.w)
	row_i := micron.layout_first_row_for_field(a.page_doc, w, a.page_field_focus)
	visible := max(1, a.detail_rect.h - 1)
	if row_i < a.page_scroll {
		a.page_scroll = row_i
	} else if row_i >= a.page_scroll + visible {
		a.page_scroll = max(0, row_i - visible + 1)
	}
}

page_click_field_at :: proc(a: ^App, x, y: int) -> bool {
	for hit in a.page_hits {
		if hit.field_i < 0 {
			continue
		}
		screen_y := a.detail_rect.y + 1 + (hit.line_idx - a.page_scroll)
		if y != screen_y {
			continue
		}
		if x >= hit.x0 && x < hit.x1 {
			a.page_field_focus = hit.field_i
			a.page_link_focus = -1
			page_toggle_focused_field(a)
			return true
		}
	}
	return false
}
