// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
App startup shutdown and wiring into the UI loop.
*/

package app

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "ren:cli"
import "ren:constants"
import "ren:micron"
import "ren:net"
import "ren:store"
import "ren:ui"
import "ren:version"

app_init :: proc(a: ^App, opts: ^cli.Options = nil) -> bool {
	a^ = {}
	a.cfg = store.config_default()
	if opts != nil {
		cli.apply_to_config(&a.cfg, opts)
	}
	_ = store.config_ensure_dirs(&a.cfg)
	store.config_load(&a.cfg)
	store.config_write_defaults_if_missing(&a.cfg)

	store.directory_init(&a.directory)
	store.directory_bind_spill(&a.directory, &a.cfg)
	store.directory_load_all(&a.directory, &a.cfg)
	store.conversations_init(&a.conversations)
	store.conversations_load(&a.conversations, &a.cfg)
	ui.list_init(&a.conv_list)
	ui.list_init(&a.net_list)
	ui.list_init(&a.config_list)
	ui.input_init(&a.compose_to)
	ui.input_init(&a.compose_body)
	a.compose_method = a.cfg.send_method
	ui.input_init(&a.conv_reply)
	ui.input_init(&a.conv_rename)
	ui.input_init(&a.config_edit)
	ui.input_init(&a.url_edit)
	ui.input_init(&a.net_search)
	ui.input_init(&a.conv_search)
	a.page_hits = make([dynamic]micron.Link_Hit)
	a.page_link_focus = -1
	a.page_field_focus = -1
	a.page_form = make([dynamic]Page_Form_Input)
	a.conv_peer_idx = make([dynamic]int)
	a.net_peer_idx = make([dynamic]int)
	a.ifaces = make([dynamic]Iface_View)
	a.tab = .Network
	a.net_view = .Nomad
	a.ui_dirty = true
	a.status_left = status_copy_buf(a.status_left_buf[:], nil, version.line(context.temp_allocator))
	a.status_right = status_copy_buf(a.status_hold[:], &a.status_hold_len, "starting")

	log_path, _ := filepath.join({a.cfg.data_dir, constants.LIBRNS_LOG_FILE})
	_ = ui.stderr_redirect_start(&a.stderr_redir, log_path)

	if !ui.loop_init(&a.loop, a.cfg.color_mode, a.cfg.mouse) {
		ui.stderr_redirect_stop(&a.stderr_redir)
		return false
	}
	config_apply_theme(&a.cfg)

	ok := net.session_create(&a.session, &a.cfg, a.cfg.display_name)
	if ok {
		a.online = net.session_start(&a.session)
	}
	if a.online {
		set_status(a, "online announced", STATUS_HOLD)
	} else {
		set_status(a, a.session.status if a.session.status != "" else "offline", STATUS_HOLD)
	}
	update_status(a)
	refresh_lists(a)
	return true
}

app_close :: proc(a: ^App) {
	_ = store.conversations_save_all(&a.conversations, &a.cfg)
	_ = store.directory_save_all(&a.directory)
	net.session_close(&a.session)
	ui.input_destroy(&a.compose_to)
	ui.input_destroy(&a.compose_body)
	ui.input_destroy(&a.conv_reply)
	ui.input_destroy(&a.conv_rename)
	ui.input_destroy(&a.config_edit)
	ui.input_destroy(&a.url_edit)
	ui.input_destroy(&a.net_search)
	ui.input_destroy(&a.conv_search)
	ui.list_destroy(&a.conv_list)
	ui.list_destroy(&a.net_list)
	ui.list_destroy(&a.config_list)
	page_clear(a)
	delete(a.page_hits)
	delete(a.page_form)
	delete(a.conv_peer_idx)
	delete(a.net_peer_idx)
	for &iface in a.ifaces {
		delete(iface.name)
		delete(iface.type_n)
	}
	delete(a.ifaces)
	store.conversations_destroy(&a.conversations)
	store.directory_destroy(&a.directory)
	ui.loop_close(&a.loop)
	ui.stderr_redirect_stop(&a.stderr_redir)
}

set_status :: proc(a: ^App, msg: string, hold: time.Duration) {
	a.status_right = status_copy_buf(a.status_hold[:], &a.status_hold_len, msg)
	a.status_until = time.tick_add(time.tick_now(), hold)
	mark_dirty(a)
}

