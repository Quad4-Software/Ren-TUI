// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Conversation list indexing, unread, labels, and custom names.
*/

package tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "ren:app"
import "ren:store"
import "ren:ui"

@(test)
test_conv_peer_idx_respects_filter :: proc(t: ^testing.T) {
	a: app.App
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)
	store.conversations_init(&a.conversations)
	defer store.conversations_destroy(&a.conversations)
	ui.list_init(&a.conv_list)
	a.conv_peer_idx = make([dynamic]int)
	defer delete(a.conv_peer_idx)
	ui.input_init(&a.conv_search)
	defer ui.input_destroy(&a.conv_search)
	defer ui.list_destroy(&a.conv_list)

	p0, p1, p2: [store.HASH_LEN]u8
	p0[0] = 1
	p1[0] = 2
	p2[0] = 3
	store.directory_upsert(&a.directory, p0, p0, .Lxmf, "alice", nil)
	store.directory_upsert(&a.directory, p1, p1, .Lxmf, "bob", nil)
	store.directory_upsert(&a.directory, p2, p2, .Lxmf, "carol", nil)
	_ = store.conversations_get_or_create(&a.conversations, p0, "alice")
	_ = store.conversations_get_or_create(&a.conversations, p1, "bob")
	_ = store.conversations_get_or_create(&a.conversations, p2, "carol")

	app.refresh_conv_list(&a)
	testing.expect_value(t, len(a.conv_list.items), 3)
	testing.expect_value(t, len(a.conv_peer_idx), 3)

	ui.input_clear(&a.conv_search)
	strings.write_string(&a.conv_search.text, "bob")
	app.refresh_conv_list(&a)
	testing.expect_value(t, len(a.conv_list.items), 1)
	testing.expect_value(t, len(a.conv_peer_idx), 1)
	idx := app.conv_selected_store_idx(&a)
	testing.expect(t, idx >= 0)
	testing.expect(t, a.conversations.items[idx].peer_hash == p1)
}

@(test)
test_bug_conv_filter_does_not_show_wrong_thread :: proc(t: ^testing.T) {
	a: app.App
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)
	store.conversations_init(&a.conversations)
	defer store.conversations_destroy(&a.conversations)
	ui.list_init(&a.conv_list)
	a.conv_peer_idx = make([dynamic]int)
	defer delete(a.conv_peer_idx)
	ui.input_init(&a.conv_search)
	defer ui.input_destroy(&a.conv_search)
	defer ui.list_destroy(&a.conv_list)

	p0, p1: [store.HASH_LEN]u8
	p0[0] = 0xaa
	p1[0] = 0xbb
	_ = store.conversations_get_or_create(&a.conversations, p0, "first")
	_ = store.conversations_get_or_create(&a.conversations, p1, "second")
	store.conversations_add_message(&a.conversations, p1, store.Stored_Message{
		direction = .In,
		content = strings.clone("secret"),
	}, "second")

	ui.input_clear(&a.conv_search)
	strings.write_string(&a.conv_search.text, "second")
	app.refresh_conv_list(&a)
	a.conv_list.selected = 0
	idx := app.conv_selected_store_idx(&a)
	testing.expect(t, idx >= 0)
	testing.expect(t, a.conversations.items[idx].peer_hash == p1)
	testing.expect(t, len(a.conversations.items[idx].messages) == 1)
	testing.expect(t, a.conversations.items[0].peer_hash == p0)
}

@(test)
test_conversation_label_custom_over_announce :: proc(t: ^testing.T) {
	d: store.Directory
	store.directory_init(&d)
	defer store.directory_destroy(&d)
	peer: [store.HASH_LEN]u8
	peer[0] = 9
	store.directory_upsert(&d, peer, peer, .Lxmf, "announce-name", nil)
	conv := store.Conversation{
		peer_hash = peer,
		title = strings.clone("old-title"),
		custom_name = strings.clone("nickname"),
	}
	defer {
		delete(conv.title)
		delete(conv.custom_name)
	}
	label := store.conversation_label(&d, conv)
	defer delete(label)
	testing.expect_value(t, label, "nickname")

	delete(conv.custom_name)
	conv.custom_name = strings.clone("")
	label2 := store.conversation_label(&d, conv)
	defer delete(label2)
	testing.expect_value(t, label2, "announce-name")
}

@(test)
test_bug_announce_does_not_clear_custom_name :: proc(t: ^testing.T) {
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)
	peer: [store.HASH_LEN]u8
	peer[0] = 7
	_ = store.conversations_get_or_create(&convs, peer, "hex")
	testing.expect(t, store.conversations_set_custom_name(&convs, peer, "keep-me"))
	testing.expect_value(t, convs.items[0].custom_name, "keep-me")
	d: store.Directory
	store.directory_init(&d)
	defer store.directory_destroy(&d)
	store.directory_upsert(&d, peer, peer, .Lxmf, "new-announce", nil)
	testing.expect_value(t, convs.items[0].custom_name, "keep-me")
	label := store.conversation_label(&d, convs.items[0])
	defer delete(label)
	testing.expect_value(t, label, "keep-me")
}

@(test)
test_conversations_custom_name_schema_v2_roundtrip :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-conv-custom-test"})
	_ = os.remove_all(base)
	_ = os.make_directory_all(base)
	defer os.remove_all(base)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	delete(cfg.data_dir)
	cfg.data_dir = strings.clone(base)

	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)
	peer: [store.HASH_LEN]u8
	peer[0] = 0x42
	_ = store.conversations_get_or_create(&convs, peer, "title")
	_ = store.conversations_set_custom_name(&convs, peer, "my friend")
	testing.expect(t, store.conversations_save_peer(&convs, &cfg, peer))

	loaded: store.Conversations
	store.conversations_init(&loaded)
	defer store.conversations_destroy(&loaded)
	store.conversations_load(&loaded, &cfg)
	testing.expect_value(t, len(loaded.items), 1)
	testing.expect_value(t, loaded.items[0].custom_name, "my friend")
}

@(test)
test_bug_custom_name_sanitizes_control_chars :: proc(t: ^testing.T) {
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)
	peer: [store.HASH_LEN]u8
	peer[0] = 3
	_ = store.conversations_get_or_create(&convs, peer, "x")
	evil := "hi\x00\x1fthere"
	testing.expect(t, store.conversations_set_custom_name(&convs, peer, evil))
	testing.expect(t, !strings.contains(convs.items[0].custom_name, "\x00"))
	testing.expect(t, !strings.contains(convs.items[0].custom_name, "\x1f"))
}

@(test)
test_conversations_clear_unread :: proc(t: ^testing.T) {
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)
	peer: [store.HASH_LEN]u8
	peer[0] = 5
	_ = store.conversations_get_or_create(&convs, peer, "p")
	store.conversations_add_message(&convs, peer, store.Stored_Message{
		direction = .In,
		content = strings.clone("hi"),
	}, "p")
	testing.expect(t, convs.items[0].unread == 1)
	testing.expect(t, store.conversations_clear_unread(&convs, peer))
	testing.expect_value(t, convs.items[0].unread, 0)
	testing.expect(t, !store.conversations_clear_unread(&convs, peer))
}
