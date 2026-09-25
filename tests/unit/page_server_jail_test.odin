// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Page server path jail. Requests must stay inside the served directory.
*/

package tests

import "core:strings"
import "core:testing"

import "ren:net"

@(test)
test_page_server_map_rejects_escape :: proc(t: ^testing.T) {
	disk, ok := net.page_server_map("/tmp/ren-pages", "/page/", "/page/index.mu")
	testing.expect(t, ok)
	testing.expect(t, strings.contains(disk, "index.mu"))

	_, bad := net.page_server_map("/tmp/ren-pages", "/page/", "/page/../secret")
	testing.expect(t, !bad)

	_, nested := net.page_server_map("/tmp/ren-pages", "/page/", "/page/a/b")
	testing.expect(t, !nested)
}
