// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Pack and parse LXMF announce app-data.
*/

package lxmf

import "core:bytes"
import "core:strings"

announce_app_data :: proc(display_name: string, stamp_cost: Maybe(i64), allocator := context.allocator) -> []u8 {
	w: Writer
	writer_init(&w)
	defer writer_destroy(&w)
	write_array_header(&w, 2)
	if display_name == "" {
		write_nil(&w)
	} else {
		write_bin(&w, transmute([]u8)display_name)
	}
	if cost, ok := stamp_cost.?; ok {
		write_int(&w, cost)
	} else {
		write_nil(&w)
	}
	return bytes.clone(writer_bytes(&w), allocator)
}

parse_announce_display_name :: proc(app_data: []u8, allocator := context.allocator) -> (string, bool) {
	if len(app_data) == 0 {
		return "", false
	}
	first := app_data[0]
	if (first >= 0x90 && first <= 0x9f) || first == 0xdc {
		r: Reader
		reader_init(&r, app_data)
		v, err := decode_value(&r)
		if err != .None || v.kind != .Array || len(v.array) < 1 {
			value_destroy(&v)
			return "", false
		}
		defer value_destroy(&v)
		b, ok := as_bytes(v.array[0])
		if !ok || b == nil {
			return "", false
		}
		return strings.clone(string(b), allocator), true
	}
	return strings.clone(string(app_data), allocator), true
}

parse_announce_stamp_cost :: proc(app_data: []u8) -> (i64, bool) {
	if len(app_data) == 0 {
		return 0, false
	}
	first := app_data[0]
	if !((first >= 0x90 && first <= 0x9f) || first == 0xdc) {
		return 0, false
	}
	r: Reader
	reader_init(&r, app_data)
	v, err := decode_value(&r)
	if err != .None || v.kind != .Array || len(v.array) < 2 {
		value_destroy(&v)
		return 0, false
	}
	defer value_destroy(&v)
	return as_int(v.array[1])
}
