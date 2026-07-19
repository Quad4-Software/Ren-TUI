// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Reticulum node session announce delivery and poll.
*/

package net

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

import rns "rns:rns"
import "ren:constants"
import "ren:lxmf"
import "ren:store"

Session :: struct {
	node:           rns.Node,
	rns_identity:   rns.Identity,
	delivery_dest:  rns.Destination,
	node_dest:      rns.Destination,
	material:       lxmf.Identity_Material,
	router:         lxmf.Router,
	started:        bool,
	announce_every: time.Duration,
	last_announce:  time.Tick,
	status:         string,
	config_path:    string,
	announces:      int,
	lxmf_heard:     int,
	nodes_heard:    int,
	paths:          Path_Finder,
	page:           Page_Job,
}

session_create :: proc(s: ^Session, cfg: ^store.Config, display_name: string) -> bool {
	s^ = {}
	interval := cfg.announce_interval_sec
	if interval < constants.MIN_ANNOUNCE_INTERVAL_SEC {
		interval = constants.DEFAULT_ANNOUNCE_INTERVAL_SEC
	}
	s.announce_every = time.Duration(interval) * time.Second
	s.status = "offline"

	material, ok := lxmf.identity_load_file(cfg.identity_path)
	if !ok {
		material, ok = lxmf.identity_generate()
		if !ok {
			s.status = "identity generate failed"
			return false
		}
		if !store.config_ensure_dirs(cfg) {
			s.status = "could not create config dir"
			return false
		}
		if !lxmf.identity_save_file(&material, cfg.identity_path) {
			s.status = "identity save failed"
			return false
		}
	}
	s.material = material
	lxmf.router_init(&s.router, material, display_name)
	lxmf.router_set_stamp_cost(&s.router, cfg.stamp_cost)

	ver := rns.version()
	if ver != rns.API_VERSION {
		s.status = fmt.tprintf("librns %s want %s", ver, rns.API_VERSION)
		return false
	}

	config_path := cfg.rns_config
	if !os.exists(config_path) {
		s.status = fmt.tprintf("missing rns config %s", config_path)
		config_path = ""
	}
	s.config_path = strings.clone(config_path)

	node, nerr := rns.node_create(config_path)
	if nerr != .Ok {
		s.status = "node create failed"
		return false
	}
	s.node = node

	id, ierr := rns.identity_load(cfg.identity_path)
	if ierr != .Ok {
		s.status = "rns identity load failed"
		return false
	}
	s.rns_identity = id

	if rns.node_set_identity(s.node, s.rns_identity) != .Ok {
		s.status = "set identity failed"
		return false
	}

	dest, derr := rns.destination_create(s.node, s.rns_identity, lxmf.APP_NAME, {lxmf.ASPECT_DELIVERY}, true)
	if derr != .Ok {
		s.status = "delivery dest failed"
		return false
	}
	s.delivery_dest = dest

	ndest, nerr2 := rns.destination_create(s.node, s.rns_identity, "nomadnetwork", {"node"}, true)
	if nerr2 == .Ok {
		s.node_dest = ndest
	}

	return true
}

session_start :: proc(s: ^Session) -> bool {
	if rns.node_start(s.node) != .Ok {
		s.status = "node start failed"
		return false
	}
	s.started = true
	s.status = "online"
	session_announce(s)
	return true
}

session_announce :: proc(s: ^Session) {
	app_data := lxmf.router_announce_data(&s.router)
	defer delete(app_data)
	_ = rns.destination_announce(s.delivery_dest, app_data)
	if s.node_dest != 0 {
		name := transmute([]u8)s.router.display_name
		_ = rns.destination_announce(s.node_dest, name)
	}
	s.last_announce = time.tick_now()
	s.announces += 1
}

session_set_display_name :: proc(s: ^Session, name: string) {
	lxmf.router_set_display_name(&s.router, name)
}

session_set_announce_interval :: proc(s: ^Session, seconds: int) {
	sec := seconds
	if sec < constants.MIN_ANNOUNCE_INTERVAL_SEC {
		sec = constants.DEFAULT_ANNOUNCE_INTERVAL_SEC
	}
	s.announce_every = time.Duration(sec) * time.Second
}

session_poll :: proc(s: ^Session, directory: ^store.Directory, conversations: ^store.Conversations, cfg: ^store.Config = nil, auto_announce := true) {
	if !s.started {
		return
	}
	if auto_announce && time.tick_since(s.last_announce) >= s.announce_every {
		session_announce(s)
	}

	app_buf := make([]u8, 64 * 1024, context.temp_allocator)
	for {
		ev, code := rns.event_poll(s.node, 0, app_buf)
		if code != .Ok || ev.kind == .None {
			break
		}
		if session_page_on_event(s, &ev) {
			continue
		}
		session_handle_event(s, &ev, directory, conversations, cfg)
	}
	session_page_tick(s)
}

