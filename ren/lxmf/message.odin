// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
LXMF message pack unpack sign and verify.
*/

package lxmf

import "core:bytes"
import "core:strings"
import "core:time"

Message :: struct {
	destination_hash: [HASH_LEN]u8,
	source_hash:      [HASH_LEN]u8,
	signature:        [SIGNATURE_LEN]u8,
	message_id:       [MESSAGE_ID_LEN]u8,
	timestamp:        f64,
	title:            string,
	content:          string,
	fields:           map[i64]Value,
	stamp:            []u8,
	method:           Method,
	state:            State,
	packed:           []u8,
	signature_ok:     bool,
	unverified:       Unverified_Reason,
	incoming:         bool,
}

message_init :: proc(m: ^Message) {
	m^ = {}
	m.fields = make(map[i64]Value)
	m.method = .Direct
	m.state = .Draft
}

message_destroy :: proc(m: ^Message) {
	delete(m.title)
	delete(m.content)
	for _, v in m.fields {
		vv := v
		value_destroy(&vv)
	}
	delete(m.fields)
	delete(m.stamp)
	delete(m.packed)
	m^ = {}
}

@(private)
encode_fields :: proc(w: ^Writer, fields: map[i64]Value) {
	keys := make([dynamic]i64, 0, len(fields), context.temp_allocator)
	for k in fields {
		append(&keys, k)
	}
	// Canonical key order so pack/unpack/verify hashes match
	for i in 0 ..< len(keys) {
		for j in i + 1 ..< len(keys) {
			if keys[j] < keys[i] {
				keys[i], keys[j] = keys[j], keys[i]
			}
		}
	}
	write_map_header(w, len(keys))
	for k in keys {
		write_int(w, k)
		encode_value(w, fields[k])
	}
}

@(private)
encode_value :: proc(w: ^Writer, v: Value) {
	switch v.kind {
	case .Nil:
		write_nil(w)
	case .Bool:
		write_bool(w, v.b)
	case .Int:
		write_int(w, v.i)
	case .Uint:
		write_uint(w, v.u)
	case .Float:
		write_f64(w, v.f)
	case .Bin:
		write_bin(w, v.bin)
	case .Str:
		write_str(w, v.str)
	case .Array:
		write_array_header(w, len(v.array))
		for item in v.array {
			encode_value(w, item)
		}
	case .Map:
		write_map_header(w, len(v.entries))
		for e in v.entries {
			encode_value(w, e.key)
			encode_value(w, e.value)
		}
	}
}

@(private)
pack_payload_core :: proc(m: ^Message, include_stamp: bool) -> []u8 {
	w: Writer
	writer_init(&w)
	defer writer_destroy(&w)

	n := 4
	if include_stamp && len(m.stamp) > 0 {
		n = 5
	}
	write_array_header(&w, n)
	write_f64(&w, m.timestamp)
	write_bin(&w, transmute([]u8)m.title)
	write_bin(&w, transmute([]u8)m.content)
	encode_fields(&w, m.fields)
	if n == 5 {
		write_bin(&w, m.stamp)
	}
	return bytes.clone(writer_bytes(&w))
}

message_pack :: proc(m: ^Message, material: ^Identity_Material, stamp_cost: int = 0, ticket: []u8 = nil) -> bool {
	if m.timestamp == 0 {
		m.timestamp = f64(time.time_to_unix_nano(time.now())) / 1_000_000_000.0
	}
	// LXMF source_hash is the sender lxmf.delivery destination hash, not identity hash
	dh := delivery_hash(material.hash[:])
	copy(m.source_hash[:], dh[:])

	payload_no_stamp := pack_payload_core(m, false)
	defer delete(payload_no_stamp)

	hashed := make([]u8, HASH_LEN + HASH_LEN + len(payload_no_stamp))
	defer delete(hashed)
	copy(hashed[0:HASH_LEN], m.destination_hash[:])
	copy(hashed[HASH_LEN:HASH_LEN * 2], m.source_hash[:])
	copy(hashed[HASH_LEN * 2:], payload_no_stamp)

	m.message_id = full_hash(hashed)

	if stamp_cost > 0 && len(m.stamp) == 0 {
		if len(ticket) == TICKET_LENGTH {
			delete(m.stamp)
			m.stamp = ticket_stamp(ticket, m.message_id[:])
		} else {
			stamp, _, ok := generate_stamp(m.message_id[:], stamp_cost)
			if !ok {
				return false
			}
			delete(m.stamp)
			m.stamp = stamp
		}
	}

	signed := make([]u8, len(hashed) + MESSAGE_ID_LEN)
	defer delete(signed)
	copy(signed, hashed)
	copy(signed[len(hashed):], m.message_id[:])

	sig, ok := identity_sign(material, signed)
	if !ok {
		return false
	}
	m.signature = sig
	m.signature_ok = true

	payload := pack_payload_core(m, true)
	defer delete(payload)

	out := make([]u8, HASH_LEN + HASH_LEN + SIGNATURE_LEN + len(payload))
	copy(out[0:HASH_LEN], m.destination_hash[:])
	copy(out[HASH_LEN:HASH_LEN * 2], m.source_hash[:])
	copy(out[HASH_LEN * 2:HASH_LEN * 2 + SIGNATURE_LEN], m.signature[:])
	copy(out[HASH_LEN * 2 + SIGNATURE_LEN:], payload)

	delete(m.packed)
	m.packed = out
	m.state = .Outbound
	return true
}

