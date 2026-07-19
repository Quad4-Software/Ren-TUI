// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Compose outbound mail and check inbound stamps.
*/

package lxmf

import "core:strings"

Router :: struct {
	material:        Identity_Material,
	display_name:    string,
	stamp_cost:      Maybe(i64),
	delivery_hash:   [HASH_LEN]u8,
	outbound:        [dynamic]Message,
	inbound_tickets: [dynamic][TICKET_LENGTH]u8,
}

router_init :: proc(r: ^Router, material: Identity_Material, display_name: string) {
	r^ = {}
	r.material = material
	r.display_name = strings.clone(display_name)
	h := material.hash
	r.delivery_hash = delivery_hash(h[:])
	r.outbound = make([dynamic]Message)
	r.inbound_tickets = make([dynamic][TICKET_LENGTH]u8)
}

router_destroy :: proc(r: ^Router) {
	delete(r.display_name)
	for &m in r.outbound {
		message_destroy(&m)
	}
	delete(r.outbound)
	delete(r.inbound_tickets)
	r^ = {}
}

router_set_stamp_cost :: proc(r: ^Router, cost: Maybe(i64)) {
	r.stamp_cost = cost
}

router_set_display_name :: proc(r: ^Router, name: string) {
	delete(r.display_name)
	r.display_name = strings.clone(name)
}

router_announce_data :: proc(r: ^Router, allocator := context.allocator) -> []u8 {
	return announce_app_data(r.display_name, r.stamp_cost, allocator)
}

router_compose :: proc(
	r: ^Router,
	dest_hash: [HASH_LEN]u8,
	title: string,
	content: string,
	method: Method = .Direct,
	peer_stamp_cost: int = 0,
	ticket: []u8 = nil,
) -> (Message, bool) {
	m: Message
	message_init(&m)
	m.destination_hash = dest_hash
	m.title = strings.clone(title)
	m.content = strings.clone(content)
	m.method = method
	if !message_pack(&m, &r.material, peer_stamp_cost, ticket) {
		message_destroy(&m)
		return {}, false
	}
	return m, true
}

router_validate_inbound_stamp :: proc(r: ^Router, m: ^Message) -> bool {
	required := 0
	if cost, ok := r.stamp_cost.?; ok {
		required = int(cost)
	}
	if required <= 0 {
		return true
	}
	tickets := make([][]u8, len(r.inbound_tickets), context.temp_allocator)
	for t, i in r.inbound_tickets {
		tt := t
		tickets[i] = tt[:]
	}
	mid := m.message_id
	ok, _ := validate_message_stamp(m.stamp, mid[:], required, tickets)
	return ok
}
