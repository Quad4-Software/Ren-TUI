// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Regression tests for announce/UI isolation and safe terminal cells.
*/

package tests

import "core:testing"

import "ren:app"
import "ren:constants"
import "ren:store"
import "ren:ui"

@(test)
test_sanitize_rune_strips_c0_and_c1 :: proc(t: ^testing.T) {
	ui.caps_init("full")
	testing.expect_value(t, ui.sanitize_rune(0x1b), ' ')
	testing.expect_value(t, ui.sanitize_rune('\n'), ' ')
	testing.expect_value(t, ui.sanitize_rune(0x7f), ' ')
	testing.expect_value(t, ui.sanitize_rune(0x9b), ' ') // CSI
	testing.expect_value(t, ui.sanitize_rune('A'), 'A')
}

@(test)
test_buffer_put_strips_controls :: proc(t: ^testing.T) {
	ui.caps_init("full")
	buf := ui.buffer_create(4, 2)
	defer ui.buffer_destroy(&buf)
	ui.buffer_put(&buf, 0, 0, 0x1b, ui.Color{}, ui.Color{})
	ui.buffer_put(&buf, 1, 0, 0x9b, ui.Color{}, ui.Color{})
	ui.buffer_text(&buf, 0, 1, "\x1b[31mhi", ui.Color{}, ui.Color{})
	testing.expect_value(t, buf.cells[0].ch, ' ')
	testing.expect_value(t, buf.cells[1].ch, ' ')
	testing.expect_value(t, buf.cells[4].ch, ' ') // ESC became space
}

@(test)
test_directory_label_sanitizes_announce_name :: proc(t: ^testing.T) {
	d: store.Directory
	store.directory_init(&d)
	defer store.directory_destroy(&d)
	h: [store.HASH_LEN]u8
	h[0] = 9
	rev0 := d.revision
	store.directory_upsert(&d, h, h, .Nomad_Node, "evil\x1b[2Jname\x9bX", nil, 1)
	testing.expect(t, d.revision > rev0)
	testing.expect(t, len(d.peers) == 1)
	name := d.peers[0].display_name
	testing.expect(t, !contains_byte(name, 0x1b))
	testing.expect(t, !contains_byte(name, 0x9b))
	testing.expect(t, contains_ascii(name, 'e') || contains_ascii(name, 'n'))
}

@(test)
test_directory_revision_stable_on_noop_upsert :: proc(t: ^testing.T) {
	d: store.Directory
	store.directory_init(&d)
	defer store.directory_destroy(&d)
	h: [store.HASH_LEN]u8
	h[0] = 3
	store.directory_upsert(&d, h, h, .Lxmf, "alice", nil, 2)
	rev := d.revision
	store.directory_upsert(&d, h, h, .Lxmf, "alice", nil, 2)
	testing.expect_value(t, d.revision, rev)
}

@(test)
test_network_list_rebuild_after_hot_cap_while_away :: proc(t: ^testing.T) {
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
	a.list_rect = {}

	keep: [store.HASH_LEN]u8
	keep[0] = 0xaa
	store.directory_upsert(&a.directory, keep, keep, .Nomad_Node, "keep-me", nil, 1)
	app.refresh_network_list(&a, 0, 0)
	a.net_dir_rev = a.directory.revision
	testing.expect(t, len(a.net_peer_idx) >= 2)
	sel := -1
	for idx, i in a.net_peer_idx {
		if idx >= 0 {
			sel = i
			break
		}
	}
	testing.expect(t, sel >= 0)
	a.net_list.selected = sel
	stale_idx := a.net_peer_idx[sel]
	testing.expect(t, stale_idx >= 0)
	testing.expect_value(t, a.directory.peers[stale_idx].hash[0], u8(0xaa))

	// Fill announces while "on Page" (list not refreshed): hot-cap may reshuffle idxs.
	for i in 0 ..< constants.PEERS_HOT_MAX + 8 {
		h: [store.HASH_LEN]u8
		h[0] = u8(i + 1)
		h[1] = u8(i >> 8)
		store.directory_upsert(&a.directory, h, h, .Nomad_Node, "flood", nil, 1)
	}
	testing.expect(t, a.directory.revision != a.net_dir_rev)

	// Esc-back path: force rebuild. Peer idxs must stay in-range.
	app.show_network_tab(&a)
	testing.expect_value(t, a.tab, app.Tab.Network)
	testing.expect_value(t, a.net_dir_rev, a.directory.revision)
	for idx in a.net_peer_idx {
		if idx < 0 {
			continue
		}
		testing.expect(t, idx < len(a.directory.peers))
		testing.expect_value(t, a.directory.peers[idx].kind, store.Peer_Kind.Nomad_Node)
	}
	visible := app.network_list_visible(&a)
	testing.expect(t, visible > 1)
}

contains_byte :: proc(s: string, b: u8) -> bool {
	for i in 0 ..< len(s) {
		if s[i] == b {
			return true
		}
	}
	return false
}

contains_ascii :: proc(s: string, ch: u8) -> bool {
	return contains_byte(s, ch)
}
