// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

package tests

import "core:strings"
import "core:testing"

import "ren:app"
import "ren:net"
import "ren:store"

@(test)
test_page_poll_result_success_parses_and_renders :: proc(t: ^testing.T) {
	a: app.App
	a.online = true
	a.session.started = true
	a.cfg.data_dir = strings.clone("/tmp/ren-tui-test-cache", context.temp_allocator)

	page := `>Test Page

Hello from the test page.
`
	a.session.page.active = true
	a.session.page.done = true
	a.session.page.ok = true
	a.session.page.is_file = false
	a.session.page.phase = .Idle
	a.session.page.node[0] = 0xab
	a.session.page.path = strings.clone("/page/index.mu")
	a.session.page.status = strings.clone("")

	data := make([]u8, len(page))
	copy(data, page)
	a.session.page.content = data

	app.page_poll_result(&a)

	testing.expect(t, a.page_source != "")
	testing.expect(t, a.tab == .Page)
	testing.expect(t, len(a.page_doc.lines) > 0)

	app.page_clear(&a)
	net.session_page_cancel(&a.session)
}
