// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Version string helpers with git commit and build date.
Commit and date are injected at compile time via -define (see Makefile).
*/

package version

import "core:fmt"

import "ren:constants"

VERSION :: constants.VERSION
GIT_COMMIT :: #config(REN_GIT_COMMIT, "unknown")
BUILD_DATE :: #config(REN_BUILD_DATE, "unknown")

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
