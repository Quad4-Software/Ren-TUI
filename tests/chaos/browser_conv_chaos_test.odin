// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Chaos and edge cases for page browse, conversations, and send/receive.
*/

package tests

import "core:math/rand"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "ren:app"
import "ren:lxmf"
import "ren:micron"
import "ren:net"
import "ren:store"
import "ren:ui"

import rns "rns:rns"

BROWSER_CHAOS_ITERS :: 60

Chaos_Fake_Send :: struct {
	opened:     int,
	sent:       int,
	closed:     int,
	packets:    int,
	fail_open:  bool,
	packet_ok:  bool,
	encrypt_ok: bool,
}

chaos_path_ensure :: proc(user: rawptr, dest: [store.HASH_LEN]u8) -> bool {
	_ = user
	_ = dest
	return true
}

chaos_link_open :: proc(user: rawptr, dest: []u8) -> (link: rns.Link, link_id: [store.HASH_LEN]u8, ok: bool) {
	_ = dest
	f := cast(^Chaos_Fake_Send)user
	f.opened += 1
	if f.fail_open {
		return 0, {}, false
	}
	return 1, {}, true
}

chaos_link_close :: proc(user: rawptr, link: rns.Link) {
	_ = link
	f := cast(^Chaos_Fake_Send)user
	f.closed += 1
}

chaos_link_send :: proc(user: rawptr, link: rns.Link, data: []u8) -> bool {
	_ = link
	_ = data
	f := cast(^Chaos_Fake_Send)user
	f.sent += 1
	return true
}

chaos_packet_send :: proc(user: rawptr, dest: []u8, data: []u8) -> bool {
	_ = dest
	_ = data
	f := cast(^Chaos_Fake_Send)user
	f.packets += 1
	return f.packet_ok
}

chaos_encrypt :: proc(user: rawptr, dest: []u8, plaintext: []u8) -> ([]u8, bool) {
	_ = dest
	f := cast(^Chaos_Fake_Send)user
	if !f.encrypt_ok {
		return nil, false
	}
	out := make([]u8, len(plaintext))
	copy(out, plaintext)
	return out, true
}

chaos_setup_send :: proc(s: ^net.Session, fake: ^Chaos_Fake_Send) -> bool {
	mat, ok := lxmf.identity_generate()
	if !ok {
		return false
	}
	s.material = mat
	lxmf.router_init(&s.router, mat, "chaos")
	s.started = true
	fake.packet_ok = true
	fake.encrypt_ok = true
	s.send_transport = net.Send_Transport{
		user = fake,
		path_ensure = chaos_path_ensure,
		link_open = chaos_link_open,
		link_close = chaos_link_close,
		link_send = chaos_link_send,
		packet_send = chaos_packet_send,
		encrypt = chaos_encrypt,
		auto_link = true,
	}
	return true
}

@(test)
test_chaos_page_parse_and_sanitize :: proc(t: ^testing.T) {
	rand.reset(0xB1005E)
	for _ in 0 ..< BROWSER_CHAOS_ITERS {
		n := int(rand.uint32() % 96)
		buf := make([]u8, n)
		for i in 0 ..< n {
			buf[i] = u8(rand.uint32() % 256)
		}
		s := app.page_sanitize_bytes(buf)
		delete(buf)
		testing.expect(t, !strings.contains(s, "\x00"))
		doc := micron.parse(s)
		_ = micron.doc_link_count(doc)
		rows := micron.layout_doc(doc, int(8 + rand.uint32() % 40))
		micron.layout_rows_destroy(&rows)
		micron.doc_destroy(&doc)
		delete(s)

		hex_buf: [64]u8
		for i in 0 ..< 32 {
			v := u8(rand.uint32() % 16)
			hex_buf[i] = '0' + v if v < 10 else 'a' + (v - 10)
		}
		url := strings.concatenate({string(hex_buf[:32]), ":/page/x.mu"})
		_, has, path, ok := app.page_parse_url(url)
		delete(url)
		name_src := "/page/index.mu"
		if ok {
			testing.expect(t, has)
			testing.expect(t, app.page_path_allowed(path))
			name_src = path
		}
		_ = app.page_path_allowed("/page/../x")
		bn := app.page_download_basename(name_src)
		delete(bn)
		if ok {
			delete(path)
		}
	}
}

