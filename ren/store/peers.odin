// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Cold peer spill to msgpack so announce storms stay out of hot RAM.
*/

package store

import "core:os"
import "core:path/filepath"
import "core:strings"

import "ren:constants"
import "ren:lxmf"

peers_spill_path :: proc(cfg: ^Config, allocator := context.allocator) -> string {
	p, _ := filepath.join({cfg.data_dir, constants.PEERS_FILE}, allocator)
	return p
}

directory_bind_spill :: proc(d: ^Directory, cfg: ^Config) {
	delete(d.spill_path)
	d.spill_path = peers_spill_path(cfg)
}

directory_load_spill_meta :: proc(d: ^Directory) {
	d.spill_count = peers_spill_count(d.spill_path)
}

peers_spill_count :: proc(path: string) -> int {
	if path == "" || !os.exists(path) {
		return 0
	}
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		return 0
	}
	defer delete(data)
	peers, ok := peers_decode(data)
	if !ok {
		return 0
	}
	n := len(peers)
	peers_destroy(peers)
	return n
}

peers_destroy :: proc(peers: [dynamic]Peer) {
	for &p in peers {
		delete(p.display_name)
	}
	delete(peers)
}

peers_encode :: proc(peers: []Peer) -> ([]u8, bool) {
	w: lxmf.Writer
	lxmf.writer_init(&w)
	defer lxmf.writer_destroy(&w)
	lxmf.write_array_header(&w, len(peers))
	for p in peers {
		lxmf.write_array_header(&w, 7)
		h := p.hash
		ih := p.identity_hash
		lxmf.write_bin(&w, h[:])
		lxmf.write_bin(&w, ih[:])
		lxmf.write_int(&w, i64(p.kind))
		lxmf.write_str(&w, p.display_name)
		if sc, ok := p.stamp_cost.?; ok {
			lxmf.write_int(&w, sc)
		} else {
			lxmf.write_nil(&w)
		}
		lxmf.write_int(&w, i64(p.hops))
		lxmf.write_f64(&w, p.last_heard)
	}
	out := make([]u8, len(w.buf))
	copy(out, w.buf[:])
	return out, true
}

peers_decode :: proc(data: []u8) -> ([dynamic]Peer, bool) {
	out := make([dynamic]Peer)
	r: lxmf.Reader
	lxmf.reader_init(&r, data)
	root, err := lxmf.decode_value(&r)
	if err != .None || root.kind != .Array {
		lxmf.value_destroy(&root)
		delete(out)
		return nil, false
	}
	defer lxmf.value_destroy(&root)
	for item in root.array {
		if item.kind != .Array || len(item.array) < 7 {
			continue
		}
		p: Peer
		if hb, ok := lxmf.as_bytes(item.array[0]); ok && len(hb) == HASH_LEN {
			copy(p.hash[:], hb)
		} else {
			continue
		}
		if ib, ok := lxmf.as_bytes(item.array[1]); ok && len(ib) == HASH_LEN {
			copy(p.identity_hash[:], ib)
		}
		if k, ok := lxmf.as_int(item.array[2]); ok {
			switch k {
			case 0:
				p.kind = .Lxmf
			case 1:
				p.kind = .Nomad_Node
			case 2:
				p.kind = .Propagation
			case:
				p.kind = .Lxmf
			}
		}
		if item.array[3].kind == .Str {
			p.display_name = strings.clone(item.array[3].str)
		} else {
			p.display_name = strings.clone("")
		}
		if item.array[4].kind != .Nil {
			if sc, ok := lxmf.as_int(item.array[4]); ok {
				p.stamp_cost = sc
			}
		}
		if h, ok := lxmf.as_int(item.array[5]); ok {
			p.hops = u8(h)
		}
		if fh, ok := lxmf.as_f64(item.array[6]); ok {
			p.last_heard = fh
		}
		append(&out, p)
	}
	return out, true
}

