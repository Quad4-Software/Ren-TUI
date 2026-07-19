// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Threaded races over pack unpack and theme helpers.
*/

package tests

import "core:strings"
import "core:sync"
import "core:thread"
import "core:testing"

import "ren:lxmf"
import "ren:ui"

WORKER_ITERS :: 24
WORKER_COUNT :: 4

Race_Msg_State :: struct {
	ok_count: int,
	mu:       sync.Mutex,
}

race_msg_worker :: proc(data: rawptr) {
	st := cast(^Race_Msg_State)data
	local_ok := 0
	for _ in 0 ..< WORKER_ITERS {
		mat, ok := lxmf.identity_generate()
		if !ok {
			continue
		}
		dest := lxmf.delivery_hash(mat.hash[:])
		msg: lxmf.Message
		lxmf.message_init(&msg)
		msg.destination_hash = dest
		msg.title = strings.clone("")
		msg.content = strings.clone("race")
		if !lxmf.message_pack(&msg, &mat) {
			lxmf.message_destroy(&msg)
			continue
		}
		out, uok := lxmf.message_unpack(msg.packed)
		lxmf.message_destroy(&msg)
		if !uok {
			continue
		}
		if lxmf.message_verify(&out, mat.sign_pub[:]) && out.content == "race" {
			local_ok += 1
		}
		lxmf.message_destroy(&out)
	}
	sync.mutex_lock(&st.mu)
	st.ok_count += local_ok
	sync.mutex_unlock(&st.mu)
}

@(test)
test_race_parallel_pack_unpack :: proc(t: ^testing.T) {
	st: Race_Msg_State
	threads := make([dynamic]^thread.Thread, 0, WORKER_COUNT)
	defer {
		for th in threads {
			thread.destroy(th)
		}
		delete(threads)
	}
	for _ in 0 ..< WORKER_COUNT {
		th := thread.create_and_start_with_data(&st, race_msg_worker)
		testing.expect(t, th != nil)
		append(&threads, th)
	}
	for th in threads {
		thread.join(th)
	}
	testing.expect(t, st.ok_count == WORKER_COUNT * WORKER_ITERS)
}

Race_Theme_State :: struct {
	reads: int,
	mu:    sync.Mutex,
}

race_theme_reader :: proc(data: rawptr) {
	st := cast(^Race_Theme_State)data
	for _ in 0 ..< 100 {
		_ = ui.theme()
		_ = ui.theme_by_name("field")
	}
	sync.mutex_lock(&st.mu)
	st.reads += 1
	sync.mutex_unlock(&st.mu)
}

@(test)
test_race_theme_concurrent_reads :: proc(t: ^testing.T) {
	ui.set_theme(ui.FIELD)
	st: Race_Theme_State
	threads := make([dynamic]^thread.Thread, 0, WORKER_COUNT)
	defer {
		for th in threads {
			thread.destroy(th)
		}
		delete(threads)
	}
	for _ in 0 ..< WORKER_COUNT {
		th := thread.create_and_start_with_data(&st, race_theme_reader)
		testing.expect(t, th != nil)
		append(&threads, th)
	}
	for th in threads {
		thread.join(th)
	}
	testing.expect_value(t, st.reads, WORKER_COUNT)
	testing.expect_value(t, ui.theme().name, "field")
}
