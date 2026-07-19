// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Unit tests for the micron page parser and link resolver.
*/

package tests

import "core:strings"
import "core:testing"

import "ren:micron"

@(test)
test_micron_parse_heading_and_literal :: proc(t: ^testing.T) {
	src := ">> Title\n`=\nliteral `!not\n`=\n`!bold` text"
	doc := micron.parse(src)
	defer micron.doc_destroy(&doc)
	testing.expect(t, len(doc.lines) >= 3)
	testing.expect(t, doc.lines[0].heading)
	testing.expect(t, len(doc.lines[0].spans) >= 1)
	testing.expect_value(t, doc.lines[0].spans[0].text, "Title")
}

@(test)
test_micron_parse_links_and_security :: proc(t: ^testing.T) {
	src := "`[home`/page/index.mu]\n`[x`javascript://alert(1)]\n`[peer`lxmf://0123456789abcdef0123456789abcdef]"
	doc := micron.parse(src)
	defer micron.doc_destroy(&doc)
	testing.expect(t, doc.link_count >= 3)

	found_page := false
	found_js := false
	found_lxmf := false
	for line in doc.lines {
		for span in line.spans {
			if span.kind != .Link {
				continue
			}
			if strings.contains(span.url, "/page/index.mu") {
				found_page = true
			}
			if strings.has_prefix(span.url, "nomadnetwork://javascript:") {
				found_js = true
			}
			if strings.contains(span.url, "lxmf://") {
				found_lxmf = true
			}
		}
	}
	testing.expect(t, found_page)
	testing.expect(t, found_js)
	testing.expect(t, found_lxmf)
}

@(test)
test_micron_resolve_page_and_lxmf :: proc(t: ^testing.T) {
	base: [16]u8
	base[0] = 0xaa

	rel := micron.resolve_link("nomadnetwork:///page/about.mu", base, true)
	defer micron.action_destroy(&rel)
	testing.expect_value(t, rel.kind, micron.Action_Kind.Page)
	testing.expect_value(t, rel.path, "/page/about.mu")
	testing.expect(t, rel.has_node)
	testing.expect_value(t, rel.node[0], u8(0xaa))

	hex := "0123456789abcdef0123456789abcdef"
	abs := micron.resolve_link("0123456789abcdef0123456789abcdef:/page/x.mu", {}, false)
	defer micron.action_destroy(&abs)
	testing.expect_value(t, abs.kind, micron.Action_Kind.Page)
	testing.expect_value(t, abs.path, "/page/x.mu")
	testing.expect(t, abs.has_node)

	lx := micron.resolve_link("lxmf://0123456789abcdef0123456789abcdef", {}, false)
	defer micron.action_destroy(&lx)
	testing.expect_value(t, lx.kind, micron.Action_Kind.Lxmf)
	testing.expect_value(t, lx.peer[0], u8(0x01))

	_ = hex

	bad := micron.resolve_link("nomadnetwork://javascript://x", {}, false)
	defer micron.action_destroy(&bad)
	testing.expect_value(t, bad.kind, micron.Action_Kind.Reject)

	ext := micron.resolve_link("https://example.com", {}, false)
	defer micron.action_destroy(&ext)
	testing.expect_value(t, ext.kind, micron.Action_Kind.External)

	trav := micron.resolve_link("/page/../secret", base, true)
	defer micron.action_destroy(&trav)
	testing.expect_value(t, trav.kind, micron.Action_Kind.Reject)
}

@(test)
test_micron_resolve_request_vars_and_relative :: proc(t: ^testing.T) {
	base: [16]u8
	base[0] = 0xbb

	dyn := micron.resolve_link("/page/forum.mu`cat=general|field.user=alice", base, true)
	defer micron.action_destroy(&dyn)
	testing.expect_value(t, dyn.kind, micron.Action_Kind.Page)
	testing.expect_value(t, dyn.path, "/page/forum.mu")
	testing.expect(t, len(dyn.request.vars) == 1)
	testing.expect_value(t, dyn.request.vars[0].key, "cat")
	testing.expect_value(t, dyn.request.vars[0].value, "general")
	testing.expect(t, len(dyn.request.fields) == 1)
	testing.expect_value(t, dyn.request.fields[0].key, "user")
	testing.expect_value(t, dyn.request.fields[0].value, "alice")

	rel := micron.resolve_link("page/about.mu", base, true)
	defer micron.action_destroy(&rel)
	testing.expect_value(t, rel.kind, micron.Action_Kind.Page)
	testing.expect_value(t, rel.path, "/page/about.mu")

	payload := micron.encode_request_data(dyn.request)
	defer delete(payload)
	testing.expect(t, len(payload) > 0)
}

@(test)
test_micron_parse_link_folds_field_spec :: proc(t: ^testing.T) {
	src := "`[Forum`/page/forum.mu`cat=gen|field.msg=hi]"
	doc := micron.parse(src)
	defer micron.doc_destroy(&doc)
	found := false
	for line in doc.lines {
		for span in line.spans {
			if span.kind != .Link {
				continue
			}
			testing.expect(t, strings.contains(span.url, "/page/forum.mu"))
			testing.expect(t, strings.contains(span.url, "cat=gen"))
			act := micron.resolve_link(span.url, {}, false)
			defer micron.action_destroy(&act)
			// no base node so page relative may reject without hash
			_ = act
			found = true
		}
	}
	testing.expect(t, found)

	base: [16]u8
	base[15] = 1
	for line in doc.lines {
		for span in line.spans {
			if span.kind != .Link {
				continue
			}
			act := micron.resolve_link(span.url, base, true)
			defer micron.action_destroy(&act)
			testing.expect_value(t, act.kind, micron.Action_Kind.Page)
			testing.expect_value(t, act.path, "/page/forum.mu")
			testing.expect(t, len(act.request.vars) >= 1)
		}
	}
}

@(test)
test_micron_sanitize_strips_controls_in_labels :: proc(t: ^testing.T) {
	src := "`[hi\x1b[31mx`/page/index.mu]"
	doc := micron.parse(src)
	defer micron.doc_destroy(&doc)
	ok := false
	for line in doc.lines {
		for span in line.spans {
			if span.kind == .Link {
				testing.expect(t, !strings.contains(span.text, "\x1b"))
				ok = true
			}
		}
	}
	testing.expect(t, ok)
}
