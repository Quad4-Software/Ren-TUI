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
	Stamping,
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
	stamp_cost:      int,
	stamp_gen:       lxmf.Stamp_Gen,
	method:          lxmf.Method,
	try_fail_over:   bool,
	failed_over:     bool,
	link:            rns.Link,
	link_id:         [store.HASH_LEN]u8,
	has_link_id:     bool,
	deadline:        time.Tick,
	phase_deadline:  time.Tick,
	path_retried:    bool,
	path_refreshed:  bool,
	persisted_out:   bool,
	reply_to:        [lxmf.MESSAGE_ID_LEN]u8,
	has_reply_to:    bool,
	stored_idx:      int,
	retry_at:        time.Tick,
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
	lxmf.stamp_gen_cancel(&s.send.stamp_gen)
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
	send_mark_stored_state(s, .Failed)
	lxmf.stamp_gen_cancel(&s.send.stamp_gen)
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
	if len(s.send.packed) == 0 {
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
		delete(s.send.wire)
		s.send.wire = nil
		s.send.failed_over = false
		return false
	}
	send_set_status(s, fmt.tprintf("failover to propagate (%s)", reason))
	s.send.deadline = time.tick_add(time.tick_now(), time.Duration(constants.LINK_TIMEOUT_SEC * 2) * time.Second)
	s.send.phase = .Finding_Path
	s.send.path_refreshed = false
	s.send.retry_at = time.tick_now()
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

// Attach the LXMF thread field so receivers can thread the reply. Must run
// before message_assign_id / message_pack since fields feed the message id hash.
@(private)
send_attach_reply_to :: proc(s: ^Session, m: ^lxmf.Message) {
	if !s.send.has_reply_to {
		return
	}
	rt := s.send.reply_to
	m.fields[lxmf.FIELD_THREAD] = lxmf.Value{kind = .Bin, bin = bytes_clone(rt[:])}
}

@(private)
send_compose_with_stamp :: proc(s: ^Session, method: lxmf.Method, stamp: []u8) -> (lxmf.Message, bool) {
	m: lxmf.Message
	lxmf.message_init(&m)
	m.destination_hash = s.send.dest
	m.title = strings.clone(s.send.title)
	m.content = strings.clone(s.send.content)
	m.method = method
	send_attach_reply_to(s, &m)
	if len(stamp) > 0 {
		m.stamp = bytes_clone(stamp)
	}
	// Stamp already filled (or cost 0). message_pack must not block on PoW.
	if !lxmf.message_pack(&m, &s.router.material, 0) {
		lxmf.message_destroy(&m)
		return {}, false
	}
	return m, true
}

@(private)
send_wire_from_packed :: proc(s: ^Session, method: lxmf.Method, packed: []u8) -> (link_target: [store.HASH_LEN]u8, wire: []u8, ok: bool) {
	switch method {
	case .Direct:
		return s.send.dest, bytes_clone(packed), true
	case .Opportunistic:
		plain := lxmf.opportunistic_plaintext(packed)
		if len(plain) == 0 {
			return {}, nil, false
		}
		return s.send.dest, bytes_clone(plain), true
	case .Propagated:
		if s.send.cfg == nil || !s.send.cfg.has_propagation_node {
			return {}, nil, false
		}
		plain := lxmf.opportunistic_plaintext(packed)
		if len(plain) == 0 {
			return {}, nil, false
		}
		enc, eok := send_encrypt(s, s.send.dest[:], plain)
		if !eok {
			return {}, nil, false
		}
		defer delete(enc)
		wrap := lxmf.pack_propagation_payload(packed, enc)
		if wrap == nil {
			return {}, nil, false
		}
		return s.send.cfg.propagation_node, wrap, true
	case .Paper, .Unknown:
		return {}, nil, false
	}
	return {}, nil, false
}

@(private)
send_prepare_method :: proc(s: ^Session, method: lxmf.Method, stamp: []u8 = nil) -> bool {
	// Reuse packed bytes on failover so stamp PoW is not repeated.
	if len(s.send.packed) > 0 && s.send.failed_over {
		link_target, wire, wok := send_wire_from_packed(s, method, s.send.packed)
		if !wok {
			return false
		}
		delete(s.send.wire)
		s.send.method = method
		s.send.link_target = link_target
		s.send.wire = wire
		return true
	}

	msg, ok := send_compose_with_stamp(s, method, stamp)
	if !ok {
		return false
	}
	defer lxmf.message_destroy(&msg)

	link_target, wire, wok := send_wire_from_packed(s, method, msg.packed)
	if !wok {
		return false
	}

	delete(s.send.packed)
	delete(s.send.wire)
	s.send.packed = bytes_clone(msg.packed)
	s.send.message_id = msg.message_id
	s.send.timestamp = msg.timestamp
	s.send.stamped = len(msg.stamp) > 0
	s.send.method = method
	s.send.link_target = link_target
	s.send.wire = wire
	return true
}

