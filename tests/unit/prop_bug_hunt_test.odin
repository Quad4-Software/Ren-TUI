// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Adversarial tests that must catch real prop/send/config bugs.
*/

package tests

import "core:strings"
import "core:testing"

import "ren:lxmf"
import "ren:net"
import "ren:store"

import rns "rns:rns"

@(test)
test_bug_parse_send_method_case_insensitive :: proc(t: ^testing.T) {
	testing.expect_value(t, lxmf.parse_send_method("Propagated"), lxmf.Method.Propagated)
	testing.expect_value(t, lxmf.parse_send_method("OPPORTUNISTIC"), lxmf.Method.Opportunistic)
	testing.expect_value(t, lxmf.parse_send_method("Direct"), lxmf.Method.Direct)
	testing.expect_value(t, lxmf.parse_send_method("PROP"), lxmf.Method.Propagated)
}

@(test)
test_bug_clear_propagation_node_none_case :: proc(t: ^testing.T) {
	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	pn: [store.HASH_LEN]u8
	pn[0] = 1
	store.config_set_propagation_node(&cfg, pn)
	store.config_set_propagation_node_hex(&cfg, "NONE")
	testing.expect(t, !cfg.has_propagation_node)
	store.config_set_propagation_node(&cfg, pn)
	store.config_set_propagation_node_hex(&cfg, "None")
	testing.expect(t, !cfg.has_propagation_node)
}

@(test)
test_bug_invalid_prop_hex_does_not_keep_stale_node :: proc(t: ^testing.T) {
	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	pn: [store.HASH_LEN]u8
	pn[0] = 0xab
	store.config_set_propagation_node(&cfg, pn)
	store.config_set_propagation_node_hex(&cfg, "not-valid-hex!!!!!!!!!!!!!")
	testing.expect(t, !cfg.has_propagation_node, "invalid hex must clear or reject prior node")
}

@(test)
test_bug_pack_propagation_rejects_empty_ciphertext :: proc(t: ^testing.T) {
	packed := make([]u8, lxmf.HASH_LEN + 4)
	defer delete(packed)
	wrap := lxmf.pack_propagation_payload(packed, nil)
	testing.expect(t, wrap == nil, "empty encrypt tail must not wrap")
	wrap2 := lxmf.pack_propagation_payload(packed, []u8{})
	testing.expect(t, wrap2 == nil, "zero-length encrypt tail must not wrap")
}

@(test)
test_bug_failover_encrypt_fail_restores_failed_state :: proc(t: ^testing.T) {
	fake: Fake_Send
	fake.packet_ok = false
	fake.encrypt_ok = false
	s: net.Session
	testing.expect(t, setup_send_session(&s, &fake))
	defer lxmf.router_destroy(&s.router)
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	s.send_transport.packet_send = fake_packet_send
	s.send_transport.encrypt = fake_encrypt

	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	pn: [store.HASH_LEN]u8
	pn[0] = 0x71
	store.config_set_propagation_node(&cfg, pn)
	cfg.try_propagation_on_fail = true

	dest: [store.HASH_LEN]u8
	dest[0] = 0x22
	testing.expect(t, net.session_send_begin(&s, dest, "", "x", &convs, &dir, &cfg, .Opportunistic))
	for _ in 0 ..< 8 {
		if !net.session_send_busy(&s) {
			break
		}
		net.session_send_tick(&s)
	}
	testing.expect(t, !s.send.ok)
	testing.expect(t, !net.session_send_busy(&s))
	testing.expect(t, len(s.send.wire) == 0, "failed failover must not leave a partial wire")
	testing.expect_value(t, s.send.method, lxmf.Method.Opportunistic)
	net.session_send_cancel(&s)
}

@(test)
test_bug_sync_ignores_request_response_before_id :: proc(t: ^testing.T) {
	s: net.Session
	s.started = true
	s.sync.active = true
	s.sync.done = false
	s.sync.phase = .Requesting
	s.sync.has_request_id = false
	s.sync.state = .Link_Established

	ev: rns.Event
	ev.kind = .Request_Response
	handled := net.session_sync_on_event(&s, &ev)
	testing.expect(t, !handled, "must ignore Request_Response before /get request id exists")
	testing.expect(t, s.sync.active)
	testing.expect(t, !s.sync.done)
	testing.expect_value(t, s.sync.phase, net.Sync_Phase.Requesting)
}

@(test)
test_bug_config_load_propagated_capitalized :: proc(t: ^testing.T) {
	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	// Simulate config_apply path: values are not lowercased by the loader.
	cfg.send_method = lxmf.parse_send_method("Propagated")
	testing.expect_value(t, cfg.send_method, lxmf.Method.Propagated)
}
