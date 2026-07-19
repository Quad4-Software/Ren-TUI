// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Maps keyboard and mouse events into app behavior.
*/

package app

import "core:fmt"

import "ren:micron"
import "ren:net"
import "ren:ui"

on_event :: proc(ev: ui.Event, user: rawptr) -> bool {
	a := cast(^App)user
	prev_status := a.session.status
	prev_ann := a.session.announces
	net.session_poll(&a.session, &a.directory, &a.conversations, &a.cfg, a.cfg.auto_announce)
	page_poll_result(a)
	if a.session.announces > prev_ann {
		set_status(a, fmt.tprintf("announced (#%d)", a.session.announces), STATUS_HOLD)
		mark_dirty(a)
	} else if a.session.status == "message received" && prev_status != "message received" {
		set_status(a, "message received", STATUS_HOLD)
		a.recv_count += 1
		mark_dirty(a)
	}
	// Rebuild lists when directory changed while on Network (incl. while away then returned).
	if a.tab == .Network {
		if a.directory.revision != a.net_dir_rev || a.net_filter_tick != a.net_filter_applied {
			refresh_network_list_if_needed(a)
			mark_dirty(a)
		}
	}
	if a.tab == .Page || net.session_page_busy(&a.session) {
		mark_dirty(a)
	}
	a.poll_ticks += 1
	if a.poll_ticks % 20 == 0 {
		if a.tab == .Interfaces {
			refresh_iface_cache(a)
		}
		mark_dirty(a)
	} else if a.tab == .Interfaces && ev.kind != .None {
		refresh_iface_cache(a)
		mark_dirty(a)
	}
	update_status(a)
	if ev.kind != .None {
		mark_dirty(a)
	}

	if ev.kind == .Ctrl_R {
		if a.online {
			net.session_announce(&a.session)
			set_status(a, fmt.tprintf("announced (#%d)", a.session.announces), STATUS_HOLD)
		}
		return false
	}

	if ev.kind == .Mouse {
		handle_mouse(a, ev)
		return false
	}

	if a.config_editing {
		if ev.kind == .Esc {
			a.config_editing = false
			ui.input_clear(&a.config_edit)
			return false
		}
		if ev.kind == .Enter {
			apply_config_edit(a)
			return false
		}
		_ = ui.input_handle(&a.config_edit, ev)
		return false
	}

	if a.url_editing {
		if ev.kind == .Esc {
			a.url_editing = false
			ui.input_clear(&a.url_edit)
			return false
		}
		if ev.kind == .Enter {
			page_apply_url_edit(a)
			return false
		}
		_ = ui.input_handle(&a.url_edit, ev)
		return false
	}

	if a.net_searching {
		if ev.kind == .Esc {
			a.net_searching = false
			return false
		}
		if ev.kind == .Enter {
			a.net_searching = false
			a.net_filter_tick += 1
			refresh_network_list_if_needed(a)
			return false
		}
		_ = ui.input_handle(&a.net_search, ev)
		a.net_filter_tick += 1
		refresh_network_list_if_needed(a)
		return false
	}

	if a.conv_searching {
		if ev.kind == .Esc {
			a.conv_searching = false
			return false
		}
		if ev.kind == .Enter {
			a.conv_searching = false
			refresh_conv_list(a)
			return false
		}
		_ = ui.input_handle(&a.conv_search, ev)
		refresh_conv_list(a)
		return false
	}

	if net.session_page_busy(&a.session) && ev.kind == .Esc {
		net.session_page_cancel(&a.session)
		set_status(a, "page fetch cancelled", STATUS_HOLD)
		return false
	}

	#partial switch ev.kind {
	case .Rune:
		if a.tab != .Compose {
			switch ev.ch {
			case '1':
				a.tab = .Conversations
				refresh_conv_list(a)
			case '2':
				show_network_tab(a)
			case '3':
				a.tab = .Page
			case '4':
				a.tab = .Interfaces
			case '5':
				a.tab = .Compose
			case '6':
				a.tab = .Config
				refresh_config_list(a)
			case '7':
				a.tab = .Guide
			case '/':
				if a.tab == .Network {
					a.net_searching = true
					set_status(a, "search peers  Enter done  Esc cancel", STATUS_HOLD)
				} else if a.tab == .Conversations {
					a.conv_searching = true
					set_status(a, "search conversations  Enter done  Esc cancel", STATUS_HOLD)
				}
			case 'l', 'L':
				if a.tab == .Network {
					a.net_view = .Lxmf
					a.net_filter_tick += 1
					refresh_network_list_if_needed(a)
				}
			case 'n', 'N':
				if a.tab == .Network {
					a.net_view = .Nomad
					a.net_filter_tick += 1
					refresh_network_list_if_needed(a)
				}
			case 'p', 'P':
				if a.tab == .Network {
					a.net_view = .Propagation
					a.net_filter_tick += 1
					refresh_network_list_if_needed(a)
				}
			case 'i', 'I':
				if a.tab == .Network || a.tab == .Page {
					try_identify_node(a)
				}
			case 's', 'S':
				if a.tab == .Page {
					page_toggle_raw(a)
				}
			case 'g', 'G':
				if a.tab == .Page || a.tab == .Network {
					page_start_url_edit(a)
				}
			case '[':
				if a.tab == .Page {
					a.page_scroll = max(0, a.page_scroll - 1)
				}
			case ']':
				if a.tab == .Page {
					a.page_scroll += 1
				}
			}
			return false
		}
	case .Tab:
		if a.tab == .Compose {
			a.compose_focus = (a.compose_focus + 1) % 2
			return false
		}
		if a.tab == .Page && !a.page_view_raw && !a.url_editing && micron.doc_link_count(a.page_doc) > 0 {
			page_cycle_link(a, 1)
			return false
		}
		a.tab = Tab((int(a.tab) + 1) % TAB_COUNT)
		switch a.tab {
		case .Network:
			show_network_tab(a)
		case .Conversations:
			refresh_conv_list(a)
		case .Config:
			refresh_config_list(a)
		case .Page, .Interfaces, .Compose, .Guide:
		}
		return false
	case .Backtab:
		if a.tab == .Page && !a.page_view_raw && !a.url_editing && micron.doc_link_count(a.page_doc) > 0 {
			page_cycle_link(a, -1)
			return false
		}
		a.tab = Tab((int(a.tab) + TAB_COUNT - 1) % TAB_COUNT)
		switch a.tab {
		case .Network:
			show_network_tab(a)
		case .Conversations:
			refresh_conv_list(a)
		case .Config:
			refresh_config_list(a)
		case .Page, .Interfaces, .Compose, .Guide:
		}
		return false
	}

	switch a.tab {
	case .Conversations:
		visible := max(1, a.list_rect.h)
		if ev.kind == .Up {
			ui.list_move(&a.conv_list, -1, visible)
			a.msg_scroll = 0
		} else if ev.kind == .Down {
			ui.list_move(&a.conv_list, 1, visible)
			a.msg_scroll = 0
		} else if ev.kind == .Page_Up {
			a.msg_scroll = max(0, a.msg_scroll - visible)
		} else if ev.kind == .Page_Down {
			a.msg_scroll += visible
		}
	case .Network:
		visible := network_list_visible(a)
		if ev.kind == .Up {
			network_move(a, -1, visible)
		} else if ev.kind == .Down {
			network_move(a, 1, visible)
		} else if ev.kind == .Page_Up {
			network_move(a, -visible, visible)
		} else if ev.kind == .Page_Down {
			network_move(a, visible, visible)
		} else if ev.kind == .Enter {
			try_fetch_selected_node(a)
		}
	case .Page:
		visible := max(1, a.detail_rect.h)
		if ev.kind == .Up || ev.kind == .Page_Up {
			a.page_scroll = max(0, a.page_scroll - (visible if ev.kind == .Page_Up else 1))
		} else if ev.kind == .Down || ev.kind == .Page_Down {
			a.page_scroll += visible if ev.kind == .Page_Down else 1
		} else if ev.kind == .Enter && !a.page_view_raw && !a.url_editing {
			page_activate_focused_link(a)
		} else if ev.kind == .Esc && a.page_source != "" && !a.url_editing {
			show_network_tab(a)
		}
	case .Interfaces:
		if ev.kind == .Up {
			a.iface_scroll = max(0, a.iface_scroll - 1)
		} else if ev.kind == .Down {
			a.iface_scroll += 1
		} else if ev.kind == .Page_Up {
			a.iface_scroll = max(0, a.iface_scroll - 3)
		} else if ev.kind == .Page_Down {
			a.iface_scroll += 3
		}
	case .Compose:
		if a.compose_focus == 0 {
			_ = ui.input_handle(&a.compose_to, ev)
		} else {
			_ = ui.input_handle(&a.compose_body, ev)
		}
		if ev.kind == .Enter {
			try_send(a)
		}
	case .Config:
		visible := max(1, a.list_rect.h)
		if ev.kind == .Up {
			ui.list_move(&a.config_list, -1, visible)
		} else if ev.kind == .Down {
			ui.list_move(&a.config_list, 1, visible)
		} else if ev.kind == .Enter {
			config_activate(a)
		}
	case .Guide:
		if ev.kind == .Up {
			a.guide_scroll = max(0, a.guide_scroll - 1)
		} else if ev.kind == .Down {
			a.guide_scroll += 1
		}
	}
	return false
}

