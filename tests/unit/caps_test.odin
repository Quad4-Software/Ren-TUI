// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Unit tests for forced terminal capability modes.
*/

package tests

import "core:testing"

import "ren:ui"

@(test)
test_caps_force_compat :: proc(t: ^testing.T) {
	ui.caps_init("compat")
	testing.expect_value(t, ui.caps_get().name, "compat")
	testing.expect_value(t, ui.caps_get().mode, ui.Color_Mode.Ansi16)
	testing.expect(t, ui.caps_get().ascii)
	tl, _, _, _, h, v := ui.caps_border()
	testing.expect_value(t, tl, '+')
	testing.expect_value(t, h, '-')
	testing.expect_value(t, v, '|')
}

@(test)
test_caps_force_dumb :: proc(t: ^testing.T) {
	ui.caps_init("dumb")
	testing.expect_value(t, ui.caps_get().name, "dumb")
	testing.expect_value(t, ui.caps_get().mode, ui.Color_Mode.None)
	testing.expect(t, !ui.caps_get().alt_screen)
	testing.expect_value(t, ui.sanitize_rune('─'), '-')
	testing.expect_value(t, ui.sanitize_rune('λ'), '?')
}

@(test)
test_caps_force_full :: proc(t: ^testing.T) {
	ui.caps_init("full")
	testing.expect_value(t, ui.caps_get().name, "full")
	testing.expect_value(t, ui.caps_get().mode, ui.Color_Mode.Truecolor)
	testing.expect(t, !ui.caps_get().ascii)
}

@(test)
test_caps_force_256 :: proc(t: ^testing.T) {
	ui.caps_init("256")
	testing.expect_value(t, ui.caps_get().name, "256")
	testing.expect_value(t, ui.caps_get().mode, ui.Color_Mode.Ansi256)
	testing.expect(t, !ui.caps_get().ascii)
	idx := ui.color_to_ansi256(ui.Color{r = 255, g = 0, b = 0})
	testing.expect(t, idx >= 16 && idx <= 231)
}
