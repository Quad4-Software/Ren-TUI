// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
No-op signal install on Windows.
*/

#+build windows
package crash

@(private)
install_posix_signals :: proc() {
}
