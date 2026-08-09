// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Workfactor stamp and ticket helpers.
*/

package lxmf

import "core:bytes"
import "core:crypto"
import "core:crypto/hkdf"
import "core:mem"
import "core:time"

STAMP_SIZE :: 32
TICKET_LENGTH :: 16
COST_TICKET :: 0x100

WORKBLOCK_EXPAND_ROUNDS :: 3000
WORKBLOCK_EXPAND_ROUNDS_PN :: 1000
WORKBLOCK_CHUNK :: 256

// Keep stamp ticks short so the TUI poll loop stays interactive.
STAMP_TICK_BUDGET :: 8 * time.Millisecond

Stamp_Gen :: struct {
	active:        bool,
	done:          bool,
	ok:            bool,
	cost:          int,
	expand_rounds: int,
	rounds_done:   int,
	attempts:      int,
	message_id:    [MESSAGE_ID_LEN]u8,
	workblock:     []u8,
	stamp:         []u8,
}

stamp_workblock_round :: proc(material: []u8, n: int, out_chunk: []u8) {
	nw: Writer
	writer_init(&nw, context.temp_allocator)
	write_int(&nw, i64(n))
	packed_n := writer_bytes(&nw)
	salt_src := make([]u8, len(material) + len(packed_n), context.temp_allocator)
	copy(salt_src, material)
	copy(salt_src[len(material):], packed_n)
	salt := full_hash(salt_src)
	hkdf.extract_and_expand(.SHA256, salt[:], material, nil, out_chunk)
}

stamp_workblock :: proc(material: []u8, expand_rounds: int = WORKBLOCK_EXPAND_ROUNDS, allocator := context.allocator) -> []u8 {
	out := make([]u8, expand_rounds * WORKBLOCK_CHUNK, allocator)
	chunk := make([]u8, WORKBLOCK_CHUNK, context.temp_allocator)
	for n in 0 ..< expand_rounds {
		stamp_workblock_round(material, n, chunk)
		copy(out[n * WORKBLOCK_CHUNK:], chunk)
	}
	return out
}

stamp_gen_begin :: proc(
	g: ^Stamp_Gen,
	message_id: []u8,
	cost: int,
	expand_rounds: int = WORKBLOCK_EXPAND_ROUNDS,
) -> bool {
	stamp_gen_cancel(g)
	if cost <= 0 || len(message_id) != MESSAGE_ID_LEN {
		return false
	}
	g.active = true
	g.done = false
	g.ok = false
	g.cost = cost
	g.expand_rounds = expand_rounds if expand_rounds > 0 else WORKBLOCK_EXPAND_ROUNDS
	g.rounds_done = 0
	g.attempts = 0
	copy(g.message_id[:], message_id)
	g.workblock = make([]u8, g.expand_rounds * WORKBLOCK_CHUNK)
	return true
}

stamp_gen_cancel :: proc(g: ^Stamp_Gen) {
	delete(g.workblock)
	delete(g.stamp)
	g^ = {}
}

// Advance stamp work until done or budget elapses. Returns true when finished.
stamp_gen_tick :: proc(g: ^Stamp_Gen, budget: time.Duration = STAMP_TICK_BUDGET) -> bool {
	if g == nil || !g.active || g.done {
		return g != nil && g.done
	}
	start := time.tick_now()
	mid := g.message_id[:]

	chunk := make([]u8, WORKBLOCK_CHUNK, context.temp_allocator)
	for g.rounds_done < g.expand_rounds {
		stamp_workblock_round(mid, g.rounds_done, chunk)
		copy(g.workblock[g.rounds_done * WORKBLOCK_CHUNK:], chunk)
		g.rounds_done += 1
		if time.tick_since(start) >= budget {
			return false
		}
	}

	candidate := make([]u8, STAMP_SIZE, context.temp_allocator)
	for {
		crypto.rand_bytes(candidate)
		g.attempts += 1
		if stamp_valid(candidate, g.cost, g.workblock) {
			delete(g.stamp)
			g.stamp = make([]u8, STAMP_SIZE)
			copy(g.stamp, candidate)
			g.ok = true
			g.done = true
			g.active = false
			return true
		}
		if time.tick_since(start) >= budget {
			return false
		}
	}
}

