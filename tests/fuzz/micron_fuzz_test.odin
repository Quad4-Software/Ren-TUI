// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Extra fuzz coverage for micron link resolve and markup edges.
*/

package tests

import "core:math/rand"
import "core:testing"

import "ren:micron"

@(test)
test_fuzz_micron_links_and_resolve_no_panic :: proc(t: ^testing.T) {
	rand.reset(0xF02203)
	src := make([]u8, 160)
	defer delete(src)
	base: [16]u8
	base[0] = 7
	for _ in 0 ..< 128 {
		n := int(rand.uint32() % u32(len(src)))
		for i in 0 ..< n {
			ch := u8(rand.uint32() % 96) + 32
			switch rand.uint32() % 12 {
			case 0:
				ch = '`'
			case 1:
				ch = '['
			case 2:
				ch = ']'
			case 3:
				ch = '<'
			case 4:
				ch = '>'
			case 5:
				ch = '\n'
			case 6:
				ch = '#'
			}
			src[i] = ch
		}
		doc := micron.parse(string(src[:n]))
		for line in doc.lines {
			for span in line.spans {
				if span.kind == .Link || span.kind == .Partial {
					act := micron.resolve_link(span.url, base, true)
					micron.action_destroy(&act)
				}
			}
		}
		micron.doc_destroy(&doc)
	}
}
