// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Acceptance checks for config theme and persist flows.
*/

package tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "ren:constants"
import "ren:lxmf"
import "ren:store"
import "ren:ui"

@(test)
test_acceptance_config_theme_persist :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-acceptance-config"})
	_ = os.remove_all(base)
	defer os.remove_all(base)
	_ = os.make_directory_all(base)

	cfg := store.config_default()
	delete(cfg.data_dir)
	delete(cfg.config_path)
	delete(cfg.display_name)
	delete(cfg.color_mode)
	delete(cfg.theme_name)
	cfg.data_dir = strings.clone(base)
	cfg.config_path, _ = filepath.join({base, "config"})
	cfg.display_name = strings.clone("TestPeer")
	cfg.color_mode = strings.clone("256")
	cfg.theme_name = strings.clone("slate")
	ui.theme_hex_set(&cfg.theme_hex, "accent", "#5a96be")
	cfg.auto_announce = false
	cfg.announce_interval_sec = 120
	cfg.mouse = false

	testing.expect(t, store.config_save(&cfg))
	defer store.config_destroy_strings(&cfg)

	loaded := store.config_default()
	delete(loaded.data_dir)
	delete(loaded.config_path)
	loaded.data_dir = strings.clone(base)
	loaded.config_path, _ = filepath.join({base, "config"})
	store.config_load(&loaded)
	defer store.config_destroy_strings(&loaded)

	testing.expect_value(t, loaded.display_name, "TestPeer")
	testing.expect_value(t, loaded.color_mode, "256")
	testing.expect_value(t, loaded.theme_name, "slate")
	testing.expect_value(t, loaded.theme_hex.accent, "#5a96be")
	testing.expect(t, !loaded.auto_announce)
	testing.expect_value(t, loaded.announce_interval_sec, 120)
	testing.expect(t, !loaded.mouse)
}

@(test)
test_acceptance_conversations_persist :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-acceptance-persist"})
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
	peer[0] = 0xab
	peer[15] = 0xcd
	msg := store.Stored_Message{
		direction = .Out,
		title = strings.clone("hi"),
		content = strings.clone("saved"),
		timestamp = 1.5,
		method = .Direct,
		verified = true,
		hops = 2,
	}
	store.conversations_add_message_persist(&convs, &cfg, peer, msg, "peer")

	path, _ := filepath.join({base, constants.CONVERSATIONS_DIR, store.hash_hex(peer, context.temp_allocator), constants.MESSAGES_FILE})
	testing.expect(t, os.exists(path))

	loaded: store.Conversations
	store.conversations_init(&loaded)
	defer store.conversations_destroy(&loaded)
	store.conversations_load(&loaded, &cfg)
	testing.expect_value(t, len(loaded.items), 1)
	testing.expect(t, loaded.items[0].peer_hash == peer)
	testing.expect_value(t, len(loaded.items[0].messages), 1)
	testing.expect_value(t, loaded.items[0].messages[0].content, "saved")
	testing.expect_value(t, loaded.items[0].messages[0].hops, u8(2))
}

@(test)
test_acceptance_opportunistic_wire_roundtrip :: proc(t: ^testing.T) {
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)
	h := mat.hash
	dest := lxmf.delivery_hash(h[:])

	msg: lxmf.Message
	lxmf.message_init(&msg)
	defer lxmf.message_destroy(&msg)
	msg.destination_hash = dest
	msg.title = strings.clone("")
	msg.content = strings.clone("from-python")
	testing.expect(t, lxmf.message_pack(&msg, &mat))

	wire := msg.packed[lxmf.HASH_LEN:]
	full := make([]u8, lxmf.HASH_LEN + len(wire))
	defer delete(full)
	copy(full[0:lxmf.HASH_LEN], dest[:])
	copy(full[lxmf.HASH_LEN:], wire)

	out, uok := lxmf.message_unpack(full, .Opportunistic)
	testing.expect(t, uok)
	defer lxmf.message_destroy(&out)
	testing.expect_value(t, out.content, "from-python")
	testing.expect_value(t, out.method, lxmf.Method.Opportunistic)
	testing.expect(t, out.destination_hash == dest)
	testing.expect(t, out.source_hash == dest)
}

@(test)
test_acceptance_source_hash_is_delivery_hash :: proc(t: ^testing.T) {
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)
	h := mat.hash
	delivery := lxmf.delivery_hash(h[:])

	msg: lxmf.Message
	lxmf.message_init(&msg)
	defer lxmf.message_destroy(&msg)
	msg.destination_hash = delivery
	msg.title = strings.clone("")
	msg.content = strings.clone("ping")
	testing.expect(t, lxmf.message_pack(&msg, &mat))
	testing.expect(t, msg.source_hash == delivery)
}

@(test)
test_acceptance_identity_file_mode_owner_only :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-acceptance-ident"})
	_ = os.remove_all(base)
	defer os.remove_all(base)
	_ = os.make_directory_all(base)

	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)
	path, _ := filepath.join({base, "identity"})
	testing.expect(t, lxmf.identity_save_file(&mat, path))

	info, err := os.stat(path, context.allocator)
	testing.expect(t, err == nil)
	defer os.file_info_delete(info, context.allocator)
	mode := info.mode
	testing.expect(t, .Read_User in mode)
	testing.expect(t, .Write_User in mode)
	testing.expect(t, .Read_Group not_in mode)
	testing.expect(t, .Write_Group not_in mode)
	testing.expect(t, .Read_Other not_in mode)
	testing.expect(t, .Write_Other not_in mode)
}
