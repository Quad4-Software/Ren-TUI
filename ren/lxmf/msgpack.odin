// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Small msgpack codec for LXMF wire and on-disk storage.
*/

package lxmf

import "core:bytes"

Msgpack_Error :: enum {
	None,
	Truncate,
	Type,
	Depth,
	Size,
}

Writer :: struct {
	buf: [dynamic]u8,
}

writer_init :: proc(w: ^Writer, allocator := context.allocator) {
	w.buf = make([dynamic]u8, 0, 64, allocator)
}

writer_destroy :: proc(w: ^Writer) {
	delete(w.buf)
	w^ = {}
}

writer_bytes :: proc(w: ^Writer) -> []u8 {
	return w.buf[:]
}

write_nil :: proc(w: ^Writer) {
	append(&w.buf, 0xc0)
}

write_bool :: proc(w: ^Writer, v: bool) {
	append(&w.buf, 0xc3 if v else 0xc2)
}

write_uint :: proc(w: ^Writer, v: u64) {
	switch {
	case v <= 0x7f:
		append(&w.buf, u8(v))
	case v <= 0xff:
		append(&w.buf, 0xcc, u8(v))
	case v <= 0xffff:
		append(&w.buf, 0xcd, u8(v >> 8), u8(v))
	case v <= 0xffff_ffff:
		append(&w.buf, 0xce, u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v))
	case:
		append(
			&w.buf,
			0xcf,
			u8(v >> 56),
			u8(v >> 48),
			u8(v >> 40),
			u8(v >> 32),
			u8(v >> 24),
			u8(v >> 16),
			u8(v >> 8),
			u8(v),
		)
	}
}

write_int :: proc(w: ^Writer, v: i64) {
	if v >= 0 {
		write_uint(w, u64(v))
		return
	}
	switch {
	case v >= -32:
		append(&w.buf, u8(int(v)))
	case v >= -128:
		append(&w.buf, 0xd0, u8(i8(v)))
	case v >= -32768:
		x := i16(v)
		append(&w.buf, 0xd1, u8(u16(x) >> 8), u8(x))
	case v >= -2147483648:
		x := i32(v)
		u := u32(x)
		append(&w.buf, 0xd2, u8(u >> 24), u8(u >> 16), u8(u >> 8), u8(u))
	case:
		u := u64(v)
		append(
			&w.buf,
			0xd3,
			u8(u >> 56),
			u8(u >> 48),
			u8(u >> 40),
			u8(u >> 32),
			u8(u >> 24),
			u8(u >> 16),
			u8(u >> 8),
			u8(u),
		)
	}
}

write_f64 :: proc(w: ^Writer, v: f64) {
	bits := transmute(u64)v
	append(
		&w.buf,
		0xcb,
		u8(bits >> 56),
		u8(bits >> 48),
		u8(bits >> 40),
		u8(bits >> 32),
		u8(bits >> 24),
		u8(bits >> 16),
		u8(bits >> 8),
		u8(bits),
	)
}

write_bin :: proc(w: ^Writer, data: []u8) {
	n := len(data)
	switch {
	case n <= 0xff:
		append(&w.buf, 0xc4, u8(n))
	case n <= 0xffff:
		append(&w.buf, 0xc5, u8(n >> 8), u8(n))
	case:
		append(&w.buf, 0xc6, u8(n >> 24), u8(n >> 16), u8(n >> 8), u8(n))
	}
	append(&w.buf, ..data)
}

write_str :: proc(w: ^Writer, s: string) {
	n := len(s)
	switch {
	case n <= 31:
		append(&w.buf, 0xa0 + u8(n))
	case n <= 0xff:
		append(&w.buf, 0xd9, u8(n))
	case n <= 0xffff:
		append(&w.buf, 0xda, u8(n >> 8), u8(n))
	case:
		append(&w.buf, 0xdb, u8(n >> 24), u8(n >> 16), u8(n >> 8), u8(n))
	}
	append(&w.buf, ..transmute([]u8)s)
}