@(test)
test_chaos_page_fetch_cancel_switch :: proc(t: ^testing.T) {
	rand.reset(0xCAFE01)
	a: app.App
	a.online = true
	a.session.started = true
	for _ in 0 ..< 40 {
		if rand.uint32() % 2 == 0 {
			a.session.page.active = true
			a.session.page.done = false
			delete(a.session.page.path)
			a.session.page.path = strings.clone("/page/old.mu")
			delete(a.session.page.status)
			a.session.page.status = strings.clone("waiting for link")
			a.session.page.node[0] = u8(rand.uint32())
			a.session.page.phase = .Waiting_Link
		}
		node: [store.HASH_LEN]u8
		node[0] = u8(rand.uint32())
		app.page_fetch(&a, node, "/page/index.mu")
		if net.session_page_busy(&a.session) {
			testing.expect_value(t, a.session.page.node[0], node[0])
			net.session_page_cancel(&a.session)
		}
	}
	net.session_page_cancel(&a.session)
	delete(a.session.status)
	net.session_event_ring_clear(&a.session.events)
}

@(test)
test_chaos_conversations_persist_edge :: proc(t: ^testing.T) {
	rand.reset(0xC0FFEE)
	base, _ := filepath.join({"/tmp", "ren-tui-chaos-conv"})
	_ = os.remove_all(base)
	defer os.remove_all(base)
	_ = os.make_directory_all(base)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	delete(cfg.data_dir)
	cfg.data_dir = strings.clone(base)
	_ = store.config_ensure_dirs(&cfg)

	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)

	for i in 0 ..< 12 {
		peer: [store.HASH_LEN]u8
		peer[0] = u8(i + 1)
		peer[1] = u8(rand.uint32())
		conv := store.conversations_get_or_create(&convs, peer, "peer")
		n := int(rand.uint32() % 5)
		for j in 0 ..< n {
			body_n := int(rand.uint32() % 48)
			body := make([]u8, body_n)
			for k in 0 ..< body_n {
				body[k] = u8(32 + rand.uint32() % 95)
			}
			append(&conv.messages, store.Stored_Message{
				direction = .In if j % 2 == 0 else .Out,
				title = strings.clone(""),
				content = strings.clone(string(body)),
				timestamp = f64(i * 10 + j),
				method = .Direct,
				verified = j % 3 != 0,
			})
			delete(body)
		}
		testing.expect(t, store.conversations_save_peer(&convs, &cfg, peer))
	}

	loaded: store.Conversations
	store.conversations_init(&loaded)
	defer store.conversations_destroy(&loaded)
	store.conversations_load(&loaded, &cfg)
	testing.expect(t, len(loaded.items) >= 1)
}