@(private)
send_start_stamping :: proc(s: ^Session) -> bool {
	m: lxmf.Message
	lxmf.message_init(&m)
	defer lxmf.message_destroy(&m)
	m.destination_hash = s.send.dest
	m.title = strings.clone(s.send.title)
	m.content = strings.clone(s.send.content)
	m.method = s.send.method
	send_attach_reply_to(s, &m)
	if !lxmf.message_assign_id(&m, &s.router.material) {
		return false
	}
	s.send.message_id = m.message_id
	s.send.timestamp = m.timestamp
	if !lxmf.stamp_gen_begin(&s.send.stamp_gen, m.message_id[:], s.send.stamp_cost) {
		return false
	}
	s.send.phase = .Stamping
	// Stamp can take seconds of CPU. Do not burn the link deadline during PoW.
	s.send.phase_deadline = time.tick_add(time.tick_now(), 10 * time.Minute)
	send_set_status(s, "computing stamp...")
	return true
}

@(private)
send_enter_delivery :: proc(s: ^Session) {
	s.send.deadline = time.tick_add(time.tick_now(), time.Duration(constants.LINK_TIMEOUT_SEC * 2) * time.Second)
	if s.send.method == .Opportunistic {
		s.send.phase = .Packet_Send
		send_set_status(s, "sending opportunistic...")
	} else {
		s.send.phase = .Finding_Path
		s.send.path_refreshed = false
		s.send.retry_at = time.tick_now()
		s.send.phase_deadline = time.tick_add(
			time.tick_now(),
			time.Duration(constants.PATH_FIND_TIMEOUT_SEC) * time.Second,
		)
		send_set_status(s, "finding path...")
	}
}

session_send_begin :: proc(
	s: ^Session,
	dest_hash: [store.HASH_LEN]u8,
	title, content: string,
	conversations: ^store.Conversations,
	directory: ^store.Directory,
	cfg: ^store.Config = nil,
	method: lxmf.Method = .Direct,
	reply_to: [lxmf.MESSAGE_ID_LEN]u8 = {},
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
	s.send.method = use_method
	s.send.reply_to = reply_to
	s.send.has_reply_to = reply_to != {}
	s.send.stored_idx = -1
	s.send.try_fail_over = cfg != nil && cfg.try_propagation_on_fail && cfg.has_propagation_node
	s.send.failed_over = false
	s.send.deadline = time.tick_add(time.tick_now(), time.Duration(constants.LINK_TIMEOUT_SEC * 2) * time.Second)
	if directory != nil {
		s.send.stamp_cost = store.directory_stamp_cost(directory, dest_hash)
	}

	// Keep the outbound text in the conversation even if path/link/stamp fails later.
	send_persist_out(s)
	s.send.persisted_out = true

	if s.send.stamp_cost > 0 {
		if !send_start_stamping(s) {
			session_send_cancel(s)
			session_event_push(s, .Send_Failed, "stamp start failed")
			return false
		}
		session_send_tick(s)
		return true
	}

	if !send_prepare_method(s, use_method) {
		session_send_cancel(s)
		session_event_push(s, .Send_Failed, "compose failed")
		return false
	}

	send_enter_delivery(s)
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
	lxmf.stamp_gen_cancel(&s.send.stamp_gen)
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
		state = .Sending,
		reply_to = s.send.reply_to,
		has_reply_to = s.send.has_reply_to,
	}
	if s.send.cfg != nil {
		store.conversations_add_message_persist(s.send.conversations, s.send.cfg, s.send.dest, stored, label)
	} else {
		store.conversations_add_message(s.send.conversations, s.send.dest, stored, label)
	}
	// The message id is assigned later (after stamping). Remember the slot so
	// state updates can patch id and state together.
	s.send.stored_idx = store.conversations_message_count(s.send.conversations, s.send.dest) - 1
}

// Flip the persisted outbound message to a new delivery state and save.
@(private)
send_mark_stored_state :: proc(s: ^Session, state: store.Message_State) {
	if s.send.conversations == nil || s.send.stored_idx < 0 {
		return
	}
	if store.conversations_update_message_at(s.send.conversations, s.send.dest, s.send.stored_idx, s.send.message_id, state) {
		if s.send.cfg != nil {
			_ = store.conversations_save_peer(s.send.conversations, s.send.cfg, s.send.dest)
		}
	}
}

