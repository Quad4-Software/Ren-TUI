// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Unified search overlay. Searches conversations (name and message text),
directory peers, and the locally served/downloaded pages and files under
data_dir. Enter on a result jumps to the matching tab.
*/

package app

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "ren:micron"
import "ren:store"
import "ren:ui"

SEARCH_MAX_RESULTS :: 200

search_begin :: proc(a: ^App) {
	a.search_open = true
	set_status(a, "search all  Enter open  Esc close", STATUS_HOLD)
	search_refresh(a)
	mark_dirty(a)
}

search_close :: proc(a: ^App) {
	a.search_open = false
	ui.input_clear(&a.search_input)
	search_clear_results(a)
	mark_dirty(a)
}

search_clear_results :: proc(a: ^App) {
	for &r in a.search_results {
		delete(r.disk)
		delete(r.req)
	}
	clear(&a.search_results)
	ui.list_clear(&a.search_list)
}

search_visible :: proc(a: ^App) -> int {
	h := a.search_list_rect.h
	if h <= 1 && a.term_h > 0 {
		return max(1, a.term_h - 8)
	}
	return max(1, h)
}

search_push :: proc(a: ^App, res: Search_Result, line: string) {
	if len(a.search_results) >= SEARCH_MAX_RESULTS {
		delete(res.disk)
		delete(res.req)
		return
	}
	append(&a.search_results, res)
	ui.list_push(&a.search_list, line)
}

search_contains :: proc(haystack, q: string) -> bool {
	if haystack == "" {
		return false
	}
	l := strings.to_lower(haystack, context.temp_allocator)
	return strings.contains(l, q)
}

search_refresh :: proc(a: ^App) {
	prev := a.search_list.selected
	search_clear_results(a)
	q := strings.to_lower(strings.trim_space(ui.input_value(&a.search_input)), context.temp_allocator)
	if q == "" {
		a.search_list.selected = 0
		a.search_list.scroll = 0
		return
	}
	search_conversations(a, q)
	search_peers(a, q)
	search_served_dirs(a, q)
	if len(a.search_list.items) == 0 {
		return
	}
	a.search_list.selected = clamp(prev, 0, len(a.search_list.items) - 1)
	a.search_list.scroll = clamp(a.search_list.scroll, 0, max(0, len(a.search_list.items) - 1))
	ui.list_ensure_visible(&a.search_list, search_visible(a))
}

// Match contact name, hash, title, or any message body.
search_conversations :: proc(a: ^App, q: string) {
	idxs := make([dynamic]int, 0, len(a.conversations.items), context.temp_allocator)
	for _, i in a.conversations.items {
		append(&idxs, i)
	}
	// Newest activity first so the top hit is the freshest thread.
	for i in 0 ..< len(idxs) {
		for j in i + 1 ..< len(idxs) {
			ti := conv_last_activity(a.conversations.items[idxs[i]])
			tj := conv_last_activity(a.conversations.items[idxs[j]])
			if tj > ti {
				idxs[i], idxs[j] = idxs[j], idxs[i]
			}
		}
	}
	for i in idxs {
		if len(a.search_results) >= SEARCH_MAX_RESULTS {
			return
		}
		conv := a.conversations.items[i]
		label := store.conversation_label(&a.directory, conv, context.temp_allocator)
		hex := store.hash_hex(conv.peer_hash, context.temp_allocator)
		matched := search_contains(label, q) ||
			search_contains(conv.title, q) ||
			search_contains(conv.custom_name, q) ||
			strings.contains(hex, q)
		snip := ""
		if !matched {
			for m in conv.messages {
				if search_contains(m.title, q) || search_contains(m.content, q) {
					matched = true
					snip = m.title if m.title != "" else m.content
					break
				}
			}
		}
		if !matched {
			continue
		}
		line: string
		if snip != "" {
			if nl := strings.index_byte(snip, '\n'); nl >= 0 {
				snip = snip[:nl]
			}
			line = fmt.tprintf("[conv] %s  | %s", label, truncate(snip, 48))
		} else {
			line = fmt.tprintf("[conv] %s", label)
		}
		search_push(a, Search_Result{kind = .Conversation, hash = conv.peer_hash}, line)
	}
}

