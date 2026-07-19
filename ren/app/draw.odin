// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Draws each tab into the cell buffer every frame.
*/

package app

import "core:fmt"
import "core:strings"

import "ren:constants"
import "ren:micron"
import "ren:net"
import "ren:store"
import "ren:ui"
import "ren:version"

GUIDE_LINES := [?]string{
	"Ren TUI",
	"",
	"Tabs 1-7  Conversations Network Page Interfaces Compose Config Guide",
	"Ctrl+R    announce now",
	"Ctrl+Q    quit",
	"",
	"Network",
	"l/n/p     LXMF / NomadNet / Propagation views",
	"/         search peers   Enter open NomadNet page",
	"i         identify to NomadNet node (needs active link)",
	"Peers hot-capped; overflow in peers.msgpack",
	"",
	"Page (micron viewer)",
	"g         open page URL (hash:/path or /path)",
	"s         toggle rendered / raw source",
	"i         identify then reload page",
	"Tab       cycle links   Enter open link   click link",
	"[ ]       scroll   PgUp/PgDn scroll   Esc back to Network",
	"Links: /page/...  hash:/page/...  lxmf://hash",
	"Dynamic: /page/x.mu`var=1|field.user=alice",
	"Dangerous schemes blocked. External http shown only.",
	"",
	"Conversations  / search",
	"",
	"Config ~/.config/ren-tui/config",
	"obfuscate_hops = yes writes RNS local_hops_delta (off by default)",
	"theme = field|slate|amber|mono under [ui]",
	"Conversations under ~/.config/ren-tui/conversations/",
	"Default display name: Anonymous",
	"",
	"Pages are display-only (no exec). Size capped.",
	"Click Your LXMF Address in Config to copy.",
}

guide_lines :: proc() -> []string {
	return GUIDE_LINES[:]
}

draw_app :: proc(buf: ^ui.Buffer, user: rawptr) {
	a := cast(^App)user
	t := ui.theme()
	w := buf.width
	h := buf.height
	a.term_w = w
	a.term_h = h
	if w < 40 || h < 10 {
		ui.buffer_text(buf, 0, 0, "terminal too small", t.error, t.bg)
		return
	}

	header, rest := ui.rect_split_horizontal(ui.Rect{0, 0, w, h}, 1)
	body, status := ui.rect_split_horizontal(rest, rest.h - 1)
	a.tab_rect = header

	tabs := TAB_LABELS[:]
	ui.draw_tabs(buf, header, tabs, int(a.tab))
	ui.draw_status(buf, status, a.status_left, a.status_right)

	switch a.tab {
	case .Conversations:
		draw_conversations(a, buf, body)
	case .Network:
		draw_network(a, buf, body)
	case .Page:
		draw_page(a, buf, body)
	case .Interfaces:
		draw_interfaces(a, buf, body)
	case .Compose:
		draw_compose(a, buf, body)
	case .Config:
		draw_config(a, buf, body)
	case .Guide:
		draw_guide(a, buf, body)
	}
}

