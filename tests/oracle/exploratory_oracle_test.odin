// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Exploratory oracles: column math, form width, paint, status hold,
unpack strictness, persist peer binding, inbound signature gate.
*/

package tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:unicode/utf8"

import "ren:app"
import "ren:constants"
import "ren:lxmf"
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
	src := "😀😀😀"
	doc := micron.parse(src)
	defer micron.doc_destroy(&doc)
	rows := micron.layout_doc(doc, 4)
	defer micron.layout_rows_destroy(&rows)
	testing.expect(t, len(rows) > 1, "wide emoji must wrap by columns not rune count")
}

@(test)
test_oracle_micron_paint_wide_glyph_continuation :: proc(t: ^testing.T) {
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

@(test)
test_oracle_message_unpack_rejects_trailing_bytes :: proc(t: ^testing.T) {
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)
	dest := lxmf.delivery_hash(mat.hash[:])
	msg: lxmf.Message
	lxmf.message_init(&msg)
	defer lxmf.message_destroy(&msg)
	msg.destination_hash = dest
	msg.timestamp = 1
	msg.title = strings.clone("")
	msg.content = strings.clone("trail")
	testing.expect(t, lxmf.message_pack(&msg, &mat))
	bad := make([]u8, len(msg.packed) + 1)
	defer delete(bad)
	copy(bad, msg.packed)
	bad[len(msg.packed)] = 0x00
	_, uok := lxmf.message_unpack(bad)
	testing.expect(t, !uok, "trailing payload bytes must fail unpack")
}

@(test)
test_oracle_message_accept_rejects_bad_sig_when_key_known :: proc(t: ^testing.T) {
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)
	dest := lxmf.delivery_hash(mat.hash[:])
	msg: lxmf.Message
	lxmf.message_init(&msg)
	defer lxmf.message_destroy(&msg)
	msg.destination_hash = dest
	msg.timestamp = 2
	msg.title = strings.clone("")
	msg.content = strings.clone("sig")
	testing.expect(t, lxmf.message_pack(&msg, &mat))

	wire := make([]u8, len(msg.packed))
	defer delete(wire)
	copy(wire, msg.packed)
	sig0 := lxmf.HASH_LEN * 2
	wire[sig0] ~= 0xff

	out, uok := lxmf.message_unpack(wire)
	testing.expect(t, uok)
	defer lxmf.message_destroy(&out)
	testing.expect(t, lxmf.message_accept_inbound_signature(&out, nil), "unknown key still allowed")
	testing.expect(t, !lxmf.message_accept_inbound_signature(&out, mat.sign_pub[:]), "known key must reject bad sig")
	testing.expect_value(t, out.unverified, lxmf.Unverified_Reason.Signature_Invalid)
}

@(test)
test_oracle_message_accept_verifies_good_sig_when_key_known :: proc(t: ^testing.T) {
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)
	dest := lxmf.delivery_hash(mat.hash[:])
	msg: lxmf.Message
	lxmf.message_init(&msg)
	defer lxmf.message_destroy(&msg)
	msg.destination_hash = dest
	msg.timestamp = 3
	msg.title = strings.clone("")
	msg.content = strings.clone("ok")
	testing.expect(t, lxmf.message_pack(&msg, &mat))
	out, uok := lxmf.message_unpack(msg.packed)
	testing.expect(t, uok)
	defer lxmf.message_destroy(&out)
	testing.expect(t, lxmf.message_accept_inbound_signature(&out, mat.sign_pub[:]))
	testing.expect(t, out.signature_ok)
}

@(test)
test_oracle_conversations_reject_peer_hash_mismatch :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-peer-hash-oracle"})
	_ = os.remove_all(base)
	defer os.remove_all(base)
	_ = os.make_directory_all(base)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	delete(cfg.data_dir)
	cfg.data_dir = strings.clone(base)
	_ = store.config_ensure_dirs(&cfg)

	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)
	peer_p: [store.HASH_LEN]u8
	peer_p[0] = 0xaa
	conv := store.conversations_get_or_create(&convs, peer_p, "P")
	append(&conv.messages, store.Stored_Message{
		direction = .In,
		title = strings.clone(""),
		content = strings.clone("secret"),
		timestamp = 1,
		method = .Direct,
	})
	testing.expect(t, store.conversations_save_peer(&convs, &cfg, peer_p))

	peer_q: [store.HASH_LEN]u8
	peer_q[0] = 0xbb
	src_dir, _ := filepath.join({
		base,
		constants.CONVERSATIONS_DIR,
		store.hash_hex(peer_p, context.temp_allocator),
	})
	dst_dir, _ := filepath.join({
		base,
		constants.CONVERSATIONS_DIR,
		store.hash_hex(peer_q, context.temp_allocator),
	})
	_ = os.make_directory_all(dst_dir)
	src_path, _ := filepath.join({src_dir, constants.MESSAGES_FILE})
	dst_path, _ := filepath.join({dst_dir, constants.MESSAGES_FILE})
	data, rerr := os.read_entire_file_from_path(src_path, context.allocator)
	testing.expect(t, rerr == nil)
	defer delete(data)
	testing.expect(t, os.write_entire_file(dst_path, data) == nil)
	_ = os.remove(src_path)

	loaded: store.Conversations
	store.conversations_init(&loaded)
	defer store.conversations_destroy(&loaded)
	store.conversations_load(&loaded, &cfg)
	for item in loaded.items {
		if item.peer_hash == peer_q {
			testing.expect_value(t, len(item.messages), 0)
		}
	}
}

@(test)
test_oracle_directory_sign_pub_roundtrip :: proc(t: ^testing.T) {
	d: store.Directory
	store.directory_init(&d)
	defer store.directory_destroy(&d)
	dest: [store.HASH_LEN]u8
	dest[0] = 0x11
	store.directory_upsert(&d, dest, dest, .Lxmf, "n", nil, 1)
	pub: [32]u8
	pub[0] = 0x7e
	testing.expect(t, store.directory_set_sign_pub(&d, dest, pub[:]))
	got, ok := store.directory_sign_pub(&d, dest)
	testing.expect(t, ok)
	testing.expect_value(t, got[0], u8(0x7e))
}

@(test)
test_oracle_duplicate_field_keys_last_wins :: proc(t: ^testing.T) {
	// Craft payload fields map with duplicate key 1. Last value must win.
	w: lxmf.Writer
	lxmf.writer_init(&w)
	defer lxmf.writer_destroy(&w)
	lxmf.write_array_header(&w, 4)
	lxmf.write_f64(&w, 1.0)
	lxmf.write_bin(&w, []u8{})
	lxmf.write_bin(&w, transmute([]u8)string("x"))
	lxmf.write_map_header(&w, 2)
	lxmf.write_int(&w, 1)
	lxmf.write_bin(&w, []u8{0xaa, 0xaa})
	lxmf.write_int(&w, 1)
	lxmf.write_bin(&w, []u8{0xbb, 0xbb})

	payload := lxmf.writer_bytes(&w)
	wire := make([]u8, lxmf.HASH_LEN * 2 + lxmf.SIGNATURE_LEN + len(payload))
	defer delete(wire)
	copy(wire[lxmf.HASH_LEN * 2 + lxmf.SIGNATURE_LEN:], payload)

	out, ok := lxmf.message_unpack(wire)
	testing.expect(t, ok)
	defer lxmf.message_destroy(&out)
	v, vok := out.fields[1]
	testing.expect(t, vok)
	testing.expect_value(t, v.kind, lxmf.Value_Kind.Bin)
	testing.expect(t, len(v.bin) == 2 && v.bin[0] == 0xbb)
}
