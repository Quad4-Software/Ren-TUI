// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
POSIX fatal signal handlers that print a short crash banner then re-raise.
*/

#+build linux, darwin, freebsd, openbsd, netbsd
package crash

import "base:runtime"
import "core:sys/posix"

import "ren:constants"
import "ren:version"

@(private)
install_posix_signals :: proc() {
	_ = posix.signal(.SIGSEGV, fault_handler)
	_ = posix.signal(.SIGABRT, fault_handler)
	_ = posix.signal(.SIGILL, fault_handler)
	_ = posix.signal(.SIGFPE, fault_handler)
	_ = posix.signal(.SIGBUS, fault_handler)
}

@(private)
fault_handler :: proc "c" (sig: posix.Signal) {
	context = runtime.default_context()
	runtime.print_string("\n=== ren-tui fatal signal ===\n")
	runtime.print_string("signal: ")
	runtime.print_int(int(sig))
	runtime.print_byte('\n')
	runtime.print_string("version: ")
	runtime.print_string(constants.APP_NAME)
	runtime.print_byte(' ')
	runtime.print_string(constants.VERSION)
	runtime.print_string(" (")
	runtime.print_string(version.GIT_COMMIT)
	runtime.print_byte(')')
	runtime.print_byte('\n')
	print_hint()
	_ = posix.signal(sig, auto_cast posix.SIG_DFL)
	_ = posix.raise(sig)
}
