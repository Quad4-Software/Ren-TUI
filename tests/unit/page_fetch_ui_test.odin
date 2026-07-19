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

	testing.expect(t, strings.has_prefix(app.page_footer_left(&a), "Ren TUI"))

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
	_ = app.refresh_iface_cache(&a)
	testing.expect_value(t, len(a.ifaces), 1)
	testing.expect_value(t, a.ifaces[0].name, "tcp")
	delete(a.ifaces[0].name)
	delete(a.ifaces[0].type_n)
	delete(a.ifaces)
}

@(test)
test_iface_cache_partial_poll_uses_miss_grace :: proc(t: ^testing.T) {
	ifaces: [dynamic]app.Iface_View
	defer {
		for &iface in ifaces {
			delete(iface.name)
			delete(iface.type_n)
		}
		delete(ifaces)
	}
	append(&ifaces, app.Iface_View{name = strings.clone("a"), type_n = strings.clone("TCP"), online = true})
	append(&ifaces, app.Iface_View{name = strings.clone("b"), type_n = strings.clone("UDP"), online = true})
	append(&ifaces, app.Iface_View{name = strings.clone("c"), type_n = strings.clone("Auto"), online = false})

	// Partial poll: only a present. Others must remain for IFACE_MISS_LIMIT-1 polls.
	only_a := []net.Iface_Info{{name = "a", type_n = "TCP", online = true, enabled = true}}
	for _ in 0 ..< app.IFACE_MISS_LIMIT - 1 {
		changed := app.apply_iface_infos(&ifaces, only_a)
		_ = changed
		testing.expect_value(t, len(ifaces), 3)
	}
	_ = app.apply_iface_infos(&ifaces, only_a)
	testing.expect_value(t, len(ifaces), 1)
	testing.expect_value(t, ifaces[0].name, "a")
}

@(test)
test_iface_sort_stable_by_name_not_online :: proc(t: ^testing.T) {
	ifaces: [dynamic]app.Iface_View
	defer {
		for &iface in ifaces {
			delete(iface.name)
			delete(iface.type_n)
		}
		delete(ifaces)
	}
	append(&ifaces, app.Iface_View{name = strings.clone("zeta"), type_n = strings.clone("TCP"), online = true})
	append(&ifaces, app.Iface_View{name = strings.clone("alpha"), type_n = strings.clone("UDP"), online = false})
	_ = app.sort_ifaces_by_name(&ifaces)
	testing.expect_value(t, ifaces[0].name, "alpha")
	testing.expect_value(t, ifaces[1].name, "zeta")

	infos := []net.Iface_Info{
		{name = "zeta", type_n = "TCP", online = false, enabled = true},
		{name = "alpha", type_n = "UDP", online = true, enabled = true},
	}
	_ = app.apply_iface_infos(&ifaces, infos)
	testing.expect_value(t, ifaces[0].name, "alpha")
	testing.expect_value(t, ifaces[1].name, "zeta")
	testing.expect(t, ifaces[0].online)
	testing.expect(t, !ifaces[1].online)
}

@(test)
test_page_loading_spinner_cycles :: proc(t: ^testing.T) {
	testing.expect_value(t, app.page_loading_spinner(0), "|")
	testing.expect_value(t, app.page_loading_spinner(1), "/")
	testing.expect_value(t, app.page_loading_spinner(2), "-")
	testing.expect_value(t, app.page_loading_spinner(3), "\\")
	testing.expect_value(t, app.page_loading_spinner(4), "|")
}

@(test)
test_footer_keybinds_page_and_conversations :: proc(t: ^testing.T) {
	a: app.App
	a.tab = .Page
	a.page_source = "hi"
	keys := app.footer_keybinds(&a)
	testing.expect(t, strings.contains(keys, "s source"))
	testing.expect(t, strings.contains(keys, "d save"))
	testing.expect(t, strings.contains(keys, "i id"))
	a.tab = .Conversations
	keys = app.footer_keybinds(&a)
	testing.expect(t, strings.contains(keys, "search"))
}

@(test)
test_page_node_display_name_known :: proc(t: ^testing.T) {
	a: app.App
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)
	node: [store.HASH_LEN]u8
	node[0] = 0xab
	store.directory_upsert(&a.directory, node, node, .Nomad_Node, "MoonGate", nil, 0)
	testing.expect_value(t, app.page_node_display_name(&a, node), "MoonGate")
	other: [store.HASH_LEN]u8
	other[0] = 0xcd
	testing.expect_value(t, app.page_node_display_name(&a, other), "unknown node")
}
