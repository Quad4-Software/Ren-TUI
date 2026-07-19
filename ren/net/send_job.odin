// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Async LXMF send (direct, opportunistic, propagate). Advances on session_poll.
Rejects when a page job is busy to avoid dual-link complexity.
*/

package net

import "core:fmt"
import "core:strings"
import "core:time"

import rns "rns:rns"
import "ren:constants"
import "ren:lxmf"
import "ren:store"

Send_Phase :: enum {
	Idle,
	Finding_Path,
	Opening_Link,
	Waiting_Link,
	Sending,
	Packet_Send,
	Done,
}

Send_Job :: struct {
	active:          bool,
	done:            bool,
	ok:              bool,
	phase:           Send_Phase,
	dest:            [store.HASH_LEN]u8,
	link_target:     [store.HASH_LEN]u8,
	title:           string,
	content:         string,
	packed:          []u8,
	wire:            []u8,
	message_id:      [lxmf.MESSAGE_ID_LEN]u8,
	timestamp:       f64,
	stamped:         bool,
	method:          lxmf.Method,
	try_fail_over:   bool,
	failed_over:     bool,
	link:            rns.Link,
	link_id:         [store.HASH_LEN]u8,
	has_link_id:     bool,
	deadline:        time.Tick,
	phase_deadline:  time.Tick,
	path_retried:    bool,
	status:          string,
	conversations:   ^store.Conversations,
	directory:       ^store.Directory,
	cfg:             ^store.Config,
}

// Optional hooks for unit tests. Nil fields use real librns.
Send_Transport :: struct {
	user:        rawptr,
	path_ensure: proc(user: rawptr, dest: [store.HASH_LEN]u8) -> bool,
	link_open:   proc(user: rawptr, dest: []u8) -> (link: rns.Link, link_id: [store.HASH_LEN]u8, ok: bool),
	link_close:  proc(user: rawptr, link: rns.Link),
	link_send:   proc(user: rawptr, link: rns.Link, data: []u8) -> bool,
	packet_send: proc(user: rawptr, dest: []u8, data: []u8) -> bool,
	encrypt:     proc(user: rawptr, dest: []u8, plaintext: []u8) -> ([]u8, bool),
	auto_link:   bool,
}

session_send_busy :: proc(s: ^Session) -> bool {
	return s.send.active && !s.send.done
}

session_send_cancel :: proc(s: ^Session) {
	if s.send.link != 0 {
		send_link_close(s, s.send.link)
		s.send.link = 0
	}
	delete(s.send.title)
	delete(s.send.content)
	delete(s.send.packed)
	delete(s.send.wire)
	delete(s.send.status)
	s.send = {}
}

@(private)
send_fail :: proc(s: ^Session, msg: string) {
	if send_try_failover(s, msg) {
		return
	}
	delete(s.send.status)
	s.send.status = strings.clone(msg)
	session_event_push(s, .Send_Failed, msg)
	s.send.ok = false
	s.send.done = true
	s.send.active = false
	s.send.phase = .Idle
	if s.send.link != 0 {
		send_link_close(s, s.send.link)
		s.send.link = 0
	}
}

@(private)
send_try_failover :: proc(s: ^Session, reason: string) -> bool {
	if s.send.failed_over || !s.send.try_fail_over {
		return false
	}
	if s.send.method != .Direct && s.send.method != .Opportunistic {
		return false
	}
	if s.send.cfg == nil || !s.send.cfg.has_propagation_node {
		return false
	}
	s.send.failed_over = true
	if s.send.link != 0 {
		send_link_close(s, s.send.link)
		s.send.link = 0
	}
	s.send.has_link_id = false
	s.send.path_retried = false
	if !send_prepare_method(s, .Propagated) {
		return false
	}
	send_set_status(s, fmt.tprintf("failover to propagate (%s)", reason))
	s.send.deadline = time.tick_add(time.tick_now(), time.Duration(constants.LINK_TIMEOUT_SEC * 2) * time.Second)
	s.send.phase = .Finding_Path
	s.send.phase_deadline = time.tick_add(
		time.tick_now(),
		time.Duration(constants.PATH_FIND_TIMEOUT_SEC) * time.Second,
	)
	session_send_tick(s)
	return true
}

@(private)
send_set_status :: proc(s: ^Session, msg: string) {
	delete(s.send.status)
	s.send.status = strings.clone(msg)
	session_set_status_text(s, msg)
}

