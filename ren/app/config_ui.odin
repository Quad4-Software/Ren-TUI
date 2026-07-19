// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Config tab row activation and inline edit handling.
*/

package app

import "core:fmt"
import "core:strconv"
import "core:strings"

import "ren:constants"
import "ren:net"
import "ren:store"
import "ren:ui"

config_activate :: proc(a: ^App) {
	row := Config_Row(a.config_list.selected)
	switch row {
	case .Name:
		start_config_edit(a, a.cfg.display_name)
	case .Auto_Announce:
		a.cfg.auto_announce = !a.cfg.auto_announce
		refresh_lists(a)
	case .Interval:
		start_config_edit(a, fmt.tprintf("%d", a.cfg.announce_interval_sec))
	case .Color:
		cycle_color_mode(a)
	case .Theme:
		cycle_theme(a)
	case .Mouse:
		a.cfg.mouse = !a.cfg.mouse
		refresh_lists(a)
	case .Obfuscate_Hops:
		a.cfg.obfuscate_hops = !a.cfg.obfuscate_hops
		refresh_lists(a)
		set_status(a, "obfuscate hops toggled (Save writes RNS local_hops_delta)", STATUS_HOLD)
	case .Restart:
		restart_stack(a)
	case .Save:
		if store.config_save(&a.cfg) {
			apply_runtime_config(a)
			set_status(a, "config saved", STATUS_HOLD)
		} else {
			set_status(a, "config save failed", STATUS_HOLD)
		}
	case .Count:
	}
}

restart_stack :: proc(a: ^App) {
	set_status(a, "restarting network stack...", STATUS_HOLD)
	ok := net.session_restart(&a.session, &a.cfg)
	a.online = ok
	if ok {
		set_status(a, "network stack restarted", STATUS_HOLD)
	} else {
		set_status(a, a.session.status if a.session.status != "" else "restart failed", STATUS_HOLD)
	}
	refresh_lists(a)
	update_status(a)
}

start_config_edit :: proc(a: ^App, value: string) {
	ui.input_clear(&a.config_edit)
	strings.write_string(&a.config_edit.text, value)
	a.config_edit.cursor = len(value)
	a.config_editing = true
}

apply_config_edit :: proc(a: ^App) {
	val := strings.trim_space(ui.input_value(&a.config_edit))
	row := Config_Row(a.config_list.selected)
	switch row {
	case .Name:
		if val != "" {
			delete(a.cfg.display_name)
			a.cfg.display_name = strings.clone(val)
			net.session_set_display_name(&a.session, a.cfg.display_name)
		}
	case .Interval:
		if n, ok := strconv.parse_int(val); ok && n >= constants.MIN_ANNOUNCE_INTERVAL_SEC {
			a.cfg.announce_interval_sec = n
			net.session_set_announce_interval(&a.session, n)
		} else {
			set_status(a, fmt.tprintf("interval min %d", constants.MIN_ANNOUNCE_INTERVAL_SEC), STATUS_HOLD)
			a.config_editing = false
			ui.input_clear(&a.config_edit)
			return
		}
	case .Auto_Announce, .Color, .Theme, .Mouse, .Obfuscate_Hops, .Restart, .Save, .Count:
	}
	a.config_editing = false
	ui.input_clear(&a.config_edit)
	refresh_lists(a)
	update_status(a)
}

cycle_color_mode :: proc(a: ^App) {
	modes := []string{"auto", "256", "full", "compat", "dumb"}
	idx := 0
	for m, i in modes {
		if m == a.cfg.color_mode {
			idx = i
			break
		}
	}
	next := modes[(idx + 1) % len(modes)]
	delete(a.cfg.color_mode)
	a.cfg.color_mode = strings.clone(next)
	refresh_lists(a)
}

cycle_theme :: proc(a: ^App) {
	names := ui.theme_names()
	idx := 0
	for n, i in names {
		if n == a.cfg.theme_name {
			idx = i
			break
		}
	}
	next := names[(idx + 1) % len(names)]
	delete(a.cfg.theme_name)
	a.cfg.theme_name = strings.clone(next)
	store.config_apply_theme(&a.cfg)
	refresh_lists(a)
}

apply_runtime_config :: proc(a: ^App) {
	net.session_set_display_name(&a.session, a.cfg.display_name)
	net.session_set_announce_interval(&a.session, a.cfg.announce_interval_sec)
	store.config_apply_theme(&a.cfg)
	update_status(a)
}
