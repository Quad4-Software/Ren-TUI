// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
App startup shutdown and wiring into the UI loop.
*/

package app

import "core:fmt"
import "core:path/filepath"
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
	store.directory_load_spill_meta(&a.directory)
	store.conversations_init(&a.conversations)
	store.conversations_load(&a.conversations, &a.cfg)
	ui.list_init(&a.conv_list)
	ui.list_init(&a.net_list)
	ui.list_init(&a.config_list)
	ui.input_init(&a.compose_to)
	ui.input_init(&a.compose_body)
	ui.input_init(&a.config_edit)
	ui.input_init(&a.url_edit)
	ui.input_init(&a.net_search)
	ui.input_init(&a.conv_search)
	a.page_hits = make([dynamic]micron.Link_Hit)
	a.page_link_focus = -1
	a.net_peer_idx = make([dynamic]int)
	a.ifaces = make([dynamic]Iface_View)
	a.tab = .Network
	a.net_view = .Nomad
	a.ui_dirty = true
	a.status_left = version.line(context.temp_allocator)
	a.status_right = "starting"

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
	net.session_close(&a.session)
	ui.input_destroy(&a.compose_to)
	ui.input_destroy(&a.compose_body)
	ui.input_destroy(&a.config_edit)
	ui.input_destroy(&a.url_edit)
	ui.input_destroy(&a.net_search)
	ui.input_destroy(&a.conv_search)
	ui.list_destroy(&a.conv_list)
	ui.list_destroy(&a.net_list)
	ui.list_destroy(&a.config_list)
	page_clear(a)
	delete(a.page_hits)
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
	n := min(len(msg), len(a.status_hold))
	copy(a.status_hold[:n], transmute([]u8)msg[:n])
	a.status_hold_len = n
	a.status_until = time.tick_add(time.tick_now(), hold)
	a.status_right = string(a.status_hold[:n])
	mark_dirty(a)
}

update_status :: proc(a: ^App) {
	a.status_left = fmt.tprintf("%s  %s", a.cfg.display_name, version.VERSION)
	if net.session_page_busy(&a.session) {
		a.status_right = net.session_page_status(&a.session)
		return
	}
	if a.status_hold_len > 0 && time.tick_diff(time.tick_now(), a.status_until) > 0 {
		a.status_right = string(a.status_hold[:a.status_hold_len])
		return
	}
	a.status_hold_len = 0
	if a.online {
		stats := net.session_stats_line(&a.session, &a.directory, context.temp_allocator)
		a.status_right = fmt.tprintf("%s  %s", a.session.status, stats)
	} else {
		a.status_right = a.session.status if a.session.status != "" else "offline"
	}
}
run :: proc(opts: ^cli.Options = nil) -> int {
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
