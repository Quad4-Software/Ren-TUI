// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
NomadNet page fetch sanitize parse and path checks.
*/

package app

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "ren:constants"
import "ren:lxmf"
import "ren:micron"
import "ren:net"
import "ren:store"
import "ren:ui"

page_clear :: proc(a: ^App) {
	micron.doc_destroy(&a.page_doc)
	clear(&a.page_hits)
	a.page_link_focus = -1
	delete(a.page_source)
	a.page_source = ""
	delete(a.page_path)
	a.page_path = ""
	a.page_node = {}
	a.page_has_node = false
	a.page_view_raw = false
	a.page_scroll = 0
}

// Strip NULs and C0 controls except tab/newline/CR. Display text only.
page_sanitize_bytes :: proc(data: []u8, allocator := context.allocator) -> string {
	out := make([dynamic]u8, 0, min(len(data), constants.PAGE_MAX_BYTES), allocator)
	n := min(len(data), constants.PAGE_MAX_BYTES)
	for i in 0 ..< n {
		b := data[i]
		switch b {
		case 0:
			continue
		case '\t', '\n', '\r':
			append(&out, b)
		case 0x01 ..= 0x1f, 0x7f:
			append(&out, ' ')
		case:
			append(&out, b)
		}
	}
	return string(out[:])
}

page_path_allowed :: proc(path: string) -> bool {
	if path == "" || !strings.has_prefix(path, "/page/") {
		return false
	}
	if strings.contains(path, "..") {
		return false
	}
	for i in 0 ..< len(path) {
		c := path[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '/', '.', '_', '-', '~':
		case:
			return false
		}
	}
	return true
}

// Parse "hash:/page/x.mu" or "/page/x.mu". Hash optional when browsing a node.
// Request vars after backtick are stripped from the path (use resolve_link for full Request_Data).
page_parse_url :: proc(s: string) -> (hash: [store.HASH_LEN]u8, has_hash: bool, path: string, ok: bool) {
	v := strings.trim_space(s)
	if v == "" {
		return {}, false, "", false
	}
	if bt := strings.index_byte(v, '`'); bt >= 0 {
		v = v[:bt]
	}
	if colon := strings.index_byte(v, ':'); colon == 32 {
		h, hok := lxmf.decode_hex32(v[:32])
		if !hok {
			return {}, false, "", false
		}
		rest := v[33:]
		if rest == "" {
			rest = constants.DEFAULT_PAGE_PATH
		}
		if !strings.has_prefix(rest, "/") {
			rest = strings.concatenate({"/", rest}, context.temp_allocator)
		}
		if !page_path_allowed(rest) {
			return {}, false, "", false
		}
		return h, true, strings.clone(rest), true
	}
	p := v
	if !strings.has_prefix(p, "/") {
		p = strings.concatenate({"/", p}, context.temp_allocator)
	}
	if !page_path_allowed(p) {
		return {}, false, "", false
	}
	return {}, false, strings.clone(p), true
}

page_url_default :: proc(a: ^App, allocator := context.allocator) -> string {
	path := a.page_path if a.page_path != "" else constants.DEFAULT_PAGE_PATH
	if a.page_has_node {
		hex := store.hash_hex(a.page_node, context.temp_allocator)
		return fmt.aprintf("%s:%s", hex, path, allocator = allocator)
	}
	row := a.net_list.selected
	if row >= 0 && row < len(a.net_peer_idx) {
		idx := a.net_peer_idx[row]
		if idx >= 0 && idx < len(a.directory.peers) {
			peer := a.directory.peers[idx]
			if peer.kind == .Nomad_Node {
				hex := store.hash_hex(peer.hash, context.temp_allocator)
				return fmt.aprintf("%s:%s", hex, constants.DEFAULT_PAGE_PATH, allocator = allocator)
			}
		}
	}
	return strings.clone(path, allocator)
}

page_apply_content :: proc(a: ^App, node: [store.HASH_LEN]u8, path: string, data: []u8) {
	page_clear(a)
	a.page_node = node
	a.page_has_node = true
	a.page_path = strings.clone(path)
	a.page_source = page_sanitize_bytes(data)
	a.page_view_raw = false
	a.page_scroll = 0
	a.page_doc = micron.parse(a.page_source)
	a.page_link_focus = 0 if a.page_doc.link_count > 0 else -1
	clear(&a.page_hits)
}