handle_mouse :: proc(a: ^App, ev: ui.Event) {
	if ev.mouse_scroll != 0 {
		switch a.tab {
		case .Conversations:
			if point_in_rect(ev.mouse_x, ev.mouse_y, a.detail_rect) {
				a.msg_scroll = max(0, a.msg_scroll + ev.mouse_scroll)
			} else {
				ui.list_move(&a.conv_list, ev.mouse_scroll, max(1, a.list_rect.h))
			}
		case .Network:
			network_move(a, ev.mouse_scroll, network_list_visible(a))
		case .Page:
			a.page_scroll = max(0, a.page_scroll + ev.mouse_scroll)
		case .Interfaces:
			a.iface_scroll = max(0, a.iface_scroll + ev.mouse_scroll)
		case .Config:
			ui.list_move(&a.config_list, ev.mouse_scroll, max(1, a.list_rect.h))
		case .Guide:
			a.guide_scroll = max(0, a.guide_scroll + ev.mouse_scroll)
		case .Compose:
		}
		return
	}
	if !ev.mouse_down || ev.mouse_btn != 0 {
		return
	}
	if point_in_rect(ev.mouse_x, ev.mouse_y, a.tab_rect) {
		click_tab(a, ev.mouse_x)
		return
	}
	if a.tab == .Config {
		if point_in_rect(ev.mouse_x, ev.mouse_y, a.lxmf_addr_rect) {
			hex := net.session_delivery_hex(&a.session, context.temp_allocator)
			if ui.clipboard_copy(hex) {
				set_status(a, "LXMF address copied", STATUS_HOLD)
			} else {
				set_status(a, "copy failed", STATUS_HOLD)
			}
			return
		}
		if point_in_rect(ev.mouse_x, ev.mouse_y, a.identity_rect) {
			hex := net.session_identity_hex(&a.session, context.temp_allocator)
			if ui.clipboard_copy(hex) {
				set_status(a, "identity copied", STATUS_HOLD)
			} else {
				set_status(a, "copy failed", STATUS_HOLD)
			}
			return
		}
	}
	if point_in_rect(ev.mouse_x, ev.mouse_y, a.list_rect) {
		row := ev.mouse_y - a.list_rect.y
		visible := max(1, a.list_rect.h)
		switch a.tab {
		case .Conversations:
			ui.list_click(&a.conv_list, row, visible)
			a.msg_scroll = 0
		case .Network:
			ui.list_click(&a.net_list, row, network_list_visible(a))
			network_skip_header(a, 1, network_list_visible(a))
		case .Config:
			ui.list_click(&a.config_list, row, visible)
		case .Interfaces, .Compose, .Guide, .Page:
		}
		return
	}
	if a.tab == .Page && point_in_rect(ev.mouse_x, ev.mouse_y, a.detail_rect) {
		_ = page_click_link_at(a, ev.mouse_x, ev.mouse_y)
	}
}

