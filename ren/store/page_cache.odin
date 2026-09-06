// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Offline page/file cache. Fetched NomadNet content is stored under
download_dir (default data_dir/pages) with a cache_ prefixed name derived
from the node hash and request path. A small plaintext index file keeps the
original node hash and page path so cached copies can be listed and opened
when the network is unreachable. Oldest entries are evicted once the count
or byte caps in constants are exceeded.
*/

package store

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "ren:constants"
import "ren:lxmf"

Page_Cache_Entry :: struct {
	node:  [HASH_LEN]u8,
	path:  string, // original request path, heap owned
	file:  string, // cache_ filename inside download_dir, heap owned
	size:  i64,
	saved: f64, // unix seconds
}

page_cache_index_path :: proc(c: ^Config, allocator := context.allocator) -> string {
	dir := config_download_dir(c, context.temp_allocator)
	p, _ := filepath.join({dir, constants.PAGE_CACHE_INDEX_FILE}, allocator)
	return p
}

page_cache_file_path :: proc(c: ^Config, file: string, allocator := context.allocator) -> string {
	dir := config_download_dir(c, context.temp_allocator)
	p, _ := filepath.join({dir, file}, allocator)
	return p
}

// cache_<hash8>_<path with non-safe bytes replaced by _>. Deterministic so
// refetches overwrite the same file.
page_cache_safe_name :: proc(node: [HASH_LEN]u8, path: string, allocator := context.allocator) -> string {
	hex := hash_hex(node, context.temp_allocator)
	h8 := hex
	if len(h8) > 8 {
		h8 = h8[:8]
	}
	b: strings.Builder
	strings.builder_init(&b, allocator = allocator)
	strings.write_string(&b, constants.PAGE_CACHE_PREFIX)
	strings.write_string(&b, h8)
	strings.write_byte(&b, '_')
	n := 0
	for i in 0 ..< len(path) {
		ch := path[i]
		safe := false
		switch ch {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '.', '_', '-', '~':
			safe = true
		}
		strings.write_byte(&b, ch if safe else '_')
		n += 1
		if n >= 64 {
			break
		}
	}
	return strings.to_string(b)
}

// Read the index file and stat each entry. Missing files are skipped.
// Returned strings are allocated with allocator.
page_cache_index_read :: proc(c: ^Config, allocator := context.allocator) -> [dynamic]Page_Cache_Entry {
	out := make([dynamic]Page_Cache_Entry, allocator)
	idx := page_cache_index_path(c, context.temp_allocator)
	data, err := os.read_entire_file_from_path(idx, context.temp_allocator)
	if err != nil {
		return out
	}
	dir := config_download_dir(c, context.temp_allocator)
	lines := strings.split_lines(string(data), context.temp_allocator)
	for line in lines {
		if line == "" {
			continue
		}
		parts := strings.split(line, "\t", context.temp_allocator)
		if len(parts) < 3 {
			continue
		}
		node, nok := lxmf.decode_hex32(parts[1])
		if !nok {
			continue
		}
		full, _ := filepath.join({dir, parts[0]}, context.temp_allocator)
		fi, serr := os.stat(full, context.temp_allocator)
		if serr != nil || fi.type != .Regular {
			continue
		}
		append(
			&out,
			Page_Cache_Entry{
				node = node,
				path = strings.clone(parts[2], allocator),
				file = strings.clone(parts[0], allocator),
				size = fi.size,
				saved = f64(time.time_to_unix_nano(fi.modification_time)) / 1e9,
			},
		)
	}
	return out
}

page_cache_entries_destroy :: proc(entries: ^[dynamic]Page_Cache_Entry) {
	for &e in entries {
		delete(e.path)
		delete(e.file)
	}
	delete(entries^)
	entries^ = nil
}

// Entries sorted newest first.
page_cache_list :: proc(c: ^Config, allocator := context.allocator) -> [dynamic]Page_Cache_Entry {
	entries := page_cache_index_read(c, allocator)
	for i in 1 ..< len(entries) {
		for j := i; j > 0 && entries[j].saved > entries[j - 1].saved; j -= 1 {
			entries[j], entries[j - 1] = entries[j - 1], entries[j]
		}
	}
	return entries
}

page_cache_index_write :: proc(c: ^Config, entries: []Page_Cache_Entry) -> bool {
	b: strings.Builder
	strings.builder_init(&b, allocator = context.temp_allocator)
	for e in entries {
		hex := hash_hex(e.node, context.temp_allocator)
		strings.write_string(&b, fmt.tprintf("%s\t%s\t%s\n", e.file, hex, e.path))
	}
	idx := page_cache_index_path(c, context.temp_allocator)
	return os.write_entire_file(idx, transmute([]u8)strings.to_string(b)) == nil
}