page_fetch :: proc(
	a: ^App,
	node: [store.HASH_LEN]u8,
	path: string,
	req: micron.Request_Data = {},
	identify_after := false,
) {
	if !a.online {
		set_status(a, "offline", STATUS_HOLD)
		return
	}
	if !page_path_allowed(path) {
		set_status(a, "bad page path", STATUS_HOLD)
		return
	}
	// Cancel in-flight fetch so opening another node mid-link replaces the job.
	if net.session_page_busy(&a.session) {
		net.session_page_cancel(&a.session)
	}
	payload := micron.encode_request_data(req)
	defer delete(payload)
	if !net.session_page_begin(&a.session, node, path, payload, identify_after) {
		set_status(a, a.session.status if a.session.status != "" else "fetch failed", STATUS_HOLD)
		return
	}
	switch_tab(a, .Page)
	set_status(a, net.session_page_status(&a.session), time.Duration(constants.PAGE_TIMEOUT_SEC) * time.Second)
}

page_poll_result :: proc(a: ^App) {
	if net.session_page_busy(&a.session) {
		msg := net.session_page_status(&a.session)
		set_status(a, msg, time.Duration(constants.PAGE_TIMEOUT_SEC) * time.Second)
		return
	}
	content, path, node, ok, finished := net.session_page_take(&a.session)
	if !finished {
		return
	}
	defer delete(path)
	if !ok {
		msg := a.session.status if a.session.status != "" else "page fetch failed"
		set_status(a, msg, STATUS_HOLD)
		delete(content)
		return
	}
	defer delete(content)
	page_apply_content(a, node, path, content)
	switch_tab(a, .Page)
	truncated := ""
	if strings.contains(a.session.status, "truncated") || len(content) >= constants.PAGE_MAX_BYTES {
		truncated = " truncated"
	}
	set_status(a, fmt.tprintf("page %s%s", path, truncated), STATUS_HOLD)
}

page_toggle_raw :: proc(a: ^App) {
	if a.page_source == "" {
		set_status(a, "no page loaded", STATUS_HOLD)
		return
	}
	a.page_view_raw = !a.page_view_raw
	a.page_scroll = 0
	set_status(a, "source view" if a.page_view_raw else "rendered view", STATUS_HOLD)
}

page_start_url_edit :: proc(a: ^App) {
	ui.input_clear(&a.url_edit)
	def := page_url_default(a, context.temp_allocator)
	strings.write_string(&a.url_edit.text, def)
	a.url_edit.cursor = len(def)
	a.url_editing = true
	set_status(a, "enter page URL  Esc cancel", STATUS_HOLD)
}

page_apply_url_edit :: proc(a: ^App) {
	val := strings.trim_space(ui.input_value(&a.url_edit))
	a.url_editing = false
	ui.input_clear(&a.url_edit)
	act := micron.resolve_link(
		val if strings.contains(val, "://") || strings.index_byte(val, '`') >= 0 else (
			strings.concatenate({"nomadnetwork://", val}, context.temp_allocator)
		),
		a.page_node,
		a.page_has_node,
	)
	defer micron.action_destroy(&act)
	if act.kind == .Page && act.has_node {
		page_fetch(a, act.node, act.path, act.request)
		return
	}
	hash, has_hash, path, ok := page_parse_url(val)
	if !ok {
		set_status(a, "bad URL (hash:/path or /path)", STATUS_HOLD)
		return
	}
	defer if path != "" do delete(path)

	node := hash
	if !has_hash {
		if a.page_has_node {
			node = a.page_node
		} else {
			row := a.net_list.selected
			if row < 0 || row >= len(a.net_peer_idx) {
				set_status(a, "select a NomadNet node first", STATUS_HOLD)
				return
			}
			idx := a.net_peer_idx[row]
			if idx < 0 || idx >= len(a.directory.peers) || a.directory.peers[idx].kind != .Nomad_Node {
				set_status(a, "select a NomadNet node first", STATUS_HOLD)
				return
			}
			node = a.directory.peers[idx].hash
		}
	}
	page_fetch(a, node, path)
}

page_line_count :: proc(a: ^App) -> int {
	if a.page_view_raw {
		if a.page_source == "" {
			return 0
		}
		n := 1
		for i in 0 ..< len(a.page_source) {
			if a.page_source[i] == '\n' {
				n += 1
			}
		}
		return min(n, constants.PAGE_MAX_LINES + 1)
	}
	w := max(1, a.detail_rect.w)
	return micron.layout_row_count(a.page_doc, w)
}

