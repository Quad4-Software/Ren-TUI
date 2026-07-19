// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Key and event decoding from raw terminal input.
*/

package ui

Key :: enum {
	None,
	Rune,
	Enter,
	Esc,
	Backspace,
	Tab,
	Backtab,
	Up,
	Down,
	Left,
	Right,
	Home,
	End,
	Page_Up,
	Page_Down,
	Delete,
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	Ctrl_A,
	Ctrl_C,
	Ctrl_D,
	Ctrl_L,
	Ctrl_N,
	Ctrl_P,
	Ctrl_Q,
	Ctrl_R,
	Ctrl_S,
	Ctrl_U,
	Ctrl_X,
	Mouse,
}

Event :: struct {
	kind:   Key,
	ch:     rune,
	ctrl:   bool,
	alt:    bool,
	mouse_x: int,
	mouse_y: int,
	mouse_btn: int,
	mouse_down: bool,
	mouse_scroll: int,
}

poll_event :: proc(timeout_ms: int = 50) -> (ev: Event, ok: bool) {
	_ = timeout_ms
	b, got := term_read_byte()
	if !got {
		return {}, false
	}

	if b == 0x1b {
		b2, got2 := term_read_byte()
		if !got2 {
			return Event{kind = .Esc}, true
		}
		if b2 == '[' {
			b3, got3 := term_read_byte()
			if !got3 {
				return Event{kind = .Esc}, true
			}
			if b3 == '<' {
				return parse_sgr_mouse()
			}
			switch b3 {
			case 'A':
				return Event{kind = .Up}, true
			case 'B':
				return Event{kind = .Down}, true
			case 'C':
				return Event{kind = .Right}, true
			case 'D':
				return Event{kind = .Left}, true
			case 'H':
				return Event{kind = .Home}, true
			case 'F':
				return Event{kind = .End}, true
			case 'Z':
				return Event{kind = .Backtab}, true
			case 'M':
				return parse_x10_mouse()
			case '1', '2', '3', '4', '5', '6':
				b4, got4 := term_read_byte()
				if got4 && b4 == '~' {
					switch b3 {
					case '1':
						return Event{kind = .Home}, true
					case '3':
						return Event{kind = .Delete}, true
					case '4':
						return Event{kind = .End}, true
					case '5':
						return Event{kind = .Page_Up}, true
					case '6':
						return Event{kind = .Page_Down}, true
					}
				}
			}
			return Event{kind = .Esc}, true
		}
		if b2 == 'O' {
			b3, got3 := term_read_byte()
			if got3 {
				switch b3 {
				case 'P':
					return Event{kind = .F1}, true
				case 'Q':
					return Event{kind = .F2}, true
				case 'R':
					return Event{kind = .F3}, true
				case 'S':
					return Event{kind = .F4}, true
				}
			}
		}
		return Event{kind = .Esc, alt = true, ch = rune(b2)}, true
	}

	switch b {
	case 0x01:
		return Event{kind = .Ctrl_A}, true
	case 0x03:
		return Event{kind = .Ctrl_C}, true
	case 0x04:
		return Event{kind = .Ctrl_D}, true
	case 0x0c:
		return Event{kind = .Ctrl_L}, true
	case 0x0e:
		return Event{kind = .Ctrl_N}, true
	case 0x10:
		return Event{kind = .Ctrl_P}, true
	case 0x11:
		return Event{kind = .Ctrl_Q}, true
	case 0x12:
		return Event{kind = .Ctrl_R}, true
	case 0x13:
		return Event{kind = .Ctrl_S}, true
	case 0x15:
		return Event{kind = .Ctrl_U}, true
	case 0x18:
		return Event{kind = .Ctrl_X}, true
	case 0x09:
		return Event{kind = .Tab}, true
	case 0x0d, 0x0a:
		return Event{kind = .Enter}, true
	case 0x7f, 0x08:
		return Event{kind = .Backspace}, true
	}

	if b >= 0x20 && b < 0x7f {
		return Event{kind = .Rune, ch = rune(b)}, true
	}
	return {}, false
}

@(private)
read_decimal :: proc() -> (n: int, term: u8, ok: bool) {
	n = 0
	for {
		b, got := term_read_byte()
		if !got {
			return 0, 0, false
		}
		if b >= '0' && b <= '9' {
			n = n * 10 + int(b - '0')
			continue
		}
		return n, b, true
	}
}

@(private)
parse_sgr_mouse :: proc() -> (Event, bool) {
	btn, t1, ok1 := read_decimal()
	if !ok1 || t1 != ';' {
		return {}, false
	}
	x, t2, ok2 := read_decimal()
	if !ok2 || t2 != ';' {
		return {}, false
	}
	y, t3, ok3 := read_decimal()
	if !ok3 {
		return {}, false
	}
	ev := Event{
		kind = .Mouse,
		mouse_x = x - 1,
		mouse_y = y - 1,
		mouse_btn = btn & 3,
		mouse_down = t3 == 'M',
	}
	if btn == 64 {
		ev.mouse_scroll = -1
	} else if btn == 65 {
		ev.mouse_scroll = 1
	}
	return ev, true
}

@(private)
parse_x10_mouse :: proc() -> (Event, bool) {
	b0, ok0 := term_read_byte()
	b1, ok1 := term_read_byte()
	b2, ok2 := term_read_byte()
	if !ok0 || !ok1 || !ok2 {
		return {}, false
	}
	btn := int(b0) - 32
	ev := Event{
		kind = .Mouse,
		mouse_x = int(b1) - 33,
		mouse_y = int(b2) - 33,
		mouse_btn = btn & 3,
		mouse_down = true,
	}
	if btn == 64 {
		ev.mouse_scroll = -1
	} else if btn == 65 {
		ev.mouse_scroll = 1
	}
	return ev, true
}
