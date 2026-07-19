// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Timed benches for micron parse/layout, conversations persist, and UI buffers.
Run: make bench
*/

package tests

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "ren:app"
import "ren:micron"
import "ren:store"
import "ren:ui"

BENCH_MICRON_ITERS :: 200
BENCH_CONV_MSGS :: 200
BENCH_LAYOUT_ITERS :: 100

@(test)
test_bench_micron_parse_and_layout :: proc(t: ^testing.T) {
	src_parts := make([dynamic]string, 0, 80)
	defer {
		for p in src_parts {
			delete(p)
		}
		delete(src_parts)
	}
	append(&src_parts, strings.clone(">`Hello`\n"))
	for i in 0 ..< 40 {
		append(&src_parts, strings.clone(fmt.tprintf("`[link%d`/page/x%d.mu]\nSome text line %d with wrap bait.\n", i, i, i)))
	}
	src := strings.concatenate(src_parts[:])
	defer delete(src)

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)

	start := time.tick_now()
	for _ in 0 ..< BENCH_MICRON_ITERS {
		doc := micron.parse(src)
		rows := micron.layout_doc(doc, 72)
		micron.layout_rows_destroy(&rows)
		micron.doc_destroy(&doc)
	}
	elapsed := time.tick_since(start)
	fmt.printf("bench micron parse+layout %d iters in %v  peak=%dB current=%dB\n", BENCH_MICRON_ITERS, elapsed, track.peak_memory_allocated, track.current_memory_allocated)
	testing.expect_value(t, track.current_memory_allocated, 0)
	for _, leak in track.allocation_map {
		fmt.printf("bench leak %dB @ %v\n", leak.size, leak.location)
	}
}

@(test)
test_bench_conversations_save_load :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-bench-conv"})
	_ = os.remove_all(base)
	defer os.remove_all(base)
	_ = os.make_directory_all(base)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	delete(cfg.data_dir)
	cfg.data_dir = strings.clone(base)
	_ = store.config_ensure_dirs(&cfg)

	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)
	peer: [store.HASH_LEN]u8
	peer[0] = 9
	conv := store.conversations_get_or_create(&convs, peer, "bench")
	for i in 0 ..< BENCH_CONV_MSGS {
		append(&conv.messages, store.Stored_Message{
			direction = .In if i % 2 == 0 else .Out,
			title = strings.clone(""),
			content = strings.clone(fmt.tprintf("msg-%d-payload-xxxxxxxx", i)),
			timestamp = f64(i),
			method = .Direct,
			verified = true,
			hops = u8(1 + i % 7),
		})
	}

	start := time.tick_now()
	testing.expect(t, store.conversations_save_peer(&convs, &cfg, peer))
	save_dt := time.tick_since(start)

	loaded: store.Conversations
	store.conversations_init(&loaded)
	defer store.conversations_destroy(&loaded)
	start = time.tick_now()
	store.conversations_load(&loaded, &cfg)
	load_dt := time.tick_since(start)
	testing.expect(t, len(loaded.items) >= 1)
	testing.expect_value(t, len(loaded.items[0].messages), BENCH_CONV_MSGS)
	fmt.printf("bench conversations save %v load %v (%d msgs)\n", save_dt, load_dt, BENCH_CONV_MSGS)
}

@(test)
test_bench_ui_buffer_clear_present_path :: proc(t: ^testing.T) {
	ui.caps_init("256")
	ui.set_theme(ui.FIELD)
	buf := ui.buffer_create(120, 40)
	defer ui.buffer_destroy(&buf)
	start := time.tick_now()
	for i in 0 ..< 300 {
		ui.buffer_clear(&buf, ui.theme().bg, ui.theme().fg)
		ui.buffer_text(&buf, 1, 1, "bench line", ui.theme().fg, ui.theme().bg)
		_ = i
	}
	elapsed := time.tick_since(start)
	fmt.printf("bench buffer clear+text 300 iters (120x40) in %v\n", elapsed)
	ui.caps_init("full")
}

@(test)
test_bench_page_sanitize_and_basename :: proc(t: ^testing.T) {
	raw := make([]u8, 64 * 1024)
	defer delete(raw)
	for i in 0 ..< len(raw) {
		raw[i] = u8(32 + i % 90)
		if i % 80 == 0 {
			raw[i] = '\n'
		}
	}
	start := time.tick_now()
	for _ in 0 ..< 50 {
		s := app.page_sanitize_bytes(raw)
		bn := app.page_download_basename("/page/index.mu")
		delete(bn)
		delete(s)
	}
	elapsed := time.tick_since(start)
	fmt.printf("bench page sanitize 64KiB x50 in %v\n", elapsed)
}

@(test)
test_bench_temp_allocator_free_all_reclaims :: proc(t: ^testing.T) {
	for round in 0 ..< 20 {
		for _ in 0 ..< 100 {
			_ = fmt.tprintf("temp-%d-%d", round, 12345)
			_ = make([]u8, 4096, context.temp_allocator)
		}
		free_all(context.temp_allocator)
	}
	testing.expect(t, true)
	fmt.printf("bench temp free_all 20 rounds ok\n")
}

@(test)
test_hops_unknown_vs_path_direct :: proc(t: ^testing.T) {
	d: store.Directory
	store.directory_init(&d)
	defer store.directory_destroy(&d)
	h: [store.HASH_LEN]u8
	h[0] = 3
	store.directory_upsert(&d, h, h, .Nomad_Node, "n", nil, 0)
	testing.expect(t, !d.peers[0].hops_known)
	testing.expect_value(t, store.format_peer_hops_peer(d.peers[0]), "hops=?")
	store.directory_apply_path_hops(&d, h, 0)
	testing.expect(t, d.peers[0].hops_known)
	testing.expect_value(t, store.format_peer_hops_peer(d.peers[0]), "hops=0")
	store.directory_upsert(&d, h, h, .Nomad_Node, "n", nil, 0)
	testing.expect(t, d.peers[0].hops_known)
	testing.expect_value(t, d.peers[0].hops, u8(0))
	store.directory_upsert(&d, h, h, .Nomad_Node, "n", nil, 4)
	testing.expect_value(t, d.peers[0].hops, u8(4))
}
