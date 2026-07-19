// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Unit tests for page path and URL parsing guards.
*/

package tests

import "core:strings"
import "core:testing"

import "ren:app"
import "ren:constants"
import "ren:micron"
import "ren:net"
import "ren:store"

@(test)
test_page_path_rejects_traversal_and_shell :: proc(t: ^testing.T) {
	testing.expect(t, app.page_path_allowed("/page/index.mu"))
	testing.expect(t, !app.page_path_allowed("../etc/passwd"))
	testing.expect(t, !app.page_path_allowed("/page/../../x"))
	testing.expect(t, !app.page_path_allowed("/page/x;rm"))
	testing.expect(t, !app.page_path_allowed("/page/x$(hi)"))
	testing.expect(t, !app.page_path_allowed("page/no-slash"))
	testing.expect(t, !app.page_path_allowed("/other/x.mu"))
}

@(test)
test_page_parse_url_hash_and_path :: proc(t: ^testing.T) {
	hash, has, path, ok := app.page_parse_url("0123456789abcdef0123456789abcdef:/page/about.mu")
	testing.expect(t, ok)
	testing.expect(t, has)
	testing.expect_value(t, path, "/page/about.mu")
	testing.expect_value(t, hash[0], u8(0x01))
	delete(path)

	_, has2, path2, ok2 := app.page_parse_url("/page/index.mu")
	testing.expect(t, ok2)
	testing.expect(t, !has2)
	testing.expect_value(t, path2, "/page/index.mu")
	delete(path2)

	_, _, _, bad := app.page_parse_url("not-a-url")
	testing.expect(t, !bad)
	_, _, _, bad2 := app.page_parse_url("/page/../x")
	testing.expect(t, !bad2)
}

@(test)
test_page_parse_url_strips_request_suffix :: proc(t: ^testing.T) {
	_, has, path, ok := app.page_parse_url("/page/forum.mu`cat=general")
	testing.expect(t, ok)
	testing.expect(t, !has)
	testing.expect_value(t, path, "/page/forum.mu")
	delete(path)
}

@(test)
test_page_sanitize_strips_controls :: proc(t: ^testing.T) {
	raw := []u8{'h', 'i', 0, 0x1b, '[', 'A', '\n', 'o', 'k'}
	s := app.page_sanitize_bytes(raw)
	defer delete(s)
	testing.expect(t, !strings.contains(s, "\x00"))
	testing.expect(t, !strings.contains(s, "\x1b"))
	testing.expect(t, strings.contains(s, "hi"))
	testing.expect(t, strings.contains(s, "ok"))
}

@(test)
test_path_hot_cache_ttl_and_cap :: proc(t: ^testing.T) {
	pf: net.Path_Finder
	a: [store.HASH_LEN]u8
	a[0] = 1
	net.path_hot_remember(&pf, a, 2)
	e, ok := net.path_hot_lookup(&pf, a)
	testing.expect(t, ok)
	testing.expect_value(t, e.hops, u8(2))

	for i in 0 ..< constants.PATH_CACHE_MAX + 3 {
		h: [store.HASH_LEN]u8
		h[0] = u8(i + 10)
		net.path_hot_remember(&pf, h, u8(i))
	}
	n := 0
	for i in 0 ..< len(pf.hot) {
		if pf.hot[i].valid {
			n += 1
		}
	}
	testing.expect_value(t, n, constants.PATH_CACHE_MAX)

	net.path_hot_invalidate(&pf, a)
	_, ok2 := net.path_hot_lookup(&pf, a)
	testing.expect(t, !ok2)
}

@(test)
test_micron_parse_limits_lines :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)
	for i in 0 ..< constants.PAGE_MAX_LINES + 50 {
		strings.write_string(&b, "line\n")
		_ = i
	}
	doc := micron.parse_limited(strings.to_string(b), 10, 64)
	defer micron.doc_destroy(&doc)
	testing.expect(t, len(doc.lines) == 11) // 10 + truncated marker
}
