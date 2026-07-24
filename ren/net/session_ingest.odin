// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Announce and LXMF ingest into store plus session events.
*/

package net

import "core:fmt"
import "core:strings"

import rns "rns:rns"
import "ren:lxmf"
import "ren:store"

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
		// Opportunistic LXMF. Ignore non-delivery destinations (e.g. nomad node).
		dest := rns.event_destination_hash(ev)
		if len(dest) == store.HASH_LEN &&
		   !lxmf.destination_hash_matches(s.router.delivery_hash, dest) {
			return
		}
		plain := rns.event_app_data(ev)
		if len(plain) == 0 {
			return
		}
		msg, ok := lxmf.message_unpack_opportunistic(s.router.delivery_hash, plain)
		if !ok {
			session_event_push(s, .Error, "lxmf unpack failed")
			return
		}
		session_store_inbound(s, &msg, directory, conversations, cfg)
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
		session_event_push(s, .Error, "lxmf unpack failed")
		return
	}
	session_store_inbound(s, &msg, directory, conversations, cfg)
}

@(private)
session_resolve_sign_pub :: proc(
	s: ^Session,
	directory: ^store.Directory,
	source: [store.HASH_LEN]u8,
) -> []u8 {
	if source == s.router.delivery_hash {
		return s.router.material.sign_pub[:]
	}
	if pub, ok := store.directory_sign_pub(directory, source); ok {
		return pub
	}
	return nil
}

@(private)
session_store_inbound :: proc(
	s: ^Session,
	msg: ^lxmf.Message,
	directory: ^store.Directory,
	conversations: ^store.Conversations,
	cfg: ^store.Config = nil,
) {
	defer lxmf.message_destroy(msg)
	if !lxmf.router_validate_inbound_stamp(&s.router, msg) {
		session_event_push(s, .Error, "stamp rejected")
		return
	}
	sign_pub := session_resolve_sign_pub(s, directory, msg.source_hash)
	if !lxmf.message_accept_inbound_signature(msg, sign_pub) {
		session_event_push(s, .Error, "signature rejected")
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
	src := store.hash_hex(msg.source_hash, context.temp_allocator)
	detail := fmt.tprintf("from %s", src)
	session_event_push(s, .Message_Received, detail)
}
