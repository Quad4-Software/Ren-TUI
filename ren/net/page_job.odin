// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Async NomadNet static page fetch. Advances on session_poll so the TUI stays live.
*/

package net

import "core:fmt"
import "core:strings"
import "core:time"

import rns "rns:rns"
import "ren:constants"
import "ren:store"

Page_Phase :: enum {
	Idle,
	Finding_Path,
	Opening_Link,
	Waiting_Link,
	Sending_Request,
	Waiting_Response,
}

Page_Job :: struct {
	active:         bool,
	done:           bool,
	ok:             bool,
	is_file:        bool,
	phase:          Page_Phase,
	node:           [store.HASH_LEN]u8,
	path:           string,
	filename:       string,
	request_data:   []u8,
	link:           rns.Link,
	link_id:        [store.HASH_LEN]u8,
	has_link_id:    bool,
	request_id:     [store.HASH_LEN]u8,
	has_request_id: bool,
	deadline:       time.Tick,
	phase_deadline: time.Tick,
	retry_at:         time.Tick,
	path_refreshed:   bool,
	link_rediscover:  bool,
	identify_after:   bool,
	started_at:     time.Tick,
	bytes_got:      int,
	bytes_total:    int,
	content:        []u8,
	status:         string,
}

session_page_busy :: proc(s: ^Session) -> bool {
	return s.page.active && !s.page.done
}

session_page_status :: proc(s: ^Session) -> string {
	if s.page.active || s.page.done {
		if s.page.is_file {
			return session_file_progress_line(s, context.temp_allocator)
		}
		if s.page.status != "" {
			return s.page.status
		}
	}
	return s.status
}

session_page_cancel :: proc(s: ^Session) {
	if s.page.link != 0 {
		_ = rns.link_close(s.page.link)
	}
	delete(s.page.path)
	delete(s.page.filename)
	delete(s.page.content)
	delete(s.page.status)
	delete(s.page.request_data)
	s.page = {}
}

@(private)
page_fail :: proc(s: ^Session, msg: string) {
	delete(s.page.status)
	s.page.status = strings.clone(msg)
	session_event_push(s, .Page_Failed, msg)
	s.page.ok = false
	s.page.done = true
	s.page.active = false
	s.page.phase = .Idle
	if s.page.link != 0 {
		_ = rns.link_close(s.page.link)
		s.page.link = 0
	}
}

@(private)
page_set_status :: proc(s: ^Session, msg: string) {
	delete(s.page.status)
	s.page.status = strings.clone(msg)
	session_set_status_text(s, msg)
}

session_page_begin :: proc(
	s: ^Session,
	node: [store.HASH_LEN]u8,
	page_path: string,
	request_payload: []u8 = nil,
	identify_after := false,
) -> bool {
	if !s.started {
		session_event_push(s, .Error, "offline")
		return false
	}
	session_page_cancel(s)
	if page_path == "" {
		session_event_push(s, .Page_Failed, "bad path")
		return false
	}
	is_file := strings.has_prefix(page_path, "/file/")
	if !is_file && !strings.has_prefix(page_path, "/page/") {
		session_event_push(s, .Page_Failed, "bad path")
		return false
	}
	if strings.contains(page_path, "..") {
		session_event_push(s, .Page_Failed, "bad path")
		return false
	}
	for i in 0 ..< len(page_path) {
		c := page_path[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '/', '.', '_', '-', '~':
		case:
			session_event_push(s, .Page_Failed, "bad path")
			return false
		}
	}
	s.page.active = true
	s.page.done = false
	s.page.ok = false
	s.page.is_file = is_file
	s.page.node = node
	s.page.path = strings.clone(page_path)
	s.page.filename = strings.clone(file_basename_from_path(page_path))
	s.page.started_at = time.tick_now()
	s.page.bytes_got = 0
	s.page.bytes_total = 0
	if len(request_payload) > 0 {
		s.page.request_data = make([]u8, len(request_payload))
		copy(s.page.request_data, request_payload)
	}
	s.page.identify_after = identify_after
	s.page.deadline = time.tick_add(time.tick_now(), time.Duration(constants.PAGE_TIMEOUT_SEC) * time.Second)
	s.page.phase = .Finding_Path
	s.page.phase_deadline = time.tick_add(
		time.tick_now(),
		time.Duration(constants.PATH_FIND_TIMEOUT_SEC) * time.Second,
	)
	s.page.retry_at = time.tick_now()
	if is_file {
		page_set_status(s, fmt.tprintf("%s  finding path...", s.page.filename))
	} else {
		page_set_status(s, fmt.tprintf("finding path for %s...", node_hash_hex(node)))
	}
	session_page_tick(s)
	return true
}

