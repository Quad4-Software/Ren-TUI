// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Version stamps via -define must not mutate tracked sources.
*/

package tests

import "core:os"
import "core:strings"
import "core:testing"

import "ren:constants"
import "ren:version"

@(test)
test_version_define_injected_or_default :: proc(t: ^testing.T) {
	testing.expect_value(t, version.VERSION, constants.VERSION)
	line := version.line()
	defer delete(line)
	testing.expect(t, strings.contains(line, constants.VERSION))
	testing.expect(t, strings.contains(line, version.GIT_COMMIT))
	testing.expect(t, strings.contains(line, version.BUILD_DATE))
	testing.expect(t, version.GIT_COMMIT != "")
	testing.expect(t, version.BUILD_DATE != "")
}

@(test)
test_bug_version_odin_not_dirty_after_make_pattern :: proc(t: ^testing.T) {
	path := "ren/version/version.odin"
	data, err := os.read_entire_file_from_path(path, context.allocator)
	testing.expect(t, err == nil)
	defer delete(data)
	src := string(data)
	testing.expect(t, strings.contains(src, "#config(REN_GIT_COMMIT"))
	testing.expect(t, strings.contains(src, "#config(REN_BUILD_DATE"))
	testing.expect(t, !strings.contains(src, "GIT_COMMIT :: \"4c0d6ba\""))
}