write_array_header :: proc(w: ^Writer, n: int) {
	switch {
	case n <= 15:
		append(&w.buf, 0x90 + u8(n))
	case n <= 0xffff:
		append(&w.buf, 0xdc, u8(n >> 8), u8(n))
	case:
		append(&w.buf, 0xdd, u8(n >> 24), u8(n >> 16), u8(n >> 8), u8(n))
	}
}

write_map_header :: proc(w: ^Writer, n: int) {
	switch {
	case n <= 15:
		append(&w.buf, 0x80 + u8(n))
	case n <= 0xffff:
		append(&w.buf, 0xde, u8(n >> 8), u8(n))
	case:
		append(&w.buf, 0xdf, u8(n >> 24), u8(n >> 16), u8(n >> 8), u8(n))
	}
}

Value_Kind :: enum {
	Nil,
	Bool,
	Int,
	Uint,
	Float,
	Bin,
	Str,
	Array,
	Map,
}

Value :: struct {
	kind:    Value_Kind,
	b:       bool,
	i:       i64,
	u:       u64,
	f:       f64,
	bin:     []u8,
	str:     string,
	array:   [dynamic]Value,
	entries: [dynamic]Map_Entry,
}

Map_Entry :: struct {
	key:   Value,
	value: Value,
}

Reader :: struct {
	data: []u8,
	pos:  int,
}

reader_init :: proc(r: ^Reader, data: []u8) {
	r.data = data
	r.pos = 0
}

@(private)
need :: proc(r: ^Reader, n: int) -> Msgpack_Error {
	if r.pos + n > len(r.data) {
		return .Truncate
	}
	return .None
}

@(private)
take :: proc(r: ^Reader, n: int) -> ([]u8, Msgpack_Error) {
	if err := need(r, n); err != .None {
		return nil, err
	}
	out := r.data[r.pos:r.pos + n]
	r.pos += n
	return out, .None
}

@(private)
read_u8 :: proc(r: ^Reader) -> (u8, Msgpack_Error) {
	b, err := take(r, 1)
	if err != .None {
		return 0, err
	}
	return b[0], .None
}

@(private)
read_be_u16 :: proc(r: ^Reader) -> (u16, Msgpack_Error) {
	b, err := take(r, 2)
	if err != .None {
		return 0, err
	}
	return u16(b[0]) << 8 | u16(b[1]), .None
}

@(private)
read_be_u32 :: proc(r: ^Reader) -> (u32, Msgpack_Error) {
	b, err := take(r, 4)
	if err != .None {
		return 0, err
	}
	return u32(b[0]) << 24 | u32(b[1]) << 16 | u32(b[2]) << 8 | u32(b[3]), .None
}

@(private)
read_be_u64 :: proc(r: ^Reader) -> (u64, Msgpack_Error) {
	b, err := take(r, 8)
	if err != .None {
		return 0, err
	}
	return (
		u64(b[0]) << 56 |
		u64(b[1]) << 48 |
		u64(b[2]) << 40 |
		u64(b[3]) << 32 |
		u64(b[4]) << 24 |
		u64(b[5]) << 16 |
		u64(b[6]) << 8 |
		u64(b[7])
	), .None
}

value_destroy :: proc(v: ^Value) {
	switch v.kind {
	case .Bin:
		delete(v.bin)
	case .Str:
		delete(v.str)
	case .Array:
		for &item in v.array {
			value_destroy(&item)
		}
		delete(v.array)
	case .Map:
		for &e in v.entries {
			value_destroy(&e.key)
			value_destroy(&e.value)
		}
		delete(v.entries)
	case .Nil, .Bool, .Int, .Uint, .Float:
	}
	v^ = {}
}

MSGPACK_MAX_DEPTH :: 32
MSGPACK_MAX_ITEMS :: 100_000
MSGPACK_MAX_BYTES :: 4 * 1024 * 1024

