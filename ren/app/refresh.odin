// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Rebuilds list widgets from live app state.
*/

package app

import "core:fmt"
import "core:strings"

import "ren:constants"
import "ren:net"
import "ren:store"
import "ren:ui"

refresh_lists :: proc(a: ^App) {
	refresh_conv_list(a)
	refresh_network_list_if_needed(a)
	refresh_iface_cache(a)
	refresh_config_list(a)
	a.ui_dirty = true
}

refresh_conv_list :: proc(a: ^App) {
	prev_conv := a.conv_list.selected
	prev_conv_scroll := a.conv_list.scroll
	ui.list_clear(&a.conv_list)
	q := strings.to_lower(strings.trim_space(ui.input_value(&a.conv_search)), context.temp_allocator)
	for conv in a.conversations.items {
		label := store.directory_label(&a.directory, conv.peer_hash)
		hex := store.hash_hex(conv.peer_hash, context.temp_allocator)
		if q != "" {
			lq := strings.to_lower(label, context.temp_allocator)
			if !strings.contains(lq, q) && !strings.contains(hex, q) {
				delete(label)
				continue
			}
		}
		unread := ""
		if conv.unread > 0 {
			unread = fmt.tprintf(" (%d)", conv.unread)
		}
		ui.list_push(&a.conv_list, fmt.tprintf("%s%s", label, unread))
		delete(label)
	}
	if len(a.conv_list.items) > 0 {
		a.conv_list.selected = clamp(prev_conv, 0, len(a.conv_list.items) - 1)
		a.conv_list.scroll = clamp(prev_conv_scroll, 0, max(0, len(a.conv_list.items) - 1))
		ui.list_ensure_visible(&a.conv_list, max(1, a.list_rect.h))
	}
}

refresh_config_list :: proc(a: ^App) {
	prev_cfg := a.config_list.selected
	ui.list_clear(&a.config_list)
	ui.list_push(&a.config_list, fmt.tprintf("Name: %s", a.cfg.display_name))
	ui.list_push(&a.config_list, fmt.tprintf("Auto announce: %s", "yes" if a.cfg.auto_announce else "no"))
	ui.list_push(&a.config_list, fmt.tprintf("Announce interval: %ds", a.cfg.announce_interval_sec))
	ui.list_push(&a.config_list, fmt.tprintf("Color: %s", a.cfg.color_mode))
	ui.list_push(&a.config_list, fmt.tprintf("Theme: %s", a.cfg.theme_name))
	ui.list_push(&a.config_list, fmt.tprintf("Mouse: %s", "yes" if a.cfg.mouse else "no"))
	ui.list_push(&a.config_list, fmt.tprintf("Obfuscate hops: %s", "yes" if a.cfg.obfuscate_hops else "no"))
	dl := a.cfg.download_dir if a.cfg.download_dir != "" else fmt.tprintf("(default %s/%s)", a.cfg.data_dir, constants.DOWNLOADS_DIR)
	ui.list_push(&a.config_list, fmt.tprintf("Download dir: %s", dl))
	ui.list_push(&a.config_list, "Restart Network Stack")
	ui.list_push(&a.config_list, "Save config")
	a.config_list.selected = clamp(prev_cfg, 0, len(a.config_list.items) - 1)
}

refresh_network_list_if_needed :: proc(a: ^App) {
	need := a.directory.revision != a.net_dir_rev ||
		a.net_filter_tick != a.net_filter_applied ||
		len(a.net_list.items) == 0
	if !need {
		return
	}
	refresh_network_list(a, a.net_list.selected, a.net_list.scroll)
	a.net_dir_rev = a.directory.revision
	a.net_filter_applied = a.net_filter_tick
}

// Always rebuild Network list. Use when returning from Page so peer idxs match
// directory after announces / hot-cap eviction while away.
show_network_tab :: proc(a: ^App) {
	switch_tab(a, .Network)
	refresh_network_list(a, a.net_list.selected, a.net_list.scroll)
	a.net_dir_rev = a.directory.revision
	a.net_filter_applied = a.net_filter_tick
}

switch_tab :: proc(a: ^App, tab: Tab) {
	if a.tab != tab {
		ui.loop_request_full_redraw(&a.loop)
	}
	a.tab = tab
	mark_dirty(a)
}

network_list_visible :: proc(a: ^App) -> int {
	h := a.list_rect.h
	if h <= 1 && a.term_h > 0 {
		return max(1, a.term_h - 4)
	}
	return max(1, h)
}

net_view_kind :: proc(v: Net_View) -> store.Peer_Kind {
	switch v {
	case .Lxmf:
		return .Lxmf
	case .Nomad:
		return .Nomad_Node
	case .Propagation:
		return .Propagation
	}
	return .Lxmf
}

