// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Tests for page fetch cancel/replace, footer hops, and iface cache stability.
*/

package tests

import "core:strings"
import "core:testing"

import "ren:app"
import "ren:net"
import "ren:store"

@(test)
test_session_page_cancel_clears_busy :: proc(t: ^testing.T) {
	s: net.Session
	s.page.active = true
	s.page.done = false
	s.page.path = strings.clone("/page/index.mu")
	s.page.status = strings.clone("waiting for link")
	s.page.node[0] = 0xaa
	net.session_page_cancel(&s)
	testing.expect(t, !net.session_page_busy(&s))
	testing.expect_value(t, s.page.path, "")
	testing.expect_value(t, s.page.status, "")
	testing.expect_value(t, s.page.phase, net.Page_Phase.Idle)
}

@(test)
test_page_fetch_cancels_prior_job_before_begin :: proc(t: ^testing.T) {
	a: app.App
	a.online = true
	a.session.started = false
	a.session.page.active = true
	a.session.page.done = false
	a.session.page.path = strings.clone("/page/old.mu")
	a.session.page.status = strings.clone("opening link")
	a.session.page.node[0] = 1
	a.session.page.phase = .Waiting_Link

	node: [store.HASH_LEN]u8
	node[0] = 2
	app.page_fetch(&a, node, "/page/index.mu")

	testing.expect(t, !net.session_page_busy(&a.session))
	testing.expect_value(t, a.session.page.path, "")
	testing.expect(t, strings.contains(a.status_right, "offline") || a.status_hold_len > 0)
}

@(test)
test_page_fetch_cancels_prior_before_new_target :: proc(t: ^testing.T) {
	a: app.App
	a.online = true
	a.session.started = true
	a.session.page.active = true
	a.session.page.done = false
	a.session.page.path = strings.clone("/page/old.mu")
	a.session.page.status = strings.clone("finding path")
	a.session.page.node[0] = 0x11
	a.session.page.phase = .Finding_Path

	node: [store.HASH_LEN]u8
	node[0] = 0x22
	app.page_fetch(&a, node, "/page/about.mu")
	// Prior job is always cancelled. New begin may fail without a live destination.
	if net.session_page_busy(&a.session) {
		testing.expect_value(t, a.session.page.node[0], u8(0x22))
		testing.expect_value(t, a.session.page.path, "/page/about.mu")
		net.session_page_cancel(&a.session)
	} else {
		testing.expect_value(t, a.session.page.path, "")
		testing.expect(t, a.session.page.node[0] != 0x11 || a.status_hold_len > 0)
	}
}

@(test)
test_footer_left_ren_tui_and_hops :: proc(t: ^testing.T) {
	a: app.App
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)

	testing.expect_value(t, app.page_footer_left(&a), "Ren TUI")

	node: [store.HASH_LEN]u8
	node[0] = 7
	store.directory_upsert(&a.directory, node, node, .Nomad_Node, "n", nil, 4)
	a.page_node = node
	a.page_has_node = true
	left := app.page_footer_left(&a)
	testing.expect(t, strings.contains(left, "Ren TUI"))
	testing.expect(t, strings.contains(left, "hops=4"))

	a.page_source = strings.clone("abcdefghij")
	defer delete(a.page_source)
	left = app.page_footer_left(&a)
	testing.expect(t, strings.contains(left, "hops=4"))
	testing.expect(t, strings.contains(left, "10B"))

	store.directory_upsert(&a.directory, node, node, .Nomad_Node, "n", nil, 0)
	// known hops preserved against announce 0
	left = app.page_footer_left(&a)
	testing.expect(t, strings.contains(left, "hops=4"))
}

@(test)
test_iface_cache_keeps_snapshot_on_empty_poll :: proc(t: ^testing.T) {
	a: app.App
	append(&a.ifaces, app.Iface_View{
		name = strings.clone("tcp"),
		type_n = strings.clone("TCP"),
		online = true,
		enabled = true,
	})
	// session not started -> list returns 0, must not wipe cache
	app.refresh_iface_cache(&a)
	testing.expect_value(t, len(a.ifaces), 1)
	testing.expect_value(t, a.ifaces[0].name, "tcp")
	delete(a.ifaces[0].name)
	delete(a.ifaces[0].type_n)
	delete(a.ifaces)
}

@(test)
test_page_loading_spinner_cycles :: proc(t: ^testing.T) {
	testing.expect_value(t, app.page_loading_spinner(0), "|")
	testing.expect_value(t, app.page_loading_spinner(1), "/")
	testing.expect_value(t, app.page_loading_spinner(2), "-")
	testing.expect_value(t, app.page_loading_spinner(3), "\\")
	testing.expect_value(t, app.page_loading_spinner(4), "|")
}
