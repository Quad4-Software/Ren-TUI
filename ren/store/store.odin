// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Config directory peers and in-memory conversation state.
*/

package store

import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:time"

import "ren:constants"
import "ren:lxmf"
import "ren:ui"

HASH_LEN :: lxmf.HASH_LEN

Peer_Kind :: enum {
	Lxmf,
	Nomad_Node,
	Propagation,
}

Peer :: struct {
	hash:          [HASH_LEN]u8,
	identity_hash: [HASH_LEN]u8,
	display_name:  string,
	stamp_cost:    Maybe(i64),
	last_heard:    f64,
	kind:          Peer_Kind,
	hops:          u8,
}

Conversation :: struct {
	peer_hash: [HASH_LEN]u8,
	title:     string,
	messages:  [dynamic]Stored_Message,
	unread:    int,
}

Stored_Message :: struct {
	id:        [lxmf.MESSAGE_ID_LEN]u8,
	direction: enum {
		In,
		Out,
	},
	title:     string,
	content:   string,
	timestamp: f64,
	method:    lxmf.Method,
	verified:  bool,
	stamped:   bool,
	hops:      u8,
}

Config :: struct {
	home:                 string,
	display_name:         string,
	identity_path:        string,
	rns_config:           string,
	data_dir:             string,
	config_path:          string,
	stamp_cost:           Maybe(i64),
	auto_announce:        bool,
	announce_interval_sec: int,
	obfuscate_hops:       bool,
	mouse:                bool,
	color_mode:           string,
	theme_name:           string,
	theme_hex:            ui.Theme_Hex,
}

user_home_dir :: proc(allocator := context.allocator) -> string {
	when ODIN_OS == .Windows {
		if profile := os.get_env("USERPROFILE", allocator); profile != "" {
			return profile
		}
		if home := os.get_env("HOME", allocator); home != "" {
			return home
		}
	} else {
		if home := os.get_env("HOME", allocator); home != "" {
			return home
		}
	}
	return strings.clone(".", allocator)
}

config_data_dir :: proc(home: string, allocator := context.allocator) -> string {
	when ODIN_OS == .Windows {
		if appdata := os.get_env("APPDATA", context.temp_allocator); appdata != "" {
			p, _ := filepath.join({appdata, constants.CONFIG_DIR_NAME}, allocator)
			return p
		}
	}
	p, _ := filepath.join({home, ".config", constants.CONFIG_DIR_NAME}, allocator)
	return p
}

config_default :: proc(allocator := context.allocator) -> Config {
	home := user_home_dir(allocator)
	base := config_data_dir(home, allocator)
	ident, _ := filepath.join({base, constants.IDENTITY_FILE}, allocator)
	cfg_path, _ := filepath.join({base, constants.CONFIG_FILE}, allocator)
	rns := resolve_rns_config(home, base, allocator)
	return Config{
		home = home,
		display_name = strings.clone(constants.DEFAULT_DISPLAY_NAME, allocator),
		identity_path = ident,
		rns_config = rns,
		data_dir = base,
		config_path = cfg_path,
		stamp_cost = nil,
		auto_announce = constants.DEFAULT_AUTO_ANNOUNCE,
		announce_interval_sec = constants.DEFAULT_ANNOUNCE_INTERVAL_SEC,
		obfuscate_hops = false,
		mouse = constants.DEFAULT_MOUSE,
		color_mode = strings.clone(constants.DEFAULT_COLOR_MODE, allocator),
		theme_name = strings.clone(constants.DEFAULT_THEME, allocator),
		theme_hex = {},
	}
}

