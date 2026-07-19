// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Bit flip and field corruption checks on packed messages.
*/

package tests

import "core:strings"
import "core:testing"

import "ren:lxmf"
import "ren:micron"

@(test)
test_mutation_packed_message_byte_flips :: proc(t: ^testing.T) {
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)
	dest := lxmf.delivery_hash(mat.hash[:])

	msg: lxmf.Message
	lxmf.message_init(&msg)
	defer lxmf.message_destroy(&msg)
	msg.destination_hash = dest
	msg.title = strings.clone("")
	msg.content = strings.clone("mutate-me")
	testing.expect(t, lxmf.message_pack(&msg, &mat))

	orig := make([]u8, len(msg.packed))
	defer delete(orig)
	copy(orig, msg.packed)

	rejected := 0
	// Flip bytes in signature and payload regions (skip first hash which is dest)
	start := lxmf.HASH_LEN
	step := max(1, (len(orig) - start) / 24)
	for i := start; i < len(orig); i += step {
		mut := make([]u8, len(orig))
		copy(mut, orig)
		mut[i] ~= 0xff
		out, uok := lxmf.message_unpack(mut)
		if !uok {
			rejected += 1
			delete(mut)
			continue
		}
		if !lxmf.message_verify(&out, mat.sign_pub[:]) {
			rejected += 1
		}
		lxmf.message_destroy(&out)
		delete(mut)
	}
	testing.expect(t, rejected > 0)
}

@(test)
test_mutation_msgpack_truncated_and_bad_type :: proc(t: ^testing.T) {
	r: lxmf.Reader
	lxmf.reader_init(&r, []u8{0x93, 0x01}) // array of 3, only one element present
	_, err := lxmf.decode_value(&r)
	testing.expect(t, err != .None)

	r2: lxmf.Reader
	lxmf.reader_init(&r2, []u8{0xc1}) // never used / reserved
	_, err2 := lxmf.decode_value(&r2)
	testing.expect_value(t, err2, lxmf.Msgpack_Error.Type)
}

@(test)
test_mutation_micron_garbage_still_lines :: proc(t: ^testing.T) {
	src := "#!\n````\n- \n\x00\xff not utf8-ish but bytes as string"
	doc := micron.parse(src)
	defer micron.doc_destroy(&doc)
	testing.expect(t, len(doc.lines) >= 1)
}

@(test)
test_mutation_identity_blob_wrong_size :: proc(t: ^testing.T) {
	_, ok := lxmf.identity_from_blob([]u8{1, 2, 3})
	testing.expect(t, !ok)
	blob: [64]u8
	mat, ok2 := lxmf.identity_from_blob(blob[:])
	testing.expect(t, ok2)
	testing.expect(t, mat.loaded)
}
