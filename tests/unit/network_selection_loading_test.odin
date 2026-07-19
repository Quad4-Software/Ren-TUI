// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Network selection stability on announces and loading panel text fit.
*/

package tests

import "core:testing"

import "ren:app"
import "ren:store"
import "ren:ui"

@(test)
test_truncate_runes_respects_emoji_cols :: proc(t: ^testing.T) {
	ui.caps_init("full")
	emoji := "hi😀bye"
	testing.expect(t, ui.string_cols(emoji) >= 6)
	cut := ui.truncate_runes(emoji, 4)
	testing.expect(t, ui.string_cols(cut) <= 4)
}

@(test)
test_buffer_text_wide_glyph_does_not_spill :: proc(t: ^testing.T) {
	ui.caps_init("full")
	buf := ui.buffer_create(8, 1)
	defer ui.buffer_destroy(&buf)
	ui.buffer_text(&buf, 0, 0, "😀ABCD", ui.Color{}, ui.Color{})
	testing.expect_value(t, buf.cells[0].ch, rune(0x1F600))
	testing.expect_value(t, buf.cells[1].ch, ui.CELL_WIDE_CONT)
	testing.expect_value(t, buf.cells[2].ch, 'A')
}

@(test)
test_buffer_text_clip_stops_before_border :: proc(t: ^testing.T) {
	ui.caps_init("full")
	buf := ui.buffer_create(10, 1)
	defer ui.buffer_destroy(&buf)
	for i in 0 ..< 10 {
		ui.buffer_put(&buf, i, 0, '#', ui.Color{}, ui.Color{})
	}
	ui.buffer_text_clip(&buf, 1, 0, 9, "😀😀😀😀😀😀", ui.Color{1, 2, 3}, ui.Color{})
	testing.expect_value(t, buf.cells[0].ch, '#')
	testing.expect_value(t, buf.cells[9].ch, '#')
	for i in 1 ..< 9 {
		testing.expect(t, buf.cells[i].ch != '#')
	}
}

@(test)
test_loading_panel_name_keeps_box_borders :: proc(t: ^testing.T) {
	ui.caps_init("full")
	a: app.App
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)

	node: [store.HASH_LEN]u8
	node[0] = 0x42
	long_name := "🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟 very-long-node-name-with-emojis"
	store.directory_upsert(&a.directory, node, node, .Nomad_Node, long_name, nil, 2)
	a.session.page.active = true
	a.session.page.done = false
	a.session.page.node = node
	a.session.page.path = "/page/index.mu"
	a.session.page.phase = .Waiting_Link
	a.session.page.status = "waiting for link"
	a.poll_ticks = 3

	buf := ui.buffer_create(40, 20)
	defer ui.buffer_destroy(&buf)
	body := ui.Rect{0, 0, 40, 20}
	app.draw_page_loading(&a, &buf, body)

	panel_w := min(body.w - 2, 56)
	panel_h := min(body.h - 2, 11)
	px := body.x + max(0, (body.w - panel_w) / 2)
	py := body.y + max(0, (body.h - panel_h) / 2)
	right := px + panel_w - 1
	left := px
	for row in 1 ..< panel_h - 1 {
		lc := buf.cells[(py + row) * buf.width + left].ch
		rc := buf.cells[(py + row) * buf.width + right].ch
		testing.expect(t, is_box_vert(lc))
		testing.expect(t, is_box_vert(rc))
	}
}

@(test)
test_network_selection_stable_on_lxmf_announce_reorder :: proc(t: ^testing.T) {
	expect_selection_stable_on_announce(t, .Lxmf, .Lxmf)
}

@(test)
test_network_selection_stable_on_nomad_announce_reorder :: proc(t: ^testing.T) {
	expect_selection_stable_on_announce(t, .Nomad, .Nomad_Node)
}

@(test)
test_network_selection_stable_on_propagation_announce_reorder :: proc(t: ^testing.T) {
	expect_selection_stable_on_announce(t, .Propagation, .Propagation)
}

