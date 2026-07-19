// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Display column width for terminal cells (East Asian / emoji aware).
*/

package ui

import "core:unicode"

// Marks the trailing cell of a wide glyph. Present skips writing it.
CELL_WIDE_CONT :: rune(0x10FFFE)

rune_cols :: proc(r: rune) -> int {
	if r == CELL_WIDE_CONT {
		return 0
	}
	w := unicode.normalized_east_asian_width(r)
	if w < 0 {
		return 1
	}
	return w
}

string_cols :: proc(s: string) -> int {
	n := 0
	for r in s {
		n += rune_cols(r)
	}
	return n
}
