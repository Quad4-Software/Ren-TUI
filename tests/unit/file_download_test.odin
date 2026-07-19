// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
NomadNet /file/ path allowlist resolve basename and progress helpers.
*/

package tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "ren:app"
import "ren:constants"
import "ren:micron"
import "ren:net"
import "ren:store"

@(test)
test_file_path_allowed :: proc(t: ^testing.T) {
	testing.expect(t, app.file_path_allowed("/file/readme.txt"))
	testing.expect(t, app.file_path_allowed("/file/a.bin"))
	testing.expect(t, !app.file_path_allowed("/page/index.mu"))
	testing.expect(t, !app.file_path_allowed("/file/../evil"))
	testing.expect(t, !app.file_path_allowed("/file/x;rm"))
	testing.expect(t, !app.file_path_allowed("file/no-slash"))
}

@(test)
test_bug_file_scheme_still_blocked :: proc(t: ^testing.T) {
	node: [16]u8
	node[0] = 1
	act := micron.resolve_link("file:///etc/passwd", node, true)
	defer micron.action_destroy(&act)
	testing.expect_value(t, act.kind, micron.Action_Kind.Reject)
}

@(test)
test_micron_resolve_file_link :: proc(t: ^testing.T) {
	node: [16]u8
	node[0] = 0xab
	rel := micron.resolve_link("/file/data.bin", node, true)
	defer micron.action_destroy(&rel)
	testing.expect_value(t, rel.kind, micron.Action_Kind.File)
	testing.expect_value(t, rel.path, "/file/data.bin")

	hex := store.hash_hex(node, context.temp_allocator)
	url := strings.concatenate({hex, ":/file/doc.txt"}, context.temp_allocator)
	abs := micron.resolve_link(url, {}, false)
	defer micron.action_destroy(&abs)
	testing.expect_value(t, abs.kind, micron.Action_Kind.File)
	testing.expect_value(t, abs.path, "/file/doc.txt")
}

@(test)
test_bug_file_path_traversal_rejected :: proc(t: ^testing.T) {
	node: [16]u8
	act := micron.resolve_link("/file/../../etc/passwd", node, true)
	defer micron.action_destroy(&act)
	testing.expect_value(t, act.kind, micron.Action_Kind.Reject)
}

@(test)
test_file_basename_from_path :: proc(t: ^testing.T) {
	testing.expect_value(t, net.file_basename_from_path("/file/readme.txt"), "readme.txt")
	testing.expect_value(t, net.file_basename_from_path("/file/a.bin`x=1"), "a.bin")
	testing.expect_value(t, net.file_basename_from_path("/file/../evil"), "download.bin")
}

@(test)
test_file_write_bytes_roundtrip :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-file-dl-test"})
	_ = os.remove_all(base)
	_ = os.make_directory_all(base)
	defer os.remove_all(base)

	data := transmute([]u8)string("hello-file")
	out, ok := app.page_write_bytes(base, "hi.bin", data)
	testing.expect(t, ok)
	defer delete(out)
	got, err := os.read_entire_file_from_path(out, context.allocator)
	testing.expect(t, err == nil)
	defer delete(got)
	testing.expect_value(t, string(got), "hello-file")
}

@(test)
test_file_progress_line_percent_and_speed :: proc(t: ^testing.T) {
	s: net.Session
	s.page.active = true
	s.page.is_file = true
	s.page.filename = strings.clone("pack.zip")
	defer delete(s.page.filename)
	s.page.started_at = time.tick_now()
	time.sleep(50 * time.Millisecond)
	s.page.bytes_got = 512
	s.page.bytes_total = 1024
	line := net.session_file_progress_line(&s)
	defer delete(line)
	testing.expect(t, strings.contains(line, "pack.zip"))
	testing.expect(t, strings.contains(line, "%"))
	testing.expect(t, strings.contains(line, "/s"))
}

@(test)
test_file_progress_line_unknown_total :: proc(t: ^testing.T) {
	s: net.Session
	s.page.active = true
	s.page.is_file = true
	s.page.filename = strings.clone("x.bin")
	defer delete(s.page.filename)
	s.page.started_at = time.tick_now()
	s.page.bytes_got = 2048
	s.page.bytes_total = 0
	line := net.session_file_progress_line(&s)
	defer delete(line)
	testing.expect(t, strings.contains(line, "x.bin"))
	testing.expect(t, strings.contains(line, "KB") || strings.contains(line, "B"))
}

@(test)
test_bug_file_max_bytes_constant :: proc(t: ^testing.T) {
	testing.expect(t, constants.FILE_MAX_BYTES > constants.PAGE_MAX_BYTES)
	testing.expect(t, constants.FILE_MAX_BYTES >= 16 * 1024 * 1024)
}
