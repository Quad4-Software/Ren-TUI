// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Fast gate that core APIs still link and behave.
*/

package tests

import "core:testing"

import "ren:constants"
import "ren:lxmf"
import "ren:store"
import "ren:ui"
import "ren:version"

@(test)
test_smoke_version :: proc(t: ^testing.T) {
	line := version.line()
	defer delete(line)
	testing.expect(t, len(line) > 0)
	testing.expect_value(t, version.VERSION, constants.VERSION)
}

@(test)
test_smoke_buffer_create :: proc(t: ^testing.T) {
	ui.set_theme(ui.FIELD)
	buf := ui.buffer_create(80, 24)
	defer ui.buffer_destroy(&buf)
	testing.expect_value(t, buf.width, 80)
	testing.expect_value(t, buf.height, 24)
	testing.expect_value(t, len(buf.cells), 80 * 24)
}

@(test)
test_smoke_msgpack_nil :: proc(t: ^testing.T) {
	w: lxmf.Writer
	lxmf.writer_init(&w)
	defer lxmf.writer_destroy(&w)
	lxmf.write_nil(&w)
	r: lxmf.Reader
	lxmf.reader_init(&r, lxmf.writer_bytes(&w))
	v, err := lxmf.decode_value(&r)
	testing.expect_value(t, err, lxmf.Msgpack_Error.None)
	testing.expect_value(t, v.kind, lxmf.Value_Kind.Nil)
}

@(test)
test_smoke_config_default :: proc(t: ^testing.T) {
	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	testing.expect(t, len(cfg.display_name) > 0)
	testing.expect(t, len(cfg.theme_name) > 0)
}

@(test)
test_smoke_theme_presets :: proc(t: ^testing.T) {
	for name in ui.theme_names() {
		th := ui.theme_by_name(name)
		testing.expect_value(t, th.name, name)
	}
	ui.set_theme(ui.FIELD)
}
