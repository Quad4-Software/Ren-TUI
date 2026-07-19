// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Unit tests for typed session event ring.
*/

package tests

import "core:strings"
import "core:testing"

import "ren:app"
import "ren:net"
import "ren:store"
import "ren:ui"

@(test)
test_session_event_default_detail :: proc(t: ^testing.T) {
	testing.expect_value(t, net.session_event_default_detail(.Message_Received), "message received")
	testing.expect_value(t, net.session_event_default_detail(.Send_Ok), "sent")
	testing.expect_value(t, net.session_event_default_detail(.Offline), "offline")
}

@(test)
test_session_event_ring_push_drain_order :: proc(t: ^testing.T) {
	s: net.Session
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	net.session_event_push(&s, .Online)
	net.session_event_push(&s, .Message_Received, "message received")
	net.session_event_push(&s, .Send_Ok)

	buf: [8]net.Session_Event
	n := net.session_events_drain(&s, buf[:])
	testing.expect_value(t, n, 3)
	testing.expect_value(t, buf[0].kind, net.Session_Event_Kind.Online)
	testing.expect_value(t, buf[1].kind, net.Session_Event_Kind.Message_Received)
	testing.expect_value(t, buf[2].kind, net.Session_Event_Kind.Send_Ok)
	for i in 0 ..< n {
		delete(buf[i].detail)
	}
	testing.expect_value(t, s.events.count, 0)
}

@(test)
test_session_event_ring_drop_oldest :: proc(t: ^testing.T) {
	s: net.Session
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	for i in 0 ..< net.SESSION_EVENT_CAP + 3 {
		net.session_event_push(&s, .Announce, "announced")
		_ = i
	}
	testing.expect_value(t, s.events.count, net.SESSION_EVENT_CAP)

	buf: [net.SESSION_EVENT_CAP]net.Session_Event
	n := net.session_events_drain(&s, buf[:])
	testing.expect_value(t, n, net.SESSION_EVENT_CAP)
	for i in 0 ..< n {
		delete(buf[i].detail)
	}
}

@(test)
test_handle_session_events_message_received :: proc(t: ^testing.T) {
	a: app.App
	ui.list_init(&a.conv_list)
	defer ui.list_destroy(&a.conv_list)
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)
	store.conversations_init(&a.conversations)
	defer store.conversations_destroy(&a.conversations)

	peer: [store.HASH_LEN]u8
	peer[0] = 0x11
	store.conversations_add_message(
		&a.conversations,
		peer,
		store.Stored_Message{
			direction = .In,
			title = strings.clone(""),
			content = strings.clone("hi"),
			timestamp = 1,
			method = .Opportunistic,
		},
		"Peer",
	)
	testing.expect_value(t, len(a.conv_list.items), 0)

	net.session_event_push(&a.session, .Message_Received)
	app.handle_session_events(&a)
	testing.expect_value(t, a.recv_count, 1)
	testing.expect(t, a.ui_dirty)
	testing.expect_value(t, len(a.conv_list.items), 1)
	net.session_event_ring_clear(&a.session.events)
	delete(a.session.status)
}
