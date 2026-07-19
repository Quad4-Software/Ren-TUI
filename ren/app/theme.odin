// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Apply store theme overrides into the UI theme.
*/

package app

import "ren:store"
import "ren:ui"

config_apply_theme :: proc(c: ^store.Config) {
	ov := c.theme_overrides
	ui.apply_theme_hex(c.theme_name, ui.Theme_Hex{
		bg = ov.bg,
		fg = ov.fg,
		muted = ov.muted,
		border = ov.border,
		accent = ov.accent,
		accent_dim = ov.accent_dim,
		highlight_bg = ov.highlight_bg,
		highlight_fg = ov.highlight_fg,
		warn = ov.warn,
		ok = ov.ok,
		error = ov.error,
		title = ov.title,
		status_bg = ov.status_bg,
		status_fg = ov.status_fg,
		input_bg = ov.input_bg,
		tab_active = ov.tab_active,
		tab_idle = ov.tab_idle,
	})
}
