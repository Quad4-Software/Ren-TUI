// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
App handlers for typed session events without a live mesh.
*/

package tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "ren:app"
import "ren:net"
import "ren:store"
import "ren:ui"

@(test)
test_app_events_message_and_send :: proc(t: ^testing.T) {
	a: app.App
	ui.list_init(&a.conv_list)
	defer ui.list_destroy(&a.conv_list)
	ui.list_init(&a.net_list)
	defer ui.list_destroy(&a.net_list)
	a.net_peer_idx = make([dynamic]int)
	defer delete(a.net_peer_idx)
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)
	store.conversations_init(&a.conversations)
	defer store.conversations_destroy(&a.conversations)

	peer: [store.HASH_LEN]u8
	peer[0] = 0x42
	_ = store.conversations_get_or_create(&a.conversations, peer, "Peer")
	app.refresh_conv_list(&a)

	net.session_event_push(&a.session, .Message_Received)
	app.handle_session_events(&a)
	testing.expect_value(t, a.recv_count, 1)
	testing.expect(t, a.ui_dirty)
	testing.expect(t, a.status_hold_len > 0)

	a.ui_dirty = false
	net.session_event_push(&a.session, .Send_Ok)
	app.handle_session_events(&a)
	testing.expect(t, a.ui_dirty)

	a.ui_dirty = false
	net.session_event_push(&a.session, .Send_Failed, "page busy")
	app.handle_session_events(&a)
	testing.expect(t, a.ui_dirty)
	testing.expect(t, a.status_hold_len > 0)

	net.session_event_ring_clear(&a.session.events)
	delete(a.session.status)
}

@(test)
test_conversations_schema_version_roundtrip :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-schema-ver"})
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
	peer: [store.HASH_LEN]u8
	peer[0] = 7
	conv := store.conversations_get_or_create(&convs, peer, "S")
	append(&conv.messages, store.Stored_Message{
		direction = .Out,
		title = strings.clone(""),
		content = strings.clone("hi"),
		timestamp = 1,
		method = .Direct,
		verified = true,
	})
	testing.expect(t, store.conversations_save_peer(&convs, &cfg, peer))

	loaded: store.Conversations
	store.conversations_init(&loaded)
	defer store.conversations_destroy(&loaded)
	store.conversations_load(&loaded, &cfg)
	testing.expect(t, len(loaded.items) >= 1)
	testing.expect_value(t, loaded.items[0].messages[0].content, "hi")
}
