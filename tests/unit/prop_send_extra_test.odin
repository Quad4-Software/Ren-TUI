// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
More unit coverage for prop send failover sync and method helpers.
*/

package tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "ren:lxmf"
import "ren:net"
import "ren:store"

@(test)
test_config_prop_fields_save_load :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-unit-prop-config"})
	_ = os.remove_all(base)
	defer os.remove_all(base)
	_ = os.make_directory_all(base)

	cfg := store.config_default()
	delete(cfg.data_dir)
	delete(cfg.config_path)
	cfg.data_dir = strings.clone(base)
	cfg.config_path, _ = filepath.join({base, "config"})

	pn: [store.HASH_LEN]u8
	pn[0] = 0xa1
	pn[15] = 0xb2
	store.config_set_propagation_node(&cfg, pn)
	cfg.send_method = .Opportunistic
	cfg.try_propagation_on_fail = false
	testing.expect(t, store.config_save(&cfg))
	defer store.config_destroy_strings(&cfg)

	data, err := os.read_entire_file_from_path(cfg.config_path, context.allocator)
	testing.expect(t, err == nil)
	defer delete(data)
	body := string(data)
	testing.expect(t, strings.contains(body, "try_propagation_on_send_fail = no"))
	testing.expect(t, strings.contains(body, "send_method = opportunistic"))
	testing.expect(t, strings.contains(body, store.hash_hex(pn, context.temp_allocator)))

	loaded := store.config_default()
	delete(loaded.data_dir)
	delete(loaded.config_path)
	loaded.data_dir = strings.clone(base)
	loaded.config_path, _ = filepath.join({base, "config"})
	store.config_load(&loaded)
	defer store.config_destroy_strings(&loaded)
	testing.expect(t, loaded.has_propagation_node)
	testing.expect(t, loaded.propagation_node == pn)
	testing.expect_value(t, loaded.send_method, lxmf.Method.Opportunistic)
	testing.expect(t, !loaded.try_propagation_on_fail)
}

@(test)
test_method_label_and_config_value :: proc(t: ^testing.T) {
	testing.expect_value(t, lxmf.method_label(.Direct), "Direct")
	testing.expect_value(t, lxmf.method_label(.Opportunistic), "Opportunistic")
	testing.expect_value(t, lxmf.method_label(.Propagated), "Propagate")
	testing.expect_value(t, lxmf.send_method_config_value(.Direct), "direct")
	testing.expect_value(t, lxmf.send_method_config_value(.Opportunistic), "opportunistic")
	testing.expect_value(t, lxmf.send_method_config_value(.Propagated), "propagated")
	testing.expect_value(t, lxmf.parse_send_method("opp"), lxmf.Method.Opportunistic)
	testing.expect_value(t, lxmf.parse_send_method("prop"), lxmf.Method.Propagated)
	testing.expect_value(t, lxmf.parse_send_method("1"), lxmf.Method.Opportunistic)
	testing.expect_value(t, lxmf.parse_send_method("2"), lxmf.Method.Direct)
	testing.expect_value(t, lxmf.parse_send_method("3"), lxmf.Method.Propagated)
}

@(test)
test_send_job_propagated_success :: proc(t: ^testing.T) {
	fake: Fake_Send
	fake.encrypt_ok = true
	s: net.Session
	testing.expect(t, setup_send_session(&s, &fake))
	defer lxmf.router_destroy(&s.router)
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	s.send_transport.encrypt = fake_encrypt

	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	pn: [store.HASH_LEN]u8
	pn[0] = 0x55
	pn[7] = 0xaa
	store.config_set_propagation_node(&cfg, pn)

	dest: [store.HASH_LEN]u8
	dest[0] = 0x99
	testing.expect(t, net.session_send_begin(&s, dest, "", "via-pn", &convs, &dir, &cfg, .Propagated))
	for _ in 0 ..< 8 {
		if !net.session_send_busy(&s) {
			break
		}
		net.session_send_tick(&s)
	}
	testing.expect(t, s.send.ok)
	testing.expect_value(t, s.send.method, lxmf.Method.Propagated)
	testing.expect(t, fake.opened >= 1)
	testing.expect(t, fake.sent >= 1)
	testing.expect_value(t, fake.packets, 0)
	testing.expect(t, fake.has_dest)
	testing.expect(t, fake.last_dest == pn)
	net.session_send_cancel(&s)
}

