// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Capability matrix across forced UI modes without a real pty.
*/

package tests

import "core:testing"

import "ren:ui"

Mode_Case :: struct {
	force:      string,
	want_name:  string,
	want_mode:  ui.Color_Mode,
	want_ascii: bool,
}

@(test)
test_cross_terminal_forced_modes :: proc(t: ^testing.T) {
	cases := []Mode_Case{
		{"full", "full", .Truecolor, false},
		{"256", "256", .Ansi256, false},
		{"compat", "compat", .Ansi16, true},
		{"dumb", "dumb", .None, true},
	}
	for c in cases {
		ui.caps_init(c.force)
		testing.expect_value(t, ui.caps.name, c.want_name)
		testing.expect_value(t, ui.caps.mode, c.want_mode)
		testing.expect_value(t, ui.caps.ascii, c.want_ascii)
	}
	ui.caps_init("full")
}

@(test)
test_cross_terminal_border_glyphs :: proc(t: ^testing.T) {
	ui.caps_init("full")
	tl, tr, bl, br, h, v := ui.caps_border()
	testing.expect(t, tl != '+')
	testing.expect(t, h != '-')
	testing.expect(t, v != '|')
	_ = tr
	_ = bl
	_ = br

	ui.caps_init("compat")
	tl, _, _, _, h, v = ui.caps_border()
	testing.expect_value(t, tl, '+')
	testing.expect_value(t, h, '-')
	testing.expect_value(t, v, '|')
	ui.caps_init("full")
}

@(test)
test_cross_terminal_sanitize_under_ascii :: proc(t: ^testing.T) {
	ui.caps_init("dumb")
	testing.expect_value(t, ui.sanitize_rune('─'), '-')
	testing.expect_value(t, ui.sanitize_rune('λ'), '?')
	testing.expect_value(t, ui.sanitize_rune('A'), 'A')

	ui.caps_init("full")
	testing.expect_value(t, ui.sanitize_rune('λ'), 'λ')
}

@(test)
test_cross_terminal_color_mapping_256 :: proc(t: ^testing.T) {
	ui.caps_init("256")
	red := ui.color_to_ansi256(ui.Color{255, 0, 0})
	testing.expect(t, red >= 16 && red <= 231)
	black := ui.color_to_ansi256(ui.Color{0, 0, 0})
	testing.expect(t, black >= 0)
	ui.caps_init("full")
}

@(test)
test_cross_terminal_theme_paint_each_mode :: proc(t: ^testing.T) {
	modes := []string{"full", "256", "compat", "dumb"}
	for mode in modes {
		ui.caps_init(mode)
		ui.set_theme(ui.SLATE)
		buf := ui.buffer_create(40, 10)
		ui.buffer_text(&buf, 1, 1, "hi", ui.theme().fg, ui.theme().bg)
		cell := ui.buffer_at(&buf, 1, 1)
		testing.expect(t, cell != nil)
		testing.expect_value(t, cell.ch, 'h')
		ui.buffer_destroy(&buf)
	}
	ui.set_theme(ui.FIELD)
	ui.caps_init("full")
}