@(private)
send_complete_ok :: proc(s: ^Session) {
	if !s.send.persisted_out {
		send_persist_out(s)
		s.send.persisted_out = true
	}
	// Direct sends ride a reliable link, so a successful link send means the
	// peer stack acknowledged receipt. Opportunistic and propagated sends are
	// fire-and-forget into the network, so they stop at Sent until a proof or
	// reply can confirm delivery.
	state := store.Message_State.Delivered if s.send.method == .Direct else store.Message_State.Sent
	send_mark_stored_state(s, state)
	session_event_push(s, .Send_Ok)
	if s.started && s.delivery_dest != 0 {
		session_announce(s)
	}
	s.send.ok = true
	s.send.done = true
	s.send.active = false
	s.send.phase = .Idle
	// Keep the delivery link open for backchannel replies (NomadNet keeps
	// LXMF links for LINK_MAX_INACTIVITY). Closing here dropped inbound
	// replies that arrived on the same link.
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
		// Unknown identity means announce/path not ready yet. Keep requesting
		// path instead of deleting the outbound and giving up immediately.
		if !s.send.path_retried || strings.contains(err, "unknown destination") || strings.contains(err, "not found") {
			s.send.path_retried = true
			if s.send.link != 0 {
				send_link_close(s, s.send.link)
				s.send.link = 0
			}
			s.send.has_link_id = false
			s.send.path_refreshed = false
			s.send.phase = .Finding_Path
			s.send.retry_at = time.tick_now()
			s.send.phase_deadline = time.tick_add(
				time.tick_now(),
				time.Duration(constants.PATH_FIND_TIMEOUT_SEC) * time.Second,
			)
			if s.send_transport.path_ensure == nil {
				path_request_refresh(s, s.send.link_target)
			}
			reason := err if err != "" else "link failed"
			send_set_status(s, fmt.tprintf("waiting for path (%s)...", reason))
			return true
		}
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
	if s.send.phase != .Stamping && time.tick_diff(now, s.send.deadline) <= 0 {
		send_fail(s, "link timeout")
		return
	}

	switch s.send.phase {
	case .Idle, .Done:
		return
	case .Stamping:
		if time.tick_diff(now, s.send.phase_deadline) <= 0 {
			send_fail(s, "stamp timeout")
			return
		}
		prev_attempts := s.send.stamp_gen.attempts
		prev_rounds := s.send.stamp_gen.rounds_done
		if !lxmf.stamp_gen_tick(&s.send.stamp_gen) {
			if s.send.stamp_gen.rounds_done != prev_rounds || s.send.stamp_gen.attempts == 0 {
				send_set_status(s, "computing stamp...")
			} else if s.send.stamp_gen.attempts != prev_attempts {
				send_set_status(s, fmt.tprintf("computing stamp (try %d)...", s.send.stamp_gen.attempts))
			}
			return
		}
		if !s.send.stamp_gen.ok || len(s.send.stamp_gen.stamp) == 0 {
			send_fail(s, "stamp failed")
			return
		}
		stamp := s.send.stamp_gen.stamp
		if !send_prepare_method(s, s.send.method, stamp) {
			send_fail(s, "compose failed")
			return
		}
		lxmf.stamp_gen_cancel(&s.send.stamp_gen)
		send_enter_delivery(s)
		session_send_tick(s)
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
		ready := send_path_ensure(s, s.send.link_target)
		if ready {
			s.send.phase = .Opening_Link
			send_set_status(s, "opening link...")
			session_send_tick(s)
			return
		}
		if time.tick_diff(now, s.send.phase_deadline) <= 0 {
			send_fail(s, "path not found")
			return
		}
		if time.tick_diff(now, s.send.retry_at) <= 0 {
			if s.send_transport.path_ensure == nil {
				if !s.send.path_refreshed {
					path_request_refresh(s, s.send.link_target)
					s.send.path_refreshed = true
					send_set_status(s, "requesting path...")
				} else {
					dh := s.send.link_target
					_ = rns.path_request(s.node, dh[:])
					send_set_status(s, "waiting for path...")
				}
			} else {
				s.send.path_refreshed = true
				send_set_status(s, "waiting for path...")
			}
			s.send.retry_at = time.tick_add(now, time.Duration(constants.PATH_RETRY_SEC) * time.Second)
		}
	case .Opening_Link:
		link, lid, ok := send_link_open(s, s.send.link_target[:])
		if !ok {
			path_hot_invalidate(&s.paths, s.send.link_target)
			if !s.send.path_retried {
				s.send.path_retried = true
				s.send.path_refreshed = false
				s.send.phase = .Finding_Path
				s.send.retry_at = time.tick_now()
				s.send.phase_deadline = time.tick_add(
					now,
					time.Duration(constants.PATH_FIND_TIMEOUT_SEC) * time.Second,
				)
				if s.send_transport.path_ensure == nil {
					path_request_refresh(s, s.send.link_target)
				}
				send_set_status(s, "link open failed, requesting path...")
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
				s.send.has_link_id = false
				s.send.path_refreshed = false
				s.send.phase = .Finding_Path
				s.send.retry_at = time.tick_now()
				s.send.phase_deadline = time.tick_add(
					now,
					time.Duration(constants.PATH_FIND_TIMEOUT_SEC) * time.Second,
				)
				if s.send_transport.path_ensure == nil {
					path_request_refresh(s, s.send.link_target)
				}
				send_set_status(s, "link timeout, re-finding path...")
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
