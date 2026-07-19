// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Hot path cache and path discovery against librns path table.
*/

package net

import "core:time"

import rns "rns:rns"
import "ren:constants"
import "ren:store"

Path_Hot :: struct {
	hash:    [store.HASH_LEN]u8,
	hops:    u8,
	expires: time.Tick,
	used:    time.Tick,
	valid:   bool,
}

Path_Finder :: struct {
	hot: [constants.PATH_CACHE_MAX]Path_Hot,
}

path_finder_clear :: proc(pf: ^Path_Finder) {
	pf^ = {}
}

path_hot_lookup :: proc(pf: ^Path_Finder, dest: [store.HASH_LEN]u8) -> (entry: ^Path_Hot, ok: bool) {
	now := time.tick_now()
	for i in 0 ..< len(pf.hot) {
		e := &pf.hot[i]
		if !e.valid {
			continue
		}
		if e.hash != dest {
			continue
		}
		if time.tick_diff(now, e.expires) <= 0 {
			e.valid = false
			return nil, false
		}
		e.used = now
		return e, true
	}
	return nil, false
}

path_hot_remember :: proc(pf: ^Path_Finder, dest: [store.HASH_LEN]u8, hops: u8) {
	now := time.tick_now()
	ttl := time.Duration(constants.PATH_TTL_SEC) * time.Second
	expires := time.tick_add(now, ttl)

	for i in 0 ..< len(pf.hot) {
		e := &pf.hot[i]
		if e.valid && e.hash == dest {
			// Do not clobber a real hop count with librns unset (0).
			if hops > 0 {
				e.hops = hops
			}
			e.expires = expires
			e.used = now
			return
		}
	}
	for i in 0 ..< len(pf.hot) {
		e := &pf.hot[i]
		if !e.valid {
			e^ = Path_Hot{hash = dest, hops = hops, expires = expires, used = now, valid = true}
			return
		}
	}
	// Evict least recently used
	oldest := 0
	for i in 1 ..< len(pf.hot) {
		if time.tick_diff(pf.hot[i].used, pf.hot[oldest].used) > 0 {
			oldest = i
		}
	}
	pf.hot[oldest] = Path_Hot{hash = dest, hops = hops, expires = expires, used = now, valid = true}
}

// Push known path hops into the directory so Network list can show real values.
path_hot_sync_directory :: proc(pf: ^Path_Finder, directory: ^store.Directory) {
	if directory == nil {
		return
	}
	for e in pf.hot {
		if e.valid && e.hops > 0 {
			store.directory_apply_path_hops(directory, e.hash, e.hops)
		}
	}
}

path_hot_invalidate :: proc(pf: ^Path_Finder, dest: [store.HASH_LEN]u8) {
	for i in 0 ..< len(pf.hot) {
		e := &pf.hot[i]
		if e.valid && e.hash == dest {
			e.valid = false
			return
		}
	}
}

path_table_lookup :: proc(node: rns.Node, dest: [store.HASH_LEN]u8) -> (hops: u8, ok: bool) {
	entries := make([]rns.Path_Entry, constants.PATH_TABLE_CAP, context.temp_allocator)
	n, err := rns.path_table(node, entries)
	if err != .Ok || n == 0 {
		return 0, false
	}
	for i in 0 ..< n {
		e := entries[i]
		if int(e.hash_len) != store.HASH_LEN {
			continue
		}
		match := true
		for j in 0 ..< store.HASH_LEN {
			if e.hash[j] != dest[j] {
				match = false
				break
			}
		}
		if match {
			return e.hops, true
		}
	}
	return 0, false
}

// Ready if cached or present in librns path table. Otherwise issues path_request.
path_ensure :: proc(s: ^Session, dest: [store.HASH_LEN]u8, request_if_missing: bool) -> (ready: bool, hops: u8) {
	if !s.started {
		return false, 0
	}
	if e, ok := path_hot_lookup(&s.paths, dest); ok {
		if hops2, tok := path_table_lookup(s.node, dest); tok {
			if hops2 > 0 {
				e.hops = hops2
			}
			return true, e.hops if e.hops > 0 else hops2
		}
		// Cache said hot but table lost it
		path_hot_invalidate(&s.paths, dest)
	}
	if hops2, tok := path_table_lookup(s.node, dest); tok {
		path_hot_remember(&s.paths, dest, hops2)
		return true, hops2
	}
	if request_if_missing {
		dh := dest
		_ = rns.path_request(s.node, dh[:])
	}
	return false, 0
}

path_request_refresh :: proc(s: ^Session, dest: [store.HASH_LEN]u8) {
	if !s.started {
		return
	}
	dh := dest
	_ = rns.node_refresh_paths(s.node, {dest})
	_ = rns.path_request(s.node, dh[:])
}
