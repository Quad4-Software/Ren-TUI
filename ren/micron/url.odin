// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
NomadNet URL formatting for Micron links.
*/

package micron

import "core:strings"

has_scheme_prefix :: proc(url: string) -> bool {
	colon := strings.index_byte(url, ':')
	if colon <= 0 || colon + 2 >= len(url) {
		return false
	}
	if url[colon + 1] != '/' || url[colon + 2] != '/' {
		return false
	}
	for i in 0 ..< colon {
		c := url[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z':
		case '0' ..= '9', '+', '.', '-':
			if i == 0 {
				return false
			}
		case:
			return false
		}
	}
	return true
}

dangerous_nav_scheme :: proc(url: string) -> bool {
	colon := strings.index_byte(url, ':')
	if colon <= 0 {
		return false
	}
	scheme := strings.to_lower(url[:colon], context.temp_allocator)
	switch scheme {
	case "javascript", "vbscript", "file", "data":
		return true
	}
	return false
}

// Ensures URLs use a scheme NomadNet tooling expects.
format_nomadnetwork_url :: proc(raw: string, allocator := context.allocator) -> string {
	url := strings.trim_space(raw)
	if url == "" {
		return ""
	}
	if has_scheme_prefix(url) {
		if dangerous_nav_scheme(url) {
			return strings.concatenate({"nomadnetwork://", url}, allocator)
		}
		return strings.clone(url, allocator)
	}
	return strings.concatenate({"nomadnetwork://", url}, allocator)
}

link_direct_url :: proc(raw: string, allocator := context.allocator) -> string {
	s, _ := strings.replace_all(raw, "nomadnetwork://", "", allocator = context.temp_allocator)
	s, _ = strings.replace_all(s, "lxmf://", "", allocator = context.temp_allocator)
	return strings.clone(s, allocator)
}
