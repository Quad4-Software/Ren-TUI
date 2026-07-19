// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Propagation node sync. Links to the selected PN and requests /get.
Full identify-gated download matches NomadNet when librns gains link_identify.
*/

package net

import "core:fmt"
import "core:strings"
import "core:time"

import rns "rns:rns"
import "ren:constants"
import "ren:store"

Prop_Sync_State :: enum {
	Idle,
	Path_Requested,
	Link_Establishing,
	Link_Established,
	Request_Sent,
	Complete,
	Failed,
	No_Node,
}

Sync_Phase :: enum {
	Idle,
	Finding_Path,
	Opening_Link,
	Waiting_Link,
	Requesting,
	Done,
}

Sync_Job :: struct {
	active:         bool,
	done:           bool,
	ok:             bool,
	phase:          Sync_Phase,
	state:          Prop_Sync_State,
	node:           [store.HASH_LEN]u8,
	link:           rns.Link,
	link_id:        [store.HASH_LEN]u8,
	has_link_id:    bool,
	request_id:     [store.HASH_LEN]u8,
	has_request_id: bool,
	deadline:       time.Tick,
	phase_deadline: time.Tick,
	path_retried:   bool,
	status:         string,
	last_result:    string,
}

session_sync_busy :: proc(s: ^Session) -> bool {
	return s.sync.active && !s.sync.done
}

session_sync_status_line :: proc(s: ^Session, cfg: ^store.Config, allocator := context.allocator) -> string {
	if cfg == nil || !cfg.has_propagation_node {
		return strings.clone("Idle (no propagation node)", allocator)
	}
	if s.sync.status != "" && (s.sync.active || s.sync.state != .Idle) {
		return strings.clone(s.sync.status, allocator)
	}
	switch s.sync.state {
	case .Idle:
		return strings.clone("Idle", allocator)
	case .Path_Requested:
		return strings.clone("Path requested", allocator)
	case .Link_Establishing:
		return strings.clone("Establishing link", allocator)
	case .Link_Established:
		return strings.clone("Link established", allocator)
	case .Request_Sent:
		return strings.clone("Request sent", allocator)
	case .Complete:
		if s.sync.last_result != "" {
			return strings.clone(s.sync.last_result, allocator)
		}
		return strings.clone("Complete", allocator)
	case .Failed:
		if s.sync.last_result != "" {
			return strings.clone(s.sync.last_result, allocator)
		}
		return strings.clone("Failed", allocator)
	case .No_Node:
		return strings.clone("No propagation node", allocator)
	}
	return strings.clone("Idle", allocator)
}

session_sync_cancel :: proc(s: ^Session) {
	if s.sync.link != 0 {
		_ = rns.link_close(s.sync.link)
		s.sync.link = 0
	}
	delete(s.sync.status)
	delete(s.sync.last_result)
	s.sync = {}
	s.sync.state = .Idle
}

@(private)
sync_set_status :: proc(s: ^Session, msg: string, state: Prop_Sync_State) {
	delete(s.sync.status)
	s.sync.status = strings.clone(msg)
	s.sync.state = state
	session_set_status_text(s, msg)
}

@(private)
sync_fail :: proc(s: ^Session, msg: string) {
	delete(s.sync.last_result)
	s.sync.last_result = strings.clone(msg)
	sync_set_status(s, msg, .Failed)
	s.sync.ok = false
	s.sync.done = true
	s.sync.active = false
	s.sync.phase = .Done
	if s.sync.link != 0 {
		_ = rns.link_close(s.sync.link)
		s.sync.link = 0
	}
}

@(private)
sync_complete :: proc(s: ^Session, msg: string) {
	delete(s.sync.last_result)
	s.sync.last_result = strings.clone(msg)
	sync_set_status(s, msg, .Complete)
	s.sync.ok = true
	s.sync.done = true
	s.sync.active = false
	s.sync.phase = .Done
	if s.sync.link != 0 {
		_ = rns.link_close(s.sync.link)
		s.sync.link = 0
	}
}

// msgpack [nil, nil] for LXMF /get message list request.
@(private)
sync_get_list_payload :: proc(allocator := context.allocator) -> []u8 {
	out := make([]u8, 3, allocator)
	out[0] = 0x92
	out[1] = 0xc0
	out[2] = 0xc0
	return out
}

session_sync_begin :: proc(s: ^Session, cfg: ^store.Config) -> bool {
	if !s.started {
		return false
	}
	if cfg == nil || !cfg.has_propagation_node {
		s.sync.state = .No_Node
		delete(s.sync.status)
		s.sync.status = strings.clone("No propagation node selected")
		return false
	}
	if session_page_busy(s) || session_send_busy(s) {
		return false
	}
	if session_sync_busy(s) {
		return false
	}

	session_sync_cancel(s)
	s.sync.active = true
	s.sync.done = false
	s.sync.ok = false
	s.sync.node = cfg.propagation_node
	s.sync.deadline = time.tick_add(time.tick_now(), time.Duration(constants.LINK_TIMEOUT_SEC * 2) * time.Second)
	s.sync.phase = .Finding_Path
	s.sync.phase_deadline = time.tick_add(
		time.tick_now(),
		time.Duration(constants.PATH_FIND_TIMEOUT_SEC) * time.Second,
	)
	sync_set_status(s, "Path requested", .Path_Requested)
	session_sync_tick(s)
	return true
}