refresh_network_list :: proc(a: ^App, prev_sel, prev_scroll: int) {
	keep_hash: [store.HASH_LEN]u8
	have_keep := false
	visual_row := 0
	if prev_sel >= 0 && prev_sel < len(a.net_peer_idx) {
		pi := a.net_peer_idx[prev_sel]
		if pi >= 0 && pi < len(a.directory.peers) {
			keep_hash = a.directory.peers[pi].hash
			have_keep = true
			visual_row = prev_sel - prev_scroll
		}
	}

	ui.list_clear(&a.net_list)
	clear(&a.net_peer_idx)

	kind := net_view_kind(a.net_view)
	q := strings.to_lower(strings.trim_space(ui.input_value(&a.net_search)), context.temp_allocator)
	title := fmt.tprintf("-- %s --", NET_VIEW_LABELS[int(a.net_view)])
	ui.list_push(&a.net_list, title)
	append(&a.net_peer_idx, -1)

	list_h := max(1, a.list_rect.h)
	if list_h <= 1 && a.term_h > 0 {
		list_h = max(1, a.term_h - 4)
	}
	list_w := max(24, a.list_rect.w)
	if list_w <= 24 && a.term_w > 0 {
		list_w = max(24, a.term_w * 2 / 3)
	}
	show_cap := ui.network_list_row_cap(list_h)
	name_cols := ui.peer_name_cols(list_w)

	idxs := make([dynamic]int, 0, 64, context.temp_allocator)
	for peer, i in a.directory.peers {
		if peer.kind != kind {
			continue
		}
		name := peer.display_name if peer.display_name != "" else "-"
		hex := store.hash_hex(peer.hash, context.temp_allocator)
		if q != "" {
			ln := strings.to_lower(name, context.temp_allocator)
			if !strings.contains(ln, q) && !strings.contains(hex, q) {
				continue
			}
		}
		append(&idxs, i)
	}
	sort_peer_idxs_by_heard(&a.directory, idxs[:])

	shown := 0
	hidden := 0
	for i in idxs {
		if shown >= show_cap {
			hidden += 1
			continue
		}
		peer := a.directory.peers[i]
		name := peer.display_name if peer.display_name != "" else "-"
		name = truncate_runes_local(name, name_cols)
		hex := store.hash_hex(peer.hash, context.temp_allocator)
		cost := ""
		if sc, ok := peer.stamp_cost.?; ok {
			cost = fmt.tprintf(" cost=%d", sc)
		}
		ui.list_push(&a.net_list, fmt.tprintf("  %s  %s%s %s", name, hex, cost, store.format_peer_hops_peer(peer)))
		append(&a.net_peer_idx, i)
		shown += 1
	}
	if shown == 0 {
		hint := "No peers in this view"
		if q != "" {
			hint = "No matches"
		}
		ui.list_push(&a.net_list, hint)
		append(&a.net_peer_idx, -1)
	} else if hidden > 0 {
		ui.list_push(&a.net_list, fmt.tprintf("  ... +%d more (narrow/filter or scroll cap)", hidden))
		append(&a.net_peer_idx, -1)
	}
	if len(a.net_list.items) == 0 {
		return
	}
	if have_keep {
		if restore_network_selection(a, keep_hash, visual_row, list_h) {
			return
		}
	}
	a.net_list.selected = clamp(prev_sel, 0, len(a.net_list.items) - 1)
	a.net_list.scroll = clamp(prev_scroll, 0, max(0, len(a.net_list.items) - 1))
	ui.list_ensure_visible(&a.net_list, list_h)
	if a.net_list.selected < len(a.net_peer_idx) && a.net_peer_idx[a.net_list.selected] < 0 {
		for i in a.net_list.selected + 1 ..< len(a.net_peer_idx) {
			if a.net_peer_idx[i] >= 0 {
				a.net_list.selected = i
				ui.list_ensure_visible(&a.net_list, list_h)
				break
			}
		}
	}
}

// Keep the same peer selected across announce-driven reorders. visual_row is
// selected_index - scroll before the rebuild.
restore_network_selection :: proc(
	a: ^App,
	keep_hash: [store.HASH_LEN]u8,
	visual_row: int,
	list_h: int,
) -> bool {
	found := -1
	for idx, i in a.net_peer_idx {
		if idx < 0 || idx >= len(a.directory.peers) {
			continue
		}
		if a.directory.peers[idx].hash == keep_hash {
			found = i
			break
		}
	}
	if found < 0 {
		return false
	}
	a.net_list.selected = found
	vr := visual_row
	if vr < 0 {
		vr = 0
	}
	a.net_list.scroll = max(0, found - vr)
	max_scroll := max(0, len(a.net_list.items) - list_h)
	if a.net_list.scroll > max_scroll {
		a.net_list.scroll = max_scroll
	}
	ui.list_ensure_visible(&a.net_list, list_h)
	return true
}

