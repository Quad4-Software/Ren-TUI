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

@(test)
test_micron_color_to_rgb_hex :: proc(t: ^testing.T) {
	fb := micron.Rgb{r = 1, g = 2, b = 3}
	c3 := micron.color_to_rgb("f00", fb)
	testing.expect_value(t, c3.r, u8(255))
	testing.expect_value(t, c3.g, u8(0))
	testing.expect_value(t, c3.b, u8(0))
	c6 := micron.color_to_rgb("112233", fb)
	testing.expect_value(t, c6.r, u8(0x11))
	testing.expect_value(t, c6.g, u8(0x22))
	testing.expect_value(t, c6.b, u8(0x33))
	def := micron.color_to_rgb("default", fb)
	testing.expect_value(t, def.r, u8(1))
}

@(test)
test_micron_layout_wraps_words :: proc(t: ^testing.T) {
	doc := micron.parse("hello world this is a long line of micron text")
	defer micron.doc_destroy(&doc)
	rows := micron.layout_doc(doc, 12, context.allocator)
	defer micron.layout_rows_destroy(&rows)
	testing.expect(t, len(rows) >= 3)
	total := 0
	for row in rows {
		w := micron.layout_row_width(row) - row.indent
		testing.expect(t, w <= 12)
		total += w
	}
	testing.expect(t, total >= 20)
}

@(test)
test_micron_layout_hard_breaks_long_token :: proc(t: ^testing.T) {
	doc := micron.parse("abcdefghijklmnopqrstuvwxyz")
	defer micron.doc_destroy(&doc)
	rows := micron.layout_doc(doc, 8, context.allocator)
	defer micron.layout_rows_destroy(&rows)
	testing.expect(t, len(rows) >= 3)
	for row in rows {
		testing.expect(t, micron.layout_row_width(row) <= 8)
	}
}

@(test)
test_micron_parse_field_metadata :: proc(t: ^testing.T) {
	src := "`<?|agree|yes`I agree>\n`<14|user`alice>\n`<^|color|red|*`Red>"
	doc := micron.parse(src)
	defer micron.doc_destroy(&doc)
	found_check := false
	found_text := false
	found_radio := false
	for line in doc.lines {
		for span in line.spans {
			if span.kind != .Field {
				continue
			}
			switch span.field_kind {
			case .Checkbox:
				testing.expect_value(t, span.field_name, "agree")
				testing.expect_value(t, span.field_value, "yes")
				testing.expect(t, strings.contains(span.text, "[ ]"))
				found_check = true
			case .Text:
				testing.expect_value(t, span.field_name, "user")
				testing.expect_value(t, span.field_value, "alice")
				testing.expect_value(t, span.field_width, 14)
				found_text = true
			case .Radio:
				testing.expect_value(t, span.field_name, "color")
				testing.expect(t, span.field_prechecked)
				testing.expect(t, strings.contains(span.text, "[x]"))
				found_radio = true
			case .None:
			}
		}
	}
	testing.expect(t, found_check)
	testing.expect(t, found_text)
	testing.expect(t, found_radio)
}

@(test)
test_micron_link_keeps_field_spec_and_collect :: proc(t: ^testing.T) {
	src := "`[Go`/page/x.mu`user|msg|*]"
	doc := micron.parse(src)
	defer micron.doc_destroy(&doc)
	spec := ""
	for line in doc.lines {
		for span in line.spans {
			if span.kind == .Link {
				spec = span.field_spec
			}
		}
	}
	testing.expect(t, strings.contains(spec, "user"))
	testing.expect(t, strings.contains(spec, "*"))

	inputs := []micron.Form_Field_Input{
		{kind = .Text, name = "user", value = "bob"},
		{kind = .Text, name = "msg", value = "hi"},
		{kind = .Checkbox, name = "extra", value = "1", checked = true},
	}
	all := micron.collect_form_fields(inputs)
	defer micron.form_fields_map_destroy(&all)
	testing.expect_value(t, all["user"], "bob")
	testing.expect_value(t, all["extra"], "1")

	req: micron.Request_Data
	micron.request_data_init(&req)
	defer micron.request_data_destroy(&req)
	micron.merge_form_fields_into_request(&req, all, "user|msg")
	testing.expect_value(t, len(req.fields), 2)
}
