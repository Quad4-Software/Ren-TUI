// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Random mixed ops to catch panics in core packages.
*/

package tests

import "core:math/rand"
import "core:strings"
import "core:testing"

import "ren:lxmf"
import "ren:micron"
import "ren:store"
import "ren:ui"

CHAOS_ITERS :: 80

Chaos_Op :: enum {
	Msgpack,
	Micron,
	Buffer,
	Theme,
	Caps,
	Identity,
	Hex,
}

@(test)
test_chaos_random_ops_no_panic :: proc(t: ^testing.T) {
	rand.reset(0xC8A05)
	ui.set_theme(ui.FIELD)
	ui.caps_init("256")

	for _ in 0 ..< CHAOS_ITERS {
		op := Chaos_Op(rand.uint32() % 7)
		switch op {
		case .Msgpack:
			n := int(rand.uint32() % 6)
			w: lxmf.Writer
			lxmf.writer_init(&w)
			lxmf.write_array_header(&w, n)
			for i in 0 ..< n {
				lxmf.write_int(&w, i64(i * int(rand.uint32() % 7)))
			}
			r: lxmf.Reader
			lxmf.reader_init(&r, lxmf.writer_bytes(&w))
			v, err := lxmf.decode_value(&r)
			if err == .None {
				lxmf.value_destroy(&v)
			}
			lxmf.writer_destroy(&w)
		case .Micron:
			src_buf := make([]u8, 48)
			n := int(rand.uint32() % u32(len(src_buf)))
			for i in 0 ..< n {
				src_buf[i] = u8(32 + rand.uint32() % 95)
				if rand.uint32() % 10 == 0 {
					src_buf[i] = '\n'
				}
			}
			doc := micron.parse(string(src_buf[:n]))
			micron.doc_destroy(&doc)
			delete(src_buf)
		case .Buffer:
			w := int(8 + rand.uint32() % 40)
			h := int(4 + rand.uint32() % 20)
			buf := ui.buffer_create(w, h)
			ui.buffer_text(&buf, 0, 0, "x", ui.theme().fg, ui.theme().bg)
			ui.buffer_resize(&buf, w + 1, h + 1)
			ui.buffer_destroy(&buf)
		case .Theme:
			names := ui.theme_names()
			name := names[rand.uint32() % u32(len(names))]
			ui.apply_theme_hex(name, {})
		case .Caps:
			modes := []string{"full", "256", "compat", "dumb"}
			ui.caps_init(modes[rand.uint32() % u32(len(modes))])
		case .Identity:
			mat, ok := lxmf.identity_generate()
			testing.expect(t, ok)
			_ = mat.hash
		case .Hex:
			h: [store.HASH_LEN]u8
			for i in 0 ..< store.HASH_LEN {
				h[i] = u8(rand.uint32())
			}
			hex := store.hash_hex(h)
			testing.expect_value(t, len(hex), store.HASH_LEN * 2)
			delete(hex)
		}
	}
	ui.set_theme(ui.FIELD)
	ui.caps_init("full")
}

@(test)
test_chaos_message_pack_random_content :: proc(t: ^testing.T) {
	rand.reset(0xC8A06)
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)
	dest := lxmf.delivery_hash(mat.hash[:])

	for _ in 0 ..< 20 {
		n := int(rand.uint32() % 40)
		body := make([]u8, n)
		for i in 0 ..< n {
			body[i] = u8(32 + rand.uint32() % 95)
		}
		msg: lxmf.Message
		lxmf.message_init(&msg)
		msg.destination_hash = dest
		msg.title = strings.clone("")
		msg.content = strings.clone(string(body))
		delete(body)
		testing.expect(t, lxmf.message_pack(&msg, &mat))
		out, uok := lxmf.message_unpack(msg.packed)
		testing.expect(t, uok)
		testing.expect(t, len(out.content) == n)
		lxmf.message_destroy(&out)
		lxmf.message_destroy(&msg)
	}
}

@(test)
test_chaos_nested_msgpack_depth_limit :: proc(t: ^testing.T) {
	// Build deeper nesting than MSGPACK_MAX_DEPTH via nested fixarrays of 1
	depth := lxmf.MSGPACK_MAX_DEPTH + 4
	buf := make([dynamic]u8, 0, depth)
	defer delete(buf)
	for _ in 0 ..< depth {
		append(&buf, 0x91) // array of 1
	}
	append(&buf, 0xc0) // nil leaf
	r: lxmf.Reader
	lxmf.reader_init(&r, buf[:])
	_, err := lxmf.decode_value(&r)
	testing.expect_value(t, err, lxmf.Msgpack_Error.Depth)
}