search_peer_view_label :: proc(kind: store.Peer_Kind) -> string {
	switch kind {
	case .Lxmf:
		return "lxmf"
	case .Nomad_Node:
		return "nomad"
	case .Propagation:
		return "prop"
	}
	return "peer"
}

search_peers :: proc(a: ^App, q: string) {
	idxs := make([dynamic]int, 0, 64, context.temp_allocator)
	for p, i in a.directory.peers {
		hex := store.hash_hex(p.hash, context.temp_allocator)
		if !search_contains(p.display_name, q) && !strings.contains(hex, q) {
			continue
		}
		append(&idxs, i)
	}
	sort_peer_idxs_by_heard(&a.directory, idxs[:])
	for i in idxs {
		if len(a.search_results) >= SEARCH_MAX_RESULTS {
			return
		}
		p := a.directory.peers[i]
		name := p.display_name if p.display_name != "" else "-"
		hex := store.hash_hex(p.hash, context.temp_allocator)
		line := fmt.tprintf("[peer] %s  %s %s  %s", name, search_peer_view_label(p.kind), hex[:16], store.format_peer_hops_peer(p))
		search_push(a, Search_Result{kind = .Peer, hash = p.hash}, line)
	}
}

search_served_dirs :: proc(a: ^App, q: string) {
	seen := make(map[string]bool, context.temp_allocator)
	pages_dir, _ := filepath.join({a.cfg.data_dir, "pages"}, context.temp_allocator)
	files_dir, _ := filepath.join({a.cfg.data_dir, "files"}, context.temp_allocator)
	search_scan_dir(a, pages_dir, "/page/", .Page, q, &seen)
	search_scan_dir(a, files_dir, "/file/", .File, q, &seen)
	// Downloaded pages land in download_dir (default data_dir/pages). Scan it
	// too when it points somewhere else so cached pages still show up.
	dl := store.config_download_dir(&a.cfg, context.temp_allocator)
	if dl != "" && dl != pages_dir && dl != files_dir {
		search_scan_downloads(a, dl, q, &seen)
	}
}

search_scan_dir :: proc(a: ^App, dir, prefix: string, kind: Search_Result_Kind, q: string, seen: ^map[string]bool) {
	if dir == "" || !os.exists(dir) {
		return
	}
	infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return
	}
	for fi in infos {
		if len(a.search_results) >= SEARCH_MAX_RESULTS {
			return
		}
		if fi.type == .Directory || !search_contains(fi.name, q) {
			continue
		}
		search_push_file(a, dir, fi.name, prefix, kind, seen)
	}
}

// Downloads are a mix of .mu pages and other files, so classify by suffix.
search_scan_downloads :: proc(a: ^App, dir: string, q: string, seen: ^map[string]bool) {
	if dir == "" || !os.exists(dir) {
		return
	}
	infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return
	}
	for fi in infos {
		if len(a.search_results) >= SEARCH_MAX_RESULTS {
			return
		}
		if fi.type == .Directory || !search_contains(fi.name, q) {
			continue
		}
		if strings.has_suffix(strings.to_lower(fi.name, context.temp_allocator), ".mu") {
			search_push_file(a, dir, fi.name, "/page/", .Page, seen)
		} else {
			search_push_file(a, dir, fi.name, "/file/", .File, seen)
		}
	}
}

search_push_file :: proc(a: ^App, dir, name, prefix: string, kind: Search_Result_Kind, seen: ^map[string]bool) {
	key := fmt.tprintf("%d:%s", kind, name)
	if seen[key] {
		return
	}
	seen[key] = true
	disk, _ := filepath.join({dir, name}, context.allocator)
	req := fmt.aprintf("%s%s", prefix, name)
	tag := "page" if kind == .Page else "file"
	search_push(a, Search_Result{kind = kind, disk = disk, req = req}, fmt.tprintf("[%s] %s", tag, name))
}

