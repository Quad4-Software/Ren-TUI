// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Display column width for micron layout and fields (East Asian / emoji aware).
*/

package micron

import "core:unicode"
import "core:unicode/utf8"

rune_cols :: proc(r: rune) -> int {
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

truncate_cols :: proc(s: string, max_cols: int) -> string {
	if max_cols <= 0 {
		return ""
	}
	cols := 0
	for r, i in s {
		w := rune_cols(r)
		if w <= 0 {
			continue
		}
		if cols + w > max_cols {
			return s[:i]
		}
		cols += w
	}
	return s
}

take_cols :: proc(s: string, max_cols: int) -> string {
	if max_cols <= 0 || len(s) == 0 {
		return ""
	}
	i := 0
	cols := 0
	for i < len(s) {
		r, size := utf8.decode_rune_in_string(s[i:])
		w := rune_cols(r)
		if w <= 0 {
			i += size
			continue
		}
		if cols + w > max_cols {
			if cols == 0 {
				return s[:i + size]
			}
			return s[:i]
		}
		cols += w
		i += size
	}
	return s[:i]
}
