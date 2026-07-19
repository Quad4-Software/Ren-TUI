// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Load and save conversations as msgpack on disk.
*/

package store

import "core:encoding/hex"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "ren:constants"
import "ren:lxmf"

conversations_dir :: proc(cfg: ^Config, allocator := context.allocator) -> string {
	p, _ := filepath.join({cfg.data_dir, constants.CONVERSATIONS_DIR}, allocator)
	return p
}

conversations_load :: proc(c: ^Conversations, cfg: ^Config) {
	dir := conversations_dir(cfg, context.temp_allocator)
	if !os.exists(dir) {
		return
	}
	entries, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil {
		return
	}
	defer {
		for e in entries {
			os.file_info_delete(e, context.allocator)
		}
		delete(entries)
	}
	for e in entries {
		if e.type != .Directory {
			continue
		}
		name := e.name
		if len(name) != HASH_LEN * 2 {
			continue
		}
		peer, ok := decode_peer_hex(name)
		if !ok {
			continue
		}
		path, _ := filepath.join({dir, name, constants.MESSAGES_FILE}, context.temp_allocator)
		data, rerr := os.read_entire_file_from_path(path, context.allocator)
		if rerr != nil {
			continue
		}
		defer delete(data)
		_ = conversations_decode_file(c, peer, data)
	}
}

conversations_save_all :: proc(c: ^Conversations, cfg: ^Config) -> bool {
	ok_all := true
	for conv in c.items {
		if !conversations_save_peer(c, cfg, conv.peer_hash) {
			ok_all = false
		}
	}
	return ok_all
}

conversations_save_peer :: proc(c: ^Conversations, cfg: ^Config, peer: [HASH_LEN]u8) -> bool {
	idx := conversations_index_of(c, peer)
	if idx < 0 {
		return false
	}
	conv := c.items[idx]
	dir := conversations_dir(cfg, context.temp_allocator)
	peer_dir, _ := filepath.join({dir, hash_hex(peer, context.temp_allocator)}, context.temp_allocator)
	if os.make_directory_all(peer_dir) != nil && !os.exists(peer_dir) {
		return false
	}
	data, ok := conversations_encode_peer(&conv)
	if !ok {
		return false
	}
	defer delete(data)
	final_path, _ := filepath.join({peer_dir, constants.MESSAGES_FILE}, context.temp_allocator)
	tmp_path := strings.concatenate({final_path, ".tmp"}, context.temp_allocator)
	if os.write_entire_file(tmp_path, data) != nil {
		return false
	}
	if os.rename(tmp_path, final_path) != nil {
		_ = os.remove(tmp_path)
		return false
	}
	return true
}

@(private)
conversations_encode_peer :: proc(conv: ^Conversation) -> ([]u8, bool) {
	w: lxmf.Writer
	lxmf.writer_init(&w)
	defer lxmf.writer_destroy(&w)

	lxmf.write_array_header(&w, 5)
	lxmf.write_int(&w, i64(constants.CONVERSATIONS_SCHEMA_VERSION))
	lxmf.write_bin(&w, conv.peer_hash[:])
	lxmf.write_str(&w, conv.title)
	lxmf.write_int(&w, i64(conv.unread))
	lxmf.write_array_header(&w, len(conv.messages))
	for m in conv.messages {
		lxmf.write_array_header(&w, 9)
		id := m.id
		lxmf.write_bin(&w, id[:])
		lxmf.write_int(&w, 0 if m.direction == .In else 1)
		lxmf.write_str(&w, m.title)
		lxmf.write_str(&w, m.content)
		lxmf.write_f64(&w, m.timestamp)
		lxmf.write_int(&w, i64(m.method))
		lxmf.write_bool(&w, m.verified)
		lxmf.write_bool(&w, m.stamped)
		lxmf.write_int(&w, i64(m.hops))
	}
	return bytes_clone(lxmf.writer_bytes(&w)), true
}

@(private)
conversations_decode_file :: proc(c: ^Conversations, peer: [HASH_LEN]u8, data: []u8) -> bool {
	r: lxmf.Reader
	lxmf.reader_init(&r, data)
	root, err := lxmf.decode_value(&r)
	if err != .None || root.kind != .Array || len(root.array) < 4 {
		lxmf.value_destroy(&root)
		return false
	}
	defer lxmf.value_destroy(&root)

	title_i := 1
	unread_i := 2
	msgs_i := 3
	if len(root.array) >= 5 {
		if ver, vok := lxmf.as_int(root.array[0]); vok {
			if ver < 1 || ver > i64(constants.CONVERSATIONS_SCHEMA_VERSION) {
				return false
			}
			title_i = 2
			unread_i = 3
			msgs_i = 4
		}
	}

	title := ""
	if root.array[title_i].kind == .Str {
		title = root.array[title_i].str
	} else if b, ok := lxmf.as_bytes(root.array[title_i]); ok {
		title = string(b)
	}
	unread: int
	if n, ok := lxmf.as_int(root.array[unread_i]); ok {
		unread = int(n)
	}
	msgs_v := root.array[msgs_i]
	if msgs_v.kind != .Array {
		return false
	}

	conv := conversations_get_or_create(c, peer, title if title != "" else hash_hex(peer, context.temp_allocator))
	conv.unread = unread
	for item in msgs_v.array {
		if item.kind != .Array || len(item.array) < 9 {
			continue
		}
		msg: Stored_Message
		if idb, ok := lxmf.as_bytes(item.array[0]); ok && len(idb) == lxmf.MESSAGE_ID_LEN {
			copy(msg.id[:], idb)
		}
		if d, ok := lxmf.as_int(item.array[1]); ok {
			msg.direction = .Out if d == 1 else .In
		}
		if item.array[2].kind == .Str {
			msg.title = strings.clone(item.array[2].str)
		} else if b, ok := lxmf.as_bytes(item.array[2]); ok {
			msg.title = string(bytes_clone(b))
		} else {
			msg.title = strings.clone("")
		}
		if item.array[3].kind == .Str {
			msg.content = strings.clone(item.array[3].str)
		} else if b, ok := lxmf.as_bytes(item.array[3]); ok {
			msg.content = string(bytes_clone(b))
		} else {
			msg.content = strings.clone("")
		}
		if ts, ok := lxmf.as_f64(item.array[4]); ok {
			msg.timestamp = ts
		}
		if m, ok := lxmf.as_int(item.array[5]); ok {
			msg.method = lxmf.Method(u8(m))
		}
		if item.array[6].kind == .Bool {
			msg.verified = item.array[6].b
		}
		if item.array[7].kind == .Bool {
			msg.stamped = item.array[7].b
		}
		if h, ok := lxmf.as_int(item.array[8]); ok {
			msg.hops = u8(h)
		}
		append(&conv.messages, msg)
	}
	return true
}

@(private)
decode_peer_hex :: proc(s: string) -> ([HASH_LEN]u8, bool) {
	if len(s) != HASH_LEN * 2 {
		return {}, false
	}
	out: [HASH_LEN]u8
	decoded, ok := hex.decode(transmute([]u8)s, context.temp_allocator)
	if !ok || len(decoded) != HASH_LEN {
		return {}, false
	}
	copy(out[:], decoded)
	return out, true
}

@(private)
bytes_clone :: proc(data: []u8, allocator := context.allocator) -> []u8 {
	out := make([]u8, len(data), allocator)
	copy(out, data)
	return out
}
