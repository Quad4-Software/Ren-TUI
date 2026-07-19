// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Property style roundtrip checks for msgpack and themes.
*/

package tests

import "core:math/rand"
import "core:testing"

import "ren:lxmf"
import "ren:store"
import "ren:ui"

@(test)
test_property_msgpack_array_roundtrip :: proc(t: ^testing.T) {
	rand.reset(0xC01001)
	for _ in 0 ..< 64 {
		n := int(rand.uint32() % 8)
		w: lxmf.Writer
		lxmf.writer_init(&w)
		lxmf.write_array_header(&w, n)
		for i in 0 ..< n {
			lxmf.write_int(&w, i64(i))
		}
		r: lxmf.Reader
		lxmf.reader_init(&r, lxmf.writer_bytes(&w))
		v, err := lxmf.decode_value(&r)
		testing.expect_value(t, err, lxmf.Msgpack_Error.None)
		testing.expect_value(t, v.kind, lxmf.Value_Kind.Array)
		testing.expect_value(t, len(v.array), n)
		lxmf.value_destroy(&v)
		lxmf.writer_destroy(&w)
	}
}

@(test)
test_property_theme_hex_roundtrip :: proc(t: ^testing.T) {
	rand.reset(0xC01002)
	for _ in 0 ..< 128 {
		c := ui.Color{
			r = u8(rand.uint32()),
			g = u8(rand.uint32()),
			b = u8(rand.uint32()),
		}
		hex := ui.format_hex_color(c)
		defer delete(hex)
		got, ok := ui.parse_hex_color(hex)
		testing.expect(t, ok)
		testing.expect_value(t, got.r, c.r)
		testing.expect_value(t, got.g, c.g)
		testing.expect_value(t, got.b, c.b)
	}
}

@(test)
test_property_hash_hex_length_invariant :: proc(t: ^testing.T) {
	rand.reset(0xC01003)
	for _ in 0 ..< 32 {
		h: [store.HASH_LEN]u8
		for i in 0 ..< store.HASH_LEN {
			h[i] = u8(rand.uint32())
		}
		hex := store.hash_hex(h)
		defer delete(hex)
		testing.expect_value(t, len(hex), store.HASH_LEN * 2)
	}
}

@(test)
test_property_delivery_hash_stable :: proc(t: ^testing.T) {
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)
	a := lxmf.delivery_hash(mat.hash[:])
	b := lxmf.delivery_hash(mat.hash[:])
	testing.expect(t, a == b)
}

@(test)
test_property_send_method_roundtrip :: proc(t: ^testing.T) {
	methods := []lxmf.Method{.Direct, .Opportunistic, .Propagated}
	for m in methods {
		got := lxmf.parse_send_method(lxmf.send_method_config_value(m))
		testing.expect_value(t, got, m)
	}
	m := lxmf.Method.Direct
	for _ in 0 ..< 3 {
		m = lxmf.cycle_send_method(m)
	}
	testing.expect_value(t, m, lxmf.Method.Direct)
}

@(test)
test_property_propagation_wrap_invariant :: proc(t: ^testing.T) {
	rand.reset(0xC01004)
	for _ in 0 ..< 32 {
		n := int(lxmf.HASH_LEN + int(rand.uint32() % 48))
		packed := make([]u8, n)
		for i in 0 ..< n {
			packed[i] = u8(rand.uint32())
		}
		enc_n := int(1 + rand.uint32() % 24)
		enc := make([]u8, enc_n)
		for i in 0 ..< enc_n {
			enc[i] = u8(rand.uint32())
		}
		wrap := lxmf.pack_propagation_payload(packed, enc)
		testing.expect(t, wrap != nil)
		testing.expect_value(t, wrap[0], u8(0x92))
		delete(wrap)
		delete(enc)
		delete(packed)
	}
}