file_basename_from_path :: proc(path: string) -> string {
	p := path
	if bt := strings.index_byte(p, '`'); bt >= 0 {
		p = p[:bt]
	}
	if p == "" || strings.contains(p, "..") {
		return "download.bin"
	}
	base := p
	if slash := strings.last_index_byte(p, '/'); slash >= 0 && slash + 1 < len(p) {
		base = p[slash + 1:]
	}
	if base == "" || base == "." || strings.contains(base, "..") {
		return "download.bin"
	}
	for i in 0 ..< len(base) {
		c := base[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '.', '_', '-', '~':
		case:
			return "download.bin"
		}
	}
	return base
}

session_file_progress_line :: proc(s: ^Session, allocator := context.allocator) -> string {
	if !s.page.active && !s.page.done {
		return ""
	}
	if !s.page.is_file {
		return s.page.status
	}
	name := s.page.filename if s.page.filename != "" else "file"
	elapsed := time.tick_since(s.page.started_at)
	secs := f64(elapsed) / f64(time.Second)
	if secs < 0.05 {
		secs = 0.05
	}
	if s.page.bytes_got <= 0 {
		if s.page.status != "" {
			return strings.clone(s.page.status, allocator)
		}
		return fmt.aprintf("%s  waiting", name, allocator = allocator)
	}
	speed := f64(s.page.bytes_got) / secs
	speed_s := format_rate(speed, context.temp_allocator)
	if s.page.bytes_total > 0 {
		pct := (100 * s.page.bytes_got) / s.page.bytes_total
		if pct > 100 {
			pct = 100
		}
		return fmt.aprintf("%s  %d%%  %s", name, pct, speed_s, allocator = allocator)
	}
	return fmt.aprintf("%s  %s  %s", name, format_bytes_short(s.page.bytes_got, context.temp_allocator), speed_s, allocator = allocator)
}

@(private)
format_rate :: proc(bps: f64, allocator := context.allocator) -> string {
	if bps < 1024 {
		return fmt.aprintf("%.0fB/s", bps, allocator = allocator)
	}
	if bps < 1024 * 1024 {
		return fmt.aprintf("%.1fKB/s", bps / 1024.0, allocator = allocator)
	}
	return fmt.aprintf("%.1fMB/s", bps / (1024.0 * 1024.0), allocator = allocator)
}

@(private)
format_bytes_short :: proc(n: int, allocator := context.allocator) -> string {
	if n < 1024 {
		return fmt.aprintf("%dB", n, allocator = allocator)
	}
	if n < 1024 * 1024 {
		return fmt.aprintf("%.1fKB", f64(n) / 1024.0, allocator = allocator)
	}
	return fmt.aprintf("%.1fMB", f64(n) / (1024.0 * 1024.0), allocator = allocator)
}

// Returns finished=true when a job completed (success or fail). Caller owns content on ok.
session_page_take :: proc(
	s: ^Session,
	allocator := context.allocator,
) -> (
	content: []u8,
	path: string,
	node: [store.HASH_LEN]u8,
	ok: bool,
	finished: bool,
	is_file: bool,
) {
	if !s.page.done {
		return nil, "", {}, false, false, false
	}
	node = s.page.node
	path = strings.clone(s.page.path, allocator)
	ok = s.page.ok
	is_file = s.page.is_file
	content = s.page.content
	s.page.content = nil
	status := s.page.status
	s.page.status = ""
	delete(s.page.path)
	s.page.path = ""
	delete(s.page.filename)
	s.page.filename = ""
	s.page.done = false
	s.page.active = false
	s.page.is_file = false
	s.page.phase = .Idle
	if status != "" {
		if ok {
			session_event_push(s, .Page_Ok, status)
		} else {
			session_event_push(s, .Page_Failed, status)
		}
		delete(status)
	}
	return content, path, node, ok, true, is_file
}

@(private)
truncate_hash8 :: proc(h: [store.HASH_LEN]u8) -> string {
	hex := store.hash_hex(h, context.temp_allocator)
	if len(hex) > 8 {
		return hex[:8]
	}
	return hex
}

node_hash_hex :: proc(h: [store.HASH_LEN]u8) -> string {
	return store.hash_hex(h, context.temp_allocator)
}

page_path_wait_status :: proc(h: [store.HASH_LEN]u8, allocator := context.allocator) -> string {
	return fmt.aprintf("waiting for path to %s...", node_hash_hex(h), allocator = allocator)
}

