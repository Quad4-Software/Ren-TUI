// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Headless ren session used by the Python LXMF live roundtrip.
Reads commands from a file and prints one machine line per event.
*/

package main

import "core:crypto/sha2"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

import "ren:constants"
import "ren:lxmf"
import "ren:net"
import "ren:store"

main :: proc() {
	os.exit(run())
}

run :: proc() -> int {
	data_dir := ""
	rns_config := ""
	commands := ""
	timeout_sec := 240
	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		a := args[i]
		switch a {
		case "--data-dir":
			if i + 1 >= len(args) {
				fmt.eprintln("ren-live-peer: --data-dir needs a path")
				return 2
			}
			i += 1
			data_dir = args[i]
		case "-c", "--rns-config":
			if i + 1 >= len(args) {
				fmt.eprintln("ren-live-peer: -c needs a path")
				return 2
			}
			i += 1
			rns_config = args[i]
		case "--commands":
			if i + 1 >= len(args) {
				fmt.eprintln("ren-live-peer: --commands needs a path")
				return 2
			}
			i += 1
			commands = args[i]
		case "-t", "--timeout":
			if i + 1 >= len(args) {
				fmt.eprintln("ren-live-peer: -t needs seconds")
				return 2
			}
			i += 1
			n, ok := strconv_parse(args[i])
			if !ok || n < 1 {
				fmt.eprintln("ren-live-peer: bad timeout")
				return 2
			}
			timeout_sec = n
		case:
			fmt.eprintf("ren-live-peer: unknown option %s\n", a)
			return 2
		}
	}
	if data_dir == "" || rns_config == "" || commands == "" {
		fmt.eprintln("ren-live-peer: need --data-dir, -c, and --commands")
		return 2
	}

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	store.config_apply_cli_overrides(&cfg, data_dir, "", rns_config)
	delete(cfg.display_name)
	cfg.display_name = strings.clone("ren-live")
	cfg.announce_interval_sec = constants.MIN_ANNOUNCE_INTERVAL_SEC
	_ = store.config_ensure_dirs(&cfg)

	session: net.Session
	directory: store.Directory
	conversations: store.Conversations
	store.directory_init(&directory)
	store.conversations_init(&conversations)
	defer {
		net.session_close(&session)
		store.directory_destroy(&directory)
		store.conversations_destroy(&conversations)
	}

	if !net.session_create(&session, &cfg, "ren-live", false) {
		fmt.eprintf("error session create %s\n", session.status)
		return 1
	}
	if !net.session_start(&session) {
		fmt.eprintf("error session start %s\n", session.status)
		return 1
	}

	hex := net.session_delivery_hex(&session)
	fmt.printf("delivery %s\n", hex)
	delete(hex)
	fmt.println("ready")

	pending := make([dynamic]string)
	defer {
		for line in pending {
			delete(line)
		}
		delete(pending)
	}
	cmd_off := 0
	inbound_seen := 0
	deadline := time.tick_add(time.tick_now(), time.Duration(timeout_sec) * time.Second)
	quit := false

	for !quit && time.tick_diff(time.tick_now(), deadline) > 0 {
		net.session_poll(&session, &directory, &conversations, &cfg)
		report_events(&session)
		inbound_seen = report_inbound(&conversations, inbound_seen)
		read_commands(commands, &cmd_off, &pending)
		if !net.session_send_busy(&session) && len(pending) > 0 {
			line := pending[0]
			ordered_remove(&pending, 0)
			quit = handle_command(&session, &conversations, &directory, &cfg, line)
			delete(line)
		}
		free_all(context.temp_allocator)
		time.sleep(50 * time.Millisecond)
	}

	if quit {
		fmt.println("bye")
		return 0
	}
	fmt.println("error timeout")
	return 1
}

@(private)
strconv_parse :: proc(s: string) -> (int, bool) {
	return strconv.parse_int(s)
}

@(private)
report_events :: proc(session: ^net.Session) {
	evs: [16]net.Session_Event
	n := net.session_events_drain(session, evs[:])
	for i in 0 ..< n {
		ev := evs[i]
		switch ev.kind {
		case .Send_Ok:
			fmt.println("tx ok")
		case .Send_Failed:
			fmt.printf("tx fail %s\n", ev.detail)
		case .Error:
			fmt.printf("error %s\n", ev.detail)
		case .None, .Online, .Offline, .Announce, .Message_Received, .Page_Ok, .Page_Failed:
		}
		delete(ev.detail)
	}
}

@(private)
report_inbound :: proc(conversations: ^store.Conversations, already: int) -> int {
	seen := 0
	for conv in conversations.items {
		for msg in conv.messages {
			if msg.direction != .In {
				continue
			}
			if seen >= already {
				sum := sha256(transmute([]u8)msg.content)
				fmt.printf("rx %d %s\n", len(msg.content), sum)
			}
			seen += 1
		}
	}
	return seen
}

@(private)
read_commands :: proc(path: string, off: ^int, pending: ^[dynamic]string) {
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil || len(data) <= off^ {
		return
	}
	chunk := string(data[off^:])
	last := strings.last_index(chunk, "\n")
	if last < 0 {
		return
	}
	complete := chunk[:last]
	off^ += last + 1
	for line in strings.split(complete, "\n", context.temp_allocator) {
		trimmed := strings.trim_space(line)
		if trimmed == "" {
			continue
		}
		append(pending, strings.clone(trimmed))
	}
}

@(private)
handle_command :: proc(
	session: ^net.Session,
	conversations: ^store.Conversations,
	directory: ^store.Directory,
	cfg: ^store.Config,
	line: string,
) -> bool {
	parts := strings.split(line, " ", context.temp_allocator)
	if len(parts) == 0 {
		return false
	}
	if parts[0] == "quit" {
		return true
	}
	if parts[0] != "send" || len(parts) < 4 {
		fmt.printf("error bad command %s\n", line)
		return false
	}
	method := lxmf.Method.Direct
	switch parts[1] {
	case "direct":
		method = .Direct
	case "opportunistic":
		method = .Opportunistic
	case:
		fmt.printf("error bad method %s\n", parts[1])
		return false
	}
	dest, ok := lxmf.decode_hex32(parts[2])
	if !ok {
		fmt.printf("error bad dest %s\n", parts[2])
		return false
	}
	body, rerr := os.read_entire_file_from_path(parts[3], context.allocator)
	if rerr != nil {
		fmt.printf("error cannot read %s\n", parts[3])
		return false
	}
	defer delete(body)
	if !net.session_send_begin(session, dest, "", string(body), conversations, directory, cfg, method) {
		fmt.println("tx fail send begin")
	}
	return false
}

@(private)
sha256 :: proc(data: []u8) -> string {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, data)
	digest: [sha2.DIGEST_SIZE_256]u8
	sha2.final(&ctx, digest[:])
	digits := "0123456789abcdef"
	out := make([]u8, 64, context.temp_allocator)
	for b, i in digest {
		out[i * 2] = digits[b >> 4]
		out[i * 2 + 1] = digits[b & 0xf]
	}
	return string(out)
}
