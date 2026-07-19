// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
User actions like sending mail and fetching NomadNet pages.
*/

package app

import "core:fmt"
import "core:strings"

import "ren:constants"
import "ren:lxmf"
import "ren:micron"
import "ren:net"
import "ren:store"
import "ren:ui"

try_fetch_selected_node :: proc(a: ^App) {
	row := a.net_list.selected
	if row < 0 || row >= len(a.net_peer_idx) {
		return
	}
	idx := a.net_peer_idx[row]
	if idx < 0 || idx >= len(a.directory.peers) {
		return
	}
	peer := a.directory.peers[idx]
	if peer.kind == .Propagation {
		set_selected_propagation_node(a)
		return
	}
	if peer.kind != .Nomad_Node {
		_ = store.directory_promote_from_spill(&a.directory, peer.hash)
		open_lxmf_peer(a, peer.hash)
		return
	}
	_ = store.directory_promote_from_spill(&a.directory, peer.hash)
	page_fetch(a, peer.hash, constants.DEFAULT_PAGE_PATH)
}

resolve_nomad_target :: proc(a: ^App) -> (node: [store.HASH_LEN]u8, path: string, req: micron.Request_Data, ok: bool) {
	if a.page_has_node {
		p := a.page_path if a.page_path != "" else constants.DEFAULT_PAGE_PATH
		return a.page_node, p, a.page_request, true
	}
	row := a.net_list.selected
	if row < 0 || row >= len(a.net_peer_idx) {
		return {}, "", {}, false
	}
	idx := a.net_peer_idx[row]
	if idx < 0 || idx >= len(a.directory.peers) {
		return {}, "", {}, false
	}
	peer := a.directory.peers[idx]
	if peer.kind != .Nomad_Node {
		return {}, "", {}, false
	}
	return peer.hash, constants.DEFAULT_PAGE_PATH, {}, true
}

// Identify to NomadNet node then reload page so scripts can see remote_identity.
// librns currently has no rns_link_identify export so we open the link and reload
// with a clear status until the ABI lands.
try_identify_node :: proc(a: ^App) {
	if !a.online {
		set_status(a, "offline", STATUS_HOLD)
		return
	}
	node, path, req, ok := resolve_nomad_target(a)
	if !ok {
		set_status(a, "select a NomadNet node or open a page first", STATUS_HOLD)
		return
	}
	set_status(a, "identify: linking then reload (librns link_identify not available yet)", STATUS_HOLD)
	page_fetch(a, node, path, req, true)
}

try_send :: proc(a: ^App) {
	to := strings.trim_space(ui.input_value(&a.compose_to))
	body := strings.trim_space(ui.input_value(&a.compose_body))
	if len(to) != 32 || body == "" {
		set_status(a, "need 32 hex address and message", STATUS_HOLD)
		return
	}
	hash_bytes, ok := lxmf.decode_hex32(to)
	if !ok {
		set_status(a, "bad LXMF address", STATUS_HOLD)
		return
	}
	if !a.online {
		set_status(a, "offline", STATUS_HOLD)
		return
	}
	method := a.compose_method
	if method == .Unknown {
		method = a.cfg.send_method
	}
	if method == .Propagated && !a.cfg.has_propagation_node {
		set_status(a, "select a propagation node in Network > Propagation first", STATUS_HOLD)
		return
	}
	if net.session_send_begin(&a.session, hash_bytes, "", body, &a.conversations, &a.directory, &a.cfg, method) {
		ui.input_clear(&a.compose_body)
		set_status(a, fmt.tprintf("sending (%s)...", lxmf.method_label(method)), STATUS_HOLD)
		mark_dirty(a)
	} else {
		set_status(a, a.session.status if a.session.status != "" else "send failed", STATUS_HOLD)
	}
}

set_selected_propagation_node :: proc(a: ^App) {
	row := a.net_list.selected
	if row < 0 || row >= len(a.net_peer_idx) {
		return
	}
	idx := a.net_peer_idx[row]
	if idx < 0 || idx >= len(a.directory.peers) {
		return
	}
	peer := a.directory.peers[idx]
	if peer.kind != .Propagation {
		set_status(a, "switch to Propagation view and select a node", STATUS_HOLD)
		return
	}
	store.config_set_propagation_node(&a.cfg, peer.hash)
	hex := store.hash_hex(peer.hash, context.temp_allocator)
	if store.config_save(&a.cfg) {
		set_status(a, fmt.tprintf("propagation node set %s", hex), STATUS_HOLD)
	} else {
		set_status(a, fmt.tprintf("propagation node set %s (save failed)", hex), STATUS_HOLD)
	}
	refresh_lists(a)
}

try_sync_propagation :: proc(a: ^App) {
	if !a.online {
		set_status(a, "offline", STATUS_HOLD)
		return
	}
	if !a.cfg.has_propagation_node {
		set_status(a, "select a propagation node first (Enter in Propagation view)", STATUS_HOLD)
		return
	}
	if net.session_sync_begin(&a.session, &a.cfg) {
		set_status(a, "syncing with propagation node...", STATUS_HOLD)
		mark_dirty(a)
	} else {
		line := net.session_sync_status_line(&a.session, &a.cfg, context.temp_allocator)
		set_status(a, line if line != "" else "sync failed", STATUS_HOLD)
	}
}

