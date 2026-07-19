// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Hex decode helpers shared by LXMF wire and UI address entry.
*/

package lxmf

hex_nibble_value :: proc(c: u8) -> int {
	switch c {
	case '0' ..= '9':
		return int(c - '0')
	case 'a' ..= 'f':
		return int(c - 'a' + 10)
	case 'A' ..= 'F':
		return int(c - 'A' + 10)
	}
	return -1
}

is_hex32 :: proc(s: string) -> bool {
	if len(s) != 32 {
		return false
	}
	for i in 0 ..< 32 {
		if hex_nibble_value(s[i]) < 0 {
			return false
		}
	}
	return true
}

decode_hex32 :: proc(s: string) -> (out: [HASH_LEN]u8, ok: bool) {
	if !is_hex32(s) {
		return {}, false
	}
	for i in 0 ..< HASH_LEN {
		hi := hex_nibble_value(s[i * 2])
		lo := hex_nibble_value(s[i * 2 + 1])
		out[i] = u8(hi << 4 | lo)
	}
	return out, true
}