draw_conversations :: proc(a: ^App, buf: ^ui.Buffer, r: ui.Rect) {
	ui.draw_box(buf, r, "conversations", true)
	inner := ui.rect_inset(r, 1)
	left, right := ui.rect_split_vertical(inner, min(28, inner.w / 3))
	a.list_rect = left
	a.detail_rect = right
	ui.draw_list(buf, left, &a.conv_list)

	t := ui.theme()
	ui.buffer_fill_rect(buf, right.x, right.y, right.w, right.h, ' ', t.fg, t.bg)
	if len(a.conversations.items) == 0 {
		ui.buffer_text(buf, right.x + 1, right.y, "No conversations yet", t.muted, t.bg)
		return
	}
	if a.conv_list.selected < 0 || a.conv_list.selected >= len(a.conversations.items) {
		ui.buffer_text(buf, right.x + 1, right.y, "Select a conversation", t.muted, t.bg)
		return
	}
	conv := a.conversations.items[a.conv_list.selected]
	start := a.msg_scroll
	if start < 0 {
		start = 0
	}
	y := right.y
	for i := start; i < len(conv.messages); i += 1 {
		if y >= right.y + right.h {
			break
		}
		msg := conv.messages[i]
		out := msg.direction == .Out
		who := "you" if out else "them"
		sig := "ok" if msg.verified else "?"
		meta := fmt.tprintf("%s  %s  hops=%d", who, sig, msg.hops)
		body := msg.content
		if msg.title != "" {
			body = fmt.tprintf("[%s] %s", msg.title, msg.content)
		}

		if out {
			mx := right.x + max(1, right.w / 4)
			mw := right.w - (mx - right.x) - 1
			ui.buffer_fill_rect(buf, mx, y, mw, 1, ' ', t.accent, t.highlight_bg)
			ui.buffer_text(buf, mx, y, truncate(meta, mw), t.accent, t.highlight_bg)
			y += 1
			if y >= right.y + right.h {
				break
			}
			ui.buffer_fill_rect(buf, mx, y, mw, 1, ' ', t.fg, t.highlight_bg)
			ui.buffer_text(buf, mx, y, truncate(body, mw), t.fg, t.highlight_bg)
		} else {
			mw := max(8, right.w * 3 / 4)
			ui.buffer_fill_rect(buf, right.x + 1, y, mw, 1, ' ', t.muted, t.input_bg)
			ui.buffer_text(buf, right.x + 1, y, truncate(meta, mw), t.muted, t.input_bg)
			y += 1
			if y >= right.y + right.h {
				break
			}
			ui.buffer_fill_rect(buf, right.x + 1, y, mw, 1, ' ', t.fg, t.input_bg)
			ui.buffer_text(buf, right.x + 1, y, truncate(body, mw), t.fg, t.input_bg)
		}
		y += 2
	}
}

truncate :: proc(s: string, max_len: int) -> string {
	if max_len <= 0 {
		return ""
	}
	if len(s) <= max_len {
		return s
	}
	return s[:max_len]
}

draw_network :: proc(a: ^App, buf: ^ui.Buffer, r: ui.Rect) {
	ui.draw_box(buf, r, "network", true)
	inner := ui.rect_inset(r, 1)
	list_w := min(max(40, inner.w * 2 / 3), max(24, inner.w - 20))
	left, right := ui.rect_split_vertical(inner, list_w)
	a.list_rect = left
	a.detail_rect = right
	ui.draw_list(buf, left, &a.net_list)
	t := ui.theme()
	ui.buffer_fill_rect(buf, right.x, right.y, right.w, right.h, ' ', t.fg, t.bg)

	view := NET_VIEW_LABELS[int(a.net_view)]
	ui.buffer_text(buf, right.x + 1, right.y, fmt.tprintf("View: %s", view), t.title, t.bg)
	ui.buffer_text(buf, right.x + 1, right.y + 1, "l LXMF   n NomadNet   p Propagation", t.muted, t.bg)
	ui.buffer_text(buf, right.x + 1, right.y + 2, "/ search   Enter/click open Nomad page", t.muted, t.bg)
	q := strings.trim_space(ui.input_value(&a.net_search))
	if q != "" || a.net_searching {
		ui.buffer_text(buf, right.x + 1, right.y + 4, truncate(fmt.tprintf("filter: %s", q if q != "" else "..."), right.w - 2), t.highlight_fg, t.bg)
	}
	stats := net.session_stats_line(&a.session, &a.directory, context.temp_allocator)
	ui.buffer_text(buf, right.x + 1, right.y + 6, truncate(stats, right.w - 2), t.muted, t.bg)
	ui.buffer_text(
		buf,
		right.x + 1,
		right.y + 8,
		truncate(fmt.tprintf("show<=%d hot<=%d  cold peers.msgpack", ui.network_list_row_cap(max(1, left.h)), constants.PEERS_HOT_MAX), right.w - 2),
		t.muted,
		t.bg,
	)
	if a.net_searching {
		edit_r := ui.Rect{right.x, right.y + right.h - 3, right.w, 3}
		ui.draw_input(buf, edit_r, &a.net_search, "search", true)
	}
}

