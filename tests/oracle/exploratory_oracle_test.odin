// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Exploratory oracles: column math, form width, paint, status hold.
These encode correct guarantees. Failures mean real bugs (or wrong oracles).
*/

package tests

import "core:strings"
import "core:testing"
import "core:unicode/utf8"

import "ren:app"
import "ren:micron"
import "ren:store"
import "ren:ui"

@(test)
test_oracle_draw_input_utf8_caret_uses_columns :: proc(t: ^testing.T) {
	// Guarantee: caret column matches display columns, not UTF-8 byte cursor.
	ui.set_theme(ui.FIELD)
	ui.caps_init("full")
	inp: ui.Input_State
	ui.input_init(&inp)
	defer ui.input_destroy(&inp)

	for _ in 0 ..< 6 {
		_ = ui.input_handle(&inp, ui.Event{kind = .Rune, ch = 'é'})
	}
	testing.expect_value(t, inp.cursor, 12)
	testing.expect_value(t, ui.string_cols(ui.input_value(&inp)), 6)

	buf := ui.buffer_create(20, 5)
	defer ui.buffer_destroy(&buf)
	ui.draw_input(&buf, ui.Rect{0, 0, 20, 3}, &inp, "x", true)

	caret_x := -1
	for x in 1 ..< 19 {
		cell := ui.buffer_at(&buf, x, 1)
		if cell != nil && cell.ch == ui.caps_cursor_glyph() {
			caret_x = x
			break
		}
	}
	testing.expect(t, caret_x >= 0, "caret must be painted")
	// After 6 single-column runes, caret should sit at inner.x + 6 = 7
	testing.expect_value(t, caret_x, 7)
}

@(test)
test_oracle_draw_input_utf8_scroll_keeps_valid_utf8 :: proc(t: ^testing.T) {
	// Guarantee: horizontal scroll never slices mid-rune.
	ui.set_theme(ui.FIELD)
	ui.caps_init("full")
	inp: ui.Input_State
	ui.input_init(&inp)
	defer ui.input_destroy(&inp)

	for _ in 0 ..< 40 {
		_ = ui.input_handle(&inp, ui.Event{kind = .Rune, ch = 'é'})
	}
	testing.expect(t, inp.cursor > 20)

	// Width 11 -> inner.w 9 -> visible 8. Cursor at end forces scroll into multi-byte text.
	buf := ui.buffer_create(11, 5)
	defer ui.buffer_destroy(&buf)
	ui.draw_input(&buf, ui.Rect{0, 0, 11, 3}, &inp, "x", true)

	row := make([dynamic]u8, 0, 32)
	defer delete(row)
	for x in 1 ..< 10 {
		cell := ui.buffer_at(&buf, x, 1)
		if cell == nil {
			continue
		}
		if cell.ch == ui.caps_cursor_glyph() || cell.ch == ' ' || cell.ch == ui.CELL_WIDE_CONT {
			continue
		}
		enc, n := utf8.encode_rune(cell.ch)
		for i in 0 ..< n {
			append(&row, enc[i])
		}
	}
	testing.expect(t, utf8.valid_string(string(row[:])), "drawn input row must be valid UTF-8")
	// Also assert caret is within the inner row.
	found_caret := false
	for x in 1 ..< 10 {
		cell := ui.buffer_at(&buf, x, 1)
		if cell != nil && cell.ch == ui.caps_cursor_glyph() {
			found_caret = true
			break
		}
	}
	testing.expect(t, found_caret, "caret must remain visible after UTF-8 scroll")
}

@(test)
test_oracle_micron_layout_emoji_wraps_by_columns :: proc(t: ^testing.T) {
	// Guarantee: wrap uses display columns (emoji is typically 2 cols).
	src := "😀😀😀"
	doc := micron.parse(src)
	defer micron.doc_destroy(&doc)
	rows := micron.layout_doc(doc, 4)
	defer micron.layout_rows_destroy(&rows)
	testing.expect(t, len(rows) > 1, "wide emoji must wrap by columns not rune count")
}

@(test)
test_oracle_micron_paint_wide_glyph_continuation :: proc(t: ^testing.T) {
	// Guarantee: page paint matches buffer_text wide-glyph model.
	ui.caps_init("full")
	src := "😀A"
	doc := micron.parse(src)
	defer micron.doc_destroy(&doc)
	buf := ui.buffer_create(8, 3)
	defer ui.buffer_destroy(&buf)
	app.paint_doc(&buf, ui.Rect{0, 0, 8, 3}, doc, 0, -1, -1, nil)
	testing.expect_value(t, buf.cells[0].ch, rune(0x1F600))
	testing.expect_value(t, buf.cells[1].ch, ui.CELL_WIDE_CONT)
	testing.expect_value(t, buf.cells[2].ch, 'A')
}

@(test)
test_oracle_page_field_width_is_columns_not_bytes :: proc(t: ^testing.T) {
	// Guarantee: micron field width is a display-column budget.
	a: app.App
	a.page_form = make([dynamic]app.Page_Form_Input)
	defer {
		for &f in a.page_form {
			delete(f.name)
			delete(f.value)
			delete(f.label)
		}
		delete(a.page_form)
	}
	append(&a.page_form, app.Page_Form_Input{
		kind = .Text,
		name = strings.clone("n"),
		value = strings.clone(""),
		label = strings.clone("n"),
		width = 5,
	})
	a.page_field_focus = 0

	for _ in 0 ..< 5 {
		ok := app.page_field_edit_rune(&a, ui.Event{kind = .Rune, ch = '😀'})
		testing.expect(t, ok)
	}
	val := a.page_form[0].value
	testing.expect(t, utf8.valid_string(val), "field value must stay valid UTF-8")
	testing.expect(t, ui.string_cols(val) <= 5, "field width must cap display columns")
}

@(test)
test_oracle_page_status_hold_does_not_leak_announce_toast :: proc(t: ^testing.T) {
	// Guarantee: Page tab does not keep Network announce hold toasts.
	a: app.App
	a.online = true
	a.session.status = "online"
	a.session.announces = 7
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)

	a.tab = .Network
	app.set_status(&a, "announced (#7)", app.STATUS_HOLD)
	a.tab = .Page
	app.update_status(&a)
	testing.expect(t, !strings.contains(a.status_right, "announced"), "Page must not show announce toast hold")
}