select_conversation :: proc(a: ^App, peer: [store.HASH_LEN]u8) {
	store_idx := store.conversations_index_of(&a.conversations, peer)
	if store_idx < 0 {
		return
	}
	list_row := -1
	for idx, row in a.conv_peer_idx {
		if idx == store_idx {
			list_row = row
			break
		}
	}
	if list_row < 0 {
		refresh_conv_list(a)
		for idx, row in a.conv_peer_idx {
			if idx == store_idx {
				list_row = row
				break
			}
		}
	}
	if list_row < 0 {
		return
	}
	a.conv_list.selected = list_row
	visible := max(1, a.list_rect.h)
	ui.list_ensure_visible(&a.conv_list, visible)
	conv := a.conversations.items[store_idx]
	a.msg_scroll = max(0, len(conv.messages) - max(1, a.detail_rect.h / 3))
	if store.conversations_clear_unread(&a.conversations, peer) {
		_ = store.conversations_save_peer(&a.conversations, &a.cfg, peer)
		refresh_conv_list(a)
		select_conversation_row_only(a, peer)
	}
	hex := store.hash_hex(peer, context.temp_allocator)
	ui.input_clear(&a.compose_to)
	strings.write_string(&a.compose_to.text, hex)
	a.compose_to.cursor = len(hex)
}

select_conversation_row_only :: proc(a: ^App, peer: [store.HASH_LEN]u8) {
	store_idx := store.conversations_index_of(&a.conversations, peer)
	if store_idx < 0 {
		return
	}
	for idx, row in a.conv_peer_idx {
		if idx == store_idx {
			a.conv_list.selected = row
			return
		}
	}
}

open_lxmf_peer :: proc(a: ^App, peer: [store.HASH_LEN]u8) {
	_ = store.directory_promote_from_spill(&a.directory, peer)
	label := store.directory_label(&a.directory, peer)
	defer delete(label)
	_ = store.conversations_get_or_create(&a.conversations, peer, label)
	_ = store.conversations_save_peer(&a.conversations, &a.cfg, peer)
	refresh_conv_list(a)
	select_conversation(a, peer)
	hex := store.hash_hex(peer, context.temp_allocator)
	ui.input_clear(&a.compose_to)
	strings.write_string(&a.compose_to.text, hex)
	a.compose_to.cursor = len(hex)
	switch_tab(a, .Conversations)
	a.conv_replying = true
	set_status(a, "opened LXMF conversation", STATUS_HOLD)
}

try_conv_reply :: proc(a: ^App) {
	idx := conv_selected_store_idx(a)
	if idx < 0 {
		set_status(a, "select a conversation", STATUS_HOLD)
		return
	}
	peer := a.conversations.items[idx].peer_hash
	body := strings.trim_space(ui.input_value(&a.conv_reply))
	if body == "" {
		set_status(a, "need a message", STATUS_HOLD)
		return
	}
	if !a.online {
		set_status(a, "offline", STATUS_HOLD)
		return
	}
	method := a.compose_method
	if method == .Unknown {
		method = a.cfg.send_method
	}
	if method == .Propagated && !a.cfg.has_propagation_node {
		set_status(a, "select a propagation node in Network > Propagation first", STATUS_HOLD)
		return
	}
	if net.session_send_begin(&a.session, peer, "", body, &a.conversations, &a.directory, &a.cfg, method) {
		ui.input_clear(&a.conv_reply)
		set_status(a, fmt.tprintf("sending (%s)...", lxmf.method_label(method)), STATUS_HOLD)
		mark_dirty(a)
	} else {
		set_status(a, a.session.status if a.session.status != "" else "send failed", STATUS_HOLD)
	}
}

start_conv_rename :: proc(a: ^App) {
	idx := conv_selected_store_idx(a)
	if idx < 0 {
		set_status(a, "select a conversation", STATUS_HOLD)
		return
	}
	conv := a.conversations.items[idx]
	cur := conv.custom_name if conv.custom_name != "" else store.conversation_label(&a.directory, conv, context.temp_allocator)
	ui.input_clear(&a.conv_rename)
	strings.write_string(&a.conv_rename.text, cur)
	a.conv_rename.cursor = len(cur)
	a.conv_renaming = true
	a.conv_replying = false
	set_status(a, "rename contact  Enter save  Esc cancel (empty clears)", STATUS_HOLD)
}

apply_conv_rename :: proc(a: ^App) {
	idx := conv_selected_store_idx(a)
	a.conv_renaming = false
	if idx < 0 {
		ui.input_clear(&a.conv_rename)
		return
	}
	peer := a.conversations.items[idx].peer_hash
	val := strings.trim_space(ui.input_value(&a.conv_rename))
	ui.input_clear(&a.conv_rename)
	_ = store.conversations_set_custom_name(&a.conversations, peer, val)
	_ = store.conversations_save_peer(&a.conversations, &a.cfg, peer)
	refresh_conv_list(a)
	select_conversation_row_only(a, peer)
	if val == "" {
		set_status(a, "custom name cleared", STATUS_HOLD)
	} else {
		set_status(a, "contact renamed", STATUS_HOLD)
	}
}