resolve_rns_config :: proc(home, data_dir: string, allocator := context.allocator) -> string {
	if override := os.get_env(constants.ENV_RNS_CONFIG, context.temp_allocator); override != "" {
		return strings.clone(override, allocator)
	}
	c1, _ := filepath.join({home, constants.RNS_CONFIG_GO}, context.temp_allocator)
	c2, _ := filepath.join({home, constants.RNS_CONFIG_PY}, context.temp_allocator)
	c3, _ := filepath.join({data_dir, constants.RNS_LOCAL_DIR}, context.temp_allocator)
	for c in ([]string{c1, c2, c3}) {
		if c != "" && os.exists(c) {
			return strings.clone(c, allocator)
		}
	}
	fallback, _ := filepath.join({home, constants.RNS_CONFIG_GO}, allocator)
	return fallback
}

config_ensure_dirs :: proc(c: ^Config) -> bool {
	err := os.make_directory_all(c.data_dir)
	return err == nil || os.exists(c.data_dir)
}

config_apply_cli_overrides :: proc(c: ^Config, data_dir, config_path, rns_config: string) {
	if data_dir != "" {
		delete(c.data_dir)
		c.data_dir = strings.clone(data_dir)
		if config_path == "" {
			delete(c.config_path)
			c.config_path, _ = filepath.join({c.data_dir, constants.CONFIG_FILE})
		}
		delete(c.identity_path)
		c.identity_path, _ = filepath.join({c.data_dir, constants.IDENTITY_FILE})
	}
	if config_path != "" {
		delete(c.config_path)
		c.config_path = strings.clone(config_path)
	}
	if rns_config != "" {
		delete(c.rns_config)
		c.rns_config = strings.clone(rns_config)
	}
}

config_reset_identity :: proc(c: ^Config) -> bool {
	if c.identity_path == "" {
		return false
	}
	if !os.exists(c.identity_path) {
		return true
	}
	return os.remove(c.identity_path) == nil
}

config_reset_conversations :: proc(c: ^Config) -> bool {
	dir := conversations_dir(c, context.temp_allocator)
	if !os.exists(dir) {
		return true
	}
	return os.remove_all(dir) == nil
}

config_load :: proc(c: ^Config) {
	data, err := os.read_entire_file_from_path(c.config_path, context.allocator)
	if err != nil {
		return
	}
	defer delete(data)
	section := ""
	lines := strings.split_lines(string(data), context.temp_allocator)
	for line in lines {
		s := strings.trim_space(line)
		if s == "" || strings.has_prefix(s, "#") || strings.has_prefix(s, ";") {
			continue
		}
		if strings.has_prefix(s, "[") && strings.has_suffix(s, "]") {
			section = strings.to_lower(s[1:len(s) - 1], context.temp_allocator)
			continue
		}
		eq := strings.index_byte(s, '=')
		if eq <= 0 {
			continue
		}
		key := strings.to_lower(strings.trim_space(s[:eq]), context.temp_allocator)
		val := strings.trim_space(s[eq + 1:])
		switch section {
		case "client":
			config_apply_client(c, key, val)
		case "network":
			config_apply_network(c, key, val)
		case "ui":
			config_apply_ui(c, key, val)
		case "theme":
			ui.theme_hex_set(&c.theme_hex, key, val)
		}
	}
}

@(private)
config_apply_client :: proc(c: ^Config, key, val: string) {
	switch key {
	case "display_name", "name":
		delete(c.display_name)
		c.display_name = strings.clone(val)
	case "auto_announce":
		c.auto_announce = parse_bool(val, true)
	case "announce_interval_sec", "announce_interval":
		if n, ok := strconv.parse_int(val); ok && n >= constants.MIN_ANNOUNCE_INTERVAL_SEC {
			c.announce_interval_sec = n
		}
	case "stamp_cost":
		if val == "" || val == "none" {
			c.stamp_cost = nil
		} else if n, ok := strconv.parse_i64(val); ok {
			c.stamp_cost = n
		}
	}
}

@(private)
config_apply_network :: proc(c: ^Config, key, val: string) {
	switch key {
	case "rns_config":
		if val != "" {
			delete(c.rns_config)
			c.rns_config = strings.clone(val)
		}
	case "obfuscate_hops", "local_hops_delta":
		c.obfuscate_hops = parse_bool(val, false)
	}
}

