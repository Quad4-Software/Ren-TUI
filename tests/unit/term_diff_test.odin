// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Unit tests for dirty-cell terminal present and hex helpers.
*/

package tests

import "core:strings"
import "core:testing"

import "ren:app"
import "ren:lxmf"
import "ren:store"
import "ren:ui"

@(test)
test_term_present_diff_smaller_on_static_frame :: proc(t: ^testing.T) {
	ui.caps_init("full")
	buf := ui.buffer_create(8, 2)
	defer ui.buffer_destroy(&buf)
	ui.buffer_text(&buf, 0, 0, "hello", ui.FIELD.fg, ui.FIELD.bg)

	term: ui.Term
	strings.builder_init(&term.out)
	defer strings.builder_destroy(&term.out)

	full: strings.Builder
	strings.builder_init(&full)
	defer strings.builder_destroy(&full)
	ui.term_present_to_builder(&term, &buf, &full, false)
	term.prev = ui.buffer_create(buf.width, buf.height)
	copy(term.prev.cells, buf.cells)
	term.has_prev = true
	defer ui.buffer_destroy(&term.prev)

	diff: strings.Builder
	strings.builder_init(&diff)
	defer strings.builder_destroy(&diff)
	ui.term_present_to_builder(&term, &buf, &diff, true)
	testing.expect(t, strings.builder_len(diff) < strings.builder_len(full))
	testing.expect(t, strings.builder_len(diff) < 16)
}

@(test)
test_lxmf_decode_hex32 :: proc(t: ^testing.T) {
	h, ok := lxmf.decode_hex32("0123456789abcdef0123456789abcdef")
	testing.expect(t, ok)
	testing.expect_value(t, h[0], u8(0x01))
	testing.expect_value(t, h[15], u8(0xef))
	_, bad := lxmf.decode_hex32("xyz")
	testing.expect(t, !bad)
}

@(test)
test_refresh_network_list_revision :: proc(t: ^testing.T) {
	a: app.App
	ui.list_init(&a.net_list)
	defer ui.list_destroy(&a.net_list)
	a.net_peer_idx = make([dynamic]int)
	defer delete(a.net_peer_idx)
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)

	peer: store.Peer
	peer.hash[0] = 1
	peer.kind = .Lxmf
	peer.display_name = strings.clone("Alpha")
	append(&a.directory.peers, peer)
	a.directory.revision = 1
	a.tab = .Network
	app.refresh_network_list_if_needed(&a)
	testing.expect(t, len(a.net_list.items) > 0)
	testing.expect_value(t, a.net_dir_rev, u64(1))
}
