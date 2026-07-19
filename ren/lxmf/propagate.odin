// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Propagation wrap for LXMF PROPAGATED delivery.
Python packs msgpack [time, [dest_hash + encrypt(packed[DEST:])]].
*/

package lxmf

import "core:bytes"
import "core:strings"
import "core:time"

// Build the payload sent over a link to a propagation node.
pack_propagation_payload :: proc(packed: []u8, encrypted_tail: []u8, allocator := context.allocator) -> []u8 {
	if len(packed) < HASH_LEN || len(encrypted_tail) == 0 {
		return nil
	}
	lxmf_data := make([]u8, HASH_LEN + len(encrypted_tail), context.temp_allocator)
	copy(lxmf_data[:HASH_LEN], packed[:HASH_LEN])
	copy(lxmf_data[HASH_LEN:], encrypted_tail)

	w: Writer
	writer_init(&w, context.temp_allocator)
	write_array_header(&w, 2)
	write_f64(&w, f64(time.time_to_unix_nano(time.now())) / 1_000_000_000.0)
	write_array_header(&w, 1)
	write_bin(&w, lxmf_data)
	return bytes.clone(writer_bytes(&w), allocator)
}

// Bytes after the destination hash, for opportunistic packet send.
opportunistic_plaintext :: proc(packed: []u8) -> []u8 {
	if len(packed) <= HASH_LEN {
		return nil
	}
	return packed[HASH_LEN:]
}

method_label :: proc(m: Method) -> string {
	switch m {
	case .Opportunistic:
		return "Opportunistic"
	case .Direct:
		return "Direct"
	case .Propagated:
		return "Propagate"
	case .Paper:
		return "Paper"
	case .Unknown:
		return "Unknown"
	}
	return "Unknown"
}

cycle_send_method :: proc(m: Method) -> Method {
	switch m {
	case .Direct:
		return .Opportunistic
	case .Opportunistic:
		return .Propagated
	case .Propagated, .Paper, .Unknown:
		return .Direct
	}
	return .Direct
}

parse_send_method :: proc(val: string) -> Method {
	v := strings.to_lower(strings.trim_space(val), context.temp_allocator)
	switch v {
	case "opportunistic", "opp", "1":
		return .Opportunistic
	case "propagated", "propagate", "prop", "3":
		return .Propagated
	case "direct", "2", "":
		return .Direct
	}
	return .Direct
}

send_method_config_value :: proc(m: Method) -> string {
	switch m {
	case .Opportunistic:
		return "opportunistic"
	case .Propagated:
		return "propagated"
	case .Direct, .Paper, .Unknown:
		return "direct"
	}
	return "direct"
}
