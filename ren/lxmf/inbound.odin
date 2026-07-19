// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Rebuild opportunistic wire bytes the way Python LXMRouter.delivery_packet does.
*/

package lxmf

import "core:bytes"

/*
Python opportunistic packets carry packed[DEST_LEN:]. Receivers prepend
destination.hash before unpack. Some paths may already deliver full packed
bytes so try the rebuilt form first then the raw buffer.
*/
opportunistic_candidates :: proc(
	delivery: [HASH_LEN]u8,
	plain: []u8,
	allocator := context.temp_allocator,
) -> [2][]u8 {
	out: [2][]u8
	if len(plain) == 0 {
		return out
	}
	dh := delivery
	rebuilt := make([]u8, HASH_LEN + len(plain), allocator)
	copy(rebuilt[0:HASH_LEN], dh[:])
	copy(rebuilt[HASH_LEN:], plain)
	out[0] = rebuilt
	out[1] = plain
	return out
}

message_unpack_opportunistic :: proc(
	delivery: [HASH_LEN]u8,
	plain: []u8,
) -> (Message, bool) {
	cands := opportunistic_candidates(delivery, plain)
	for cand in cands {
		if len(cand) == 0 {
			continue
		}
		msg, ok := message_unpack(cand, .Opportunistic)
		if ok {
			return msg, true
		}
	}
	return {}, false
}

message_unpack_link_data :: proc(data: []u8) -> (Message, bool) {
	if len(data) == 0 {
		return {}, false
	}
	msg, ok := message_unpack(data, .Direct)
	if ok {
		return msg, true
	}
	return {}, false
}

destination_hash_matches :: proc(delivery: [HASH_LEN]u8, dest: []u8) -> bool {
	if len(dest) != HASH_LEN {
		return false
	}
	dh := delivery
	return bytes.equal(dest, dh[:])
}
