// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Unit tests for themes clipboard and version helpers.
*/

package tests

import "core:strings"
import "core:testing"

import "ren:constants"
import "ren:store"
import "ren:ui"
import "ren:version"

@(test)
test_theme_hex_and_presets :: proc(t: ^testing.T) {
	c, ok := ui.parse_hex_color("#c4783a")
	testing.expect(t, ok)
	testing.expect_value(t, c.r, u8(0xc4))
	testing.expect_value(t, c.g, u8(0x78))
	testing.expect_value(t, c.b, u8(0x3a))

	slate := ui.theme_by_name("slate")
	testing.expect_value(t, slate.name, "slate")
	ui.apply_theme_hex("amber", ui.Theme_Hex{accent = "#112233"})
	th := ui.theme()
	testing.expect_value(t, th.name, "amber")
	testing.expect_value(t, th.accent.r, u8(0x11))
	ui.set_theme(ui.FIELD)
}

@(test)
test_clipboard_osc52_empty_rejected :: proc(t: ^testing.T) {
	testing.expect(t, !ui.clipboard_copy(""))
}

@(test)
test_version_line_format :: proc(t: ^testing.T) {
	line := version.line()
	defer delete(line)
	testing.expect(t, strings.contains(line, "ren-tui"))
	testing.expect(t, strings.contains(line, version.VERSION))
	testing.expect(t, strings.contains(line, version.BUILD_DATE))
}

@(test)
test_hash_hex_length :: proc(t: ^testing.T) {
	h: [store.HASH_LEN]u8
	h[0] = 0xff
	hex := store.hash_hex(h)
	defer delete(hex)
	testing.expect_value(t, len(hex), store.HASH_LEN * 2)
}

@(test)
test_default_display_name_anonymous :: proc(t: ^testing.T) {
	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	testing.expect_value(t, cfg.display_name, constants.DEFAULT_DISPLAY_NAME)
	testing.expect_value(t, cfg.theme_name, constants.DEFAULT_THEME)
	testing.expect(t, cfg.auto_announce == constants.DEFAULT_AUTO_ANNOUNCE)
	testing.expect(t, cfg.announce_interval_sec >= constants.MIN_ANNOUNCE_INTERVAL_SEC)
}

@(test)
test_config_parse_bool :: proc(t: ^testing.T) {
	testing.expect(t, store.parse_bool("yes", false))
	testing.expect(t, !store.parse_bool("no", true))
	testing.expect(t, store.parse_bool("maybe", true))
}

@(test)
test_version_baked :: proc(t: ^testing.T) {
	testing.expect_value(t, version.VERSION, constants.VERSION)
}
