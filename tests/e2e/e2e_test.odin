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
	app.paint_doc(&buf, ui.Rect{2, 2, 20, 5}, doc, 0, -1, -1, nil)
	heading := ui.buffer_at(&buf, 4, 2)
	testing.expect(t, heading != nil)
	testing.expect_value(t, heading.ch, 'P')

	long := micron.parse("alpha bravo charlie delta echo foxtrot")
	defer micron.doc_destroy(&long)
	app.paint_doc(&buf, ui.Rect{0, 10, 12, 4}, long, 0, -1, -1, nil)
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

@(test)
test_e2e_compose_shows_method :: proc(t: ^testing.T) {
	ui.set_theme(ui.FIELD)
	ui.caps_init("256")
	a: app.App
	ui.input_init(&a.compose_to)
	defer ui.input_destroy(&a.compose_to)
	ui.input_init(&a.compose_body)
	defer ui.input_destroy(&a.compose_body)
	a.compose_method = .Propagated

	buf := ui.buffer_create(50, 12)
	defer ui.buffer_destroy(&buf)
	app.draw_compose(&a, &buf, ui.Rect{0, 0, 50, 12})

	found := false
	for cell in buf.cells {
		if cell.ch == 'P' {
			found = true
			break
		}
	}
	testing.expect(t, found)
	_ = lxmf.method_label(a.compose_method)
}

@(test)
test_e2e_network_propagation_panel :: proc(t: ^testing.T) {
	ui.set_theme(ui.FIELD)
	ui.caps_init("256")
	a: app.App
	a.cfg = store.config_default()
	defer store.config_destroy_strings(&a.cfg)
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)
	ui.list_init(&a.net_list)
	defer ui.list_destroy(&a.net_list)
	ui.input_init(&a.net_search)
	defer ui.input_destroy(&a.net_search)
	a.net_view = .Propagation
	a.term_w = 80
	a.term_h = 24

	pn: [store.HASH_LEN]u8
	pn[0] = 0x10
	store.config_set_propagation_node(&a.cfg, pn)
	a.session.sync.state = .Complete
	a.session.sync.last_result = strings.clone("Sync complete")
	defer delete(a.session.sync.last_result)

	buf := ui.buffer_create(80, 24)
	defer ui.buffer_destroy(&buf)
	app.draw_network(&a, &buf, ui.Rect{0, 0, 80, 24})

	has_prop := false
	has_sync := false
	row := make([]u8, buf.width)
	defer delete(row)
	for y in 0 ..< buf.height {
		n := 0
		for x in 0 ..< buf.width {
			c := buf.cells[y * buf.width + x].ch
			if c > 0 && c < 128 {
				row[n] = u8(c)
				n += 1
			}
		}
		line := string(row[:n])
		if strings.contains(line, "Prop node") {
			has_prop = true
		}
		if strings.contains(line, "Sync") {
			has_sync = true
		}
	}
	testing.expect(t, has_prop)
	testing.expect(t, has_sync)
}

@(test)
test_e2e_prop_config_roundtrip :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-e2e-prop"})
	_ = os.remove_all(base)
	defer os.remove_all(base)
	_ = os.make_directory_all(base)

	cfg := store.config_default()
	delete(cfg.data_dir)
	delete(cfg.config_path)
	cfg.data_dir = strings.clone(base)
	cfg.config_path, _ = filepath.join({base, "config"})
	pn: [store.HASH_LEN]u8
	pn[3] = 0x3c
	store.config_set_propagation_node(&cfg, pn)
	cfg.send_method = .Opportunistic
	testing.expect(t, store.config_save(&cfg))
	defer store.config_destroy_strings(&cfg)

	loaded := store.config_default()
	delete(loaded.data_dir)
	delete(loaded.config_path)
	loaded.data_dir = strings.clone(base)
	loaded.config_path, _ = filepath.join({base, "config"})
	store.config_load(&loaded)
	defer store.config_destroy_strings(&loaded)
	testing.expect(t, loaded.has_propagation_node)
	testing.expect_value(t, loaded.send_method, lxmf.Method.Opportunistic)
}
