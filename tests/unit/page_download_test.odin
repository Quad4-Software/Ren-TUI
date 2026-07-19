// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Page download basename and write path tests.
*/

package tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "ren:app"
import "ren:constants"
import "ren:store"

@(test)
test_page_download_basename_from_path :: proc(t: ^testing.T) {
	a := app.page_download_basename("/page/index.mu")
	defer delete(a)
	testing.expect_value(t, a, "index.mu")

	b := app.page_download_basename("/page/about.mu")
	defer delete(b)
	testing.expect_value(t, b, "about.mu")

	c := app.page_download_basename("/page/forum.mu`cat=x")
	defer delete(c)
	testing.expect_value(t, c, "forum.mu")

	d := app.page_download_basename("/page/noext")
	defer delete(d)
	testing.expect_value(t, d, "noext.mu")

	e := app.page_download_basename("")
	defer delete(e)
	testing.expect_value(t, e, "index.mu")

	f := app.page_download_basename("/page/../evil.mu")
	defer delete(f)
	testing.expect_value(t, f, "index.mu")
}

@(test)
test_config_download_dir_default_and_override :: proc(t: ^testing.T) {
	cfg := store.config_default()
	defer store.config_destroy_strings(&cfg)
	delete(cfg.data_dir)
	cfg.data_dir = strings.clone("/tmp/ren-tui-dl-cfg")
	delete(cfg.download_dir)
	cfg.download_dir = strings.clone("")

	def := store.config_download_dir(&cfg)
	defer delete(def)
	want, _ := filepath.join({"/tmp/ren-tui-dl-cfg", constants.DOWNLOADS_DIR})
	defer delete(want)
	testing.expect_value(t, def, want)

	delete(cfg.download_dir)
	cfg.download_dir = strings.clone("micron-pages")
	rel := store.config_download_dir(&cfg)
	defer delete(rel)
	want_rel, _ := filepath.join({"/tmp/ren-tui-dl-cfg", "micron-pages"})
	defer delete(want_rel)
	testing.expect_value(t, rel, want_rel)

	delete(cfg.download_dir)
	cfg.download_dir = strings.clone("/var/tmp/ren-pages")
	abs := store.config_download_dir(&cfg)
	defer delete(abs)
	testing.expect_value(t, abs, "/var/tmp/ren-pages")
}

@(test)
test_page_write_download_roundtrip :: proc(t: ^testing.T) {
	base, _ := filepath.join({"/tmp", "ren-tui-page-dl"})
	_ = os.remove_all(base)
	defer os.remove_all(base)
	_ = os.make_directory_all(base)

	out, ok := app.page_write_download(base, "index.mu", ">hello\n")
	testing.expect(t, ok)
	defer delete(out)
	data, err := os.read_entire_file_from_path(out, context.allocator)
	testing.expect(t, err == nil)
	defer delete(data)
	testing.expect_value(t, string(data), ">hello\n")
}
