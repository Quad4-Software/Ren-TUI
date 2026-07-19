// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Compose method line and Network Propagation panel rendering.
*/

package tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "ren:app"
import "ren:lxmf"
import "ren:store"
import "ren:ui"

buffer_collect_text :: proc(buf: ^ui.Buffer, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator = allocator)
	for y in 0 ..< buf.height {
		for x in 0 ..< buf.width {
			cell := ui.buffer_at(buf, x, y)
			if cell == nil || cell.ch == 0 || cell.ch == ui.CELL_WIDE_CONT {
				continue
			}
			if cell.ch == ' ' {
				strings.write_byte(&b, ' ')
				continue
			}
			strings.write_rune(&b, cell.ch)
		}
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

@(test)
test_compose_method_draw_and_cycle :: proc(t: ^testing.T) {
	ui.set_theme(ui.FIELD)
	ui.caps_init("256")
	a: app.App
	ui.input_init(&a.compose_to)
	defer ui.input_destroy(&a.compose_to)
	ui.input_init(&a.compose_body)
	defer ui.input_destroy(&a.compose_body)
	a.compose_method = .Direct
	a.compose_focus = 1

	buf := ui.buffer_create(48, 14)
	defer ui.buffer_destroy(&buf)
	app.draw_compose(&a, &buf, ui.Rect{0, 0, 48, 14})
	text := buffer_collect_text(&buf)
	testing.expect(t, strings.contains(text, "method: Direct"))

	a.compose_method = lxmf.cycle_send_method(a.compose_method)
	ui.buffer_fill_rect(&buf, 0, 0, buf.width, buf.height, ' ', ui.theme().fg, ui.theme().bg)
	app.draw_compose(&a, &buf, ui.Rect{0, 0, 48, 14})
	text = buffer_collect_text(&buf)
	testing.expect(t, strings.contains(text, "method: Opportunistic"))

	a.compose_method = lxmf.cycle_send_method(a.compose_method)
	ui.buffer_fill_rect(&buf, 0, 0, buf.width, buf.height, ' ', ui.theme().fg, ui.theme().bg)
	app.draw_compose(&a, &buf, ui.Rect{0, 0, 48, 14})
	text = buffer_collect_text(&buf)
	testing.expect(t, strings.contains(text, "method: Propagate"))
}

@(test)
test_network_propagation_panel_shows_prop_and_sync :: proc(t: ^testing.T) {
	ui.set_theme(ui.FIELD)
	ui.caps_init("256")
	a: app.App
	a.cfg = store.config_default()
	defer store.config_destroy_strings(&a.cfg)
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)
	ui.list_init(&a.net_list)
	defer ui.list_destroy(&a.net_list)
	ui.input_init(&a.net_search)
	defer ui.input_destroy(&a.net_search)
	a.net_view = .Propagation
	a.term_w = 80
	a.term_h = 24

	pn: [store.HASH_LEN]u8
	pn[0] = 0xab
	pn[15] = 0xcd
	store.config_set_propagation_node(&a.cfg, pn)
	a.session.sync.state = .Request_Sent
	a.session.sync.status = strings.clone("Request sent")
	defer delete(a.session.sync.status)

	buf := ui.buffer_create(80, 24)
	defer ui.buffer_destroy(&buf)
	app.draw_network(&a, &buf, ui.Rect{0, 0, 80, 24})
	text := buffer_collect_text(&buf)
	testing.expect(t, strings.contains(text, "Prop node:"))
	testing.expect(t, strings.contains(text, "Sync:"))
}

@(test)
test_config_activate_send_method_updates_compose :: proc(t: ^testing.T) {
	a: app.App
	a.cfg = store.config_default()
	defer store.config_destroy_strings(&a.cfg)
	a.compose_method = .Direct
	a.cfg.send_method = .Direct
	ui.list_init(&a.config_list)
	defer ui.list_destroy(&a.config_list)
	for _ in 0 ..< int(app.Config_Row.Count) {
		ui.list_push(&a.config_list, "row")
	}
	a.config_list.selected = int(app.Config_Row.Send_Method)
	app.config_activate(&a)
	testing.expect_value(t, a.cfg.send_method, lxmf.Method.Opportunistic)
	testing.expect_value(t, a.compose_method, lxmf.Method.Opportunistic)
	delete(a.net_peer_idx)
}

@(test)
test_set_selected_propagation_node :: proc(t: ^testing.T) {
	a: app.App
	a.cfg = store.config_default()
	defer store.config_destroy_strings(&a.cfg)
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)
	ui.list_init(&a.net_list)
	defer ui.list_destroy(&a.net_list)
	a.net_view = .Propagation

	h: [store.HASH_LEN]u8
	h[0] = 0x44
	h[15] = 0x55
	store.directory_upsert(&a.directory, h, {}, .Propagation, "propagation", nil, 2)
	append(&a.net_peer_idx, 0)
	a.net_list.selected = 0

	base, _ := filepath.join({"/tmp", "ren-tui-unit-set-pn"})
	_ = os.remove_all(base)
	defer os.remove_all(base)
	_ = os.make_directory_all(base)
	delete(a.cfg.data_dir)
	delete(a.cfg.config_path)
	a.cfg.data_dir = strings.clone(base)
	a.cfg.config_path, _ = filepath.join({base, "config"})

	app.set_selected_propagation_node(&a)
	testing.expect(t, a.cfg.has_propagation_node)
	testing.expect(t, a.cfg.propagation_node == h)
	delete(a.net_peer_idx)
	ui.list_clear(&a.net_list)
	ui.list_clear(&a.config_list)
}