// Save fetched content into the cache and refresh the index. Safe to call on
// every successful fetch. Caps are enforced after the write.
page_cache_save :: proc(c: ^Config, node: [HASH_LEN]u8, path: string, data: []u8) -> bool {
	if len(data) == 0 || path == "" {
		return false
	}
	dir := config_download_dir(c, context.temp_allocator)
	if dir == "" {
		return false
	}
	if os.make_directory_all(dir) != nil && !os.exists(dir) {
		return false
	}
	name := page_cache_safe_name(node, path, context.temp_allocator)
	full, _ := filepath.join({dir, name}, context.temp_allocator)
	tmp := strings.concatenate({full, ".tmp"}, context.temp_allocator)
	if os.write_entire_file(tmp, data) != nil {
		return false
	}
	if os.rename(tmp, full) != nil {
		_ = os.remove(tmp)
		return false
	}
	entries := page_cache_index_read(c, context.temp_allocator)
	defer page_cache_entries_destroy(&entries)
	kept := make([dynamic]Page_Cache_Entry, 0, len(entries) + 1, context.temp_allocator)
	for e in entries {
		if e.file == name || (e.node == node && e.path == path) {
			continue
		}
		append(&kept, e)
	}
	append(
		&kept,
		Page_Cache_Entry{
			node = node,
			path = path,
			file = name,
			size = i64(len(data)),
			saved = f64(time.time_to_unix_nano(time.now())) / 1e9,
		},
	)
	_ = page_cache_index_write(c, kept[:])
	page_cache_enforce(c)
	return true
}

// Find a cached copy for a path. When has_node is false the newest copy from
// any node wins. Returned entry strings are allocated with allocator.
page_cache_match :: proc(
	c: ^Config,
	node: [HASH_LEN]u8,
	has_node: bool,
	path: string,
	allocator := context.allocator,
) -> (
	e: Page_Cache_Entry,
	ok: bool,
) {
	if path == "" {
		return {}, false
	}
	entries := page_cache_index_read(c, context.temp_allocator)
	defer page_cache_entries_destroy(&entries)
	best := -1
	for x, i in entries {
		if x.path != path {
			continue
		}
		if has_node {
			if x.node == node {
				best = i
				break
			}
		} else if best < 0 || x.saved > entries[best].saved {
			best = i
		}
	}
	if best < 0 {
		return {}, false
	}
	src := entries[best]
	e.node = src.node
	e.path = strings.clone(src.path, allocator)
	e.file = strings.clone(src.file, allocator)
	e.size = src.size
	e.saved = src.saved
	return e, true
}

page_cache_entry_destroy :: proc(e: ^Page_Cache_Entry) {
	delete(e.path)
	delete(e.file)
	e^ = {}
}

// Read the cached bytes for a matched entry. Caller owns the result.
page_cache_read :: proc(c: ^Config, file: string, allocator := context.allocator) -> (data: []u8, ok: bool) {
	if file == "" {
		return nil, false
	}
	full := page_cache_file_path(c, file, context.temp_allocator)
	d, err := os.read_entire_file_from_path(full, allocator)
	if err != nil {
		return nil, false
	}
	return d, true
}

// Delete oldest cached files until both caps are satisfied.
page_cache_enforce :: proc(c: ^Config) {
	entries := page_cache_index_read(c, context.temp_allocator)
	defer page_cache_entries_destroy(&entries)
	total: i64 = 0
	for e in entries {
		total += e.size
	}
	if len(entries) <= constants.PAGE_CACHE_MAX_FILES && total <= i64(constants.PAGE_CACHE_MAX_BYTES) {
		return
	}
	// Oldest first so the front of `kept` is what gets evicted.
	for i in 1 ..< len(entries) {
		for j := i; j > 0 && entries[j].saved < entries[j - 1].saved; j -= 1 {
			entries[j], entries[j - 1] = entries[j - 1], entries[j]
		}
	}
	dir := config_download_dir(c, context.temp_allocator)
	kept := make([dynamic]Page_Cache_Entry, 0, len(entries), context.temp_allocator)
	count := 0
	for e in entries {
		over_count := len(entries) - count > constants.PAGE_CACHE_MAX_FILES
		over_bytes := total > i64(constants.PAGE_CACHE_MAX_BYTES)
		if over_count || over_bytes {
			full, _ := filepath.join({dir, e.file}, context.temp_allocator)
			_ = os.remove(full)
			total -= e.size
			count += 1
			continue
		}
		append(&kept, e)
	}
	_ = page_cache_index_write(c, kept[:])
}
