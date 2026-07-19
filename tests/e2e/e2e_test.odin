// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
End to end flows without a live Reticulum mesh.
*/

package tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "ren:lxmf"
import "ren:micron"
import "ren:store"
import "ren:ui"
import "ren:app"

@(test)
test_e2e_identity_pack_unpack_verify :: proc(t: ^testing.T) {
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)

	dest := lxmf.delivery_hash(mat.hash[:])
	msg: lxmf.Message
	lxmf.message_init(&msg)
	defer lxmf.message_destroy(&msg)
	msg.destination_hash = dest
	msg.title = strings.clone("e2e")
	msg.content = strings.clone("hello mesh")
	testing.expect(t, lxmf.message_pack(&msg, &mat))

	out, uok := lxmf.message_unpack(msg.packed)
	testing.expect(t, uok)
	defer lxmf.message_destroy(&out)
	testing.expect_value(t, out.title, "e2e")
	testing.expect_value(t, out.content, "hello mesh")
	testing.expect(t, lxmf.message_verify(&out, mat.sign_pub[:]))
}

@(test)
test_e2e_persist_conversation_reload :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-e2e-persist"})
	_ = os.remove_all(base)
	defer os.remove_all(base)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	delete(cfg.data_dir)
	cfg.data_dir = strings.clone(base)

	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)

	peer: [store.HASH_LEN]u8
	peer[0] = 0x11
	peer[15] = 0x22
	msg := store.Stored_Message{
		direction = .In,
		title = strings.clone(""),
		content = strings.clone("persisted-e2e"),
		timestamp = 42,
		method = .Direct,
		verified = true,
		hops = 1,
	}
	store.conversations_add_message_persist(&convs, &cfg, peer, msg, "peer")

	loaded: store.Conversations
	store.conversations_init(&loaded)
	defer store.conversations_destroy(&loaded)
	store.conversations_load(&loaded, &cfg)
	testing.expect_value(t, len(loaded.items), 1)
	testing.expect_value(t, loaded.items[0].messages[0].content, "persisted-e2e")
}

@(test)
test_e2e_draw_widgets_into_buffer :: proc(t: ^testing.T) {
	ui.set_theme(ui.FIELD)
	ui.caps_init("256")
	buf := ui.buffer_create(60, 20)
	defer ui.buffer_destroy(&buf)

	r := ui.Rect{0, 0, 60, 20}
	ui.draw_box(&buf, r, "e2e", true)
	list: ui.List_State
	ui.list_init(&list)
	defer ui.list_destroy(&list)
	ui.list_push(&list, "one")
	ui.list_push(&list, "two")
	inner := ui.rect_inset(r, 1)
	ui.draw_list(&buf, inner, &list)

	cell := ui.buffer_at(&buf, 1, 0)
	testing.expect(t, cell != nil)
	testing.expect(t, cell.ch != 0)

	doc := micron.parse("> Page\nbody")
	defer micron.doc_destroy(&doc)
	app.paint_doc(&buf, ui.Rect{2, 2, 20, 5}, doc, 0, -1, nil)
	heading := ui.buffer_at(&buf, 4, 2)
	testing.expect(t, heading != nil)
	testing.expect_value(t, heading.ch, 'P')

	long := micron.parse("alpha bravo charlie delta echo foxtrot")
	defer micron.doc_destroy(&long)
	app.paint_doc(&buf, ui.Rect{0, 10, 12, 4}, long, 0, -1, nil)
	row0 := ui.buffer_at(&buf, 0, 10)
	row1 := ui.buffer_at(&buf, 0, 11)
	testing.expect(t, row0 != nil && row0.ch != 0)
	testing.expect(t, row1 != nil && row1.ch != 0)
}

@(test)
test_e2e_config_theme_apply_roundtrip :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-e2e-config"})
	_ = os.remove_all(base)
	defer os.remove_all(base)
	_ = os.make_directory_all(base)

	cfg := store.config_default()
	delete(cfg.data_dir)
	delete(cfg.config_path)
	delete(cfg.theme_name)
	cfg.data_dir = strings.clone(base)
	cfg.config_path, _ = filepath.join({base, "config"})
	cfg.theme_name = strings.clone("slate")
	store.theme_overrides_set(&cfg.theme_overrides, "accent", "#aabbcc")
	testing.expect(t, store.config_save(&cfg))
	defer store.config_destroy_strings(&cfg)

	loaded := store.config_default()
	delete(loaded.data_dir)
	delete(loaded.config_path)
	loaded.data_dir = strings.clone(base)
	loaded.config_path, _ = filepath.join({base, "config"})
	store.config_load(&loaded)
	defer store.config_destroy_strings(&loaded)
	ui.apply_theme_hex(loaded.theme_name, ui.Theme_Hex{
		accent = loaded.theme_overrides.accent,
	})
	th := ui.theme()
	testing.expect_value(t, th.name, "slate")
	testing.expect_value(t, th.accent.r, u8(0xaa))
	ui.set_theme(ui.FIELD)
}
