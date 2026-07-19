// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Frame loop clear draw present then poll input.
Redraw only when the app marks itself dirty.
*/

package ui

Loop :: struct {
	term:   Term,
	buf:    Buffer,
	quit:   bool,
	status: string,
	theme:  Theme,
	caps:   Caps,
}

loop_init :: proc(l: ^Loop, preferred_color := "", enable_mouse := true) -> bool {
	l^ = {}
	l.theme = FIELD
	loop_activate(l)
	caps_init(preferred_color)
	if !enable_mouse {
		caps_ptr().mouse = false
	}
	if !term_init(&l.term, preferred_color, enable_mouse) {
		loop_deactivate(l)
		return false
	}
	l.buf = buffer_create(l.term.width, l.term.height)
	return true
}

loop_close :: proc(l: ^Loop) {
	buffer_destroy(&l.buf)
	term_close(&l.term)
	loop_deactivate(l)
}

Draw_Proc :: #type proc(buf: ^Buffer, user: rawptr)
Event_Proc :: #type proc(ev: Event, user: rawptr) -> bool
Dirty_Proc :: #type proc(user: rawptr) -> bool

loop_run :: proc(l: ^Loop, draw: Draw_Proc, on_event: Event_Proc, user: rawptr, is_dirty: Dirty_Proc = nil) {
	loop_activate(l)
	force := true
	for !l.quit {
		term_query_size(&l.term)
		if l.buf.width != l.term.width || l.buf.height != l.term.height {
			buffer_resize(&l.buf, l.term.width, l.term.height)
			force = true
		}
		dirty := force
		if !dirty && is_dirty != nil {
			dirty = is_dirty(user)
		}
		if dirty {
			t := l.theme
			buffer_clear(&l.buf, t.bg, t.fg)
			if draw != nil {
				draw(&l.buf, user)
			}
			term_present(&l.term, &l.buf)
			force = false
		}

		ev, ok := poll_event(50)
		if !ok {
			ev = Event{kind = .None}
		}
		if ev.kind == .Ctrl_C || ev.kind == .Ctrl_Q {
			l.quit = true
			continue
		}
		if on_event != nil {
			if on_event(ev, user) {
				l.quit = true
			}
		}
	}
}
