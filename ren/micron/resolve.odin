// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Resolve Micron link destinations into safe TUI actions.
Never opens shells, files, or external executables.
*/

package micron

import "core:strings"

import "ren:lxmf"

action_destroy :: proc(a: ^Action) {
	if a == nil {
		return
	}
	delete(a.path)
	delete(a.url)
	delete(a.reason)
	request_data_destroy(&a.request)
	a^ = {}
}

decode_hex32_bytes :: proc(s: string) -> (out: [16]u8, ok: bool) {
	return lxmf.decode_hex32(s)
}

strip_destination_prefix :: proc(raw: string) -> string {
	s := trim_ascii_spaces(raw)
	for strings.has_prefix(s, "nomadnetwork://") {
		s = s[len("nomadnetwork://"):]
	}
	return trim_ascii_spaces(s)
}

path_charset_ok :: proc(path: string) -> bool {
	if path == "" {
		return false
	}
	if !strings.has_prefix(path, "/page/") && !strings.has_prefix(path, "/file/") {
		return false
	}
	if strings.contains(path, "..") {
		return false
	}
	for i in 0 ..< len(path) {
		c := path[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '/', '.', '_', '-', '~':
		case:
			return false
		}
	}
	return true
}

normalize_page_path :: proc(raw: string) -> string {
	p := trim_ascii_spaces(raw)
	if p == "" {
		return ""
	}
	if !strings.has_prefix(p, "/") {
		p = strings.concatenate({"/", p}, context.temp_allocator)
	}
	return p
}

scheme_of :: proc(s: string) -> string {
	colon := strings.index_byte(s, ':')
	if colon <= 0 {
		return ""
	}
	return strings.to_lower(s[:colon], context.temp_allocator)
}

make_nomad_action :: proc(
	node: [16]u8,
	has_node: bool,
	path: string,
	req: Request_Data,
	formatted: string,
	allocator := context.allocator,
) -> Action {
	kind := Action_Kind.Page
	if strings.has_prefix(path, "/file/") {
		kind = .File
	}
	return Action{
		kind = kind,
		node = node,
		has_node = has_node,
		path = strings.clone(path, allocator),
		url = strings.clone(formatted, allocator),
		request = req,
	}
}

make_page_action :: proc(
	node: [16]u8,
	has_node: bool,
	path: string,
	req: Request_Data,
	formatted: string,
	allocator := context.allocator,
) -> Action {
	return make_nomad_action(node, has_node, path, req, formatted, allocator)
}

