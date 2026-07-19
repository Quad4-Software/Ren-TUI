// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Version string helpers with git commit and build date.
*/

package version

import "core:fmt"

import "ren:constants"

VERSION :: constants.VERSION
GIT_COMMIT :: "unknown"
BUILD_DATE :: "2026-07-19T09:48Z"

full :: proc(allocator := context.allocator) -> string {
	return fmt.aprintf("%s+%s", VERSION, GIT_COMMIT, allocator = allocator)
}

line :: proc(allocator := context.allocator) -> string {
	return fmt.aprintf(
		"%s %s (%s %s)",
		constants.APP_NAME,
		VERSION,
		GIT_COMMIT,
		BUILD_DATE,
		allocator = allocator,
	)
}

short_line :: proc(allocator := context.allocator) -> string {
	return fmt.aprintf("%s %s", constants.APP_NAME, VERSION, allocator = allocator)
}