decode_value :: proc(r: ^Reader, allocator := context.allocator) -> (Value, Msgpack_Error) {
	return decode_value_depth(r, 0, allocator)
}

@(private)
check_blob_len :: proc(n: int) -> Msgpack_Error {
	if n < 0 || n > MSGPACK_MAX_BYTES {
		return .Size
	}
	return .None
}

@(private)
check_collection_len :: proc(n: int) -> Msgpack_Error {
	if n < 0 || n > MSGPACK_MAX_ITEMS {
		return .Size
	}
	return .None
}

@(private)
decode_value_depth :: proc(r: ^Reader, depth: int, allocator := context.allocator) -> (Value, Msgpack_Error) {
	if depth > MSGPACK_MAX_DEPTH {
		return {}, .Depth
	}
	b, err := read_u8(r)
	if err != .None {
		return {}, err
	}

	switch {
	case b <= 0x7f:
		return Value{kind = .Uint, u = u64(b)}, .None
	case b >= 0xe0:
		return Value{kind = .Int, i = i64(i8(b))}, .None
	case b >= 0xa0 && b <= 0xbf:
		n := int(b - 0xa0)
		if e := check_blob_len(n); e != .None {
			return {}, e
		}
		data, e := take(r, n)
		if e != .None {
			return {}, e
		}
		s := string(bytes.clone(data, allocator))
		return Value{kind = .Str, str = s}, .None
	case b >= 0x90 && b <= 0x9f:
		return decode_array(r, int(b - 0x90), depth, allocator)
	case b >= 0x80 && b <= 0x8f:
		return decode_map_n(r, int(b - 0x80), depth, allocator)
	}

	switch b {
	case 0xc0:
		return Value{kind = .Nil}, .None
	case 0xc2:
		return Value{kind = .Bool, b = false}, .None
	case 0xc3:
		return Value{kind = .Bool, b = true}, .None
	case 0xcc:
		v, e := read_u8(r)
		return Value{kind = .Uint, u = u64(v)}, e
	case 0xcd:
		v, e := read_be_u16(r)
		return Value{kind = .Uint, u = u64(v)}, e
	case 0xce:
		v, e := read_be_u32(r)
		return Value{kind = .Uint, u = u64(v)}, e
	case 0xcf:
		v, e := read_be_u64(r)
		return Value{kind = .Uint, u = v}, e
	case 0xd0:
		v, e := read_u8(r)
		return Value{kind = .Int, i = i64(i8(v))}, e
	case 0xd1:
		v, e := read_be_u16(r)
		return Value{kind = .Int, i = i64(i16(v))}, e
	case 0xd2:
		v, e := read_be_u32(r)
		return Value{kind = .Int, i = i64(i32(v))}, e
	case 0xd3:
		v, e := read_be_u64(r)
		return Value{kind = .Int, i = i64(v)}, e
	case 0xcb:
		bits, e := read_be_u64(r)
		if e != .None {
			return {}, e
		}
		return Value{kind = .Float, f = transmute(f64)bits}, .None
	case 0xc4:
		n, e := read_u8(r)
		if e != .None {
			return {}, e
		}
		return decode_bin(r, int(n), allocator)
	case 0xc5:
		n, e := read_be_u16(r)
		if e != .None {
			return {}, e
		}
		return decode_bin(r, int(n), allocator)
	case 0xc6:
		n, e := read_be_u32(r)
		if e != .None {
			return {}, e
		}
		return decode_bin(r, int(n), allocator)
	case 0xd9:
		n, e := read_u8(r)
		if e != .None {
			return {}, e
		}
		return decode_str(r, int(n), allocator)
	case 0xda:
		n, e := read_be_u16(r)
		if e != .None {
			return {}, e
		}
		return decode_str(r, int(n), allocator)
	case 0xdb:
		n, e := read_be_u32(r)
		if e != .None {
			return {}, e
		}
		return decode_str(r, int(n), allocator)
	case 0xdc:
		n, e := read_be_u16(r)
		if e != .None {
			return {}, e
		}
		return decode_array(r, int(n), depth, allocator)
	case 0xdd:
		n, e := read_be_u32(r)
		if e != .None {
			return {}, e
		}
		return decode_array(r, int(n), depth, allocator)
	case 0xde:
		n, e := read_be_u16(r)
		if e != .None {
			return {}, e
		}
		return decode_map_n(r, int(n), depth, allocator)
	case 0xdf:
		n, e := read_be_u32(r)
		if e != .None {
			return {}, e
		}
		return decode_map_n(r, int(n), depth, allocator)
	}

	return {}, .Type
}