message_unpack :: proc(data: []u8, method: Method = .Direct) -> (Message, bool) {
	min_len := HASH_LEN * 2 + SIGNATURE_LEN + 1
	if len(data) < min_len {
		return {}, false
	}

	m: Message
	message_init(&m)
	m.incoming = true
	m.method = method
	m.state = .Incoming
	m.packed = bytes.clone(data)

	copy(m.destination_hash[:], data[0:HASH_LEN])
	copy(m.source_hash[:], data[HASH_LEN:HASH_LEN * 2])
	copy(m.signature[:], data[HASH_LEN * 2:HASH_LEN * 2 + SIGNATURE_LEN])
	packed_payload := data[HASH_LEN * 2 + SIGNATURE_LEN:]

	r: Reader
	reader_init(&r, packed_payload)
	payload, err := decode_value(&r, context.allocator)
	if err != .None || payload.kind != .Array || len(payload.array) < 4 {
		message_destroy(&m)
		return {}, false
	}
	defer value_destroy(&payload)

	ts, ts_ok := as_f64(payload.array[0])
	if !ts_ok {
		message_destroy(&m)
		return {}, false
	}
	m.timestamp = ts

	title_b, t_ok := as_bytes(payload.array[1])
	content_b, c_ok := as_bytes(payload.array[2])
	if !t_ok || !c_ok {
		message_destroy(&m)
		return {}, false
	}
	m.title = string(bytes.clone(title_b))
	m.content = string(bytes.clone(content_b))

	if payload.array[3].kind == .Map {
		for e in payload.array[3].entries {
			key, key_ok := as_int(e.key)
			if !key_ok {
				continue
			}
			cloned := clone_value(e.value)
			if old, exists := m.fields[key]; exists {
				old_v := old
				value_destroy(&old_v)
			}
			m.fields[key] = cloned
		}
	}

	if len(payload.array) > 4 {
		stamp_b, s_ok := as_bytes(payload.array[4])
		if s_ok && stamp_b != nil {
			m.stamp = bytes.clone(stamp_b)
		}
	}

	if r.pos != len(packed_payload) {
		message_destroy(&m)
		return {}, false
	}

	payload_core := pack_payload_from_parts(m.timestamp, m.title, m.content, m.fields)
	defer delete(payload_core)

	hashed := make([]u8, HASH_LEN + HASH_LEN + len(payload_core))
	defer delete(hashed)
	copy(hashed[0:HASH_LEN], m.destination_hash[:])
	copy(hashed[HASH_LEN:HASH_LEN * 2], m.source_hash[:])
	copy(hashed[HASH_LEN * 2:], payload_core)
	m.message_id = full_hash(hashed)
	m.unverified = .Source_Unknown
	m.signature_ok = false

	return m, true
}

// Allow store when no key is known. Reject only when sign_pub is present and verify fails.
message_accept_inbound_signature :: proc(m: ^Message, sign_pub: []u8) -> bool {
	if len(sign_pub) == 0 {
		return true
	}
	return message_verify(m, sign_pub)
}

message_verify :: proc(m: ^Message, sign_pub: []u8) -> bool {
	payload_core := pack_payload_from_parts(m.timestamp, m.title, m.content, m.fields)
	defer delete(payload_core)

	hashed := make([]u8, HASH_LEN + HASH_LEN + len(payload_core))
	defer delete(hashed)
	copy(hashed[0:HASH_LEN], m.destination_hash[:])
	copy(hashed[HASH_LEN:HASH_LEN * 2], m.source_hash[:])
	copy(hashed[HASH_LEN * 2:], payload_core)

	signed := make([]u8, len(hashed) + MESSAGE_ID_LEN)
	defer delete(signed)
	copy(signed, hashed)
	copy(signed[len(hashed):], m.message_id[:])

	if identity_verify(sign_pub, signed, m.signature[:]) {
		m.signature_ok = true
		m.unverified = .None
		return true
	}
	m.signature_ok = false
	m.unverified = .Signature_Invalid
	return false
}

@(private)
pack_payload_from_parts :: proc(ts: f64, title, content: string, fields: map[i64]Value) -> []u8 {
	tmp: Message
	tmp.timestamp = ts
	tmp.title = title
	tmp.content = content
	tmp.fields = fields
	return pack_payload_core(&tmp, false)
}

@(private)
clone_value :: proc(v: Value, allocator := context.allocator) -> Value {
	out := v
	switch v.kind {
	case .Bin:
		out.bin = bytes.clone(v.bin, allocator)
	case .Str:
		out.str = strings.clone(v.str, allocator)
	case .Array:
		out.array = make([dynamic]Value, 0, len(v.array), allocator)
		for item in v.array {
			append(&out.array, clone_value(item, allocator))
		}
	case .Map:
		out.entries = make([dynamic]Map_Entry, 0, len(v.entries), allocator)
		for e in v.entries {
			append(&out.entries, Map_Entry{key = clone_value(e.key, allocator), value = clone_value(e.value, allocator)})
		}
	case .Nil, .Bool, .Int, .Uint, .Float:
	}
	return out
}