@(private)
send_path_ensure :: proc(s: ^Session, dest: [store.HASH_LEN]u8) -> bool {
	if s.send_transport.path_ensure != nil {
		return s.send_transport.path_ensure(s.send_transport.user, dest)
	}
	found, _ := path_ensure(s, dest, true)
	return found
}

@(private)
send_link_open :: proc(s: ^Session, dest: []u8) -> (out_link: rns.Link, link_id: [store.HASH_LEN]u8, ok: bool) {
	if s.send_transport.link_open != nil {
		return s.send_transport.link_open(s.send_transport.user, dest)
	}
	opened, lerr := rns.link_open(s.node, dest)
	if lerr != .Ok {
		return 0, {}, false
	}
	return opened, {}, true
}

@(private)
send_link_close :: proc(s: ^Session, link: rns.Link) {
	if s.send_transport.link_close != nil {
		s.send_transport.link_close(s.send_transport.user, link)
		return
	}
	_ = rns.link_close(link)
}

@(private)
send_link_send :: proc(s: ^Session, link: rns.Link, data: []u8) -> bool {
	if s.send_transport.link_send != nil {
		return s.send_transport.link_send(s.send_transport.user, link, data)
	}
	if rns.link_send(link, data) == .Ok {
		return true
	}
	return rns.link_send_resource(link, data, "lxmf") == .Ok
}

@(private)
send_packet_send :: proc(s: ^Session, dest: []u8, data: []u8) -> bool {
	if s.send_transport.packet_send != nil {
		return s.send_transport.packet_send(s.send_transport.user, dest, data)
	}
	return rns.packet_send(s.node, dest, data) == .Ok
}

@(private)
send_encrypt :: proc(s: ^Session, dest: []u8, plaintext: []u8) -> ([]u8, bool) {
	if s.send_transport.encrypt != nil {
		return s.send_transport.encrypt(s.send_transport.user, dest, plaintext)
	}
	out, err := rns.destination_encrypt(dest, plaintext)
	if err != .Ok {
		return nil, false
	}
	return out, true
}

@(private)
send_prepare_method :: proc(s: ^Session, method: lxmf.Method) -> bool {
	cost := 0
	if s.send.directory != nil {
		cost = store.directory_stamp_cost(s.send.directory, s.send.dest)
	}
	msg, ok := lxmf.router_compose(&s.router, s.send.dest, s.send.title, s.send.content, method, cost)
	if !ok {
		return false
	}
	defer lxmf.message_destroy(&msg)

	delete(s.send.packed)
	delete(s.send.wire)
	s.send.packed = bytes_clone(msg.packed)
	s.send.message_id = msg.message_id
	s.send.timestamp = msg.timestamp
	s.send.stamped = len(msg.stamp) > 0
	s.send.method = method
	s.send.wire = nil

	switch method {
	case .Direct:
		s.send.link_target = s.send.dest
		s.send.wire = bytes_clone(msg.packed)
	case .Opportunistic:
		s.send.link_target = s.send.dest
		plain := lxmf.opportunistic_plaintext(msg.packed)
		if len(plain) == 0 {
			return false
		}
		s.send.wire = bytes_clone(plain)
	case .Propagated:
		if s.send.cfg == nil || !s.send.cfg.has_propagation_node {
			return false
		}
		s.send.link_target = s.send.cfg.propagation_node
		plain := lxmf.opportunistic_plaintext(msg.packed)
		if len(plain) == 0 {
			return false
		}
		enc, eok := send_encrypt(s, s.send.dest[:], plain)
		if !eok {
			return false
		}
		defer delete(enc)
		wrap := lxmf.pack_propagation_payload(msg.packed, enc)
		if wrap == nil {
			return false
		}
		s.send.wire = wrap
	case .Paper, .Unknown:
		return false
	}
	return true
}

