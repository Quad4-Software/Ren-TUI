// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Static page and file server for a nomadnetwork.node destination.
Serves files from data_dir/pages/ and data_dir/files/ over the librns
request/response API.  Paths are jailed to those directories and ".."
is rejected.
*/

package net

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import rns "rns:rns"
import "ren:store"

DEFAULT_PAGE :: `>Ren TUI Node

This node is now serving pages and files over Reticulum.
`

NOT_FOUND_PAGE := transmute([]u8)string(">Not Found\n\nThe requested page was not found.\n")
NOT_FOUND_FILE := transmute([]u8)string(">Not Found\n\nThe requested file was not found.\n")

Page_Server :: struct {
	enabled:   bool,
	node:      rns.Node,
	dest:      rns.Destination,
	pages_dir: string,
	files_dir: string,
	served:    int,
}

page_server_init :: proc(s: ^Page_Server, node: rns.Node, dest: rns.Destination, cfg: ^store.Config, enabled: bool) -> bool {
	s^ = {}
	if !enabled {
		return true
	}
	if node == 0 || dest == 0 {
		return false
	}
	s.enabled = true
	s.node = node
	s.dest = dest
	s.pages_dir, _ = filepath.join({cfg.data_dir, "pages"}, context.allocator)
	s.files_dir, _ = filepath.join({cfg.data_dir, "files"}, context.allocator)

	if err := os.make_directory_all(s.pages_dir); err != nil && !os.exists(s.pages_dir) {
		return false
	}
	if err := os.make_directory_all(s.files_dir); err != nil && !os.exists(s.files_dir) {
		return false
	}

	page_server_ensure_defaults(s)
	_ = page_server_register(s, dest, s.pages_dir, "/page/")
	_ = page_server_register(s, dest, s.files_dir, "/file/")
	return true
}

page_server_destroy :: proc(s: ^Page_Server) {
	delete(s.pages_dir)
	delete(s.files_dir)
	s^ = {}
}

page_server_ensure_defaults :: proc(s: ^Page_Server) {
	index_path, _ := filepath.join({s.pages_dir, "index.mu"}, context.temp_allocator)
	if !os.exists(index_path) {
		_ = os.write_entire_file(index_path, DEFAULT_PAGE)
	}
}

page_server_register :: proc(s: ^Page_Server, dest: rns.Destination, dir, prefix: string) -> int {
	if !os.exists(dir) {
		return 0
	}
	infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return 0
	}
	count := 0
	for fi in infos {
		if fi.type == .Directory {
			continue
		}
		if !page_server_name_safe(fi.name) {
			continue
		}
		request_path := fmt.tprintf("%s%s", prefix, fi.name)
		if rns.destination_register_request_handler(dest, request_path) == .Ok {
			count += 1
		}
	}
	return count
}

page_server_name_safe :: proc(name: string) -> bool {
	if name == "" || strings.contains(name, "..") {
		return false
	}
	for i in 0 ..< len(name) {
		c := name[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '.', '_', '-', '~':
		case:
			return false
		}
	}
	return true
}

page_server_serve :: proc(s: ^Page_Server, node: rns.Node, ev: ^rns.Event) -> bool {
	if !s.enabled || s.node == 0 {
		return false
	}
	if ev.path_truncated != 0 {
		return false
	}
	path := rns.event_path(ev)
	req_id := rns.event_request_id(ev)
	if len(req_id) == 0 {
		return false
	}

	if strings.has_prefix(path, "/page/") {
		disk, ok := page_server_map(s.pages_dir, "/page/", path)
		if !ok {
			_ = rns.request_respond(node, req_id, NOT_FOUND_PAGE)
			s.served += 1
			return true
		}
		data, rerr := os.read_entire_file_from_path(disk, context.allocator)
		if rerr != nil {
			_ = rns.request_respond(node, req_id, NOT_FOUND_PAGE)
		} else {
			_ = rns.request_respond(node, req_id, data)
			delete(data, context.allocator)
		}
		s.served += 1
		return true
	}

	if strings.has_prefix(path, "/file/") {
		disk, ok := page_server_map(s.files_dir, "/file/", path)
		if !ok {
			_ = rns.request_respond(node, req_id, NOT_FOUND_FILE)
			s.served += 1
			return true
		}
		data, rerr := os.read_entire_file_from_path(disk, context.allocator)
		if rerr != nil {
			_ = rns.request_respond(node, req_id, NOT_FOUND_FILE)
		} else {
			name := filepath.base(disk)
			_ = rns.request_respond_file(node, req_id, name, data)
			delete(data, context.allocator)
		}
		s.served += 1
		return true
	}

	_ = rns.request_respond(node, req_id, NOT_FOUND_PAGE)
	return true
}

page_server_map :: proc(server_dir, prefix, request_path: string) -> (disk_path: string, ok: bool) {
	if !strings.has_prefix(request_path, prefix) {
		return "", false
	}
	rel := request_path[len(prefix):]
	if rel == "" || strings.contains(rel, "..") || !page_server_name_safe(rel) {
		return "", false
	}
	joined, _ := filepath.join({server_dir, rel}, context.temp_allocator)
	cleaned, _ := filepath.clean(joined)
	if !strings.has_prefix(cleaned, server_dir) {
		return "", false
	}
	return cleaned, true
}
