// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Math tests for TUI layout budgets and related helpers.
*/

package tests

import "core:strings"
import "core:testing"

import "ren:app"
import "ren:constants"
import "ren:net"
import "ren:store"
import "ren:ui"
import "ren:version"

@(test)
test_layout_status_right_cols_never_overflows :: proc(t: ^testing.T) {
	cases := [][2]int{{40, 10}, {80, 20}, {120, 60}, {20, 18}, {10, 0}, {0, 0}}
	for c in cases {
		w := c[0]
		left := c[1]
		right := ui.status_right_cols(w, left)
		testing.expect(t, right >= 0)
		if w > 0 {
			testing.expect(t, left + 1 + right + 2 <= w || right == 0)
		}
	}
	testing.expect_value(t, ui.status_right_cols(80, 20), 57)
	testing.expect_value(t, ui.status_right_cols(40, 30), 7)
	testing.expect_value(t, ui.status_right_cols(10, 20), 0)
}

@(test)
test_layout_network_list_row_cap_scales_with_height :: proc(t: ^testing.T) {
	small := ui.network_list_row_cap(5)
	mid := ui.network_list_row_cap(20)
	big := ui.network_list_row_cap(80)
	testing.expect(t, small >= 24)
	testing.expect(t, mid > small)
	testing.expect(t, big >= mid)
	testing.expect(t, big <= constants.PEERS_HOT_MAX)
	testing.expect_value(t, ui.network_list_row_cap(10), 60)
}

@(test)
test_layout_peer_name_cols_leaves_room_for_hash :: proc(t: ^testing.T) {
	cols := ui.peer_name_cols(80)
	testing.expect(t, cols >= 8)
	testing.expect(t, cols + 2 + 2 + 32 + 14 <= 80 || cols == 8)
	testing.expect_value(t, ui.peer_name_cols(40), 8)
}

@(test)
test_layout_iface_cards_per_page :: proc(t: ^testing.T) {
	testing.expect_value(t, ui.iface_cards_per_page(4), 1)
	testing.expect_value(t, ui.iface_cards_per_page(9), 2)
	testing.expect_value(t, ui.iface_cards_per_page(14), 3)
	testing.expect(t, ui.iface_cards_per_page(0) >= 1)
}

@(test)
test_layout_peers_hot_cap_for_term :: proc(t: ^testing.T) {
	tiny := ui.peers_hot_cap_for_term(12, 40)
	wide := ui.peers_hot_cap_for_term(40, 160)
	testing.expect(t, tiny >= 32)
	testing.expect(t, wide >= tiny)
	testing.expect(t, wide <= constants.PEERS_HOT_MAX)
}

@(test)
test_status_draw_truncates_right_to_budget :: proc(t: ^testing.T) {
	ui.caps_init("full")
	buf := ui.buffer_create(40, 1)
	defer ui.buffer_destroy(&buf)
	left := "ren-tui 0.1.0"
	right := "waiting for path to 0123456789abcdef0123456789abcdef and more noise"
	ui.draw_status(&buf, ui.Rect{0, 0, 40, 1}, left, right)
	right_cols := ui.status_right_cols(40, strings.rune_count(left))
	testing.expect(t, right_cols > 0)
	// Last cell should not be empty noise from wrap; stay on one row.
	for x in 0 ..< 40 {
		_ = ui.buffer_at(&buf, x, 0)
	}
	testing.expect_value(t, buf.height, 1)
}

@(test)
test_version_includes_build_date_field :: proc(t: ^testing.T) {
	line := version.line()
	defer delete(line)
	testing.expect(t, strings.contains(line, version.VERSION))
	testing.expect(t, strings.contains(line, version.GIT_COMMIT))
	testing.expect(t, strings.contains(line, version.BUILD_DATE))
	short := version.short_line()
	defer delete(short)
	testing.expect(t, strings.contains(short, "ren-tui"))
	testing.expect(t, !strings.contains(short, version.BUILD_DATE))
}

@(test)
test_iface_rank_sorts_down_last :: proc(t: ^testing.T) {
	ifaces := make([dynamic]app.Iface_View, 0, 4)
	defer {
		delete(ifaces)
	}
	append(&ifaces, app.Iface_View{name = "z-down", online = false, enabled = false})
	append(&ifaces, app.Iface_View{name = "a-up", online = true, enabled = true})
	append(&ifaces, app.Iface_View{name = "m-enabled", online = false, enabled = true})
	app.sort_ifaces(&ifaces)
	testing.expect_value(t, ifaces[0].name, "a-up")
	testing.expect_value(t, ifaces[1].name, "m-enabled")
	testing.expect_value(t, ifaces[2].name, "z-down")
}

@(test)
test_format_byte_count_scales :: proc(t: ^testing.T) {
	testing.expect_value(t, app.format_byte_count(500), "500B")
	testing.expect(t, strings.contains(app.format_byte_count(2048), "KiB"))
	testing.expect(t, strings.contains(app.format_byte_count(3 * 1024 * 1024), "MiB"))
}

@(test)
test_page_path_wait_shows_full_hash :: proc(t: ^testing.T) {
	h: [store.HASH_LEN]u8
	for i in 0 ..< store.HASH_LEN {
		h[i] = u8(i)
	}
	msg := net.page_path_wait_status(h, context.temp_allocator)
	hex := store.hash_hex(h, context.temp_allocator)
	testing.expect(t, strings.contains(msg, hex))
	testing.expect_value(t, len(hex), 32)
	testing.expect(t, strings.has_prefix(msg, "waiting for path to "))
}