@(test)
test_network_scroll_keeps_visual_row_on_reorder :: proc(t: ^testing.T) {
	a: app.App
	ui.list_init(&a.net_list)
	defer ui.list_destroy(&a.net_list)
	a.net_peer_idx = make([dynamic]int)
	defer delete(a.net_peer_idx)
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)
	a.net_view = .Nomad
	a.term_h = 40
	a.term_w = 120
	a.list_rect = ui.Rect{0, 0, 60, 6}

	keep := peer_hash(0x20)
	for i in 0 ..< 12 {
		h := peer_hash(u8(0x30 + i))
		store.directory_upsert(&a.directory, h, h, .Nomad_Node, "old", nil, 1)
		// Half above keep, half below.
		heard := f64(60 + i) if i < 6 else f64(40 - i)
		set_peer_heard(&a.directory, h, heard)
	}
	store.directory_upsert(&a.directory, keep, keep, .Nomad_Node, "keep", nil, 1)
	set_peer_heard(&a.directory, keep, 50)

	app.refresh_network_list(&a, 0, 0)
	sel := find_peer_row(&a, keep)
	testing.expect(t, sel >= 4)
	a.net_list.selected = sel
	a.net_list.scroll = max(0, sel - 3)
	visual := a.net_list.selected - a.net_list.scroll
	testing.expect(t, a.net_list.scroll > 0)
	testing.expect(t, visual >= 0 && visual < 6)

	newer := peer_hash(0x99)
	store.directory_upsert(&a.directory, newer, newer, .Nomad_Node, "newest", nil, 1)
	set_peer_heard(&a.directory, newer, 200)
	app.refresh_network_list(&a, a.net_list.selected, a.net_list.scroll)

	testing.expect_value(t, find_peer_row(&a, keep), a.net_list.selected)
	testing.expect_value(t, a.net_list.selected - a.net_list.scroll, visual)
}

expect_selection_stable_on_announce :: proc(
	t: ^testing.T,
	view: app.Net_View,
	kind: store.Peer_Kind,
) {
	a: app.App
	ui.list_init(&a.net_list)
	defer ui.list_destroy(&a.net_list)
	a.net_peer_idx = make([dynamic]int)
	defer delete(a.net_peer_idx)
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)
	a.net_view = view
	a.term_h = 40
	a.term_w = 120
	a.list_rect = ui.Rect{0, 0, 60, 16}

	keep := peer_hash(0x55)
	other := peer_hash(0x11)
	store.directory_upsert(&a.directory, other, other, kind, "other", nil, 1)
	set_peer_heard(&a.directory, other, 10)
	store.directory_upsert(&a.directory, keep, keep, kind, "keep-me", nil, 2)
	set_peer_heard(&a.directory, keep, 20)

	app.refresh_network_list(&a, 0, 0)
	sel := find_peer_row(&a, keep)
	testing.expect(t, sel >= 0)
	a.net_list.selected = sel
	a.net_list.scroll = max(0, sel - 1)

	top := peer_hash(0xee)
	store.directory_upsert(&a.directory, top, top, kind, "brand-new", nil, 3)
	set_peer_heard(&a.directory, top, 30)
	app.refresh_network_list(&a, a.net_list.selected, a.net_list.scroll)

	testing.expect_value(t, find_peer_row(&a, keep), a.net_list.selected)
	testing.expect(t, a.net_list.selected != find_peer_row(&a, top))
}

find_peer_row :: proc(a: ^app.App, hash: [store.HASH_LEN]u8) -> int {
	for idx, i in a.net_peer_idx {
		if idx < 0 || idx >= len(a.directory.peers) {
			continue
		}
		if a.directory.peers[idx].hash == hash {
			return i
		}
	}
	return -1
}

set_peer_heard :: proc(d: ^store.Directory, hash: [store.HASH_LEN]u8, heard: f64) {
	for &p in d.peers {
		if p.hash == hash {
			p.last_heard = heard
			return
		}
	}
}

peer_hash :: proc(b0: u8) -> [store.HASH_LEN]u8 {
	h: [store.HASH_LEN]u8
	h[0] = b0
	h[1] = 0xab
	return h
}

is_box_vert :: proc(ch: rune) -> bool {
	switch ch {
	case '│', '┃', '┆', '┇', '|':
		return true
	}
	return false
}
