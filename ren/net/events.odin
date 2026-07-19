// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Typed session events for UI and tools. Status text is display only.
Ring overflow drops the oldest event.
*/

package net

import "core:strings"

SESSION_EVENT_CAP :: 32

Session_Event_Kind :: enum {
	None,
	Online,
	Offline,
	Announce,
	Message_Received,
	Send_Ok,
	Send_Failed,
	Page_Ok,
	Page_Failed,
	Error,
}

Session_Event :: struct {
	kind:   Session_Event_Kind,
	detail: string,
}

Session_Event_Ring :: struct {
	buf:   [SESSION_EVENT_CAP]Session_Event,
	head:  int,
	count: int,
}

session_event_default_detail :: proc(kind: Session_Event_Kind) -> string {
	switch kind {
	case .None:
		return ""
	case .Online:
		return "online"
	case .Offline:
		return "offline"
	case .Announce:
		return "announced"
	case .Message_Received:
		return "message received"
	case .Send_Ok:
		return "sent"
	case .Send_Failed:
		return "send failed"
	case .Page_Ok:
		return "page ok"
	case .Page_Failed:
		return "page failed"
	case .Error:
		return "error"
	}
	return ""
}

session_event_ring_clear :: proc(r: ^Session_Event_Ring) {
	for i in 0 ..< r.count {
		idx := (r.head + i) % SESSION_EVENT_CAP
		delete(r.buf[idx].detail)
		r.buf[idx] = {}
	}
	r.head = 0
	r.count = 0
}

session_event_push :: proc(s: ^Session, kind: Session_Event_Kind, detail: string = "") {
	text := detail
	if text == "" {
		text = session_event_default_detail(kind)
	}
	delete(s.status)
	s.status = strings.clone(text)

	r := &s.events
	if r.count == SESSION_EVENT_CAP {
		old := r.buf[r.head]
		delete(old.detail)
		r.buf[r.head] = {}
		r.head = (r.head + 1) % SESSION_EVENT_CAP
		r.count -= 1
	}
	idx := (r.head + r.count) % SESSION_EVENT_CAP
	r.buf[idx] = Session_Event{
		kind = kind,
		detail = strings.clone(text),
	}
	r.count += 1
}

session_event_push_status :: proc(s: ^Session, kind: Session_Event_Kind, detail: string) {
	session_event_push(s, kind, detail)
}

session_set_status_text :: proc(s: ^Session, text: string) {
	delete(s.status)
	s.status = strings.clone(text)
}

session_events_drain :: proc(s: ^Session, out: []Session_Event) -> int {
	r := &s.events
	n := min(r.count, len(out))
	for i in 0 ..< n {
		idx := (r.head + i) % SESSION_EVENT_CAP
		out[i] = r.buf[idx]
		r.buf[idx] = {}
	}
	r.head = (r.head + n) % SESSION_EVENT_CAP
	r.count -= n
	return n
}

session_events_has :: proc(s: ^Session, kind: Session_Event_Kind) -> bool {
	r := &s.events
	for i in 0 ..< r.count {
		idx := (r.head + i) % SESSION_EVENT_CAP
		if r.buf[idx].kind == kind {
			return true
		}
	}
	return false
}
