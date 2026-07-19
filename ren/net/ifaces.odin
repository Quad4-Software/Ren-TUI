// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Interface listing without exposing librns types to app.
*/

package net

import "core:strings"

import rns "rns:rns"

Iface_Info :: struct {
	name:       string,
	type_n:     string,
	online:     bool,
	enabled:    bool,
	rx:         u64,
	tx:         u64,
	rx_packets: u64,
	tx_packets: u64,
}

session_list_ifaces :: proc(s: ^Session, out: []Iface_Info) -> int {
	entries: [64]rns.Interface_Entry
	n := session_interfaces(s, entries[:])
	if n > len(out) {
		n = len(out)
	}
	for i in 0 ..< n {
		e := entries[i]
		name := rns.interface_name(&e)
		typ := rns.interface_type(&e)
		out[i] = Iface_Info{
			name = strings.clone(name),
			type_n = strings.clone(friendly_iface_type(typ, name)),
			online = e.online != 0,
			enabled = e.enabled != 0,
			rx = e.rx_bytes,
			tx = e.tx_bytes,
			rx_packets = e.rx_packets,
			tx_packets = e.tx_packets,
		}
	}
	return n
}

friendly_iface_type :: proc(typ, name: string) -> string {
	t := strings.to_lower(typ, context.temp_allocator)
	n := strings.to_lower(name, context.temp_allocator)
	switch {
	case strings.contains(t, "tcp") || strings.contains(n, "tcp"):
		return "TCP"
	case strings.contains(t, "udp"):
		return "UDP"
	case strings.contains(t, "unix") || strings.contains(t, "backbone") || strings.contains(n, "backbone"):
		return "Backbone (unix)"
	case strings.contains(t, "auto") || strings.contains(n, "auto"):
		return "Auto"
	case strings.contains(t, "i2p"):
		return "I2P"
	case strings.contains(t, "quic"):
		return "QUIC"
	case strings.contains(t, "https"):
		return "HTTPS"
	case strings.contains(t, "dns"):
		return "DNS"
	}
	if typ != "" {
		return typ
	}
	return "Interface"
}
