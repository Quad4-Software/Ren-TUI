// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Crash diagnostics: assertion/panic banner and optional stack frames.
*/

package crash

import "base:runtime"
import "core:debug/trace"
import "core:fmt"
import "core:os"

import "ren:constants"
import "ren:version"

trace_ctx: trace.Context
trace_ready: bool

install :: proc() {
	trace_ready = trace.init(&trace_ctx)
	install_posix_signals()
}

close :: proc() {
	if trace_ready {
		_ = trace.destroy(&trace_ctx)
		trace_ready = false
	}
}

assertion_failure :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
	print_banner(prefix, message, loc)
	print_stack(1)
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

print_stack :: proc(skip: uint) {
	if !trace_ready || trace.in_resolve(&trace_ctx) {
		runtime.print_string("(stack trace unavailable build with -debug for frames)\n")
		return
	}
	buf: [64]trace.Frame
	frames := trace.frames(&trace_ctx, skip, buf[:])
	if len(frames) == 0 {
		runtime.print_string("(no stack frames resolved build with -debug)\n")
		return
	}
	runtime.print_string("stack:\n")
	shown := 0
	for f, i in frames {
		fl := trace.resolve(&trace_ctx, f, context.temp_allocator)
		if fl.loc.file_path == "" && fl.loc.line == 0 {
			continue
		}
		runtime.print_string("  #")
		runtime.print_int(i)
		runtime.print_string(" ")
		runtime.print_caller_location(fl.loc)
		runtime.print_byte('\n')
		shown += 1
	}
	if shown == 0 {
		runtime.print_string("(no stack frames resolved build with -debug)\n")
	}
}

print_hint :: proc() {
	runtime.print_string("hint: check librns.log under the data dir and re-run with REN_KEEP_STDERR=1\n")
	runtime.print_string("=== end crash ===\n")
}
