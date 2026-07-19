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

// Parse `a=1|field.user=alice|name` style specs. Bare names and * are ignored here
// (form collect uses split_field_list_spec + build_request_payload).
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

// Split a NomadNet link field list into names (includes bare names and *).
split_field_list_spec :: proc(spec: string, allocator := context.allocator) -> []string {
	s := trim_ascii_spaces(spec)
	if s == "" {
		return nil
	}
	parts := make([dynamic]string, 0, 4, allocator)
	start := 0
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
		if part == "" {
			continue
		}
		append(&parts, strings.clone(part, allocator))
	}
	return parts[:]
}

// Form field snapshot for CollectFormFields (matches micron-parser-go FieldInput).
Form_Field_Input :: struct {
	kind:    Field_Kind,
	name:    string,
	value:   string,
	checked: bool,
}

// Build name->value map from live form widgets (checkbox join, radio last-wins).
collect_form_fields :: proc(inputs: []Form_Field_Input, allocator := context.allocator) -> map[string]string {
	out := make(map[string]string, allocator)
	put :: proc(out: ^map[string]string, name, value: string, allocator := context.allocator) {
		if prev, ok := out[name]; ok {
			delete(prev)
			out[name] = strings.clone(value, allocator)
			return
		}
		out[strings.clone(name, allocator)] = strings.clone(value, allocator)
	}
	for item in inputs {
		if item.name == "" {
			continue
		}
		switch item.kind {
		case .Checkbox:
			if !item.checked {
				continue
			}
			if prev, ok := out[item.name]; ok && prev != "" {
				joined := strings.concatenate({prev, ",", item.value}, allocator)
				delete(prev)
				out[item.name] = joined
			} else {
				put(&out, item.name, item.value, allocator)
			}
		case .Radio:
			if item.checked {
				put(&out, item.name, item.value, allocator)
			}
		case .Text, .None:
			put(&out, item.name, item.value, allocator)
		}
	}
	return out
}

form_fields_map_destroy :: proc(m: ^map[string]string) {
	if m == nil {
		return
	}
	for k, v in m {
		delete(k)
		delete(v)
	}
	clear(m)
	delete(m^)
	m^ = {}
}

// Select fields from all_fields using field_spec (* = all, else named list).
// Matches micron-parser-go BuildRequestPayload field selection.
merge_form_fields_into_request :: proc(
	req: ^Request_Data,
	all_fields: map[string]string,
	field_spec: string,
	allocator := context.allocator,
) {
	if req == nil {
		return
	}
	spec := trim_ascii_spaces(field_spec)
	if spec == "" {
		return
	}
	if spec == "*" {
		for k, v in all_fields {
			append(&req.fields, Request_Pair{strings.clone(k, allocator), strings.clone(v, allocator)})
		}
		return
	}
	names := split_field_list_spec(spec, context.temp_allocator)
	for n in names {
		if n == "*" {
			for k, v in all_fields {
				append(&req.fields, Request_Pair{strings.clone(k, allocator), strings.clone(v, allocator)})
			}
			return
		}
		if strings.index_byte(n, '=') >= 0 {
			continue
		}
		if v, ok := all_fields[n]; ok {
			append(&req.fields, Request_Pair{strings.clone(n, allocator), strings.clone(v, allocator)})
		}
	}
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