update_status :: proc(a: ^App) {
	left := page_footer_left(a)
	a.status_left = status_copy_buf(a.status_left_buf[:], nil, left)
	if net.session_page_busy(&a.session) {
		a.status_right = status_copy_buf(a.status_hold[:], &a.status_hold_len, net.session_page_status(&a.session))
		return
	}
	if a.status_hold_len > 0 && a.tab != .Page && time.tick_diff(time.tick_now(), a.status_until) > 0 {
		a.status_right = string(a.status_hold[:a.status_hold_len])
		return
	}
	a.status_hold_len = 0
	// Page view stays free of announce directory stats (hot/cold/ann).
	if a.tab == .Page {
		if a.online {
			msg := a.session.status if a.session.status != "" else "online"
			a.status_right = status_copy_buf(a.status_hold[:], &a.status_hold_len, msg)
		} else {
			a.status_right = status_copy_buf(a.status_hold[:], &a.status_hold_len, "offline")
		}
		return
	}
	if a.online {
		stats := net.session_stats_line(&a.session, &a.directory, context.temp_allocator)
		msg := fmt.tprintf("%s  %s", a.session.status, stats)
		a.status_right = status_copy_buf(a.status_hold[:], &a.status_hold_len, msg)
	} else {
		msg := a.session.status if a.session.status != "" else "offline"
		a.status_right = status_copy_buf(a.status_hold[:], &a.status_hold_len, msg)
	}
}

// Copy into a fixed buffer so status strings survive temp-allocator free_all.
status_copy_buf :: proc(buf: []u8, len_out: ^int, msg: string) -> string {
	n := min(len(msg), len(buf))
	if n > 0 {
		copy(buf[:n], transmute([]u8)msg[:n])
	}
	if len_out != nil {
		len_out^ = n
	}
	return string(buf[:n])
}

page_footer_left :: proc(a: ^App) -> string {
	node, has := page_active_node(a)
	size := page_footer_size(a)
	base := "Ren TUI"
	if has {
		hops_part := "hops=?"
		if hops, ok := page_node_hops(a, node); ok {
			hops_part = fmt.tprintf("hops=%d", hops)
		}
		if size != "" {
			base = fmt.tprintf("Ren TUI  %s  %s", hops_part, size)
		} else {
			base = fmt.tprintf("Ren TUI  %s", hops_part)
		}
	} else if size != "" {
		base = fmt.tprintf("Ren TUI  %s", size)
	}
	keys := footer_keybinds(a)
	if keys == "" {
		return base
	}
	return fmt.tprintf("%s  %s", base, keys)
}

footer_keybinds :: proc(a: ^App) -> string {
	switch a.tab {
	case .Page:
		if net.session_page_busy(&a.session) {
			return "Esc cancel"
		}
		if a.page_error != "" && a.page_source == "" {
			return "g retry  Esc Network"
		}
		if a.page_source != "" {
			return "g URL  s source  d save  i id  Tab focus"
		}
		return "g URL  Esc Network"
	case .Conversations:
		return "r rename  Enter reply  / search  Up/Dn list  PgUp/Dn msgs"
	case .Network:
		return "l/n/p views  / search  Enter set/open  u sync"
	case .Interfaces:
		return "Up/Dn scroll"
	case .Compose:
		return "Tab fields  m method  Enter send"
	case .Config:
		return "Enter edit/toggle  Up/Dn"
	case .Guide:
		return "Up/Dn scroll"
	}
	return ""
}

page_footer_size :: proc(a: ^App) -> string {
	n := len(a.page_source)
	if n == 0 {
		return ""
	}
	return format_byte_count(u64(n))
}

page_active_node :: proc(a: ^App) -> (node: [store.HASH_LEN]u8, ok: bool) {
	if net.session_page_busy(&a.session) {
		return a.session.page.node, true
	}
	if a.page_has_node {
		return a.page_node, true
	}
	return {}, false
}

page_node_hops :: proc(a: ^App, node: [store.HASH_LEN]u8) -> (hops: u8, ok: bool) {
	if e, pok := net.path_hot_lookup(&a.session.paths, node); pok && e.hops > 0 {
		return e.hops, true
	}
	for p in a.directory.peers {
		if p.hash == node {
			if !p.hops_known || p.hops == 0 {
				return 0, false
			}
			return p.hops, true
		}
	}
	return 0, false
}

// True when Page-tab status omits directory announce stats (hot/cold/ann).
page_status_omits_announce_stats :: proc(a: ^App) -> bool {
	update_status(a)
	s := a.status_right
	if strings.contains(s, "hot:") || strings.contains(s, "cold:") {
		return false
	}
	if strings.contains(s, "ann:") {
		return false
	}
	return true
}

run :: proc(opts: ^cli.Options = nil) -> int {
	if opts != nil && opts.daemon {
		return run_daemon(opts)
	}
	a: App
	if !app_init(&a, opts) {
		fmt.eprintln("ren-tui: failed to start UI")
		return 1
	}
	defer app_close(&a)
	ui.loop_run(&a.loop, draw_app, on_event, &a, app_is_dirty)
	return 0
}

app_is_dirty :: proc(user: rawptr) -> bool {
	a := cast(^App)user
	if a.ui_dirty {
		a.ui_dirty = false
		return true
	}
	return false
}