// Resolve a formatted Micron URL against an optional current NomadNet node.
resolve_link :: proc(
	raw_url: string,
	base_node: [16]u8,
	has_base: bool,
	allocator := context.allocator,
) -> Action {
	formatted := trim_ascii_spaces(raw_url)
	if formatted == "" {
		return Action{kind = .Reject, reason = strings.clone("empty link", allocator)}
	}

	dest := strip_destination_prefix(formatted)
	path_part, req := split_destination_request(dest, allocator)
	if path_part == "" {
		request_data_destroy(&req)
		return Action{kind = .Reject, reason = strings.clone("empty destination", allocator)}
	}

	if dangerous_nav_scheme(path_part) || dangerous_nav_scheme(formatted) {
		request_data_destroy(&req)
		return Action{
			kind = .Reject,
			url = strings.clone(formatted, allocator),
			reason = strings.clone("blocked scheme", allocator),
		}
	}

	scheme := scheme_of(path_part)
	switch scheme {
	case "javascript", "vbscript", "file", "data":
		request_data_destroy(&req)
		return Action{
			kind = .Reject,
			url = strings.clone(formatted, allocator),
			reason = strings.clone("blocked scheme", allocator),
		}
	case "http", "https", "mailto":
		request_data_destroy(&req)
		return Action{kind = .External, url = strings.clone(path_part, allocator)}
	case "lxmf":
		request_data_destroy(&req)
		peer_s := path_part[len("lxmf://"):] if strings.has_prefix(path_part, "lxmf://") else path_part[len("lxmf:"):]
		peer_s = trim_ascii_spaces(peer_s)
		if at := strings.index_byte(peer_s, '@'); at >= 0 {
			peer_s = peer_s[at + 1:]
		}
		if slash := strings.index_byte(peer_s, '/'); slash >= 0 {
			peer_s = peer_s[:slash]
		}
		peer, ok := decode_hex32_bytes(peer_s)
		if !ok {
			return Action{kind = .Reject, reason = strings.clone("bad lxmf address", allocator)}
		}
		return Action{kind = .Lxmf, peer = peer, url = strings.clone(formatted, allocator)}
	}

	lower := strings.to_lower(path_part, context.temp_allocator)
	if strings.has_prefix(lower, "lxmf@") || strings.has_prefix(lower, "lxmf.delivery@") {
		request_data_destroy(&req)
		at := strings.index_byte(path_part, '@')
		if at < 0 || at + 1 >= len(path_part) {
			return Action{kind = .Reject, reason = strings.clone("bad lxmf address", allocator)}
		}
		peer_s := path_part[at + 1:]
		if slash := strings.index_byte(peer_s, '/'); slash >= 0 {
			peer_s = peer_s[:slash]
		}
		peer, ok := decode_hex32_bytes(trim_ascii_spaces(peer_s))
		if !ok {
			return Action{kind = .Reject, reason = strings.clone("bad lxmf address", allocator)}
		}
		return Action{kind = .Lxmf, peer = peer, url = strings.clone(formatted, allocator)}
	}

	if strings.has_prefix(path_part, "/") ||
	   (!strings.contains(path_part, "://") &&
		(strings.has_prefix(normalize_page_path(path_part), "/page/") ||
			strings.has_prefix(normalize_page_path(path_part), "/file/"))) {
		path := normalize_page_path(path_part)
		if !path_charset_ok(path) {
			request_data_destroy(&req)
			return Action{kind = .Reject, reason = strings.clone("bad path", allocator)}
		}
		if !has_base {
			request_data_destroy(&req)
			return Action{kind = .Reject, reason = strings.clone("no current node", allocator)}
		}
		return make_nomad_action(base_node, true, path, req, formatted, allocator)
	}

	if strings.has_prefix(path_part, ":/") {
		path := path_part[1:]
		if !path_charset_ok(path) {
			request_data_destroy(&req)
			return Action{kind = .Reject, reason = strings.clone("bad path", allocator)}
		}
		if !has_base {
			request_data_destroy(&req)
			return Action{kind = .Reject, reason = strings.clone("no current node", allocator)}
		}
		return make_nomad_action(base_node, true, path, req, formatted, allocator)
	}

	colon := strings.index_byte(path_part, ':')
	if colon == 32 && lxmf.is_hex32(path_part[:32]) {
		node, nok := decode_hex32_bytes(path_part[:32])
		if !nok {
			request_data_destroy(&req)
			return Action{kind = .Reject, reason = strings.clone("bad node hash", allocator)}
		}
		rest := path_part[33:]
		path := "/page/index.mu"
		if rest != "" {
			path = normalize_page_path(rest)
		}
		if !path_charset_ok(path) {
			request_data_destroy(&req)
			return Action{kind = .Reject, reason = strings.clone("bad path", allocator)}
		}
		return make_nomad_action(node, true, path, req, formatted, allocator)
	}

	if lxmf.is_hex32(path_part) {
		request_data_destroy(&req)
		node, nok := decode_hex32_bytes(path_part)
		if !nok {
			return Action{kind = .Reject, reason = strings.clone("bad node hash", allocator)}
		}
		return make_page_action(node, true, "/page/index.mu", {}, formatted, allocator)
	}

	if len(path_part) == 33 && path_part[32] == ':' && lxmf.is_hex32(path_part[:32]) {
		request_data_destroy(&req)
		node, nok := decode_hex32_bytes(path_part[:32])
		if !nok {
			return Action{kind = .Reject, reason = strings.clone("bad node hash", allocator)}
		}
		return make_page_action(node, true, "/page/index.mu", {}, formatted, allocator)
	}

	request_data_destroy(&req)
	return Action{
		kind = .Reject,
		url = strings.clone(formatted, allocator),
		reason = strings.clone("unsupported link", allocator),
	}
}