@(test)
test_chaos_send_receive_events_and_cancel :: proc(t: ^testing.T) {
	rand.reset(0x5EAD)
	fake: Chaos_Fake_Send
	a: app.App
	ui.list_init(&a.conv_list)
	defer ui.list_destroy(&a.conv_list)
	store.conversations_init(&a.conversations)
	defer store.conversations_destroy(&a.conversations)
	store.directory_init(&a.directory)
	defer store.directory_destroy(&a.directory)
	testing.expect(t, chaos_setup_send(&a.session, &fake))
	defer lxmf.router_destroy(&a.session.router)
	defer net.session_event_ring_clear(&a.session.events)
	defer net.session_send_cancel(&a.session)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	pn: [store.HASH_LEN]u8
	pn[0] = 0x5e
	store.config_set_propagation_node(&cfg, pn)
	cfg.try_propagation_on_fail = true

	for _ in 0 ..< 30 {
		op := rand.uint32() % 5
		switch op {
		case 0:
			net.session_event_push(&a.session, .Message_Received, "in")
			app.handle_session_events(&a)
		case 1:
			net.session_event_push(&a.session, .Send_Ok, "ok")
			app.handle_session_events(&a)
		case 2:
			net.session_event_push(&a.session, .Send_Failed, "fail")
			app.handle_session_events(&a)
		case 3:
			dest: [store.HASH_LEN]u8
			dest[0] = u8(1 + rand.uint32() % 200)
			if net.session_send_busy(&a.session) {
				net.session_send_cancel(&a.session)
			}
			methods := []lxmf.Method{.Direct, .Opportunistic, .Propagated}
			method := methods[rand.uint32() % u32(len(methods))]
			_ = net.session_send_begin(&a.session, dest, "", "chaos", &a.conversations, &a.directory, &cfg, method)
			for _ in 0 ..< 3 {
				if !net.session_send_busy(&a.session) {
					break
				}
				net.session_send_tick(&a.session)
			}
			if rand.uint32() % 2 == 0 {
				net.session_send_cancel(&a.session)
			}
		case 4:
			_ = net.session_sync_begin(&a.session, &cfg)
		}
	}
	net.session_send_cancel(&a.session)
	testing.expect(t, a.recv_count >= 0)
	delete(a.session.status)
}

@(test)
test_edge_send_rejected_while_page_busy :: proc(t: ^testing.T) {
	fake: Chaos_Fake_Send
	s: net.Session
	testing.expect(t, chaos_setup_send(&s, &fake))
	defer lxmf.router_destroy(&s.router)
	defer net.session_event_ring_clear(&s.events)

	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)
	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)

	s.page.active = true
	s.page.done = false
	s.page.path = strings.clone("/page/x.mu")
	defer net.session_page_cancel(&s)

	dest: [store.HASH_LEN]u8
	dest[0] = 9
	ok := net.session_send_begin(&s, dest, "", "blocked", &convs, &dir, nil)
	testing.expect(t, !ok)
}

@(test)
test_edge_sync_rejected_while_send_busy :: proc(t: ^testing.T) {
	fake: Chaos_Fake_Send
	s: net.Session
	testing.expect(t, chaos_setup_send(&s, &fake))
	defer lxmf.router_destroy(&s.router)
	defer net.session_event_ring_clear(&s.events)
	defer delete(s.status)

	convs: store.Conversations
	store.conversations_init(&convs)
	defer store.conversations_destroy(&convs)
	dir: store.Directory
	store.directory_init(&dir)
	defer store.directory_destroy(&dir)

	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	pn: [store.HASH_LEN]u8
	pn[0] = 1
	store.config_set_propagation_node(&cfg, pn)

	dest: [store.HASH_LEN]u8
	dest[0] = 2
	testing.expect(t, net.session_send_begin(&s, dest, "", "hold", &convs, &dir, nil, .Direct))
	ok := net.session_sync_begin(&s, &cfg)
	testing.expect(t, !ok)
	net.session_send_cancel(&s)
}

@(test)
test_edge_empty_page_download_status :: proc(t: ^testing.T) {
	a: app.App
	a.page_source = ""
	app.page_download(&a)
	testing.expect(t, a.status_hold_len > 0)
}

@(test)
test_edge_micron_huge_line_and_link_flood :: proc(t: ^testing.T) {
	parts := make([dynamic]string, 0, 40)
	defer {
		for p in parts {
			delete(p)
		}
		delete(parts)
	}
	long := strings.repeat("A", 800)
	defer delete(long)
	append(&parts, strings.clone(long))
	for i in 0 ..< 30 {
		append(&parts, strings.clone("`[x`/page/x.mu]"))
		_ = i
	}
	src := strings.join(parts[:], "\n")
	defer delete(src)
	doc := micron.parse(src)
	defer micron.doc_destroy(&doc)
	rows := micron.layout_doc(doc, 20)
	defer micron.layout_rows_destroy(&rows)
	testing.expect(t, len(rows) >= 1)
}
