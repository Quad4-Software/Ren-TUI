// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Fuzz style random byte decoding for msgpack and micron.
*/

package tests

import "core:math/rand"
import "core:testing"

import "ren:lxmf"
import "ren:micron"

FUZZ_ITERS :: 256

@(test)
test_fuzz_msgpack_random_bytes_no_panic :: proc(t: ^testing.T) {
	rand.reset(0xF02201)
	buf := make([]u8, 64)
	defer delete(buf)
	for _ in 0 ..< FUZZ_ITERS {
		n := int(rand.uint32() % u32(len(buf))) + 1
		for i in 0 ..< n {
			buf[i] = u8(rand.uint32())
		}
		r: lxmf.Reader
		lxmf.reader_init(&r, buf[:n])
		v, err := lxmf.decode_value(&r)
		if err == .None {
			lxmf.value_destroy(&v)
		}
	}
}

@(test)
test_fuzz_msgpack_rejects_huge_array_header :: proc(t: ^testing.T) {
	// array32 with length past MSGPACK_MAX_ITEMS
	data := []u8{0xdd, 0xff, 0xff, 0xff, 0xff}
	r: lxmf.Reader
	lxmf.reader_init(&r, data)
	_, err := lxmf.decode_value(&r)
	testing.expect_value(t, err, lxmf.Msgpack_Error.Size)
}

@(test)
test_fuzz_micron_random_text_no_panic :: proc(t: ^testing.T) {
	rand.reset(0xF02202)
	src := make([]u8, 128)
	defer delete(src)
	for _ in 0 ..< FUZZ_ITERS {
		n := int(rand.uint32() % u32(len(src)))
		for i in 0 ..< n {
			ch := u8(rand.uint32() % 96) + 32
			if rand.uint32() % 16 == 0 {
				ch = '\n'
			}
			src[i] = ch
		}
		doc := micron.parse(string(src[:n]))
		micron.doc_destroy(&doc)
	}
}