session_send_begin :: proc(
	s: ^Session,
	dest_hash: [store.HASH_LEN]u8,
	title, content: string,
	conversations: ^store.Conversations,
	directory: ^store.Directory,
	cfg: ^store.Config = nil,
	method: lxmf.Method = .Direct,
) -> bool {
	if !s.started {
		session_event_push(s, .Send_Failed, "offline")
		return false
	}
	if session_page_busy(s) {
		session_event_push(s, .Send_Failed, "page busy")
		return false
	}
	if session_send_busy(s) {
		session_event_push(s, .Send_Failed, "send busy")
		return false
	}
	if session_sync_busy(s) {
		session_event_push(s, .Send_Failed, "sync busy")
		return false
	}

	use_method := method
	if use_method == .Unknown {
		use_method = .Direct
	}
	if use_method == .Propagated && (cfg == nil || !cfg.has_propagation_node) {
		session_event_push(s, .Send_Failed, "select a propagation node first")
		return false
	}

	session_send_cancel(s)
	s.send.active = true
	s.send.done = false
	s.send.ok = false
	s.send.dest = dest_hash
	s.send.title = strings.clone(title)
	s.send.content = strings.clone(content)
	s.send.conversations = conversations
	s.send.directory = directory
	s.send.cfg = cfg
	s.send.try_fail_over = cfg != nil && cfg.try_propagation_on_fail && cfg.has_propagation_node
	s.send.failed_over = false
	s.send.deadline = time.tick_add(time.tick_now(), time.Duration(constants.LINK_TIMEOUT_SEC * 2) * time.Second)

	if !send_prepare_method(s, use_method) {
		session_send_cancel(s)
		session_event_push(s, .Send_Failed, "compose failed")
		return false
	}

	if use_method == .Opportunistic {
		s.send.phase = .Packet_Send
		send_set_status(s, "sending opportunistic...")
	} else {
		s.send.phase = .Finding_Path
		s.send.phase_deadline = time.tick_add(
			time.tick_now(),
			time.Duration(constants.PATH_FIND_TIMEOUT_SEC) * time.Second,
		)
		send_set_status(s, "finding path...")
	}
	session_send_tick(s)
	return true
}

// Blocking wrapper kept for ren-listen style tools. Prefer session_send_begin in the TUI.
session_send_direct :: proc(
	s: ^Session,
	dest_hash: [store.HASH_LEN]u8,
	title, content: string,
	conversations: ^store.Conversations,
	directory: ^store.Directory,
	cfg: ^store.Config = nil,
) -> bool {
	if !session_send_begin(s, dest_hash, title, content, conversations, directory, cfg, .Direct) {
		return false
	}
	app_buf := s.poll_buf
	if len(app_buf) == 0 {
		app_buf = make([]u8, EVENT_APP_BUF_SIZE, context.temp_allocator)
	}
	for session_send_busy(s) {
		if time.tick_diff(time.tick_now(), s.send.deadline) <= 0 {
			send_fail(s, "link timeout")
			break
		}
		ev, code := rns.event_poll(s.node, 50, app_buf)
		if code == .Ok && ev.kind != .None {
			if !session_send_on_event(s, &ev) {
				session_handle_event(s, &ev, directory, conversations, cfg)
			}
		}
		session_send_tick(s)
	}
	ok := s.send.ok
	session_send_finish_cleanup(s)
	return ok
}

@(private)
session_send_finish_cleanup :: proc(s: ^Session) {
	delete(s.send.title)
	delete(s.send.content)
	delete(s.send.packed)
	delete(s.send.wire)
	delete(s.send.status)
	s.send.title = ""
	s.send.content = ""
	s.send.packed = nil
	s.send.wire = nil
	s.send.status = ""
	s.send.active = false
	s.send.done = false
	s.send.phase = .Idle
	s.send.conversations = nil
	s.send.directory = nil
	s.send.cfg = nil
}

@(private)
send_persist_out :: proc(s: ^Session) {
	if s.send.directory == nil || s.send.conversations == nil {
		return
	}
	label := store.directory_label(s.send.directory, s.send.dest)
	defer delete(label)
	stored := store.Stored_Message{
		id = s.send.message_id,
		direction = .Out,
		title = strings.clone(s.send.title),
		content = strings.clone(s.send.content),
		timestamp = s.send.timestamp,
		method = s.send.method,
		verified = true,
		stamped = s.send.stamped,
		hops = store.directory_hops(s.send.directory, s.send.dest),
	}
	if s.send.cfg != nil {
		store.conversations_add_message_persist(s.send.conversations, s.send.cfg, s.send.dest, stored, label)
	} else {
		store.conversations_add_message(s.send.conversations, s.send.dest, stored, label)
	}
}

@(private)
send_complete_ok :: proc(s: ^Session) {
	send_persist_out(s)
	session_event_push(s, .Send_Ok)
	if s.started && s.delivery_dest != 0 {
		session_announce(s)
	}
	s.send.ok = true
	s.send.done = true
	s.send.active = false
	s.send.phase = .Idle
	if s.send.link != 0 {
		send_link_close(s, s.send.link)
		s.send.link = 0
	}
}

