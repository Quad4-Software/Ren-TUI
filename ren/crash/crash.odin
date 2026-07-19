// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Crash diagnostics: assertion/panic banner without core:debug/trace.
Odin's trace package links -lstdc++exp (GCC 14+) which breaks slim CI images.
*/

package crash

import "base:runtime"
import "core:fmt"
import "core:os"

import "ren:constants"
import "ren:version"

install :: proc() {
	install_posix_signals()
}

close :: proc() {
}

assertion_failure :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
	print_banner(prefix, message, loc)
	print_hint()
	runtime.trap()
}

@(private)
print_banner :: proc(prefix, message: string, loc: runtime.Source_Code_Location) {
	runtime.print_string("\n=== ren-tui crash ===\n")
	runtime.print_caller_location(loc)
	runtime.print_byte('\n')
	runtime.print_string(prefix)
	if len(message) > 0 {
		runtime.print_string(": ")
		runtime.print_string(message)
	}
	runtime.print_byte('\n')
	runtime.print_string("version: ")
	runtime.print_string(fmt.tprintf("%s %s (%s %s)", constants.APP_NAME, constants.VERSION, version.GIT_COMMIT, version.BUILD_DATE))
	runtime.print_byte('\n')
	print_env_line("TERM", os.get_env("TERM", context.temp_allocator))
	print_env_line("COLORTERM", os.get_env("COLORTERM", context.temp_allocator))
	print_env_line(constants.ENV_UI, os.get_env(constants.ENV_UI, context.temp_allocator))
	print_env_line(constants.ENV_RNS_CONFIG, os.get_env(constants.ENV_RNS_CONFIG, context.temp_allocator))
	runtime.print_string("os: ")
	runtime.print_string(fmt.tprintf("%v", ODIN_OS))
	runtime.print_string("  arch: ")
	runtime.print_string(fmt.tprintf("%v", ODIN_ARCH))
	runtime.print_byte('\n')
}

@(private)
print_env_line :: proc(key, val: string) {
	runtime.print_string(key)
	runtime.print_string("=")
	if val == "" {
		runtime.print_string("(unset)")
	} else {
		runtime.print_string(val)
	}
	runtime.print_byte('\n')
}

print_hint :: proc() {
	runtime.print_string("hint: check librns.log under the data dir and re-run with REN_KEEP_STDERR=1\n")
	runtime.print_string("=== end crash ===\n")
}
