// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
OSC 52 clipboard copy through the terminal.
*/

package ui

import "core:encoding/base64"
import "core:fmt"

clipboard_copy :: proc(text: string) -> bool {
	if text == "" {
		return false
	}
	encoded, err := base64.encode(transmute([]u8)text, allocator = context.temp_allocator)
	if err != nil {
		return false
	}
	seq := fmt.tprintf("\x1b]52;c;%s\x07", string(encoded))
	return display_write(transmute([]u8)seq)
}
