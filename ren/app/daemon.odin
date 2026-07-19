// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Headless background session for -d/--daemon.
*/

package app

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:time"

import "ren:cli"
import "ren:constants"
import "ren:net"
import "ren:store"
import "ren:ui"
import "ren:version"

run_daemon :: proc(opts: ^cli.Options) -> int {
	cfg := store.config_default()
	if opts != nil {
		cli.apply_to_config(&cfg, opts)
	}
	defer store.config_destroy_strings(&cfg)

	_ = store.config_ensure_dirs(&cfg)
	store.config_load(&cfg)
	store.config_write_defaults_if_missing(&cfg)

	pid_path := cli.daemon_pid_path(cfg.data_dir)
	defer delete(pid_path)
	log_path := cli.daemon_log_path(cfg.data_dir)
	defer delete(log_path)

	if running, pid := cli.daemon_already_running(pid_path); running {
		fmt.eprintf("ren-tui: daemon already running (pid %d)\n", pid)
		return 1
	}

	fmt.printf("ren-tui %s daemon\n", version.line(context.temp_allocator))
	fmt.printf("pid file  %s\n", pid_path)
	fmt.printf("log file  %s\n", log_path)
	fmt.printf("identity  %s\n", cfg.identity_path)
	fmt.println("detaching...")

	dir := filepath.dir(log_path)
	_ = os.make_directory_all(dir)

	ok, derr := cli.daemonize(log_path)
	if !ok {
		fmt.eprintf("ren-tui: %s\n", derr)
		return 1
	}

	if !cli.daemon_write_pid(pid_path) {
		fmt.eprintln("ren-tui daemon: failed to write pid file")
		return 1
	}
	defer cli.daemon_remove_pid(pid_path)

	cli.daemon_install_stop_signals()

	log_path_librns, _ := filepath.join({cfg.data_dir, constants.LIBRNS_LOG_FILE})
	defer delete(log_path_librns)
	stderr_redir: ui.Stderr_Redirect
	_ = ui.stderr_redirect_start(&stderr_redir, log_path_librns)
	defer ui.stderr_redirect_stop(&stderr_redir)

	directory: store.Directory
	conversations: store.Conversations
	store.directory_init(&directory)
	store.directory_bind_spill(&directory, &cfg)
	store.directory_load_spill_meta(&directory)
	store.conversations_init(&conversations)
	store.conversations_load(&conversations, &cfg)
	defer {
		_ = store.conversations_save_all(&conversations, &cfg)
		store.conversations_destroy(&conversations)
		store.directory_destroy(&directory)
	}

	session: net.Session
	if !net.session_create(&session, &cfg, cfg.display_name) {
		fmt.eprintf("ren-tui daemon: session create failed: %s\n", session.status)
		return 1
	}
	defer net.session_close(&session)

	if !net.session_start(&session) {
		fmt.eprintf("ren-tui daemon: session start failed: %s\n", session.status)
		return 1
	}

	hex := net.session_delivery_hex(&session)
	fmt.printf("ren-tui daemon online delivery=%s\n", hex)

	last_save := time.tick_now()
	for !cli.daemon_should_stop() {
		net.session_poll(&session, &directory, &conversations, &cfg, cfg.auto_announce)
		buf: [net.SESSION_EVENT_CAP]net.Session_Event
		n := net.session_events_drain(&session, buf[:])
		for i in 0 ..< n {
			ev := buf[i]
			defer delete(ev.detail)
			switch ev.kind {
			case .Message_Received:
				fmt.printf("message received %s\n", ev.detail if ev.detail != "" else "")
			case .Send_Ok:
				fmt.printf("send ok %s\n", ev.detail)
			case .Send_Failed:
				fmt.printf("send failed %s\n", ev.detail)
			case .Error:
				fmt.printf("error %s\n", ev.detail)
			case .Online:
				fmt.printf("online %s\n", ev.detail)
			case .Offline:
				fmt.printf("offline %s\n", ev.detail)
			case .Page_Ok, .Page_Failed, .Announce, .None:
			}
		}
		if time.tick_since(last_save) >= 30 * time.Second {
			_ = store.conversations_save_all(&conversations, &cfg)
			last_save = time.tick_now()
		}
		free_all(context.temp_allocator)
		time.sleep(100 * time.Millisecond)
	}

	fmt.println("ren-tui daemon stopping")
	_ = store.conversations_save_all(&conversations, &cfg)
	return 0
}