@(private)
decode_bin :: proc(r: ^Reader, n: int, allocator := context.allocator) -> (Value, Msgpack_Error) {
	if e := check_blob_len(n); e != .None {
		return {}, e
	}
	data, e2 := take(r, n)
	if e2 != .None {
		return {}, e2
	}
	return Value{kind = .Bin, bin = bytes.clone(data, allocator)}, .None
}

@(private)
decode_str :: proc(r: ^Reader, n: int, allocator := context.allocator) -> (Value, Msgpack_Error) {
	if e := check_blob_len(n); e != .None {
		return {}, e
	}
	data, e2 := take(r, n)
	if e2 != .None {
		return {}, e2
	}
	return Value{kind = .Str, str = string(bytes.clone(data, allocator))}, .None
}

@(private)
decode_array :: proc(r: ^Reader, n: int, depth: int, allocator := context.allocator) -> (Value, Msgpack_Error) {
	if e := check_collection_len(n); e != .None {
		return {}, e
	}
	arr := make([dynamic]Value, 0, n, allocator)
	for _ in 0 ..< n {
		item, err := decode_value_depth(r, depth + 1, allocator)
		if err != .None {
			for &v in arr {
				value_destroy(&v)
			}
			delete(arr)
			return {}, err
		}
		append(&arr, item)
	}
	return Value{kind = .Array, array = arr}, .None
}

@(private)
decode_map_n :: proc(r: ^Reader, n: int, depth: int, allocator := context.allocator) -> (Value, Msgpack_Error) {
	if e := check_collection_len(n); e != .None {
		return {}, e
	}
	m := make([dynamic]Map_Entry, 0, n, allocator)
	for _ in 0 ..< n {
		key, kerr := decode_value_depth(r, depth + 1, allocator)
		if kerr != .None {
			for &e in m {
				value_destroy(&e.key)
				value_destroy(&e.value)
			}
			delete(m)
			return {}, kerr
		}
		val, verr := decode_value_depth(r, depth + 1, allocator)
		if verr != .None {
			value_destroy(&key)
			for &e in m {
				value_destroy(&e.key)
				value_destroy(&e.value)
			}
			delete(m)
			return {}, verr
		}
		append(&m, Map_Entry{key = key, value = val})
	}
	return Value{kind = .Map, entries = m}, .None
}

as_f64 :: proc(v: Value) -> (f64, bool) {
	#partial switch v.kind {
	case .Float:
		return v.f, true
	case .Int:
		return f64(v.i), true
	case .Uint:
		return f64(v.u), true
	}
	return 0, false
}

as_int :: proc(v: Value) -> (i64, bool) {
	#partial switch v.kind {
	case .Int:
		return v.i, true
	case .Uint:
		if v.u > u64(max(i64)) {
			return 0, false
		}
		return i64(v.u), true
	}
	return 0, false
}

as_bytes :: proc(v: Value) -> ([]u8, bool) {
	#partial switch v.kind {
	case .Bin:
		return v.bin, true
	case .Str:
		return transmute([]u8)v.str, true
	case .Nil:
		return nil, true
	}
	return nil, false
}
