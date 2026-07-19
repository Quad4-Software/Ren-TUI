// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Black-box checks through public store and lxmf surfaces only.
*/

package tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "ren:lxmf"
import "ren:store"

@(test)
test_blackbox_config_file_prop_section :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-blackbox-prop"})
	_ = os.remove_all(base)
	defer os.remove_all(base)
	_ = os.make_directory_all(base)

	cfg := store.config_default()
	delete(cfg.data_dir)
	delete(cfg.config_path)
	cfg.data_dir = strings.clone(base)
	cfg.config_path, _ = filepath.join({base, "config"})
	pn: [store.HASH_LEN]u8
	for i in 0 ..< store.HASH_LEN {
		pn[i] = u8(i + 1)
	}
	store.config_set_propagation_node(&cfg, pn)
	cfg.send_method = .Opportunistic
	cfg.try_propagation_on_fail = false
	testing.expect(t, store.config_save(&cfg))
	defer store.config_destroy_strings(&cfg)

	raw, err := os.read_entire_file_from_path(cfg.config_path, context.allocator)
	testing.expect(t, err == nil)
	defer delete(raw)
	text := string(raw)
	testing.expect(t, strings.contains(text, "[client]"))
	testing.expect(t, strings.contains(text, "send_method = opportunistic"))
	testing.expect(t, strings.contains(text, "try_propagation_on_send_fail = no"))
	testing.expect(t, strings.contains(text, "propagation_node = "))
	testing.expect(t, strings.contains(text, store.hash_hex(pn, context.temp_allocator)))
}

@(test)
test_blackbox_method_cycle_closed_loop :: proc(t: ^testing.T) {
	start := lxmf.Method.Direct
	m := start
	seen_opp := false
	seen_prop := false
	for _ in 0 ..< 6 {
		m = lxmf.cycle_send_method(m)
		if m == .Opportunistic {
			seen_opp = true
		}
		if m == .Propagated {
			seen_prop = true
		}
	}
	testing.expect(t, seen_opp)
	testing.expect(t, seen_prop)
	testing.expect_value(t, m, start)
}

@(test)
test_blackbox_propagation_label_none :: proc(t: ^testing.T) {
	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)
	label := store.config_propagation_label(&cfg, &dir, context.temp_allocator)
	testing.expect(t, strings.contains(label, "none"))
}