draw_page :: proc(a: ^App, buf: ^ui.Buffer, r: ui.Rect) {
	ui.draw_box(buf, r, "page", true)
	inner := ui.rect_inset(r, 1)
	a.list_rect = {}
	a.detail_rect = inner
	t := ui.theme()
	ui.buffer_fill_rect(buf, inner.x, inner.y, inner.w, inner.h, ' ', t.fg, t.bg)

	header_h := 1
	mode := "RAW" if a.page_view_raw else "view"
	path := a.page_path if a.page_path != "" else "-"
	hex := "-"
	if a.page_has_node {
		hex = store.hash_hex(a.page_node, context.temp_allocator)
		if len(hex) > 12 {
			hex = hex[:12]
		}
	}
	ui.buffer_text(
		buf,
		inner.x + 1,
		inner.y,
		truncate(fmt.tprintf("%s  %s  [%s]", hex, path, mode), inner.w - 2),
		t.title,
		t.bg,
	)

	body := ui.Rect{
		inner.x,
		inner.y + header_h,
		inner.w,
		max(0, inner.h - header_h - (3 if a.url_editing else 0)),
	}
	if net.session_page_busy(&a.session) {
		msg := net.session_page_status(&a.session)
		ui.buffer_text(buf, body.x + 1, body.y, "Loading NomadNet page...", t.title, t.bg)
		ui.buffer_text(buf, body.x + 1, body.y + 1, truncate(msg, body.w - 2), t.highlight_fg, t.bg)
		ui.buffer_text(buf, body.x + 1, body.y + 3, "Esc cancels fetch", t.muted, t.bg)
	} else if a.page_source == "" {
		ui.buffer_text(buf, body.x + 1, body.y, "No page loaded", t.muted, t.bg)
		ui.buffer_text(buf, body.x + 1, body.y + 1, "Open a NomadNet node from Network (Enter)", t.muted, t.bg)
		ui.buffer_text(buf, body.x + 1, body.y + 2, "or press g to enter hash:/page/index.mu", t.muted, t.bg)
	} else if a.page_view_raw {
		raw_lines := strings.split_lines(a.page_source, context.temp_allocator)
		if len(raw_lines) > constants.PAGE_MAX_LINES {
			raw_lines = raw_lines[:constants.PAGE_MAX_LINES]
		}
		ui.draw_text_block(buf, body, raw_lines, a.page_scroll)
	} else {
		paint_doc(buf, body, a.page_doc, a.page_scroll, a.page_link_focus, &a.page_hits)
	}

	if a.url_editing {
		edit_r := ui.Rect{inner.x, inner.y + inner.h - 3, inner.w, 3}
		ui.draw_input(buf, edit_r, &a.url_edit, "page URL", true)
	}
}

draw_interfaces :: proc(a: ^App, buf: ^ui.Buffer, r: ui.Rect) {
	ui.draw_box(buf, r, "interfaces", true)
	inner := ui.rect_inset(r, 1)
	a.list_rect = inner
	a.detail_rect = {}
	t := ui.theme()
	if len(a.ifaces) == 0 {
		ui.buffer_text(buf, inner.x + 1, inner.y, "No interfaces yet", t.muted, t.bg)
		return
	}
	card_h := 4
	gap := 1
	per_page := ui.iface_cards_per_page(inner.h)
	if a.iface_scroll > max(0, len(a.ifaces) - per_page) {
		a.iface_scroll = max(0, len(a.ifaces) - per_page)
	}
	y := inner.y
	end := min(len(a.ifaces), a.iface_scroll + per_page)
	for i in a.iface_scroll ..< end {
		iface := a.ifaces[i]
		box := ui.Rect{inner.x, y, inner.w, card_h}
		if box.y + box.h > inner.y + inner.h {
			break
		}
		online := iface.online
		title_fg := t.ok if online else t.muted
		ui.draw_box(buf, box, iface.type_n, online)
		ui.buffer_text(buf, box.x + 2, box.y + 1, truncate(iface.name, box.w - 4), title_fg, t.bg)
		stats := iface_stats_line(iface)
		ui.buffer_text(buf, box.x + 2, box.y + 2, truncate(stats, box.w - 4), t.fg, t.bg)
		y += card_h + gap
	}
	if len(a.ifaces) > per_page {
		hint := fmt.tprintf("%d-%d / %d", a.iface_scroll + 1, end, len(a.ifaces))
		ui.buffer_text(buf, inner.x + 1, inner.y + inner.h - 1, hint, t.muted, t.bg)
	}
}

