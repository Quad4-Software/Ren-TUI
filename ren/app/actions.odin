// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
User actions like sending mail and fetching NomadNet pages.
*/

package app

import "core:strings"

import "ren:constants"
import "ren:lxmf"
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
	if peer.kind != .Nomad_Node {
		hex := store.hash_hex(peer.hash, context.temp_allocator)
		ui.input_clear(&a.compose_to)
		strings.write_string(&a.compose_to.text, hex)
		a.compose_to.cursor = len(hex)
		a.tab = .Compose
		a.compose_focus = 1
		set_status(a, "compose to selected peer", STATUS_HOLD)
		return
	}
	page_fetch(a, peer.hash, constants.DEFAULT_PAGE_PATH)
}

resolve_nomad_target :: proc(a: ^App) -> (node: [store.HASH_LEN]u8, path: string, ok: bool) {
	if a.page_has_node {
		p := a.page_path if a.page_path != "" else constants.DEFAULT_PAGE_PATH
		return a.page_node, p, true
	}
	row := a.net_list.selected
	if row < 0 || row >= len(a.net_peer_idx) {
		return {}, "", false
	}
	idx := a.net_peer_idx[row]
	if idx < 0 || idx >= len(a.directory.peers) {
		return {}, "", false
	}
	peer := a.directory.peers[idx]
	if peer.kind != .Nomad_Node {
		return {}, "", false
	}
	return peer.hash, constants.DEFAULT_PAGE_PATH, true
}

// Identify to NomadNet node then reload page so scripts can see remote_identity.
// librns currently has no rns_link_identify export so we open the link and reload
// with a clear status until the ABI lands.
try_identify_node :: proc(a: ^App) {
	if !a.online {
		set_status(a, "offline", STATUS_HOLD)
		return
	}
	node, path, ok := resolve_nomad_target(a)
	if !ok {
		set_status(a, "select a NomadNet node or open a page first", STATUS_HOLD)
		return
	}
	set_status(a, "identify: linking then reload (librns link_identify not available yet)", STATUS_HOLD)
	page_fetch(a, node, path, {}, true)
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
	if net.session_send_begin(&a.session, hash_bytes, "", body, &a.conversations, &a.directory, &a.cfg) {
		ui.input_clear(&a.compose_body)
		set_status(a, "sending...", STATUS_HOLD)
		mark_dirty(a)
	} else {
		set_status(a, a.session.status if a.session.status != "" else "send failed", STATUS_HOLD)
	}
}

select_conversation :: proc(a: ^App, peer: [store.HASH_LEN]u8) {
	idx := store.conversations_index_of(&a.conversations, peer)
	if idx < 0 {
		return
	}
	a.conv_list.selected = idx
	visible := max(1, a.list_rect.h)
	ui.list_ensure_visible(&a.conv_list, visible)
	conv := a.conversations.items[idx]
	a.msg_scroll = max(0, len(conv.messages) - max(1, a.detail_rect.h / 3))
}

open_lxmf_peer :: proc(a: ^App, peer: [store.HASH_LEN]u8) {
	hex := store.hash_hex(peer, context.temp_allocator)
	_ = store.conversations_get_or_create(&a.conversations, peer, hex)
	refresh_conv_list(a)
	select_conversation(a, peer)
	ui.input_clear(&a.compose_to)
	strings.write_string(&a.compose_to.text, hex)
	a.compose_to.cursor = len(hex)
	a.tab = .Conversations
	set_status(a, "opened LXMF conversation", STATUS_HOLD)
}
