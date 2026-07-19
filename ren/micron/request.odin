// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
NomadNet link request var_/field_ payload encoding.
*/

package micron

import "core:strings"

import "ren:lxmf"

Request_Pair :: struct {
	key:   string,
	value: string,
}

Request_Data :: struct {
	vars:   [dynamic]Request_Pair,
	fields: [dynamic]Request_Pair,
}

request_data_init :: proc(r: ^Request_Data, allocator := context.allocator) {
	r.vars = make([dynamic]Request_Pair, allocator)
	r.fields = make([dynamic]Request_Pair, allocator)
}

request_data_destroy :: proc(r: ^Request_Data) {
	if r == nil {
		return
	}
	for p in r.vars {
		delete(p.key)
		delete(p.value)
	}
	for p in r.fields {
		delete(p.key)
		delete(p.value)
	}
	delete(r.vars)
	delete(r.fields)
	r^ = {}
}

request_data_empty :: proc(r: Request_Data) -> bool {
	return len(r.vars) == 0 && len(r.fields) == 0
}

request_data_clone :: proc(src: Request_Data, allocator := context.allocator) -> Request_Data {
	out: Request_Data
	request_data_init(&out, allocator)
	for p in src.vars {
		append(&out.vars, Request_Pair{strings.clone(p.key, allocator), strings.clone(p.value, allocator)})
	}
	for p in src.fields {
		append(&out.fields, Request_Pair{strings.clone(p.key, allocator), strings.clone(p.value, allocator)})
	}
	return out
}

merge_request_pair :: proc(r: ^Request_Data, key, value: string, allocator := context.allocator) {
	k := trim_ascii_spaces(key)
	v := trim_ascii_spaces(value)
	if k == "" {
		return
	}
	if strings.has_prefix(k, "field.") {
		name := k[len("field."):]
		if name == "" {
			return
		}
		append(&r.fields, Request_Pair{strings.clone(name, allocator), strings.clone(v, allocator)})
		return
	}
	append(&r.vars, Request_Pair{strings.clone(k, allocator), strings.clone(v, allocator)})
}

// Parse `a=1|field.user=alice|name` style specs. Bare names are ignored (no form state).
parse_request_spec :: proc(spec: string, allocator := context.allocator) -> Request_Data {
	out: Request_Data
	request_data_init(&out, allocator)
	if trim_ascii_spaces(spec) == "" {
		return out
	}
	start := 0
	s := spec
	for start <= len(s) {
		rel := strings.index_byte(s[start:], '|')
		part: string
		if rel < 0 {
			part = s[start:]
			start = len(s) + 1
		} else {
			part = s[start:start + rel]
			start = start + rel + 1
		}
		part = trim_ascii_spaces(part)
		if part == "" || part == "*" {
			continue
		}
		eq := strings.index_byte(part, '=')
		if eq <= 0 {
			continue
		}
		merge_request_pair(&out, part[:eq], part[eq + 1:], allocator)
	}
	return out
}

split_destination_request :: proc(dest: string, allocator := context.allocator) -> (base: string, req: Request_Data) {
	before, after, ok := cut_once(dest, '`')
	if !ok {
		return trim_ascii_spaces(dest), {}
	}
	req = parse_request_spec(after, allocator)
	return trim_ascii_spaces(before), req
}

// Msgpack map of var_* / field_* strings for rns_link_request data.
encode_request_data :: proc(r: Request_Data, allocator := context.allocator) -> []u8 {
	n := len(r.vars) + len(r.fields)
	if n == 0 {
		return nil
	}
	w: lxmf.Writer
	lxmf.writer_init(&w, allocator)
	lxmf.write_map_header(&w, n)
	for p in r.vars {
		lxmf.write_str(&w, strings.concatenate({"var_", p.key}, context.temp_allocator))
		lxmf.write_str(&w, p.value)
	}
	for p in r.fields {
		lxmf.write_str(&w, strings.concatenate({"field_", p.key}, context.temp_allocator))
		lxmf.write_str(&w, p.value)
	}
	out := make([]u8, len(w.buf), allocator)
	copy(out, w.buf[:])
	lxmf.writer_destroy(&w)
	return out
}