@(private)
config_apply_ui :: proc(c: ^Config, key, val: string) {
	switch key {
	case "mouse":
		c.mouse = parse_bool(val, true)
	case "color", "color_mode", "colormode":
		delete(c.color_mode)
		c.color_mode = strings.clone(val)
	case "theme", "theme_name":
		delete(c.theme_name)
		c.theme_name = strings.clone(val)
	}
}

config_apply_theme :: proc(c: ^Config) {
	ui.apply_theme_hex(c.theme_name, c.theme_hex)
}

config_destroy_strings :: proc(c: ^Config) {
	delete(c.home)
	delete(c.display_name)
	delete(c.identity_path)
	delete(c.rns_config)
	delete(c.data_dir)
	delete(c.config_path)
	delete(c.color_mode)
	delete(c.theme_name)
	ui.theme_hex_destroy(&c.theme_hex)
}

parse_bool :: proc(val: string, fallback: bool) -> bool {
	v := strings.to_lower(val, context.temp_allocator)
	switch v {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	}
	return fallback
}

config_save :: proc(c: ^Config) -> bool {
	if !config_ensure_dirs(c) {
		return false
	}
	stamp := ""
	if cost, ok := c.stamp_cost.?; ok {
		stamp = fmt.tprintf("%d", cost)
	}
	theme_block := config_theme_block(c)
	body := fmt.tprintf(
		"# ren-tui configuration\n" +
		"# Plaintext file with no extension (NomadNet-style).\n" +
		"\n" +
		"[client]\n" +
		"display_name = %s\n" +
		"auto_announce = %s\n" +
		"announce_interval_sec = %d\n" +
		"stamp_cost = %s\n" +
		"\n" +
		"[network]\n" +
		"rns_config = %s\n" +
		"obfuscate_hops = %s\n" +
		"\n" +
		"[ui]\n" +
		"color = %s\n" +
		"theme = %s\n" +
		"mouse = %s\n" +
		"%s",
		c.display_name,
		"yes" if c.auto_announce else "no",
		c.announce_interval_sec,
		stamp,
		c.rns_config,
		"yes" if c.obfuscate_hops else "no",
		c.color_mode,
		c.theme_name,
		"yes" if c.mouse else "no",
		theme_block,
	)
	ok := os.write_entire_file(c.config_path, transmute([]u8)body) == nil
	if ok {
		_ = config_sync_rns_local_hops_delta(c)
	}
	return ok
}

// Patch RNS config [reticulum] local_hops_delta for Python RNS / stacks that honor it.
// Go reticulum-go and current librns ignore this key. Default remains off.
config_sync_rns_local_hops_delta :: proc(c: ^Config) -> bool {
	path := c.rns_config
	if path == "" {
		return false
	}
	want := "Yes" if c.obfuscate_hops else "No"
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		if !c.obfuscate_hops {
			return true
		}
		body := fmt.tprintf("# written by ren-tui\n[reticulum]\nlocal_hops_delta = %s\n", want)
		return os.write_entire_file(path, transmute([]u8)body) == nil
	}
	defer delete(data)

	lines := strings.split_lines(string(data), context.temp_allocator)
	out: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	in_ret := false
	seen_key := false
	wrote_section := false
	for line in lines {
		s := strings.trim_space(line)
		if strings.has_prefix(s, "[") && strings.has_suffix(s, "]") {
			if in_ret && !seen_key {
				strings.write_string(&out, fmt.tprintf("local_hops_delta = %s\n", want))
				seen_key = true
			}
			sec := strings.to_lower(s[1:len(s) - 1], context.temp_allocator)
			in_ret = sec == "reticulum"
			if in_ret {
				wrote_section = true
			}
			strings.write_string(&out, line)
			strings.write_string(&out, "\n")
			continue
		}
		if in_ret {
			eq := strings.index_byte(s, '=')
			if eq > 0 {
				key := strings.to_lower(strings.trim_space(s[:eq]), context.temp_allocator)
				if key == "local_hops_delta" {
					strings.write_string(&out, fmt.tprintf("local_hops_delta = %s\n", want))
					seen_key = true
					continue
				}
			}
		}
		strings.write_string(&out, line)
		strings.write_string(&out, "\n")
	}
	if in_ret && !seen_key {
		strings.write_string(&out, fmt.tprintf("local_hops_delta = %s\n", want))
		seen_key = true
	}
	if !wrote_section {
		strings.write_string(&out, fmt.tprintf("\n[reticulum]\nlocal_hops_delta = %s\n", want))
	}
	return os.write_entire_file(path, transmute([]u8)strings.to_string(out)) == nil
}