draw_compose :: proc(a: ^App, buf: ^ui.Buffer, r: ui.Rect) {
	ui.draw_box(buf, r, "compose", true)
	inner := ui.rect_inset(r, 1)
	to_rect := ui.Rect{inner.x, inner.y, inner.w, 3}
	body_rect := ui.Rect{inner.x, inner.y + 3, inner.w, max(3, inner.h - 4)}
	hint := ui.Rect{inner.x, inner.y + inner.h - 1, inner.w, 1}
	a.list_rect = to_rect
	a.detail_rect = body_rect
	ui.draw_input(buf, to_rect, &a.compose_to, "to (LXMF address)", a.compose_focus == 0)
	ui.draw_input(buf, body_rect, &a.compose_body, "message", a.compose_focus == 1)
	t := ui.theme()
	ui.buffer_text(buf, hint.x, hint.y, "Enter send   Tab focus", t.muted, t.bg)
}

draw_config :: proc(a: ^App, buf: ^ui.Buffer, r: ui.Rect) {
	ui.draw_box(buf, r, "config", true)
	inner := ui.rect_inset(r, 1)
	left, right := ui.rect_split_vertical(inner, min(42, inner.w / 2))
	a.list_rect = left
	a.detail_rect = right
	ui.draw_list(buf, left, &a.config_list)

	t := ui.theme()
	ui.buffer_fill_rect(buf, right.x, right.y, right.w, right.h, ' ', t.fg, t.bg)
	y := right.y
	ui.buffer_text(buf, right.x + 1, y, version.short_line(context.temp_allocator), t.title, t.bg)
	y += 1
	ui.buffer_text(
		buf,
		right.x + 1,
		y,
		truncate(fmt.tprintf("commit %s  built %s", version.GIT_COMMIT, version.BUILD_DATE), right.w - 2),
		t.muted,
		t.bg,
	)
	y += 2
	ui.buffer_text(buf, right.x + 1, y, fmt.tprintf("Config: %s", a.cfg.config_path), t.fg, t.bg)
	y += 1
	ui.buffer_text(buf, right.x + 1, y, fmt.tprintf("RNS: %s", a.cfg.rns_config), t.fg, t.bg)
	y += 2
	if a.online {
		lxmf_hex := net.session_delivery_hex(&a.session, context.temp_allocator)
		id_hex := net.session_identity_hex(&a.session, context.temp_allocator)
		ui.buffer_text(buf, right.x + 1, y, "Your LXMF Address", t.title, t.bg)
		y += 1
		a.lxmf_addr_rect = ui.Rect{right.x + 1, y, min(len(lxmf_hex), right.w - 2), 1}
		ui.buffer_text(buf, right.x + 1, y, lxmf_hex, t.accent, t.bg)
		y += 2
		ui.buffer_text(buf, right.x + 1, y, "Your Identity", t.title, t.bg)
		y += 1
		a.identity_rect = ui.Rect{right.x + 1, y, min(len(id_hex), right.w - 2), 1}
		ui.buffer_text(buf, right.x + 1, y, id_hex, t.fg, t.bg)
		y += 2
		ui.buffer_text(buf, right.x + 1, y, "Click LXMF Address to copy", t.muted, t.bg)
		y += 2
	} else {
		a.lxmf_addr_rect = {}
		a.identity_rect = {}
	}
	if a.config_editing {
		edit_r := ui.Rect{right.x, y, right.w, 3}
		ui.draw_input(buf, edit_r, &a.config_edit, "edit value", true)
		y += 4
		ui.buffer_text(buf, right.x + 1, y, "Enter apply   Esc cancel", t.muted, t.bg)
	} else {
		ui.buffer_text(buf, right.x + 1, y, "Enter edit/toggle   Restart Network Stack   Ctrl+R announce", t.muted, t.bg)
	}
}

draw_guide :: proc(a: ^App, buf: ^ui.Buffer, r: ui.Rect) {
	ui.draw_box(buf, r, "guide", true)
	inner := ui.rect_inset(r, 1)
	a.list_rect = inner
	a.detail_rect = {}
	ui.draw_text_block(buf, inner, guide_lines(), a.guide_scroll)
}