network_move :: proc(a: ^App, delta, visible: int) {
	ui.list_move(&a.net_list, delta, visible)
	network_skip_header(a, delta, visible)
}

network_skip_header :: proc(a: ^App, direction, visible: int) {
	if len(a.net_peer_idx) == 0 {
		return
	}
	dir := 1 if direction >= 0 else -1
	for _ in 0 ..< len(a.net_peer_idx) {
		sel := a.net_list.selected
		if sel < 0 || sel >= len(a.net_peer_idx) {
			return
		}
		if a.net_peer_idx[sel] >= 0 {
			ui.list_ensure_visible(&a.net_list, visible)
			return
		}
		next := sel + dir
		if next < 0 || next >= len(a.net_list.items) {
			return
		}
		a.net_list.selected = next
	}
	ui.list_ensure_visible(&a.net_list, visible)
}

point_in_rect :: proc(x, y: int, r: ui.Rect) -> bool {
	return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h
}

click_tab :: proc(a: ^App, x: int) {
	cx := a.tab_rect.x + 1
	for label, i in TAB_LABELS {
		w := len(label)
		if x >= cx && x < cx + w {
			a.tab = Tab(i)
			switch a.tab {
			case .Network:
				show_network_tab(a)
			case .Conversations:
				refresh_conv_list(a)
			case .Config:
				refresh_config_list(a)
			case .Page, .Interfaces, .Compose, .Guide:
			}
			mark_dirty(a)
			return
		}
		cx += w + 2
	}
}
