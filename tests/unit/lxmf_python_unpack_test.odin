// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Cross-codec: unpack Python LXMF packed bytes in Odin.
Fixtures are hex files from tests/interop/python_lxmf_interop.py.
*/

package tests

import "core:testing"

import "ren:lxmf"

PY_OPP_FULL_HEX :: #load("../interop/fixtures/py_opp_full.hex")
PY_OPP_WIRE_HEX :: #load("../interop/fixtures/py_opp_wire.hex")
PY_DIRECT_FULL_HEX :: #load("../interop/fixtures/py_direct_full.hex")
PY_DELIVERY_HEX :: #load("../interop/fixtures/py_delivery.hex")

@(private)
fixture_hex_bytes :: proc(hex_src: string, allocator := context.temp_allocator) -> []u8 {
	hex := transmute([]u8)hex_src
	out := make([dynamic]u8, 0, len(hex) / 2, allocator)
	for i := 0; i + 1 < len(hex); i += 2 {
		for i < len(hex) && (hex[i] == '\n' || hex[i] == '\r' || hex[i] == ' ') {
			i += 1
		}
		if i + 1 >= len(hex) {
			break
		}
		hi := hex_nibble(hex[i])
		lo := hex_nibble(hex[i + 1])
		append(&out, (hi << 4) | lo)
	}
	return out[:]
}

@(private)
fixture_delivery_hash :: proc() -> [lxmf.HASH_LEN]u8 {
	out: [lxmf.HASH_LEN]u8
	b := fixture_hex_bytes(string(PY_DELIVERY_HEX))
	n := min(len(b), lxmf.HASH_LEN)
	copy(out[:n], b[:n])
	return out
}

@(private)
hex_nibble :: proc(c: u8) -> u8 {
	switch c {
	case '0' ..= '9':
		return c - '0'
	case 'a' ..= 'f':
		return c - 'a' + 10
	case 'A' ..= 'F':
		return c - 'A' + 10
	}
	return 0
}

@(test)
test_unpack_python_opportunistic_fixture :: proc(t: ^testing.T) {
	full := fixture_hex_bytes(string(PY_OPP_FULL_HEX))
	testing.expect(t, len(full) > lxmf.HASH_LEN * 2 + lxmf.SIGNATURE_LEN)
	out, ok := lxmf.message_unpack(full, .Opportunistic)
	testing.expect(t, ok)
	if !ok {
		return
	}
	defer lxmf.message_destroy(&out)
	testing.expect_value(t, out.content, "ping-body")
	testing.expect_value(t, out.title, "t")
}

@(test)
test_unpack_python_opportunistic_wire_rebuild :: proc(t: ^testing.T) {
	wire := fixture_hex_bytes(string(PY_OPP_WIRE_HEX))
	dest := fixture_delivery_hash()
	testing.expect(t, dest != [lxmf.HASH_LEN]u8{})

	out, ok := lxmf.message_unpack_opportunistic(dest, wire)
	testing.expect(t, ok)
	if !ok {
		return
	}
	defer lxmf.message_destroy(&out)
	testing.expect_value(t, out.content, "ping-body")
	testing.expect(t, out.destination_hash == dest)
}

@(test)
test_unpack_python_opportunistic_already_full :: proc(t: ^testing.T) {
	full := fixture_hex_bytes(string(PY_OPP_FULL_HEX))
	dest := fixture_delivery_hash()
	out, ok := lxmf.message_unpack_opportunistic(dest, full)
	testing.expect(t, ok)
	if !ok {
		return
	}
	defer lxmf.message_destroy(&out)
	testing.expect_value(t, out.content, "ping-body")
}

@(test)
test_unpack_python_direct_fixture :: proc(t: ^testing.T) {
	full := fixture_hex_bytes(string(PY_DIRECT_FULL_HEX))
	testing.expect(t, len(full) > lxmf.HASH_LEN * 2 + lxmf.SIGNATURE_LEN)
	out, ok := lxmf.message_unpack_link_data(full)
	testing.expect(t, ok)
	if !ok {
		return
	}
	defer lxmf.message_destroy(&out)
	testing.expect_value(t, out.content, "direct-ping")
	testing.expect_value(t, out.title, "t")
}

@(test)
test_opportunistic_candidates_order :: proc(t: ^testing.T) {
	dest: [lxmf.HASH_LEN]u8
	dest[0] = 0xaa
	plain := []u8{1, 2, 3}
	cands := lxmf.opportunistic_candidates(dest, plain)
	testing.expect_value(t, len(cands[0]), lxmf.HASH_LEN + 3)
	testing.expect_value(t, cands[0][0], u8(0xaa))
	testing.expect_value(t, len(cands[1]), 3)
}
