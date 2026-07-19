// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Test oracles: expected wire and config shapes for prop delivery.
*/

package tests

import "core:testing"

import "ren:lxmf"
import "ren:store"

@(test)
test_oracle_send_method_labels :: proc(t: ^testing.T) {
	// NomadNet-facing labels shown in Compose.
	testing.expect_value(t, lxmf.method_label(.Direct), "Direct")
	testing.expect_value(t, lxmf.method_label(.Opportunistic), "Opportunistic")
	testing.expect_value(t, lxmf.method_label(.Propagated), "Propagate")
}

@(test)
test_oracle_config_keys_written :: proc(t: ^testing.T) {
	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	pn: [store.HASH_LEN]u8
	pn[0] = 0xff
	store.config_set_propagation_node(&cfg, pn)
	cfg.send_method = .Propagated
	cfg.try_propagation_on_fail = true

	testing.expect_value(t, lxmf.send_method_config_value(cfg.send_method), "propagated")
	hex := store.hash_hex(cfg.propagation_node, context.temp_allocator)
	testing.expect_value(t, len(hex), 32)
	testing.expect(t, cfg.has_propagation_node)
}

@(test)
test_oracle_propagation_wrap_msgpack_header :: proc(t: ^testing.T) {
	packed := make([]u8, lxmf.HASH_LEN + 4)
	defer delete(packed)
	enc := []u8{0x10, 0x20}
	wrap := lxmf.pack_propagation_payload(packed, enc)
	defer delete(wrap)
	// msgpack fixarray 2
	testing.expect_value(t, wrap[0], u8(0x92))
}

@(test)
test_oracle_opportunistic_strip_preserves_tail :: proc(t: ^testing.T) {
	packed := make([]u8, lxmf.HASH_LEN + 3)
	defer delete(packed)
	packed[lxmf.HASH_LEN] = 0xaa
	packed[lxmf.HASH_LEN + 1] = 0xbb
	packed[lxmf.HASH_LEN + 2] = 0xcc
	tail := lxmf.opportunistic_plaintext(packed)
	testing.expect_value(t, len(tail), 3)
	testing.expect_value(t, tail[0], u8(0xaa))
	testing.expect_value(t, tail[2], u8(0xcc))
}
