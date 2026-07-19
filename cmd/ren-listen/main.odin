// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
CLI that listens for LXMF and NomadNet announces then exits.
*/

package main

import "core:fmt"
import "core:os"
import "core:time"

import "ren:cli"
import "ren:crash"
import "ren:net"
import "ren:store"
import "ren:version"

main :: proc() {
	crash.install()
	context.assertion_failure_proc = crash.assertion_failure

	opts, err := cli.parse_args(os.args[1:], true)
	if err != "" {
		fmt.eprintf("ren-listen: %s\n", err)
		cli.print_help_listen()
		cli.options_destroy(&opts)
		crash.close()
		os.exit(2)
	}

	cfg := store.config_default()
	cli.apply_to_config(&cfg, &opts)

	if handled, code := cli.run_utility_actions(&cfg, &opts); handled {
		store.config_destroy_strings(&cfg)
		cli.options_destroy(&opts)
		crash.close()
		os.exit(code)
	}

	_ = store.config_ensure_dirs(&cfg)

	fmt.printf("ren-tui   %s\n", version.line(context.temp_allocator))
	fmt.printf("identity  %s\n", cfg.identity_path)
	fmt.printf("rns       %s\n", cfg.rns_config)
	fmt.printf("listen    %d seconds\n", opts.timeout_sec)

	session: net.Session
	directory: store.Directory
	conversations: store.Conversations
	store.directory_init(&directory)
	store.conversations_init(&conversations)

	exit_code := 0
	if !net.session_create(&session, &cfg, cfg.display_name) {
		fmt.eprintf("session create failed: %s\n", session.status)
		exit_code = 1
	} else if !net.session_start(&session) {
		fmt.eprintf("session start failed: %s\n", session.status)
		exit_code = 1
	} else {
		hex := net.session_delivery_hex(&session)
		fmt.printf("delivery  %s\n", hex)
		fmt.printf("announced lxmf.delivery and nomadnetwork.node\n")

		deadline := time.tick_add(time.tick_now(), time.Duration(opts.timeout_sec) * time.Second)
		last_report := time.tick_now()
		for time.tick_diff(time.tick_now(), deadline) > 0 {
			net.session_poll(&session, &directory, &conversations)
			if time.tick_since(last_report) >= 2 * time.Second {
				print_snapshot(&directory, &session)
				last_report = time.tick_now()
			}
			time.sleep(100 * time.Millisecond)
		}

		fmt.println("--- final ---")
		print_snapshot(&directory, &session)
		lxmf_n := store.directory_count_kind(&directory, .Lxmf)
		node_n := store.directory_count_kind(&directory, .Nomad_Node)
		if lxmf_n == 0 && node_n == 0 {
			fmt.eprintln("no lxmf.delivery or nomadnetwork.node announces heard")
			exit_code = 1
		} else {
			fmt.println("ok")
		}
	}

	net.session_close(&session)
	store.directory_destroy(&directory)
	store.conversations_destroy(&conversations)
	store.config_destroy_strings(&cfg)
	cli.options_destroy(&opts)
	crash.close()
	os.exit(exit_code)
}

print_snapshot :: proc(d: ^store.Directory, s: ^net.Session) {
	fmt.printf(
		"heard lxmf=%d nodes=%d pn=%d other=%d announces_sent=%d\n",
		store.directory_count_kind(d, .Lxmf),
		store.directory_count_kind(d, .Nomad_Node),
		store.directory_count_kind(d, .Propagation),
		d.heard_other,
		s.announces,
	)
	shown := 0
	for p in d.peers {
		if shown >= 12 {
			break
		}
		kind := "lxmf"
		switch p.kind {
		case .Lxmf:
			kind = "lxmf"
		case .Nomad_Node:
			kind = "node"
		case .Propagation:
			kind = "pn"
		}
		name := p.display_name if p.display_name != "" else "-"
		hex := store.hash_hex(p.hash, context.temp_allocator)
		cost := "-"
		if sc, ok := p.stamp_cost.?; ok {
			cost = fmt.tprintf("%d", sc)
		}
		fmt.printf("  [%s] %-24s %s cost=%s hops=%d\n", kind, name, hex, cost, p.hops)
		shown += 1
	}
}