@(private)
config_theme_block :: proc(c: ^Config) -> string {
	if !ui.theme_hex_has_any(c.theme_hex) {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, "\n[theme]\n")
	write_ov :: proc(b: ^strings.Builder, key, val: string) {
		if val == "" {
			return
		}
		strings.write_string(b, key)
		strings.write_string(b, " = ")
		strings.write_string(b, val)
		strings.write_string(b, "\n")
	}
	ov := c.theme_hex
	write_ov(&b, "bg", ov.bg)
	write_ov(&b, "fg", ov.fg)
	write_ov(&b, "muted", ov.muted)
	write_ov(&b, "border", ov.border)
	write_ov(&b, "accent", ov.accent)
	write_ov(&b, "accent_dim", ov.accent_dim)
	write_ov(&b, "highlight_bg", ov.highlight_bg)
	write_ov(&b, "highlight_fg", ov.highlight_fg)
	write_ov(&b, "warn", ov.warn)
	write_ov(&b, "ok", ov.ok)
	write_ov(&b, "error", ov.error)
	write_ov(&b, "title", ov.title)
	write_ov(&b, "status_bg", ov.status_bg)
	write_ov(&b, "status_fg", ov.status_fg)
	write_ov(&b, "input_bg", ov.input_bg)
	write_ov(&b, "tab_active", ov.tab_active)
	write_ov(&b, "tab_idle", ov.tab_idle)
	return strings.to_string(b)
}

config_write_defaults_if_missing :: proc(c: ^Config) {
	if os.exists(c.config_path) {
		return
	}
	_ = config_save(c)
}

Directory :: struct {
	peers:       [dynamic]Peer,
	heard_lxmf:  int,
	heard_nodes: int,
	heard_other: int,
	revision:    u64,
	spill_path:  string,
	spill_count: int,
}

directory_init :: proc(d: ^Directory) {
	d^ = {}
	d.peers = make([dynamic]Peer)
}

directory_destroy :: proc(d: ^Directory) {
	for &p in d.peers {
		delete(p.display_name)
	}
	delete(d.peers)
	delete(d.spill_path)
	d^ = {}
}

directory_count_kind :: proc(d: ^Directory, kind: Peer_Kind) -> int {
	n := 0
	for p in d.peers {
		if p.kind == kind {
			n += 1
		}
	}
	return n
}

directory_upsert :: proc(
	d: ^Directory,
	dest: [HASH_LEN]u8,
	identity: [HASH_LEN]u8,
	kind: Peer_Kind,
	name: string,
	stamp: Maybe(i64),
	hops: u8 = 0,
) {
	now := f64(time.time_to_unix_nano(time.now())) / 1e9
	safe_name := sanitize_display_label(name)
	for &p in d.peers {
		if p.hash == dest {
			ui_changed := false
			if safe_name != "" && safe_name != p.display_name {
				delete(p.display_name)
				p.display_name = safe_name
				safe_name = ""
				ui_changed = true
			}
			if p.identity_hash != identity || p.kind != kind {
				ui_changed = true
			}
			// Hops/stamp/last_heard update without list rebuild thrash.
			p.identity_hash = identity
			p.kind = kind
			p.stamp_cost = stamp
			p.last_heard = now
			p.hops = hops
			if safe_name != "" {
				delete(safe_name)
			}
			if ui_changed {
				d.revision += 1
			}
			return
		}
	}
	peer := Peer{
		hash = dest,
		identity_hash = identity,
		display_name = safe_name,
		stamp_cost = stamp,
		last_heard = now,
		kind = kind,
		hops = hops,
	}
	append(&d.peers, peer)
	d.revision += 1
	switch kind {
	case .Lxmf:
		d.heard_lxmf += 1
	case .Nomad_Node:
		d.heard_nodes += 1
	case .Propagation:
		d.heard_other += 1
	}
	directory_enforce_hot_cap(d)
}