search_activate :: proc(a: ^App) {
	row := a.search_list.selected
	if row < 0 || row >= len(a.search_results) {
		search_close(a)
		return
	}
	res := a.search_results[row]
	// Copy heap fields before search_close frees them.
	disk := strings.clone(res.disk, context.temp_allocator)
	req := strings.clone(res.req, context.temp_allocator)
	kind := res.kind
	hash := res.hash
	search_close(a)
	switch kind {
	case .Conversation:
		ui.input_clear(&a.conv_search)
		switch_tab(a, .Conversations)
		refresh_conv_list(a)
		select_conversation(a, hash)
	case .Peer:
		search_show_peer(a, hash)
	case .Page:
		search_open_local_page(a, disk, req)
	case .File:
		search_save_file(a, disk)
	}
}

search_show_peer :: proc(a: ^App, hash: [store.HASH_LEN]u8) {
	_ = store.directory_promote_from_spill(&a.directory, hash)
	view := Net_View.Lxmf
	for p in a.directory.peers {
		if p.hash == hash {
			switch p.kind {
			case .Lxmf:
				view = .Lxmf
			case .Nomad_Node:
				view = .Nomad
			case .Propagation:
				view = .Propagation
			}
			break
		}
	}
	a.net_view = view
	ui.input_clear(&a.net_search)
	a.net_filter_tick += 1
	show_network_tab(a)
	for idx, row in a.net_peer_idx {
		if idx < 0 || idx >= len(a.directory.peers) {
			continue
		}
		if a.directory.peers[idx].hash == hash {
			a.net_list.selected = row
			ui.list_ensure_visible(&a.net_list, network_list_visible(a))
			break
		}
	}
}

search_open_local_page :: proc(a: ^App, disk, req: string) {
	data, err := os.read_entire_file_from_path(disk, context.allocator)
	if err != nil {
		set_status(a, "cannot open page file", STATUS_HOLD)
		return
	}
	defer delete(data)
	page_clear(a)
	a.page_path = strings.clone(req)
	a.page_source = page_sanitize_bytes(data)
	a.page_doc = micron.parse(a.page_source)
	a.page_link_focus = 0 if a.page_doc.link_count > 0 else -1
	page_form_init_from_doc(a)
	a.page_has_node = false
	switch_tab(a, .Page)
	set_status(a, fmt.tprintf("local page %s", req), STATUS_HOLD)
}

// Local served files are already on disk. Copy into download_dir so the user
// gets a copy in the usual spot, unless it already lives there.
search_save_file :: proc(a: ^App, disk: string) {
	dir := store.config_download_dir(&a.cfg, context.temp_allocator)
	if filepath.dir(disk) == dir {
		set_status(a, fmt.tprintf("already in downloads: %s", disk), STATUS_HOLD)
		return
	}
	data, err := os.read_entire_file_from_path(disk, context.allocator)
	if err != nil {
		set_status(a, "cannot open file", STATUS_HOLD)
		return
	}
	defer delete(data)
	name := filepath.base(disk)
	out, ok := page_write_bytes(dir, name, data)
	if !ok {
		set_status(a, "file save failed", STATUS_HOLD)
		return
	}
	defer delete(out)
	set_status(a, fmt.tprintf("saved %s", out), STATUS_HOLD)
}

// Modal input for the overlay. Called only while a.search_open is set.
search_handle_event :: proc(a: ^App, ev: ui.Event) {
	#partial switch ev.kind {
	case .Esc:
		search_close(a)
	case .Enter:
		search_activate(a)
	case .Up:
		ui.list_move(&a.search_list, -1, search_visible(a))
	case .Down:
		ui.list_move(&a.search_list, 1, search_visible(a))
	case .Page_Up:
		ui.list_move(&a.search_list, -search_visible(a), search_visible(a))
	case .Page_Down:
		ui.list_move(&a.search_list, search_visible(a), search_visible(a))
	case:
		if ui.input_handle(&a.search_input, ev) {
			search_refresh(a)
		}
	}
}
