// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Unit tests for async LXMF send job with fake transport.
*/

package tests

import "core:testing"

import "ren:lxmf"
import "ren:net"
import "ren:store"

import rns "rns:rns"

Fake_Send :: struct {
	opened:     int,
	sent:       int,
	closed:     int,
	packets:    int,
	fail_open:  bool,
	fail_until: int,
	packet_ok:  bool,
	encrypt_ok: bool,
}

fake_path_ensure :: proc(user: rawptr, dest: [store.HASH_LEN]u8) -> bool {
	_ = user
	_ = dest
	return true
}

fake_link_open :: proc(user: rawptr, dest: []u8) -> (link: rns.Link, link_id: [store.HASH_LEN]u8, ok: bool) {
	_ = dest
	f := cast(^Fake_Send)user
	f.opened += 1
	if f.fail_open || (f.fail_until > 0 && f.opened <= f.fail_until) {
		return 0, {}, false
	}
	return 1, {}, true
}

fake_link_close :: proc(user: rawptr, link: rns.Link) {
	_ = link
	f := cast(^Fake_Send)user
	f.closed += 1
}

fake_link_send :: proc(user: rawptr, link: rns.Link, data: []u8) -> bool {
	_ = link
	_ = data
	f := cast(^Fake_Send)user
	f.sent += 1
	return true
}

fake_packet_send :: proc(user: rawptr, dest: []u8, data: []u8) -> bool {
	_ = dest
	_ = data
	f := cast(^Fake_Send)user
	f.packets += 1
	return f.packet_ok
}

fake_encrypt :: proc(user: rawptr, dest: []u8, plaintext: []u8) -> ([]u8, bool) {
	_ = dest
	f := cast(^Fake_Send)user
	if !f.encrypt_ok {
		return nil, false
	}
	out := make([]u8, len(plaintext))
	copy(out, plaintext)
	return out, true
}

setup_send_session :: proc(s: ^net.Session, fake: ^Fake_Send) -> bool {
	mat, ok := lxmf.identity_generate()
	if !ok {
		return false
	}
	s.material = mat
	lxmf.router_init(&s.router, mat, "test")
	s.started = true
	s.send_transport = net.Send_Transport{
		user = fake,
		path_ensure = fake_path_ensure,
		link_open = fake_link_open,
		link_close = fake_link_close,
		link_send = fake_link_send,
		auto_link = true,
	}
	return true
}

@(test)
test_send_job_begin_to_success :: proc(t: ^testing.T) {
	fake: Fake_Send
	s: net.Session
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
	dest[0] = 0xab
	testing.expect(t, net.session_send_begin(&s, dest, "", "hello", &convs, &dir, nil))
	for _ in 0 ..< 8 {
		if !net.session_send_busy(&s) {
			break
		}
		net.session_send_tick(&s)
	}
	testing.expect(t, s.send.ok)
	testing.expect(t, !net.session_send_busy(&s))
	testing.expect_value(t, fake.opened, 1)
	testing.expect_value(t, fake.sent, 1)
	testing.expect(t, net.session_events_has(&s, .Send_Ok) || s.status == "sent")
	net.session_send_cancel(&s)
}

@(test)
test_send_job_reject_when_page_busy :: proc(t: ^testing.T) {
	fake: Fake_Send
	s: net.Session
	testing.expect(t, setup_send_session(&s, &fake))
	defer lxmf.router_destroy(&s.router)
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	s.page.active = true
	s.page.done = false

	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)

	dest: [store.HASH_LEN]u8
	ok := net.session_send_begin(&s, dest, "", "hello", &convs, &dir, nil)
	testing.expect(t, !ok)
	testing.expect_value(t, s.status, "page busy")
}

@(test)
test_send_job_link_open_failed :: proc(t: ^testing.T) {
	fake: Fake_Send
	fake.fail_open = true
	s: net.Session
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
	dest[1] = 1
	testing.expect(t, net.session_send_begin(&s, dest, "", "x", &convs, &dir, nil))
	// First open fails then retries once then fails
	for _ in 0 ..< 4 {
		if !net.session_send_busy(&s) {
			break
		}
		net.session_send_tick(&s)
	}
	testing.expect(t, !s.send.ok)
	testing.expect(t, s.status == "link open failed" || strings_has_send_failed(&s))
	net.session_send_cancel(&s)
}

strings_has_send_failed :: proc(s: ^net.Session) -> bool {
	return net.session_events_has(s, .Send_Failed)
}