sanitize_display_label :: proc(name: string, allocator := context.allocator) -> string {
	if name == "" {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator = allocator)
	n := 0
	for r in name {
		ch := r
		if ch < 0x20 || ch == 0x7f || (ch >= 0x80 && ch <= 0x9f) {
			ch = ' '
		}
		strings.write_rune(&b, ch)
		n += 1
		if n >= 64 {
			break
		}
	}
	return strings.to_string(b)
}

directory_stamp_cost :: proc(d: ^Directory, dest: [HASH_LEN]u8) -> int {
	for p in d.peers {
		if p.hash == dest {
			if cost, ok := p.stamp_cost.?; ok {
				return int(cost)
			}
		}
	}
	return 0
}

directory_hops :: proc(d: ^Directory, dest: [HASH_LEN]u8) -> u8 {
	for p in d.peers {
		if p.hash == dest {
			return p.hops
		}
	}
	return 0
}

directory_label :: proc(d: ^Directory, hash: [HASH_LEN]u8, allocator := context.allocator) -> string {
	for p in d.peers {
		if p.hash == hash {
			if p.display_name != "" {
				return strings.clone(p.display_name, allocator)
			}
		}
	}
	return hash_hex(hash, allocator)
}

hash_hex :: proc(hash: [HASH_LEN]u8, allocator := context.allocator) -> string {
	h := hash
	encoded, err := hex.encode(h[:], allocator)
	if err != nil {
		return fmt.tprintf("%02x", hash[0])
	}
	return string(encoded)
}

Conversations :: struct {
	items: [dynamic]Conversation,
}

conversations_init :: proc(c: ^Conversations) {
	c.items = make([dynamic]Conversation)
}

conversations_destroy :: proc(c: ^Conversations) {
	for &conv in c.items {
		delete(conv.title)
		for &m in conv.messages {
			delete(m.title)
			delete(m.content)
		}
		delete(conv.messages)
	}
	delete(c.items)
	c^ = {}
}

conversations_index_of :: proc(c: ^Conversations, peer: [HASH_LEN]u8) -> int {
	for conv, i in c.items {
		if conv.peer_hash == peer {
			return i
		}
	}
	return -1
}

conversations_get_or_create :: proc(c: ^Conversations, peer: [HASH_LEN]u8, title: string) -> ^Conversation {
	for &conv in c.items {
		if conv.peer_hash == peer {
			return &conv
		}
	}
	conv := Conversation{
		peer_hash = peer,
		title = strings.clone(title),
		messages = make([dynamic]Stored_Message),
	}
	append(&c.items, conv)
	return &c.items[len(c.items) - 1]
}

conversations_add_message :: proc(c: ^Conversations, peer: [HASH_LEN]u8, msg: Stored_Message, title: string) {
	conv := conversations_get_or_create(c, peer, title)
	append(&conv.messages, msg)
	if msg.direction == .In {
		conv.unread += 1
	}
}

conversations_add_message_persist :: proc(c: ^Conversations, cfg: ^Config, peer: [HASH_LEN]u8, msg: Stored_Message, title: string) {
	conversations_add_message(c, peer, msg, title)
	_ = conversations_save_peer(c, cfg, peer)
}
