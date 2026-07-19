// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Regression tests for past packing and UI bugs.
*/

package tests

import "core:os"
import "core:strings"
import "core:testing"

import "ren:lxmf"
import "ren:ui"

@(test)
test_bug_field_map_canonical_order :: proc(t: ^testing.T) {
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)
	dest := lxmf.delivery_hash(mat.hash[:])

	pack_keys :: proc(dest: [lxmf.HASH_LEN]u8, mat: ^lxmf.Identity_Material, keys: []i64) -> ([]u8, bool) {
		msg: lxmf.Message
		lxmf.message_init(&msg)
		defer lxmf.message_destroy(&msg)
		msg.destination_hash = dest
		msg.timestamp = 12345.0
		msg.title = strings.clone("")
		msg.content = strings.clone("fields")
		for k in keys {
			msg.fields[k] = lxmf.Value{kind = .Int, i = k * 10}
		}
		if !lxmf.message_pack(&msg, mat) {
			return nil, false
		}
		out := make([]u8, len(msg.packed))
		copy(out, msg.packed)
		return out, true
	}

	a, aok := pack_keys(dest, &mat, []i64{1, 2, 3, 4, 5})
	testing.expect(t, aok)
	defer delete(a)
	b, bok := pack_keys(dest, &mat, []i64{5, 4, 3, 2, 1})
	testing.expect(t, bok)
	defer delete(b)
	testing.expect(t, len(a) == len(b))
	same := true
	for i in 0 ..< len(a) {
		if a[i] != b[i] {
			same = false
			break
		}
	}
	testing.expect(t, same)

	out, uok := lxmf.message_unpack(a)
	testing.expect(t, uok)
	defer lxmf.message_destroy(&out)
	testing.expect(t, lxmf.message_verify(&out, mat.sign_pub[:]))
}

@(test)
test_bug_no_color_honored_on_linux_term :: proc(t: ^testing.T) {
	os.set_env("NO_COLOR", "1")
	os.set_env("TERM", "linux")
	os.unset_env("REN_UI")
	defer {
		os.unset_env("NO_COLOR")
		os.unset_env("TERM")
	}
	ui.caps_init("")
	testing.expect_value(t, ui.caps_get().mode, ui.Color_Mode.None)
	testing.expect_value(t, ui.caps_get().name, "nocolor")
	ui.caps_init("full")
}

@(test)
test_bug_utf8_input_cursor_and_backspace :: proc(t: ^testing.T) {
	inp: ui.Input_State
	ui.input_init(&inp)
	defer ui.input_destroy(&inp)

	_ = ui.input_handle(&inp, ui.Event{kind = .Rune, ch = 'é'})
	val := ui.input_value(&inp)
	testing.expect_value(t, len(val), 2)
	testing.expect_value(t, inp.cursor, 2)

	_ = ui.input_handle(&inp, ui.Event{kind = .Backspace})
	val = ui.input_value(&inp)
	testing.expect_value(t, len(val), 0)
	testing.expect_value(t, inp.cursor, 0)
}

@(test)
test_bug_as_int_rejects_huge_uint :: proc(t: ^testing.T) {
	v := lxmf.Value{kind = .Uint, u = 1 << 63}
	_, ok := lxmf.as_int(v)
	testing.expect(t, !ok)

	v2 := lxmf.Value{kind = .Uint, u = u64(max(i64))}
	n, ok2 := lxmf.as_int(v2)
	testing.expect(t, ok2)
	testing.expect_value(t, n, max(i64))
}

@(test)
test_bug_draw_input_home_scroll :: proc(t: ^testing.T) {
	ui.set_theme(ui.FIELD)
	ui.caps_init("256")
	inp: ui.Input_State
	ui.input_init(&inp)
	defer ui.input_destroy(&inp)

	for _ in 0 ..< 40 {
		_ = ui.input_handle(&inp, ui.Event{kind = .Rune, ch = 'a'})
	}
	_ = ui.input_handle(&inp, ui.Event{kind = .Home})
	testing.expect_value(t, inp.cursor, 0)

	buf := ui.buffer_create(20, 5)
	defer ui.buffer_destroy(&buf)
	ui.draw_input(&buf, ui.Rect{0, 0, 20, 3}, &inp, "x", true)
	// Home keeps window at start: caret on col 0, next cell is still 'a'
	caret := ui.buffer_at(&buf, 1, 1)
	testing.expect(t, caret != nil)
	testing.expect_value(t, caret.ch, ui.caps_cursor_glyph())
	next := ui.buffer_at(&buf, 2, 1)
	testing.expect(t, next != nil)
	testing.expect_value(t, next.ch, 'a')
}