page_activate_url :: proc(a: ^App, url: string) {
	act := micron.resolve_link(url, a.page_node, a.page_has_node)
	defer micron.action_destroy(&act)
	switch act.kind {
	case .None:
		set_status(a, "empty link", STATUS_HOLD)
	case .Page:
		if !act.has_node {
			set_status(a, "no node for page link", STATUS_HOLD)
			return
		}
		page_fetch(a, act.node, act.path, act.request)
	case .Lxmf:
		open_lxmf_peer(a, act.peer)
	case .External:
		shown := act.url if len(act.url) <= 48 else act.url[:48]
		set_status(a, fmt.tprintf("external: %s", shown), STATUS_HOLD)
	case .Reject:
		reason := act.reason if act.reason != "" else "blocked link"
		set_status(a, reason, STATUS_HOLD)
	}
}

page_activate_focused_link :: proc(a: ^App) {
	if a.page_view_raw || a.page_link_focus < 0 {
		return
	}
	n := 0
	for line in a.page_doc.lines {
		for span in line.spans {
			if span.kind != .Link && span.kind != .Partial {
				continue
			}
			if n == a.page_link_focus {
				page_activate_url(a, span.url)
				return
			}
			n += 1
		}
	}
}

page_cycle_link :: proc(a: ^App, delta: int) {
	total := micron.doc_link_count(a.page_doc)
	if total <= 0 {
		a.page_link_focus = -1
		return
	}
	if a.page_link_focus < 0 {
		a.page_link_focus = 0 if delta >= 0 else total - 1
	} else {
		a.page_link_focus = (a.page_link_focus + delta % total + total) % total
	}
	ensure_page_link_visible(a)
}

ensure_page_link_visible :: proc(a: ^App) {
	if a.page_link_focus < 0 {
		return
	}
	w := max(1, a.detail_rect.w)
	row_i := micron.layout_first_row_for_link(a.page_doc, w, a.page_link_focus)
	visible := max(1, a.detail_rect.h - 1)
	if row_i < a.page_scroll {
		a.page_scroll = row_i
	} else if row_i >= a.page_scroll + visible {
		a.page_scroll = max(0, row_i - visible + 1)
	}
}

page_click_link_at :: proc(a: ^App, x, y: int) -> bool {
	for hit in a.page_hits {
		screen_y := a.detail_rect.y + 1 + (hit.line_idx - a.page_scroll)
		if y != screen_y {
			continue
		}
		if x >= hit.x0 && x < hit.x1 {
			page_activate_url(a, hit.url)
			return true
		}
	}
	return false
}

// Basename for saving a fetched page. Always ends with .mu when possible.
page_download_basename :: proc(page_path: string, allocator := context.allocator) -> string {
	p := page_path
	if bt := strings.index_byte(p, '`'); bt >= 0 {
		p = p[:bt]
	}
	p = strings.trim_space(p)
	if p == "" || strings.contains(p, "..") {
		return strings.clone("index.mu", allocator)
	}
	base := filepath.base(p)
	if base == "" || base == "." || base == "/" || base == "\\" {
		return strings.clone("index.mu", allocator)
	}
	if strings.contains(base, "/") || strings.contains(base, "\\") {
		return strings.clone("index.mu", allocator)
	}
	for i in 0 ..< len(base) {
		c := base[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '.', '_', '-', '~':
		case:
			return strings.clone("index.mu", allocator)
		}
	}
	lower := strings.to_lower(base, context.temp_allocator)
	if strings.has_suffix(lower, ".mu") {
		return strings.clone(base, allocator)
	}
	return strings.concatenate({base, ".mu"}, allocator)
}

page_download :: proc(a: ^App) {
	if a.page_source == "" {
		set_status(a, "no page loaded", STATUS_HOLD)
		return
	}
	name := page_download_basename(a.page_path if a.page_path != "" else constants.DEFAULT_PAGE_PATH)
	defer delete(name)
	dir := store.config_download_dir(&a.cfg)
	defer delete(dir)
	out, ok := page_write_download(dir, name, a.page_source)
	if !ok {
		set_status(a, "page download failed", STATUS_HOLD)
		return
	}
	defer delete(out)
	set_status(a, fmt.tprintf("saved %s", out), STATUS_HOLD)
}

page_write_download :: proc(dir, filename, content: string, allocator := context.allocator) -> (path: string, ok: bool) {
	if dir == "" || filename == "" {
		return "", false
	}
	if os.make_directory_all(dir) != nil && !os.exists(dir) {
		return "", false
	}
	final_path, _ := filepath.join({dir, filename}, allocator)
	tmp_path := strings.concatenate({final_path, ".tmp"}, context.temp_allocator)
	if os.write_entire_file(tmp_path, transmute([]u8)content) != nil {
		delete(final_path)
		return "", false
	}
	if os.rename(tmp_path, final_path) != nil {
		_ = os.remove(tmp_path)
		delete(final_path)
		return "", false
	}
	return final_path, true
}
