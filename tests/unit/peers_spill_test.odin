// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Tests for peer hot-cap spill and hops-stable directory revision.
*/

package tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "ren:constants"
import "ren:store"

@(test)
test_directory_hops_do_not_bump_revision :: proc(t: ^testing.T) {
	d: store.Directory
	store.directory_init(&d)
	defer store.directory_destroy(&d)
	h: [store.HASH_LEN]u8
	h[0] = 42
	store.directory_upsert(&d, h, h, .Lxmf, "bob", nil, 1)
	rev := d.revision
	store.directory_upsert(&d, h, h, .Lxmf, "bob", nil, 9)
	testing.expect_value(t, d.revision, rev)
	testing.expect_value(t, d.peers[0].hops, u8(9))
}

@(test)
test_directory_hot_cap_spills_to_msgpack :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-peers-spill-test"})
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

	for i in 0 ..< constants.PEERS_HOT_MAX + 5 {
		h: [store.HASH_LEN]u8
		h[0] = u8(i)
		h[1] = u8(i >> 8)
		store.directory_upsert(&d, h, h, .Nomad_Node, "n", nil, 1)
	}
	testing.expect(t, len(d.peers) <= constants.PEERS_HOT_MAX)
	testing.expect(t, d.spill_count > 0)
	testing.expect(t, os.exists(d.spill_path))
}