@(private)
session_handle_event :: proc(
	s: ^Session,
	ev: ^rns.Event,
	directory: ^store.Directory,
	conversations: ^store.Conversations,
	cfg: ^store.Config = nil,
) {
	switch ev.kind {
	case .Announce:
		dest := rns.event_destination_hash(ev)
		ident := rns.event_identity_hash(ev)
		app := rns.event_app_data(ev)
		if len(dest) != store.HASH_LEN {
			return
		}
		dh: [store.HASH_LEN]u8
		copy(dh[:], dest)
		ih: [store.HASH_LEN]u8
		if len(ident) == store.HASH_LEN {
			copy(ih[:], ident)
		}

		kind := lxmf.classify_announce(dh[:], ih[:])
		if kind == .Unknown && len(ident) != store.HASH_LEN {
			if name, nok := lxmf.parse_announce_display_name(app); nok {
				stamp, sok := lxmf.parse_announce_stamp_cost(app)
				cost: Maybe(i64)
				if sok {
					cost = stamp
				}
				store.directory_upsert(directory, dh, ih, .Lxmf, name, cost, ev.hops)
				delete(name)
				s.lxmf_heard += 1
				return
			}
			if len(app) > 0 {
				store.directory_upsert(directory, dh, ih, .Nomad_Node, string(app), nil, ev.hops)
				s.nodes_heard += 1
				return
			}
		}
		switch kind {
		case .Lxmf_Delivery:
			name, nok := lxmf.parse_announce_display_name(app)
			stamp, sok := lxmf.parse_announce_stamp_cost(app)
			cost: Maybe(i64)
			if sok {
				cost = stamp
			}
			label := name if nok else ""
			store.directory_upsert(directory, dh, ih, .Lxmf, label, cost, ev.hops)
			if nok {
				delete(name)
			}
			s.lxmf_heard += 1
		case .Nomad_Node:
			label := string(app) if len(app) > 0 else ""
			store.directory_upsert(directory, dh, ih, .Nomad_Node, label, nil, ev.hops)
			s.nodes_heard += 1
		case .Lxmf_Propagation:
			store.directory_upsert(directory, dh, ih, .Propagation, "propagation", nil, ev.hops)
		case .Unknown:
			directory.heard_other += 1
		}
	case .Link_Data:
		session_ingest_lxmf(s, rns.event_app_data(ev), .Direct, directory, conversations, cfg)
	case .Destination_Data:
		// Opportunistic LXMF: plaintext is packed[DEST_LEN:] so prepend our delivery hash
		plain := rns.event_app_data(ev)
		if len(plain) == 0 {
			return
		}
		full := make([]u8, store.HASH_LEN + len(plain), context.temp_allocator)
		copy(full[0:store.HASH_LEN], s.router.delivery_hash[:])
		copy(full[store.HASH_LEN:], plain)
		session_ingest_lxmf(s, full, .Opportunistic, directory, conversations, cfg)
	case .Resource_Concluded:
		session_ingest_lxmf(s, rns.event_app_data(ev), .Direct, directory, conversations, cfg)
	case .Link_Established, .Link_Failed, .Link_Closed,
	     .Request_Incoming, .Request_Response, .Request_Failed,
	     .Resource_Started, .None:
	}
}

@(private)
session_ingest_lxmf :: proc(
	s: ^Session,
	data: []u8,
	method: lxmf.Method,
	directory: ^store.Directory,
	conversations: ^store.Conversations,
	cfg: ^store.Config = nil,
) {
	if len(data) == 0 {
		return
	}
	msg, ok := lxmf.message_unpack(data, method)
	if !ok {
		s.status = "lxmf unpack failed"
		return
	}
	defer lxmf.message_destroy(&msg)
	if !lxmf.router_validate_inbound_stamp(&s.router, &msg) {
		s.status = "stamp rejected"
		return
	}
	label := store.directory_label(directory, msg.source_hash)
	defer delete(label)
	stored := store.Stored_Message{
		id = msg.message_id,
		direction = .In,
		title = strings.clone(msg.title),
		content = strings.clone(msg.content),
		timestamp = msg.timestamp,
		method = msg.method,
		verified = msg.signature_ok,
		stamped = len(msg.stamp) > 0,
		hops = store.directory_hops(directory, msg.source_hash),
	}
	if cfg != nil {
		store.conversations_add_message_persist(conversations, cfg, msg.source_hash, stored, label)
	} else {
		store.conversations_add_message(conversations, msg.source_hash, stored, label)
	}
	s.status = "message received"
}