@(private)
hashes_equal :: proc(a, b: []u8) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i in 0 ..< len(a) {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// Handle link/request events for the active page job. Returns true if consumed.
session_page_on_event :: proc(s: ^Session, ev: ^rns.Event) -> bool {
	if !s.page.active || s.page.done {
		return false
	}
	switch ev.kind {
	case .Link_Established:
		if s.page.phase != .Waiting_Link {
			return false
		}
		dest := rns.event_destination_hash(ev)
		lid := rns.event_link_id(ev)
		ours := false
		if s.page.has_link_id && hashes_equal(lid, s.page.link_id[:]) {
			ours = true
		} else if len(dest) == store.HASH_LEN && hashes_equal(dest, s.page.node[:]) {
			ours = true
		}
		if !ours {
			return false
		}
		path_hot_remember(&s.paths, s.page.node, ev.hops)
		if s.page.identify_after {
			// ContextLinkIdentify (0xFB) needs rns_link_identify which librns lacks.
			page_set_status(s, "linked (identify pending: no librns API) requesting...")
		} else {
			page_set_status(s, fmt.tprintf("requesting %s...", s.page.path))
		}
		s.page.phase = .Sending_Request
		return true
	case .Link_Failed:
		if s.page.phase != .Waiting_Link && s.page.phase != .Opening_Link {
			return false
		}
		dest := rns.event_destination_hash(ev)
		lid := rns.event_link_id(ev)
		ours := false
		if s.page.has_link_id && hashes_equal(lid, s.page.link_id[:]) {
			ours = true
		} else if len(dest) == store.HASH_LEN && hashes_equal(dest, s.page.node[:]) {
			ours = true
		}
		if !ours {
			return false
		}
		err := rns.event_error_message(ev)
		path_hot_invalidate(&s.paths, s.page.node)
		if err != "" {
			page_fail(s, fmt.tprintf("link failed: %s", err))
		} else {
			page_fail(s, "cannot establish link")
		}
		return true
	case .Request_Response:
		if s.page.phase != .Waiting_Response {
			return false
		}
		if s.page.has_request_id {
			rid := rns.event_request_id(ev)
			if len(rid) > 0 && !hashes_equal(rid, s.page.request_id[:]) {
				return false
			}
		}
		data := rns.event_app_data(ev)
		if len(data) == 0 {
			page_fail(s, "empty" if s.page.is_file else "page empty")
			return true
		}
		max_n := constants.PAGE_MAX_BYTES
		if s.page.is_file {
			max_n = constants.FILE_MAX_BYTES
		}
		truncated := false
		if len(data) > max_n {
			data = data[:max_n]
			truncated = true
		}
		s.page.bytes_got = len(data)
		s.page.bytes_total = len(data)
		s.page.content = bytes_clone(data)
		s.page.ok = true
		s.page.done = true
		s.page.active = false
		s.page.phase = .Idle
		if s.page.link != 0 {
			_ = rns.link_close(s.page.link)
			s.page.link = 0
		}
		if s.page.is_file {
			line := session_file_progress_line(s, context.temp_allocator)
			if truncated {
				page_set_status(s, fmt.tprintf("%s truncated", line))
			} else {
				page_set_status(s, fmt.tprintf("saved %s", s.page.filename))
			}
		} else if truncated {
			page_set_status(s, "page ok truncated")
		} else {
			page_set_status(s, fmt.tprintf("page %s", s.page.path))
		}
		return true
	case .Request_Failed:
		if s.page.phase != .Waiting_Response && s.page.phase != .Sending_Request {
			return false
		}
		if s.page.has_request_id {
			rid := rns.event_request_id(ev)
			if len(rid) > 0 && !hashes_equal(rid, s.page.request_id[:]) {
				return false
			}
		}
		err := rns.event_error_message(ev)
		kind := "file" if s.page.is_file else "page"
		if err != "" {
			page_fail(s, fmt.tprintf("%s request failed: %s", kind, err))
		} else {
			page_fail(s, fmt.tprintf("%s request failed", kind))
		}
		return true
	case .Resource_Started:
		if !s.page.is_file || s.page.phase != .Waiting_Response {
			return false
		}
		data := rns.event_app_data(ev)
		if len(data) >= 4 {
			// Best-effort total size if present as first bytes (librns may not provide).
			_ = data
		}
		page_set_status(s, fmt.tprintf("%s  transferring...", s.page.filename))
		return true
	case .Resource_Concluded:
		if !s.page.is_file || (s.page.phase != .Waiting_Response && s.page.phase != .Sending_Request) {
			return false
		}
		data := rns.event_app_data(ev)
		if len(data) == 0 {
			page_fail(s, "file empty")
			return true
		}
		if len(data) > constants.FILE_MAX_BYTES {
			data = data[:constants.FILE_MAX_BYTES]
			page_set_status(s, fmt.tprintf("%s truncated", s.page.filename))
		}
		s.page.bytes_got = len(data)
		s.page.bytes_total = len(data)
		s.page.content = bytes_clone(data)
		s.page.ok = true
		s.page.done = true
		s.page.active = false
		s.page.phase = .Idle
		if s.page.link != 0 {
			_ = rns.link_close(s.page.link)
			s.page.link = 0
		}
		page_set_status(s, fmt.tprintf("saved %s", s.page.filename))
		return true
	case .Announce, .Link_Data, .Link_Closed, .Request_Incoming, .Destination_Data, .None:
		return false
	}
	return false
}

session_page_tick :: proc(s: ^Session) {
	if !s.page.active || s.page.done {
		return
	}
	now := time.tick_now()
	if time.tick_diff(now, s.page.deadline) <= 0 {
		switch s.page.phase {
		case .Finding_Path:
			page_fail(s, "path not found (timeout)")
		case .Opening_Link, .Waiting_Link:
			page_fail(s, "link timeout")
		case .Sending_Request, .Waiting_Response:
			page_fail(s, "page timeout")
		case .Idle:
			page_fail(s, "page timeout")
		}
		return
	}

	switch s.page.phase {
	case .Idle:
	case .Finding_Path:
		ready, hops := path_ensure(s, s.page.node, true)
		_ = hops
		if ready {
			s.page.phase = .Opening_Link
			page_set_status(s, fmt.tprintf("opening link to %s...", node_hash_hex(s.page.node)))
			session_page_tick(s)
			return
		}
		if time.tick_diff(now, s.page.phase_deadline) <= 0 {
			page_fail(s, "path not found")
			return
		}
		if time.tick_diff(now, s.page.retry_at) <= 0 {
			if !s.page.path_refreshed {
				path_request_refresh(s, s.page.node)
				s.page.path_refreshed = true
				page_set_status(s, fmt.tprintf("refreshing path for %s...", node_hash_hex(s.page.node)))
			} else {
				dh := s.page.node
				_ = rns.path_request(s.node, dh[:])
				page_set_status(s, page_path_wait_status(s.page.node, context.temp_allocator))
			}
			s.page.retry_at = time.tick_add(now, time.Duration(constants.PATH_RETRY_SEC) * time.Second)
		}
	case .Opening_Link:
		dh := s.page.node
		link, lerr := rns.link_open(s.node, dh[:])
		if lerr != .Ok || link == 0 {
			path_hot_invalidate(&s.paths, s.page.node)
			if !s.page.link_rediscover {
				s.page.link_rediscover = true
				s.page.path_refreshed = false
				s.page.phase = .Finding_Path
				s.page.phase_deadline = time.tick_add(
					now,
					time.Duration(constants.PATH_FIND_TIMEOUT_SEC) * time.Second,
				)
				path_request_refresh(s, s.page.node)
				page_set_status(s, "link open failed, re-finding path...")
				return
			}
			page_fail(s, "cannot open link")
			return
		}
		s.page.link = link
		if id, ierr := rns.link_id(link); ierr == .Ok {
			s.page.link_id = id
			s.page.has_link_id = true
		}
		s.page.phase = .Waiting_Link
		s.page.phase_deadline = time.tick_add(
			now,
			time.Duration(constants.LINK_TIMEOUT_SEC) * time.Second,
		)
		page_set_status(s, fmt.tprintf("waiting for link to %s...", node_hash_hex(s.page.node)))
	case .Waiting_Link:
		if time.tick_diff(now, s.page.phase_deadline) <= 0 {
			path_hot_invalidate(&s.paths, s.page.node)
			if !s.page.link_rediscover {
				s.page.link_rediscover = true
				s.page.path_refreshed = false
				if s.page.link != 0 {
					_ = rns.link_close(s.page.link)
					s.page.link = 0
				}
				s.page.has_link_id = false
				s.page.phase = .Finding_Path
				s.page.phase_deadline = time.tick_add(
					now,
					time.Duration(constants.PATH_FIND_TIMEOUT_SEC) * time.Second,
				)
				path_request_refresh(s, s.page.node)
				page_set_status(s, "link timeout, re-finding path...")
				return
			}
			page_fail(s, "link timeout")
		}
	case .Sending_Request:
		timeout_ms := i32(constants.PAGE_TIMEOUT_SEC * 1000)
		remaining := time.tick_diff(now, s.page.deadline)
		if remaining > 0 {
			timeout_ms = i32(remaining / time.Millisecond)
			if timeout_ms < 1000 {
				timeout_ms = 1000
			}
		}
		rid, rerr := rns.link_request(s.node, s.page.link, s.page.path, s.page.request_data, timeout_ms)
		if rerr != .Ok {
			page_fail(s, "page request failed")
			return
		}
		s.page.request_id = rid
		s.page.has_request_id = true
		s.page.phase = .Waiting_Response
		page_set_status(s, fmt.tprintf("waiting for %s...", s.page.path))
	case .Waiting_Response:
	}
}
