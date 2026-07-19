// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Propagation sync status line and begin reject paths.
*/

package tests

import "core:strings"
import "core:testing"

import "ren:lxmf"
import "ren:net"
import "ren:store"

@(test)
test_session_sync_status_line_matrix :: proc(t: ^testing.T) {
	s: net.Session
	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)

	line := net.session_sync_status_line(&s, &cfg, context.temp_allocator)
	testing.expect(t, strings.contains(line, "no propagation node"))

	pn: [store.HASH_LEN]u8
	pn[0] = 1
	store.config_set_propagation_node(&cfg, pn)

	line = net.session_sync_status_line(&s, &cfg, context.temp_allocator)
	testing.expect_value(t, line, "Idle")

	s.sync.state = .Path_Requested
	s.sync.status = strings.clone("Path requested")
	line = net.session_sync_status_line(&s, &cfg, context.temp_allocator)
	testing.expect_value(t, line, "Path requested")
	delete(s.sync.status)
	s.sync.status = ""

	s.sync.state = .Complete
	s.sync.last_result = strings.clone("got 2")
	line = net.session_sync_status_line(&s, &cfg, context.temp_allocator)
	testing.expect_value(t, line, "got 2")
	delete(s.sync.last_result)

	s.sync.state = .Failed
	s.sync.last_result = strings.clone("boom")
	line = net.session_sync_status_line(&s, &cfg, context.temp_allocator)
	testing.expect_value(t, line, "boom")
	delete(s.sync.last_result)

	s.sync.state = .Request_Sent
	line = net.session_sync_status_line(&s, &cfg, context.temp_allocator)
	testing.expect_value(t, line, "Request sent")
}

@(test)
test_session_sync_begin_rejects :: proc(t: ^testing.T) {
	s: net.Session
	s.started = true
	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)

	ok := net.session_sync_begin(&s, &cfg)
	testing.expect(t, !ok)
	testing.expect_value(t, s.sync.state, net.Prop_Sync_State.No_Node)
	delete(s.sync.status)
	s.sync.status = ""

	pn: [store.HASH_LEN]u8
	pn[0] = 9
	store.config_set_propagation_node(&cfg, pn)

	s.page.active = true
	s.page.done = false
	ok = net.session_sync_begin(&s, &cfg)
	testing.expect(t, !ok)
	s.page.active = false

	fake: Fake_Send
	testing.expect(t, setup_send_session(&s, &fake))
	defer lxmf.router_destroy(&s.router)
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)

	dest: [store.HASH_LEN]u8
	dest[0] = 2
	testing.expect(t, net.session_send_begin(&s, dest, "", "busy", &convs, &dir, nil, .Direct))
	ok = net.session_sync_begin(&s, &cfg)
	testing.expect(t, !ok)
	net.session_send_cancel(&s)
}

@(test)
test_propagation_wrap_short_packed_nil :: proc(t: ^testing.T) {
	short := []u8{1, 2, 3}
	wrap := lxmf.pack_propagation_payload(short, []u8{9})
	testing.expect(t, wrap == nil)
	plain := lxmf.opportunistic_plaintext(short)
	testing.expect(t, plain == nil)
}