peers_spill_load_all :: proc(path: string) -> [dynamic]Peer {
	if path == "" || !os.exists(path) {
		return make([dynamic]Peer)
	}
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		return make([dynamic]Peer)
	}
	defer delete(data)
	peers, ok := peers_decode(data)
	if !ok {
		return make([dynamic]Peer)
	}
	return peers
}

peers_spill_save_all :: proc(path: string, peers: []Peer) -> bool {
	if path == "" {
		return false
	}
	dir := filepath.dir(path)
	_ = os.make_directory_all(dir)
	data, ok := peers_encode(peers)
	if !ok {
		return false
	}
	defer delete(data)
	tmp := strings.concatenate({path, ".tmp"}, context.temp_allocator)
	if os.write_entire_file(tmp, data) != nil {
		return false
	}
	if os.rename(tmp, path) != nil {
		_ = os.remove(tmp)
		return false
	}
	return true
}

// Evict coldest hot peers into spill file until under PEERS_HOT_MAX.
directory_enforce_hot_cap :: proc(d: ^Directory) {
	for len(d.peers) > constants.PEERS_HOT_MAX {
		coldest := 0
		for i in 1 ..< len(d.peers) {
			if d.peers[i].last_heard < d.peers[coldest].last_heard {
				coldest = i
			}
		}
		cold := d.peers[coldest]
		ordered_remove(&d.peers, coldest)
		_ = peers_spill_upsert(d.spill_path, cold)
		delete(cold.display_name)
		d.spill_count = peers_spill_count(d.spill_path)
		d.revision += 1
	}
}

peers_spill_upsert :: proc(path: string, peer: Peer) -> bool {
	cold := peers_spill_load_all(path)
	defer peers_destroy(cold)
	found := false
	for &p in cold {
		if p.hash == peer.hash {
			delete(p.display_name)
			p.display_name = strings.clone(peer.display_name)
			p.identity_hash = peer.identity_hash
			p.kind = peer.kind
			p.stamp_cost = peer.stamp_cost
			p.hops = peer.hops
			p.last_heard = peer.last_heard
			found = true
			break
		}
	}
	if !found {
		append(&cold, Peer{
			hash = peer.hash,
			identity_hash = peer.identity_hash,
			display_name = strings.clone(peer.display_name),
			stamp_cost = peer.stamp_cost,
			hops = peer.hops,
			last_heard = peer.last_heard,
			kind = peer.kind,
		})
	}
	// Cap spill by dropping coldest
	for len(cold) > constants.PEERS_SPILL_MAX {
		ci := 0
		for i in 1 ..< len(cold) {
			if cold[i].last_heard < cold[ci].last_heard {
				ci = i
			}
		}
		delete(cold[ci].display_name)
		ordered_remove(&cold, ci)
	}
	return peers_spill_save_all(path, cold[:])
}

// Promote a spilled peer into hot RAM if present.
directory_promote_from_spill :: proc(d: ^Directory, dest: [HASH_LEN]u8) -> bool {
	for p in d.peers {
		if p.hash == dest {
			return true
		}
	}
	cold := peers_spill_load_all(d.spill_path)
	defer peers_destroy(cold)
	idx := -1
	for i in 0 ..< len(cold) {
		if cold[i].hash == dest {
			idx = i
			break
		}
	}
	if idx < 0 {
		return false
	}
	p := cold[idx]
	append(&d.peers, Peer{
		hash = p.hash,
		identity_hash = p.identity_hash,
		display_name = strings.clone(p.display_name),
		stamp_cost = p.stamp_cost,
		hops = p.hops,
		last_heard = p.last_heard,
		kind = p.kind,
	})
	delete(cold[idx].display_name)
	ordered_remove(&cold, idx)
	_ = peers_spill_save_all(d.spill_path, cold[:])
	d.spill_count = len(cold)
	d.revision += 1
	directory_enforce_hot_cap(d)
	return true
}