sort_peer_idxs_by_heard :: proc(d: ^store.Directory, idxs: []int) {
	n := len(idxs)
	for i in 0 ..< n {
		for j in i + 1 ..< n {
			if d.peers[idxs[j]].last_heard > d.peers[idxs[i]].last_heard {
				idxs[i], idxs[j] = idxs[j], idxs[i]
			}
		}
	}
}

truncate_runes_local :: proc(s: string, max_cols: int) -> string {
	return ui.truncate_runes(s, max_cols)
}

refresh_iface_cache :: proc(a: ^App) -> bool {
	infos: [64]net.Iface_Info
	n := net.session_list_ifaces(&a.session, infos[:])
	// librns can briefly return an empty list mid-poll. Keep the last good snapshot.
	if n == 0 {
		return false
	}
	changed := apply_iface_infos(&a.ifaces, infos[:n])
	for i in 0 ..< n {
		delete(infos[i].name)
		delete(infos[i].type_n)
	}
	return changed
}

// Merge a non-empty iface poll into cache. Partial polls use miss grace instead of instant delete.
// Order is stable by name so online flips do not reshuffle cards.
apply_iface_infos :: proc(ifaces: ^[dynamic]Iface_View, infos: []net.Iface_Info) -> bool {
	if len(infos) == 0 {
		return false
	}
	changed := false
	seen := make(map[string]bool, context.temp_allocator)
	for e in infos {
		seen[e.name] = true
		found := false
		for &iface in ifaces {
			if iface.name != e.name {
				continue
			}
			if iface.online != e.online ||
			   iface.enabled != e.enabled ||
			   iface.rx != e.rx ||
			   iface.tx != e.tx ||
			   iface.rx_packets != e.rx_packets ||
			   iface.tx_packets != e.tx_packets {
				changed = true
			}
			iface.online = e.online
			iface.enabled = e.enabled
			iface.rx = e.rx
			iface.tx = e.tx
			iface.rx_packets = e.rx_packets
			iface.tx_packets = e.tx_packets
			iface.miss_count = 0
			if iface.type_n != e.type_n {
				delete(iface.type_n)
				iface.type_n = strings.clone(e.type_n)
				changed = true
			}
			found = true
			break
		}
		if !found {
			append(ifaces, Iface_View{
				name = strings.clone(e.name),
				type_n = strings.clone(e.type_n),
				online = e.online,
				enabled = e.enabled,
				rx = e.rx,
				tx = e.tx,
				rx_packets = e.rx_packets,
				tx_packets = e.tx_packets,
				miss_count = 0,
			})
			changed = true
		}
	}
	for i := len(ifaces) - 1; i >= 0; i -= 1 {
		if seen[ifaces[i].name] {
			continue
		}
		ifaces[i].miss_count += 1
		if ifaces[i].miss_count < IFACE_MISS_LIMIT {
			continue
		}
		delete(ifaces[i].name)
		delete(ifaces[i].type_n)
		ordered_remove(ifaces, i)
		changed = true
	}
	if sort_ifaces_by_name(ifaces) {
		changed = true
	}
	return changed
}

sort_ifaces_by_name :: proc(ifaces: ^[dynamic]Iface_View) -> bool {
	n := len(ifaces)
	moved := false
	for i in 0 ..< n {
		for j in i + 1 ..< n {
			if ifaces[j].name < ifaces[i].name {
				ifaces[i], ifaces[j] = ifaces[j], ifaces[i]
				moved = true
			}
		}
	}
	return moved
}

sort_ifaces :: proc(ifaces: ^[dynamic]Iface_View) {
	_ = sort_ifaces_by_name(ifaces)
}

// Kept for callers that still rank by state (tests / debug). Cards no longer sort by this.
iface_rank :: proc(iface: Iface_View) -> int {
	if iface.online {
		return 0
	}
	if iface.enabled {
		return 1
	}
	return 2
}

format_byte_count :: proc(n: u64, allocator := context.temp_allocator) -> string {
	if n < 1024 {
		return fmt.aprintf("%dB", n, allocator = allocator)
	}
	if n < 1024 * 1024 {
		return fmt.aprintf("%.1fKiB", f64(n) / 1024.0, allocator = allocator)
	}
	if n < 1024 * 1024 * 1024 {
		return fmt.aprintf("%.1fMiB", f64(n) / (1024.0 * 1024.0), allocator = allocator)
	}
	return fmt.aprintf("%.2fGiB", f64(n) / (1024.0 * 1024.0 * 1024.0), allocator = allocator)
}

iface_stats_line :: proc(iface: Iface_View, allocator := context.temp_allocator) -> string {
	state := "up" if iface.online else ("enabled" if iface.enabled else "down")
	return fmt.aprintf(
		"%-8s  rx=%s (%d)  tx=%s (%d)",
		state,
		format_byte_count(iface.rx, allocator),
		iface.rx_packets,
		format_byte_count(iface.tx, allocator),
		iface.tx_packets,
		allocator = allocator,
	)
}

mark_dirty :: proc(a: ^App) {
	a.ui_dirty = true
}
