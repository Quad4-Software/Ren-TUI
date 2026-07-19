// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Config theme hex overrides without UI package types.
*/

package store

import "core:strings"

Theme_Overrides :: struct {
	bg:           string,
	fg:           string,
	muted:        string,
	border:       string,
	accent:       string,
	accent_dim:   string,
	highlight_bg: string,
	highlight_fg: string,
	warn:         string,
	ok:           string,
	error:        string,
	title:        string,
	status_bg:    string,
	status_fg:    string,
	input_bg:     string,
	tab_active:   string,
	tab_idle:     string,
}

theme_overrides_destroy :: proc(ov: ^Theme_Overrides) {
	delete(ov.bg)
	delete(ov.fg)
	delete(ov.muted)
	delete(ov.border)
	delete(ov.accent)
	delete(ov.accent_dim)
	delete(ov.highlight_bg)
	delete(ov.highlight_fg)
	delete(ov.warn)
	delete(ov.ok)
	delete(ov.error)
	delete(ov.title)
	delete(ov.status_bg)
	delete(ov.status_fg)
	delete(ov.input_bg)
	delete(ov.tab_active)
	delete(ov.tab_idle)
	ov^ = {}
}

theme_overrides_set :: proc(ov: ^Theme_Overrides, key, val: string) {
	set :: proc(dst: ^string, val: string) {
		delete(dst^)
		dst^ = strings.clone(val)
	}
	switch key {
	case "bg":
		set(&ov.bg, val)
	case "fg":
		set(&ov.fg, val)
	case "muted":
		set(&ov.muted, val)
	case "border":
		set(&ov.border, val)
	case "accent":
		set(&ov.accent, val)
	case "accent_dim":
		set(&ov.accent_dim, val)
	case "highlight_bg":
		set(&ov.highlight_bg, val)
	case "highlight_fg":
		set(&ov.highlight_fg, val)
	case "warn":
		set(&ov.warn, val)
	case "ok":
		set(&ov.ok, val)
	case "error":
		set(&ov.error, val)
	case "title":
		set(&ov.title, val)
	case "status_bg":
		set(&ov.status_bg, val)
	case "status_fg":
		set(&ov.status_fg, val)
	case "input_bg":
		set(&ov.input_bg, val)
	case "tab_active":
		set(&ov.tab_active, val)
	case "tab_idle":
		set(&ov.tab_idle, val)
	}
}

theme_overrides_has_any :: proc(ov: Theme_Overrides) -> bool {
	return ov.bg != "" || ov.fg != "" || ov.muted != "" || ov.border != "" ||
		ov.accent != "" || ov.accent_dim != "" || ov.highlight_bg != "" || ov.highlight_fg != "" ||
		ov.warn != "" || ov.ok != "" || ov.error != "" || ov.title != "" ||
		ov.status_bg != "" || ov.status_fg != "" || ov.input_bg != "" ||
		ov.tab_active != "" || ov.tab_idle != ""
}