session_sync_on_event :: proc(s: ^Session, ev: ^rns.Event) -> bool {
	if !s.sync.active || s.sync.done {
		return false
	}
	switch ev.kind {
	case .Link_Established:
		if s.sync.phase != .Waiting_Link {
			return false
		}
		dest := rns.event_destination_hash(ev)
		lid := rns.event_link_id(ev)
		ours := false
		if s.sync.has_link_id && hashes_equal(lid, s.sync.link_id[:]) {
			ours = true
		} else if len(dest) == store.HASH_LEN && hashes_equal(dest, s.sync.node[:]) {
			ours = true
		}
		if !ours {
			return false
		}
		path_hot_remember(&s.paths, s.sync.node, ev.hops)
		s.sync.phase = .Requesting
		sync_set_status(s, "Link established", .Link_Established)
		return true
	case .Link_Failed:
		if s.sync.phase != .Waiting_Link && s.sync.phase != .Opening_Link {
			return false
		}
		dest := rns.event_destination_hash(ev)
		lid := rns.event_link_id(ev)
		ours := false
		if s.sync.has_link_id && hashes_equal(lid, s.sync.link_id[:]) {
			ours = true
		} else if len(dest) == store.HASH_LEN && hashes_equal(dest, s.sync.node[:]) {
			ours = true
		}
		if !ours {
			return false
		}
		path_hot_invalidate(&s.paths, s.sync.node)
		sync_fail(s, "Link failed")
		return true
	case .Request_Response:
		if s.sync.phase != .Requesting || !s.sync.has_request_id {
			return false
		}
		rid := rns.event_request_id(ev)
		if !hashes_equal(rid, s.sync.request_id[:]) {
			return false
		}
		sync_complete(s, "Sync complete")
		return true
	case .Request_Failed:
		if s.sync.phase != .Requesting || !s.sync.has_request_id {
			return false
		}
		rid := rns.event_request_id(ev)
		if !hashes_equal(rid, s.sync.request_id[:]) {
			return false
		}
		err := rns.event_error_message(ev)
		if err != "" {
			sync_fail(s, fmt.tprintf("Sync failed: %s", err))
		} else {
			sync_fail(s, "Sync request failed")
		}
		return true
	case .Announce, .Link_Data, .Link_Closed, .Request_Incoming,
	     .Resource_Started, .Resource_Concluded, .Destination_Data, .None:
		return false
	}
	return false
}

session_sync_tick :: proc(s: ^Session) {
	if !s.sync.active || s.sync.done {
		return
	}
	now := time.tick_now()
	if time.tick_diff(now, s.sync.deadline) <= 0 {
		sync_fail(s, "Sync timeout")
		return
	}

	switch s.sync.phase {
	case .Idle, .Done:
		return
	case .Finding_Path:
		_, _ = path_ensure(s, s.sync.node, true)
		s.sync.phase = .Opening_Link
		sync_set_status(s, "Establishing link", .Link_Establishing)
	case .Opening_Link:
		opened, lerr := rns.link_open(s.node, s.sync.node[:])
		if lerr != .Ok {
			if !s.sync.path_retried {
				s.sync.path_retried = true
				_, _ = path_ensure(s, s.sync.node, true)
				sync_set_status(s, "Retrying link", .Link_Establishing)
				return
			}
			sync_fail(s, "Could not open link")
			return
		}
		s.sync.link = opened
		s.sync.phase = .Waiting_Link
		s.sync.phase_deadline = time.tick_add(
			now,
			time.Duration(constants.LINK_TIMEOUT_SEC) * time.Second,
		)
		sync_set_status(s, "Establishing link", .Link_Establishing)
	case .Waiting_Link:
		if time.tick_diff(now, s.sync.phase_deadline) <= 0 {
			if !s.sync.path_retried {
				s.sync.path_retried = true
				if s.sync.link != 0 {
					_ = rns.link_close(s.sync.link)
					s.sync.link = 0
				}
				_, _ = path_ensure(s, s.sync.node, true)
				s.sync.phase = .Opening_Link
				sync_set_status(s, "Retrying link", .Link_Establishing)
				return
			}
			sync_fail(s, "Link timeout")
		}
	case .Requesting:
		if s.sync.link == 0 {
			sync_fail(s, "Link missing")
			return
		}
		if s.sync.has_request_id {
			if time.tick_diff(now, s.sync.phase_deadline) <= 0 {
				sync_fail(s, "Sync request timeout")
			}
			return
		}
		payload := sync_get_list_payload(context.temp_allocator)
		rid, err := rns.link_request(s.node, s.sync.link, "/get", payload, i32(constants.LINK_TIMEOUT_SEC * 1000))
		if err != .Ok {
			sync_fail(s, "Could not request /get")
			return
		}
		s.sync.request_id = rid
		s.sync.has_request_id = true
		s.sync.phase_deadline = time.tick_add(
			now,
			time.Duration(constants.LINK_TIMEOUT_SEC) * time.Second,
		)
		sync_set_status(s, "Request sent", .Request_Sent)
	}
}
