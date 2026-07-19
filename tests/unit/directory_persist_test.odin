// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Directory load/save across reboot for LXMF NomadNet and prop peers.
*/

package tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "ren:constants"
import "ren:store"

@(test)
test_directory_save_load_all_kinds :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-dir-persist-test"})
	_ = os.remove_all(base)
	_ = os.make_directory_all(base)
	defer os.remove_all(base)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	delete(cfg.data_dir)
	cfg.data_dir = strings.clone(base)

	d: store.Directory
	store.directory_init(&d)
	defer store.directory_destroy(&d)
	store.directory_bind_spill(&d, &cfg)

	lx, nn, pn: [store.HASH_LEN]u8
	lx[0] = 1
	nn[0] = 2
	pn[0] = 3
	store.directory_upsert(&d, lx, lx, .Lxmf, "lxmf-peer", nil)
	store.directory_upsert(&d, nn, nn, .Nomad_Node, "nomad-node", nil)
	store.directory_upsert(&d, pn, pn, .Propagation, "propagation", nil)
	testing.expect(t, store.directory_save_all(&d))

	d2: store.Directory
	store.directory_init(&d2)
	defer store.directory_destroy(&d2)
	store.directory_bind_spill(&d2, &cfg)
	store.directory_load_all(&d2, &cfg)
	testing.expect(t, store.directory_count_kind(&d2, .Lxmf) >= 1)
	testing.expect(t, store.directory_count_kind(&d2, .Nomad_Node) >= 1)
	testing.expect(t, store.directory_count_kind(&d2, .Propagation) >= 1)

	found_lx := false
	found_nn := false
	for p in d2.peers {
		if p.hash == lx && p.display_name == "lxmf-peer" {
			found_lx = true
		}
		if p.hash == nn && p.display_name == "nomad-node" {
			found_nn = true
		}
	}
	testing.expect(t, found_lx)
	testing.expect(t, found_nn)
}

@(test)
test_directory_seed_propagation_from_config :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-dir-seed-prop"})
	_ = os.remove_all(base)
	_ = os.make_directory_all(base)
	defer os.remove_all(base)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	delete(cfg.data_dir)
	cfg.data_dir = strings.clone(base)
	pn: [store.HASH_LEN]u8
	pn[0] = 0x55
	store.config_set_propagation_node(&cfg, pn)

	d: store.Directory
	store.directory_init(&d)
	defer store.directory_destroy(&d)
	store.directory_bind_spill(&d, &cfg)
	store.directory_load_all(&d, &cfg)
	testing.expect(t, store.directory_count_kind(&d, .Propagation) >= 1)
	found := false
	for p in d.peers {
		if p.hash == pn && p.kind == .Propagation {
			found = true
		}
	}
	testing.expect(t, found)
}

@(test)
test_bug_corrupt_peers_msgpack_does_not_crash :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-dir-corrupt"})
	_ = os.remove_all(base)
	_ = os.make_directory_all(base)
	defer os.remove_all(base)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	delete(cfg.data_dir)
	cfg.data_dir = strings.clone(base)

	path, _ := filepath.join({base, constants.PEERS_FILE})
	_ = os.write_entire_file(path, transmute([]u8)string("not-msgpack!!!"))

	d: store.Directory
	store.directory_init(&d)
	defer store.directory_destroy(&d)
	store.directory_bind_spill(&d, &cfg)
	store.directory_load_all(&d, &cfg)
	testing.expect_value(t, len(d.peers), 0)
}

@(test)
test_bug_empty_peers_file_loads_empty :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-dir-empty"})
	_ = os.remove_all(base)
	_ = os.make_directory_all(base)
	defer os.remove_all(base)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	delete(cfg.data_dir)
	cfg.data_dir = strings.clone(base)

	d: store.Directory
	store.directory_init(&d)
	defer store.directory_destroy(&d)
	store.directory_bind_spill(&d, &cfg)
	store.directory_load_all(&d, &cfg)
	testing.expect_value(t, len(d.peers), 0)
}