@(test)
test_send_job_failover_disabled :: proc(t: ^testing.T) {
	fake: Fake_Send
	fake.fail_open = true
	s: net.Session
	testing.expect(t, setup_send_session(&s, &fake))
	defer lxmf.router_destroy(&s.router)
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	pn: [store.HASH_LEN]u8
	pn[0] = 0x42
	store.config_set_propagation_node(&cfg, pn)
	cfg.try_propagation_on_fail = false

	dest: [store.HASH_LEN]u8
	dest[1] = 3
	testing.expect(t, net.session_send_begin(&s, dest, "", "x", &convs, &dir, &cfg, .Direct))
	for _ in 0 ..< 8 {
		if !net.session_send_busy(&s) {
			break
		}
		net.session_send_tick(&s)
	}
	testing.expect(t, !s.send.ok)
	testing.expect(t, !s.send.failed_over)
	net.session_send_cancel(&s)
}

@(test)
test_send_job_failover_without_node :: proc(t: ^testing.T) {
	fake: Fake_Send
	fake.fail_open = true
	s: net.Session
	testing.expect(t, setup_send_session(&s, &fake))
	defer lxmf.router_destroy(&s.router)
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	cfg.try_propagation_on_fail = true

	dest: [store.HASH_LEN]u8
	dest[1] = 4
	testing.expect(t, net.session_send_begin(&s, dest, "", "x", &convs, &dir, &cfg, .Direct))
	for _ in 0 ..< 8 {
		if !net.session_send_busy(&s) {
			break
		}
		net.session_send_tick(&s)
	}
	testing.expect(t, !s.send.ok)
	testing.expect(t, !s.send.failed_over)
	net.session_send_cancel(&s)
}

@(test)
test_send_job_opportunistic_failover_to_propagate :: proc(t: ^testing.T) {
	fake: Fake_Send
	fake.packet_ok = false
	fake.encrypt_ok = true
	s: net.Session
	testing.expect(t, setup_send_session(&s, &fake))
	defer lxmf.router_destroy(&s.router)
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	s.send_transport.packet_send = fake_packet_send
	s.send_transport.encrypt = fake_encrypt

	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	pn: [store.HASH_LEN]u8
	pn[0] = 0x77
	store.config_set_propagation_node(&cfg, pn)
	cfg.try_propagation_on_fail = true

	dest: [store.HASH_LEN]u8
	dest[0] = 0x88
	testing.expect(t, net.session_send_begin(&s, dest, "", "opp-fail", &convs, &dir, &cfg, .Opportunistic))
	for _ in 0 ..< 12 {
		if !net.session_send_busy(&s) {
			break
		}
		net.session_send_tick(&s)
	}
	testing.expect(t, s.send.ok)
	testing.expect(t, s.send.failed_over)
	testing.expect_value(t, s.send.method, lxmf.Method.Propagated)
	testing.expect(t, fake.sent >= 1)
	net.session_send_cancel(&s)
}

@(test)
test_send_job_reject_when_sync_busy :: proc(t: ^testing.T) {
	fake: Fake_Send
	s: net.Session
	testing.expect(t, setup_send_session(&s, &fake))
	defer lxmf.router_destroy(&s.router)
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	s.sync.active = true
	s.sync.done = false

	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)
	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)

	dest: [store.HASH_LEN]u8
	ok := net.session_send_begin(&s, dest, "", "blocked", &convs, &dir, nil, .Direct)
	testing.expect(t, !ok)
	testing.expect_value(t, s.status, "sync busy")
}
