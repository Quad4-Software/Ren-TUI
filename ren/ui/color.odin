// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Themes RGB colors and optional hex overrides.
*/

package ui

import "core:fmt"
import "core:strconv"
import "core:strings"

Color :: struct {
	r, g, b: u8,
}

Theme :: struct {
	name:         string,
	bg:           Color,
	fg:           Color,
	muted:        Color,
	border:       Color,
	accent:       Color,
	accent_dim:   Color,
	highlight_bg: Color,
	highlight_fg: Color,
	warn:         Color,
	ok:           Color,
	error:        Color,
	title:        Color,
	status_bg:    Color,
	status_fg:    Color,
	input_bg:     Color,
	tab_active:   Color,
	tab_idle:     Color,
}

// Optional hex overrides from config [theme]. Empty string means unset.
Theme_Hex :: struct {
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

FIELD :: Theme{
	name         = "field",
	bg           = {12, 18, 24},
	fg           = {216, 208, 192},
	muted        = {120, 118, 110},
	border       = {70, 82, 92},
	accent       = {196, 120, 58},
	accent_dim   = {140, 90, 48},
	highlight_bg = {36, 48, 56},
	highlight_fg = {232, 224, 208},
	warn         = {196, 150, 60},
	ok           = {120, 150, 110},
	error        = {180, 80, 70},
	title        = {210, 170, 120},
	status_bg    = {22, 30, 38},
	status_fg    = {180, 176, 164},
	input_bg     = {20, 28, 34},
	tab_active   = {196, 120, 58},
	tab_idle     = {100, 110, 118},
}

SLATE :: Theme{
	name         = "slate",
	bg           = {16, 20, 26},
	fg           = {200, 210, 220},
	muted        = {110, 120, 130},
	border       = {60, 72, 88},
	accent       = {90, 150, 190},
	accent_dim   = {60, 110, 140},
	highlight_bg = {32, 42, 54},
	highlight_fg = {220, 230, 240},
	warn         = {190, 160, 70},
	ok           = {100, 160, 130},
	error        = {190, 90, 90},
	title        = {150, 190, 220},
	status_bg    = {22, 28, 36},
	status_fg    = {160, 170, 180},
	input_bg     = {20, 26, 34},
	tab_active   = {90, 150, 190},
	tab_idle     = {90, 100, 112},
}

AMBER :: Theme{
	name         = "amber",
	bg           = {18, 14, 10},
	fg           = {230, 210, 170},
	muted        = {140, 120, 90},
	border       = {90, 70, 40},
	accent       = {220, 150, 40},
	accent_dim   = {160, 110, 30},
	highlight_bg = {40, 30, 18},
	highlight_fg = {245, 230, 190},
	warn         = {220, 170, 50},
	ok           = {140, 160, 90},
	error        = {200, 80, 60},
	title        = {240, 190, 100},
	status_bg    = {28, 22, 14},
	status_fg    = {190, 170, 130},
	input_bg     = {26, 20, 12},
	tab_active   = {220, 150, 40},
	tab_idle     = {120, 100, 70},
}

MONO :: Theme{
	name         = "mono",
	bg           = {0, 0, 0},
	fg           = {220, 220, 220},
	muted        = {140, 140, 140},
	border       = {100, 100, 100},
	accent       = {255, 255, 255},
	accent_dim   = {180, 180, 180},
	highlight_bg = {40, 40, 40},
	highlight_fg = {255, 255, 255},
	warn         = {200, 200, 200},
	ok           = {180, 180, 180},
	error        = {160, 160, 160},
	title        = {255, 255, 255},
	status_bg    = {20, 20, 20},
	status_fg    = {200, 200, 200},
	input_bg     = {16, 16, 16},
	tab_active   = {255, 255, 255},
	tab_idle     = {120, 120, 120},
}

THEME_PRESETS := [?]Theme{FIELD, SLATE, AMBER, MONO}
THEME_NAMES := [?]string{"field", "slate", "amber", "mono"}

_active: ^Loop
_standalone_theme := FIELD

loop_activate :: proc(l: ^Loop) {
	_active = l
}

loop_deactivate :: proc(l: ^Loop) {
	if _active == l {
		_active = nil
	}
}

theme_presets :: proc() -> []Theme {
	return THEME_PRESETS[:]
}

theme_names :: proc() -> []string {
	return THEME_NAMES[:]
}

theme_by_name :: proc(name: string) -> Theme {
	n := strings.to_lower(strings.trim_space(name), context.temp_allocator)
	for t in theme_presets() {
		if t.name == n {
			return t
		}
	}
	return FIELD
}

set_theme :: proc(t: Theme) {
	if _active != nil {
		_active.theme = t
		return
	}
	_standalone_theme = t
}

theme :: proc() -> Theme {
	if _active != nil {
		return _active.theme
	}
	return _standalone_theme
}

parse_hex_color :: proc(s: string) -> (Color, bool) {
	v := strings.trim_space(s)
	if v == "" {
		return {}, false
	}
	if strings.has_prefix(v, "#") {
		v = v[1:]
	}
	if len(v) != 6 {
		return {}, false
	}
	r, rok := strconv.parse_u64_of_base(v[0:2], 16)
	g, gok := strconv.parse_u64_of_base(v[2:4], 16)
	b, bok := strconv.parse_u64_of_base(v[4:6], 16)
	if !rok || !gok || !bok {
		return {}, false
	}
	return Color{u8(r), u8(g), u8(b)}, true
}

format_hex_color :: proc(c: Color, allocator := context.allocator) -> string {
	return fmt.aprintf("#%02x%02x%02x", c.r, c.g, c.b, allocator = allocator)
}

apply_theme_hex :: proc(base_name: string, ov: Theme_Hex) {
	t := theme_by_name(base_name)
	if c, ok := parse_hex_color(ov.bg); ok do t.bg = c
	if c, ok := parse_hex_color(ov.fg); ok do t.fg = c
	if c, ok := parse_hex_color(ov.muted); ok do t.muted = c
	if c, ok := parse_hex_color(ov.border); ok do t.border = c
	if c, ok := parse_hex_color(ov.accent); ok do t.accent = c
	if c, ok := parse_hex_color(ov.accent_dim); ok do t.accent_dim = c
	if c, ok := parse_hex_color(ov.highlight_bg); ok do t.highlight_bg = c
	if c, ok := parse_hex_color(ov.highlight_fg); ok do t.highlight_fg = c
	if c, ok := parse_hex_color(ov.warn); ok do t.warn = c
	if c, ok := parse_hex_color(ov.ok); ok do t.ok = c
	if c, ok := parse_hex_color(ov.error); ok do t.error = c
	if c, ok := parse_hex_color(ov.title); ok do t.title = c
	if c, ok := parse_hex_color(ov.status_bg); ok do t.status_bg = c
	if c, ok := parse_hex_color(ov.status_fg); ok do t.status_fg = c
	if c, ok := parse_hex_color(ov.input_bg); ok do t.input_bg = c
	if c, ok := parse_hex_color(ov.tab_active); ok do t.tab_active = c
	if c, ok := parse_hex_color(ov.tab_idle); ok do t.tab_idle = c
	set_theme(t)
}

theme_hex_destroy :: proc(ov: ^Theme_Hex) {
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

theme_hex_set :: proc(ov: ^Theme_Hex, key, val: string) {
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

theme_hex_has_any :: proc(ov: Theme_Hex) -> bool {
	return ov.bg != "" || ov.fg != "" || ov.muted != "" || ov.border != "" ||
		ov.accent != "" || ov.accent_dim != "" || ov.highlight_bg != "" || ov.highlight_fg != "" ||
		ov.warn != "" || ov.ok != "" || ov.error != "" || ov.title != "" ||
		ov.status_bg != "" || ov.status_fg != "" || ov.input_bg != "" ||
		ov.tab_active != "" || ov.tab_idle != ""
}
