// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Unit tests for msgpack identity and LXMF messages.
*/

package tests

import "core:crypto"
import "core:strings"
import "core:testing"

import "ren:lxmf"

@(test)
test_msgpack_roundtrip_array :: proc(t: ^testing.T) {
	w: lxmf.Writer
	lxmf.writer_init(&w)
	defer lxmf.writer_destroy(&w)
	lxmf.write_array_header(&w, 3)
	lxmf.write_f64(&w, 1.5)
	lxmf.write_bin(&w, transmute([]u8)string("hi"))
	lxmf.write_nil(&w)

	r: lxmf.Reader
	lxmf.reader_init(&r, lxmf.writer_bytes(&w))
	v, err := lxmf.decode_value(&r)
	testing.expect_value(t, err, lxmf.Msgpack_Error.None)
	testing.expect_value(t, v.kind, lxmf.Value_Kind.Array)
	testing.expect_value(t, len(v.array), 3)
	lxmf.value_destroy(&v)
}

@(test)
test_message_pack_unpack :: proc(t: ^testing.T) {
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)

	h := mat.hash
	dest := lxmf.delivery_hash(h[:])
	msg: lxmf.Message
	lxmf.message_init(&msg)
	defer lxmf.message_destroy(&msg)
	msg.destination_hash = dest
	msg.title = strings.clone("hello")
	msg.content = strings.clone("from ren")
	testing.expect(t, lxmf.message_pack(&msg, &mat))
	testing.expect(t, len(msg.packed) > 96)

	out, uok := lxmf.message_unpack(msg.packed)
	testing.expect(t, uok)
	defer lxmf.message_destroy(&out)
	testing.expect_value(t, out.title, "hello")
	testing.expect_value(t, out.content, "from ren")
	testing.expect(t, lxmf.message_verify(&out, mat.sign_pub[:]))
}

@(test)
test_announce_app_data :: proc(t: ^testing.T) {
	data := lxmf.announce_app_data("Ren", 8)
	defer delete(data)
	name, nok := lxmf.parse_announce_display_name(data)
	testing.expect(t, nok)
	defer delete(name)
	testing.expect_value(t, name, "Ren")
	cost, cok := lxmf.parse_announce_stamp_cost(data)
	testing.expect(t, cok)
	testing.expect_value(t, cost, i64(8))
}

@(test)
test_stamp_roundtrip_low_cost :: proc(t: ^testing.T) {
	id: [lxmf.MESSAGE_ID_LEN]u8
	crypto.rand_bytes(id[:])
	// Use tiny expand rounds for speed while proving PoW path
	rounds := 4
	cost := 8
	wb := lxmf.stamp_workblock(id[:], rounds)
	defer delete(wb)
	testing.expect_value(t, len(wb), rounds * lxmf.WORKBLOCK_CHUNK)

	stamp, value, ok := lxmf.generate_stamp(id[:], cost, rounds)
	testing.expect(t, ok)
	defer delete(stamp)
	testing.expect(t, lxmf.stamp_valid(stamp, cost, wb))
	testing.expect(t, value >= 0)
}

@(test)
test_ticket_stamp :: proc(t: ^testing.T) {
	ticket: [lxmf.TICKET_LENGTH]u8
	mid: [lxmf.MESSAGE_ID_LEN]u8
	crypto.rand_bytes(ticket[:])
	crypto.rand_bytes(mid[:])
	stamp := lxmf.ticket_stamp(ticket[:], mid[:])
	defer delete(stamp)
	testing.expect_value(t, len(stamp), lxmf.TICKET_LENGTH)
	testing.expect(t, lxmf.ticket_stamp_matches(stamp, ticket[:], mid[:]))
	ok, value := lxmf.validate_message_stamp(stamp, mid[:], 8, {ticket[:]})
	testing.expect(t, ok)
	testing.expect_value(t, value, lxmf.COST_TICKET)
}

@(test)
test_classify_announce_hashes :: proc(t: ^testing.T) {
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)
	h := mat.hash
	delivery := lxmf.delivery_hash(h[:])
	node := lxmf.nomad_node_hash(h[:])
	prop := lxmf.propagation_hash(h[:])
	testing.expect(t, delivery != node)
	testing.expect(t, delivery != prop)
	dh := delivery
	nh := node
	ph := prop
	testing.expect_value(t, lxmf.classify_announce(dh[:], h[:]), lxmf.Announce_Kind.Lxmf_Delivery)
	testing.expect_value(t, lxmf.classify_announce(nh[:], h[:]), lxmf.Announce_Kind.Nomad_Node)
	testing.expect_value(t, lxmf.classify_announce(ph[:], h[:]), lxmf.Announce_Kind.Lxmf_Propagation)
}

@(test)
test_message_with_stamp_cost :: proc(t: ^testing.T) {
	mat, ok := lxmf.identity_generate()
	testing.expect(t, ok)
	h := mat.hash
	dest := lxmf.delivery_hash(h[:])
	msg: lxmf.Message
	lxmf.message_init(&msg)
	defer lxmf.message_destroy(&msg)
	msg.destination_hash = dest
	msg.title = strings.clone("")
	msg.content = strings.clone("stamped")
	// stamp generation with full 3000 rounds is slow at high cost
	// use generate via message_pack with cost 0 here and attach manually
	testing.expect(t, lxmf.message_pack(&msg, &mat, 0))
	testing.expect_value(t, len(msg.stamp), 0)

	stamp, _, sok := lxmf.generate_stamp(msg.message_id[:], 6, 8)
	testing.expect(t, sok)
	defer delete(stamp)

	msg2: lxmf.Message
	lxmf.message_init(&msg2)
	defer lxmf.message_destroy(&msg2)
	msg2.destination_hash = dest
	msg2.title = strings.clone("")
	msg2.content = strings.clone("stamped")
	msg2.stamp = make([]u8, len(stamp))
	copy(msg2.stamp, stamp)
	testing.expect(t, lxmf.message_pack(&msg2, &mat, 0))
	testing.expect(t, len(msg2.stamp) > 0)

	out, uok := lxmf.message_unpack(msg2.packed)
	testing.expect(t, uok)
	defer lxmf.message_destroy(&out)
	testing.expect(t, len(out.stamp) > 0)
}
