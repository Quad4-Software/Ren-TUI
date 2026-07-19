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

EVENT_APP_BUF_SIZE :: 64 * 1024

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
	events:         Session_Event_Ring,
	config_path:    string,
	announces:      int,
	lxmf_heard:     int,
	nodes_heard:    int,
	paths:          Path_Finder,
	page:           Page_Job,
	send:           Send_Job,
	send_transport: Send_Transport,
	poll_buf:       []u8,
}

session_create :: proc(s: ^Session, cfg: ^store.Config, display_name: string) -> bool {
	s^ = {}
	s.poll_buf = make([]u8, EVENT_APP_BUF_SIZE)
	interval := cfg.announce_interval_sec
	if interval < constants.MIN_ANNOUNCE_INTERVAL_SEC {
		interval = constants.DEFAULT_ANNOUNCE_INTERVAL_SEC
	}
	s.announce_every = time.Duration(interval) * time.Second
	session_set_status_text(s, "offline")

	material, ok := lxmf.identity_load_file(cfg.identity_path)
	if !ok {
		material, ok = lxmf.identity_generate()
		if !ok {
			session_event_push(s, .Error, "identity generate failed")
			return false
		}
		if !store.config_ensure_dirs(cfg) {
			session_event_push(s, .Error, "could not create config dir")
			return false
		}
		if !lxmf.identity_save_file(&material, cfg.identity_path) {
			session_event_push(s, .Error, "identity save failed")
			return false
		}
	}
	s.material = material
	lxmf.router_init(&s.router, material, display_name)
	lxmf.router_set_stamp_cost(&s.router, cfg.stamp_cost)

	ver := rns.version()
	if ver != rns.API_VERSION {
		session_event_push(s, .Error, fmt.tprintf("librns %s want %s", ver, rns.API_VERSION))
		return false
	}

	config_path := cfg.rns_config
	if !os.exists(config_path) {
		session_event_push(s, .Error, fmt.tprintf("missing rns config %s", config_path))
		config_path = ""
	}
	s.config_path = strings.clone(config_path)

	node, nerr := rns.node_create(config_path)
	if nerr != .Ok {
		session_event_push(s, .Error, "node create failed")
		return false
	}
	s.node = node

	// Same identity file lxmf already loaded or wrote. One file owner, two readers.
	id, ierr := rns.identity_load(cfg.identity_path)
	if ierr != .Ok {
		session_event_push(s, .Error, "rns identity load failed")
		return false
	}
	s.rns_identity = id

	if rns.node_set_identity(s.node, s.rns_identity) != .Ok {
		session_event_push(s, .Error, "set identity failed")
		return false
	}

	dest, derr := rns.destination_create(s.node, s.rns_identity, lxmf.APP_NAME, {lxmf.ASPECT_DELIVERY}, true)
	if derr != .Ok {
		session_event_push(s, .Error, "delivery dest failed")
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
		session_event_push(s, .Error, "node start failed")
		return false
	}
	s.started = true
	session_event_push(s, .Online)
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

	app_buf := s.poll_buf
	if len(app_buf) == 0 {
		app_buf = make([]u8, EVENT_APP_BUF_SIZE, context.temp_allocator)
	}
	for {
		ev, code := rns.event_poll(s.node, 0, app_buf)
		if code != .Ok || ev.kind == .None {
			break
		}
		if session_page_on_event(s, &ev) {
			continue
		}
		if session_send_on_event(s, &ev) {
			continue
		}
		session_handle_event(s, &ev, directory, conversations, cfg)
	}
	session_page_tick(s)
	session_send_tick(s)
	path_hot_sync_directory(&s.paths, directory)
}

@(private)
bytes_clone :: proc(data: []u8, allocator := context.allocator) -> []u8 {
	out := make([]u8, len(data), allocator)
	copy(out, data)
	return out
}

session_close :: proc(s: ^Session) {
	session_page_cancel(s)
	session_send_cancel(s)
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
	session_event_ring_clear(&s.events)
	delete(s.status)
	delete(s.poll_buf)
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