session_send_direct :: proc(
	s: ^Session,
	dest_hash: [store.HASH_LEN]u8,
	title, content: string,
	conversations: ^store.Conversations,
	directory: ^store.Directory,
	cfg: ^store.Config = nil,
) -> bool {
	cost := store.directory_stamp_cost(directory, dest_hash)
	msg, ok := lxmf.router_compose(&s.router, dest_hash, title, content, .Direct, cost)
	if !ok {
		s.status = "compose failed"
		return false
	}
	defer lxmf.message_destroy(&msg)

	dh := dest_hash
	_, _ = path_ensure(s, dest_hash, true)
	link, lerr := rns.link_open(s.node, dh[:])
	if lerr != .Ok {
		s.status = "link open failed"
		return false
	}
	deadline := time.tick_add(time.tick_now(), time.Duration(constants.LINK_TIMEOUT_SEC) * time.Second)
	established := false
	app_buf := make([]u8, 64 * 1024, context.temp_allocator)
	for time.tick_diff(time.tick_now(), deadline) > 0 {
		ev, code := rns.event_poll(s.node, 200, app_buf)
		if code != .Ok {
			continue
		}
		if ev.kind == .Announce || ev.kind == .Link_Data || ev.kind == .Destination_Data || ev.kind == .Resource_Concluded {
			session_handle_event(s, &ev, directory, conversations, cfg)
		}
		if ev.kind == .Link_Established {
			established = true
			break
		}
		if ev.kind == .Link_Failed {
			break
		}
	}
	if !established {
		_ = rns.link_close(link)
		// One recovery attempt: refresh path then reopen
		_ = rns.node_refresh_paths(s.node, {dest_hash})
		_ = rns.path_request(s.node, dh[:])
		link2, lerr2 := rns.link_open(s.node, dh[:])
		if lerr2 != .Ok {
			s.status = "link timeout"
			return false
		}
		link = link2
		deadline = time.tick_add(time.tick_now(), time.Duration(constants.LINK_TIMEOUT_SEC) * time.Second)
		for time.tick_diff(time.tick_now(), deadline) > 0 {
			ev, code := rns.event_poll(s.node, 200, app_buf)
			if code != .Ok {
				continue
			}
			if ev.kind == .Announce || ev.kind == .Link_Data || ev.kind == .Destination_Data || ev.kind == .Resource_Concluded {
				session_handle_event(s, &ev, directory, conversations, cfg)
			}
			if ev.kind == .Link_Established {
				established = true
				break
			}
			if ev.kind == .Link_Failed {
				break
			}
		}
		if !established {
			_ = rns.link_close(link)
			s.status = "link timeout"
			return false
		}
	}

	send_err := rns.link_send(link, msg.packed)
	if send_err != .Ok {
		_ = rns.link_send_resource(link, msg.packed, "lxmf")
	}
	_ = rns.link_close(link)

	label := store.directory_label(directory, dest_hash)
	defer delete(label)
	stored := store.Stored_Message{
		id = msg.message_id,
		direction = .Out,
		title = strings.clone(title),
		content = strings.clone(content),
		timestamp = msg.timestamp,
		method = .Direct,
		verified = true,
		stamped = len(msg.stamp) > 0,
		hops = store.directory_hops(directory, dest_hash),
	}
	if cfg != nil {
		store.conversations_add_message_persist(conversations, cfg, dest_hash, stored, label)
	} else {
		store.conversations_add_message(conversations, dest_hash, stored, label)
	}
	s.status = "sent"
	// Re-announce so peers get a fresh path back to our lxmf.delivery destination
	session_announce(s)
	return true
}

@(private)
bytes_clone :: proc(data: []u8, allocator := context.allocator) -> []u8 {
	out := make([]u8, len(data), allocator)
	copy(out, data)
	return out
}

session_close :: proc(s: ^Session) {
	session_page_cancel(s)
	path_finder_clear(&s.paths)
	if s.delivery_dest != 0 {
		_ = rns.destination_destroy(s.delivery_dest)
	}
	if s.node_dest != 0 {
		_ = rns.destination_destroy(s.node_dest)
	}
	if s.started {
		_ = rns.node_stop(s.node)
	}
	if s.rns_identity != 0 {
		_ = rns.identity_destroy(s.rns_identity)
	}
	if s.node != 0 {
		_ = rns.node_destroy(s.node)
	}
	lxmf.router_destroy(&s.router)
	delete(s.config_path)
	s^ = {}
}

session_delivery_hex :: proc(s: ^Session, allocator := context.allocator) -> string {
	return store.hash_hex(s.router.delivery_hash, allocator)
}

session_identity_hex :: proc(s: ^Session, allocator := context.allocator) -> string {
	return store.hash_hex(s.material.hash, allocator)
}

session_stats_line :: proc(s: ^Session, directory: ^store.Directory, allocator := context.allocator) -> string {
	return fmt.aprintf(
		"hot:%d cold:%d lxmf:%d nodes:%d ann:%d",
		len(directory.peers),
		directory.spill_count,
		store.directory_count_kind(directory, .Lxmf),
		store.directory_count_kind(directory, .Nomad_Node),
		s.announces,
		allocator = allocator,
	)
}

session_interfaces :: proc(s: ^Session, out: []rns.Interface_Entry) -> int {
	if !s.started || s.node == 0 {
		return 0
	}
	n, err := rns.interfaces_list(s.node, out)
	if err != .Ok && err != .Truncated {
		return 0
	}
	if n > len(out) {
		n = len(out)
	}
	return n
}

session_restart :: proc(s: ^Session, cfg: ^store.Config) -> bool {
	name := strings.clone(s.router.display_name, context.temp_allocator)
	session_close(s)
	if !session_create(s, cfg, name) {
		return false
	}
	return session_start(s)
}