session_send_on_event :: proc(s: ^Session, ev: ^rns.Event) -> bool {
	if !s.send.active || s.send.done {
		return false
	}
	switch ev.kind {
	case .Link_Established:
		if s.send.phase != .Waiting_Link {
			return false
		}
		dest := rns.event_destination_hash(ev)
		lid := rns.event_link_id(ev)
		ours := false
		if s.send.has_link_id && hashes_equal(lid, s.send.link_id[:]) {
			ours = true
		} else if len(dest) == store.HASH_LEN && hashes_equal(dest, s.send.link_target[:]) {
			ours = true
		}
		if !ours && !s.send_transport.auto_link {
			return false
		}
		path_hot_remember(&s.paths, s.send.link_target, ev.hops)
		s.send.phase = .Sending
		send_set_status(s, "sending...")
		return true
	case .Link_Failed:
		if s.send.phase != .Waiting_Link && s.send.phase != .Opening_Link {
			return false
		}
		dest := rns.event_destination_hash(ev)
		lid := rns.event_link_id(ev)
		ours := false
		if s.send.has_link_id && hashes_equal(lid, s.send.link_id[:]) {
			ours = true
		} else if len(dest) == store.HASH_LEN && hashes_equal(dest, s.send.link_target[:]) {
			ours = true
		}
		if !ours && !s.send_transport.auto_link {
			return false
		}
		path_hot_invalidate(&s.paths, s.send.link_target)
		err := rns.event_error_message(ev)
		if err != "" {
			send_fail(s, fmt.tprintf("link failed %s", err))
		} else {
			send_fail(s, "cannot establish link")
		}
		return true
	case .Announce, .Link_Data, .Link_Closed, .Request_Incoming, .Request_Response, .Request_Failed,
	     .Resource_Started, .Resource_Concluded, .Destination_Data, .None:
		return false
	}
	return false
}

session_send_tick :: proc(s: ^Session) {
	if !s.send.active || s.send.done {
		return
	}
	now := time.tick_now()
	if time.tick_diff(now, s.send.deadline) <= 0 {
		send_fail(s, "link timeout")
		return
	}

	switch s.send.phase {
	case .Idle, .Done:
		return
	case .Packet_Send:
		if len(s.send.wire) == 0 {
			send_fail(s, "empty opportunistic payload")
			return
		}
		if !send_packet_send(s, s.send.dest[:], s.send.wire) {
			send_fail(s, "opportunistic send failed")
			return
		}
		send_complete_ok(s)
	case .Finding_Path:
		_ = send_path_ensure(s, s.send.link_target)
		s.send.phase = .Opening_Link
		send_set_status(s, "opening link...")
	case .Opening_Link:
		link, lid, ok := send_link_open(s, s.send.link_target[:])
		if !ok {
			if !s.send.path_retried {
				s.send.path_retried = true
				_ = send_path_ensure(s, s.send.link_target)
				send_set_status(s, "retrying link...")
				return
			}
			send_fail(s, "link open failed")
			return
		}
		s.send.link = link
		if lid != {} {
			s.send.link_id = lid
			s.send.has_link_id = true
		}
		s.send.phase = .Waiting_Link
		s.send.phase_deadline = time.tick_add(
			now,
			time.Duration(constants.LINK_TIMEOUT_SEC) * time.Second,
		)
		send_set_status(s, "waiting for link...")
		if s.send_transport.auto_link {
			s.send.phase = .Sending
			send_set_status(s, "sending...")
		}
	case .Waiting_Link:
		if time.tick_diff(now, s.send.phase_deadline) <= 0 {
			if !s.send.path_retried {
				s.send.path_retried = true
				if s.send.link != 0 {
					send_link_close(s, s.send.link)
					s.send.link = 0
				}
				_ = send_path_ensure(s, s.send.link_target)
				s.send.phase = .Opening_Link
				send_set_status(s, "retrying link...")
				return
			}
			send_fail(s, "link timeout")
		}
	case .Sending:
		if s.send.link == 0 {
			send_fail(s, "link missing")
			return
		}
		payload := s.send.wire if len(s.send.wire) > 0 else s.send.packed
		if !send_link_send(s, s.send.link, payload) {
			send_fail(s, "send failed")
			return
		}
		send_complete_ok(s)
	}
}

// Test helper: mark waiting send as linked then tick to completion.
session_send_test_establish :: proc(s: ^Session) {
	if s.send.phase == .Waiting_Link || s.send.phase == .Opening_Link {
		s.send.phase = .Sending
		send_set_status(s, "sending...")
	}
	session_send_tick(s)
}
