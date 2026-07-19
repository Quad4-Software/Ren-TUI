// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Shared CLI flags for ren-tui and ren-listen.
*/

package cli

import "core:fmt"
import "core:strconv"
import "core:strings"

import "ren:constants"
import "ren:store"
import "ren:version"

Options :: struct {
	help:                bool,
	version:             bool,
	paths:               bool,
	reset_config:        bool,
	reset_conversations: bool,
	reset_identity:      bool,
	config_path:         string,
	data_dir:            string,
	rns_config:          string,
	timeout_sec:         int,
	listen_mode:         bool,
}

options_destroy :: proc(o: ^Options) {
	delete(o.config_path)
	delete(o.data_dir)
	delete(o.rns_config)
	o^ = {}
}

print_version :: proc() {
	fmt.printf("%s\n", version.line())
}

print_help_tui :: proc() {
	fmt.printf(
		`%s %s - terminal LXMF / NomadNet client

Usage:
  ren-tui [options]

Options:
  -h, --help                 show this help
  -v, -V, --version          show version
      --paths                print resolved config paths and exit
      --config PATH          app config file (default ~/.config/ren-tui/config)
      --data-dir PATH        data directory (default ~/.config/ren-tui)
  -c, --rns-config PATH      Reticulum config file
      --reset-config         rewrite app config with defaults
      --reset-conversations  delete stored conversations
      --reset-identity       delete local identity (regenerated on next start)
      --reset                reset config and conversations (not identity)

Environment:
  %s            override Reticulum config path
  %s                   force UI color mode (full/256/compat/dumb)
  NO_COLOR                 disable color
  HOME                     used to resolve ~/.config/ren-tui

Files:
  ~/.config/ren-tui/config
  ~/.config/ren-tui/identity
  ~/.config/ren-tui/conversations/
  ~/.config/ren-tui/librns.log

`,
		constants.APP_NAME,
		constants.VERSION,
		constants.ENV_RNS_CONFIG,
		constants.ENV_UI,
	)
}

print_help_listen :: proc() {
	fmt.printf(
		`ren-listen %s - listen for LXMF / NomadNet announces

Usage:
  ren-listen [options]

Options:
  -h, --help              show this help
  -v, -V, --version       show version
      --paths             print resolved config paths and exit
  -t, --timeout SECONDS   listen duration (default %d)
  -c, --rns-config PATH   Reticulum config file
      --config PATH       app config file
      --data-dir PATH     data directory

Environment:
  %s           override Reticulum config path

`,
		constants.VERSION,
		constants.LISTEN_DEFAULT_SEC,
		constants.ENV_RNS_CONFIG,
	)
}

print_paths :: proc(cfg: ^store.Config) {
	fmt.printf("app           %s\n", constants.APP_NAME)
	fmt.printf("version       %s\n", version.line(context.temp_allocator))
	fmt.printf("home          %s\n", cfg.home)
	fmt.printf("data_dir      %s\n", cfg.data_dir)
	fmt.printf("config        %s\n", cfg.config_path)
	fmt.printf("identity      %s\n", cfg.identity_path)
	fmt.printf("conversations %s\n", store.conversations_dir(cfg, context.temp_allocator))
	fmt.printf("rns_config    %s\n", cfg.rns_config)
	fmt.printf("librns_log    %s/%s\n", cfg.data_dir, constants.LIBRNS_LOG_FILE)
}

parse_args :: proc(args: []string, listen_mode: bool) -> (opts: Options, err: string) {
	opts.listen_mode = listen_mode
	opts.timeout_sec = constants.LISTEN_DEFAULT_SEC
	for i := 0; i < len(args); i += 1 {
		a := args[i]
		switch a {
		case "-h", "--help":
			opts.help = true
		case "-v", "-V", "--version":
			opts.version = true
		case "--paths":
			opts.paths = true
		case "--reset-config":
			opts.reset_config = true
		case "--reset-conversations":
			opts.reset_conversations = true
		case "--reset-identity":
			opts.reset_identity = true
		case "--reset":
			opts.reset_config = true
			opts.reset_conversations = true
		case "--config":
			if i + 1 >= len(args) {
				return opts, "--config needs a path"
			}
			i += 1
			opts.config_path = strings.clone(args[i])
		case "--data-dir":
			if i + 1 >= len(args) {
				return opts, "--data-dir needs a path"
			}
			i += 1
			opts.data_dir = strings.clone(args[i])
		case "-c", "--rns-config":
			if i + 1 >= len(args) {
				return opts, "-c/--rns-config needs a path"
			}
			i += 1
			opts.rns_config = strings.clone(args[i])
		case "-t", "--timeout":
			if !listen_mode {
				return opts, fmt.tprintf("unknown option %s", a)
			}
			if i + 1 >= len(args) {
				return opts, "-t/--timeout needs seconds"
			}
			i += 1
			n, ok := strconv.parse_int(args[i])
			if !ok || n <= 0 {
				return opts, "bad -t/--timeout value"
			}
			opts.timeout_sec = n
		case:
			return opts, fmt.tprintf("unknown option %s", a)
		}
	}
	return opts, ""
}

apply_to_config :: proc(cfg: ^store.Config, opts: ^Options) {
	store.config_apply_cli_overrides(cfg, opts.data_dir, opts.config_path, opts.rns_config)
}

run_utility_actions :: proc(cfg: ^store.Config, opts: ^Options) -> (handled: bool, code: int) {
	if opts.help {
		if opts.listen_mode {
			print_help_listen()
		} else {
			print_help_tui()
		}
		return true, 0
	}
	if opts.version {
		print_version()
		return true, 0
	}
	if opts.paths {
		print_paths(cfg)
		return true, 0
	}

	did_reset := false
	if opts.reset_conversations {
		if !store.config_reset_conversations(cfg) {
			fmt.eprintln("failed to reset conversations")
			return true, 1
		}
		fmt.println("conversations reset")
		did_reset = true
	}
	if opts.reset_identity {
		if !store.config_reset_identity(cfg) {
			fmt.eprintln("failed to reset identity")
			return true, 1
		}
		fmt.println("identity reset")
		did_reset = true
	}
	if opts.reset_config {
		fresh := store.config_default()
		store.config_apply_cli_overrides(&fresh, opts.data_dir, opts.config_path, opts.rns_config)
		defer store.config_destroy_strings(&fresh)
		if !store.config_ensure_dirs(&fresh) {
			fmt.eprintln("failed to create data dir")
			return true, 1
		}
		if !store.config_save(&fresh) {
			fmt.eprintln("failed to reset config")
			return true, 1
		}
		fmt.printf("config rewritten %s\n", fresh.config_path)
		did_reset = true
	}
	if did_reset {
		return true, 0
	}
	return false, 0
}
