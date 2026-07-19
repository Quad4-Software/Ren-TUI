// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Propagation config, wrap packing, and send method helpers.
*/

package tests

import "core:testing"

import "ren:lxmf"
import "ren:net"
import "ren:store"

@(test)
test_prop_config_roundtrip :: proc(t: ^testing.T) {
	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)

	testing.expect(t, !cfg.has_propagation_node)
	testing.expect(t, cfg.try_propagation_on_fail)
	testing.expect_value(t, cfg.send_method, lxmf.Method.Direct)

	node: [store.HASH_LEN]u8
	node[0] = 0x11
	node[15] = 0xee
	store.config_set_propagation_node(&cfg, node)
	testing.expect(t, cfg.has_propagation_node)
	testing.expect(t, cfg.propagation_node == node)

	cfg.send_method = .Propagated
	cfg.try_propagation_on_fail = false
	hex := store.hash_hex(node, context.temp_allocator)
	store.config_set_propagation_node_hex(&cfg, "")
	testing.expect(t, !cfg.has_propagation_node)
	store.config_set_propagation_node_hex(&cfg, hex)
	testing.expect(t, cfg.has_propagation_node)
	testing.expect(t, cfg.propagation_node == node)
}

@(test)
test_send_method_cycle :: proc(t: ^testing.T) {
	m := lxmf.Method.Direct
	m = lxmf.cycle_send_method(m)
	testing.expect_value(t, m, lxmf.Method.Opportunistic)
	m = lxmf.cycle_send_method(m)
	testing.expect_value(t, m, lxmf.Method.Propagated)
	m = lxmf.cycle_send_method(m)
	testing.expect_value(t, m, lxmf.Method.Direct)
	testing.expect_value(t, lxmf.parse_send_method("propagated"), lxmf.Method.Propagated)
	testing.expect_value(t, lxmf.parse_send_method("opportunistic"), lxmf.Method.Opportunistic)
}

@(test)
test_propagation_wrap_shape :: proc(t: ^testing.T) {
	packed := make([]u8, 20)
	defer delete(packed)
	for i in 0 ..< 16 {
		packed[i] = u8(i)
	}
	packed[16] = 0xaa
	enc := []u8{1, 2, 3, 4}
	wrap := lxmf.pack_propagation_payload(packed, enc)
	defer delete(wrap)
	testing.expect(t, len(wrap) > 20)
	testing.expect_value(t, wrap[0], u8(0x92))
	plain := lxmf.opportunistic_plaintext(packed)
	testing.expect_value(t, len(plain), 4)
	testing.expect_value(t, plain[0], u8(0xaa))
}

@(test)
test_send_job_opportunistic :: proc(t: ^testing.T) {
	fake: Fake_Send
	s: net.Session
	testing.expect(t, setup_send_session(&s, &fake))
	defer lxmf.router_destroy(&s.router)
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	fake.packet_ok = true
	s.send_transport.packet_send = fake_packet_send

	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)

	dest: [store.HASH_LEN]u8
	dest[0] = 0xcd
	testing.expect(t, net.session_send_begin(&s, dest, "", "hi", &convs, &dir, nil, .Opportunistic))
	for _ in 0 ..< 4 {
		if !net.session_send_busy(&s) {
			break
		}
		net.session_send_tick(&s)
	}
	testing.expect(t, s.send.ok)
	testing.expect_value(t, fake.packets, 1)
	testing.expect_value(t, fake.opened, 0)
	net.session_send_cancel(&s)
}

@(test)
test_send_job_propagate_needs_node :: proc(t: ^testing.T) {
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

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)

	dest: [store.HASH_LEN]u8
	ok := net.session_send_begin(&s, dest, "", "x", &convs, &dir, &cfg, .Propagated)
	testing.expect(t, !ok)
}

@(test)
test_send_job_failover_to_propagate :: proc(t: ^testing.T) {
	fake: Fake_Send
	fake.fail_until = 2
	s: net.Session
	testing.expect(t, setup_send_session(&s, &fake))
	defer lxmf.router_destroy(&s.router)
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	s.send_transport.encrypt = fake_encrypt
	fake.encrypt_ok = true

	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	pn: [store.HASH_LEN]u8
	pn[0] = 0x42
	store.config_set_propagation_node(&cfg, pn)
	cfg.try_propagation_on_fail = true

	dest: [store.HASH_LEN]u8
	dest[1] = 9
	testing.expect(t, net.session_send_begin(&s, dest, "", "x", &convs, &dir, &cfg, .Direct))

	for _ in 0 ..< 16 {
		if !net.session_send_busy(&s) {
			break
		}
		net.session_send_tick(&s)
	}
	testing.expect(t, s.send.ok)
	testing.expect(t, s.send.failed_over)
	net.session_send_cancel(&s)
}