stamp_value :: proc(workblock: []u8, stamp: []u8) -> int {
	material := make([]u8, len(workblock) + len(stamp), context.temp_allocator)
	copy(material, workblock)
	copy(material[len(workblock):], stamp)
	digest := full_hash(material)
	return leading_zero_bits(digest[:])
}

stamp_valid :: proc(stamp: []u8, target_cost: int, workblock: []u8) -> bool {
	if len(stamp) != STAMP_SIZE || target_cost <= 0 || target_cost > 256 {
		return false
	}
	material := make([]u8, len(workblock) + len(stamp), context.temp_allocator)
	copy(material, workblock)
	copy(material[len(workblock):], stamp)
	digest := full_hash(material)
	target: [STAMP_SIZE]u8
	bit_from_lsb := 256 - target_cost
	from_msb := 255 - bit_from_lsb
	byte_i := from_msb / 8
	bit_i := 7 - (from_msb % 8)
	target[byte_i] = 1 << u8(bit_i)
	return bytes_be_leq(digest[:], target[:])
}

@(private)
bytes_be_leq :: proc(a, b: []u8) -> bool {
	n := min(len(a), len(b))
	for i in 0 ..< n {
		if a[i] < b[i] {
			return true
		}
		if a[i] > b[i] {
			return false
		}
	}
	return len(a) <= len(b)
}

@(private)
leading_zero_bits :: proc(digest: []u8) -> int {
	value := 0
	for b in digest {
		if b == 0 {
			value += 8
			continue
		}
		for bit in 0 ..< 8 {
			if (b & (0x80 >> u8(bit))) == 0 {
				value += 1
			} else {
				return value
			}
		}
	}
	return value
}

generate_stamp :: proc(
	message_id: []u8,
	stamp_cost: int,
	expand_rounds: int = WORKBLOCK_EXPAND_ROUNDS,
	allocator := context.allocator,
) -> (stamp: []u8, value: int, ok: bool) {
	if stamp_cost <= 0 || len(message_id) != MESSAGE_ID_LEN {
		return nil, 0, false
	}
	workblock := stamp_workblock(message_id, expand_rounds, context.temp_allocator)
	candidate := make([]u8, STAMP_SIZE, allocator)
	for {
		crypto.rand_bytes(candidate)
		if stamp_valid(candidate, stamp_cost, workblock) {
			return candidate, stamp_value(workblock, candidate), true
		}
	}
}

ticket_stamp :: proc(ticket: []u8, message_id: []u8, allocator := context.allocator) -> []u8 {
	buf := make([]u8, len(ticket) + len(message_id), context.temp_allocator)
	copy(buf, ticket)
	copy(buf[len(ticket):], message_id)
	h := truncated_hash(buf)
	return bytes.clone(h[:], allocator)
}

ticket_stamp_matches :: proc(stamp: []u8, ticket: []u8, message_id: []u8) -> bool {
	if len(stamp) != TICKET_LENGTH || len(ticket) != TICKET_LENGTH {
		return false
	}
	expected := ticket_stamp(ticket, message_id, context.temp_allocator)
	return mem.compare(stamp, expected) == 0
}

validate_message_stamp :: proc(
	stamp: []u8,
	message_id: []u8,
	required_cost: int,
	tickets: [][]u8 = nil,
) -> (ok: bool, value: int) {
	if required_cost <= 0 {
		return true, 0
	}
	if len(stamp) == TICKET_LENGTH {
		for ticket in tickets {
			if ticket_stamp_matches(stamp, ticket, message_id) {
				return true, COST_TICKET
			}
		}
	}
	if len(stamp) != STAMP_SIZE {
		return false, 0
	}
	workblock := stamp_workblock(message_id, WORKBLOCK_EXPAND_ROUNDS, context.temp_allocator)
	if !stamp_valid(stamp, required_cost, workblock) {
		return false, 0
	}
	return true, stamp_value(workblock, stamp)
}
