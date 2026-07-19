// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Micron document types for NomadNet-compatible display.
Display-only: no exec scripts or shell.
*/

package micron

Align :: enum {
	Left,
	Center,
	Right,
}

Span_Kind :: enum {
	Text,
	Link,
	Field,
	Partial,
	HR,
}

Field_Kind :: enum {
	None,
	Text,
	Checkbox,
	Radio,
}

Style :: struct {
	fg:        string,
	bg:        string,
	bold:      bool,
	underline: bool,
	italic:    bool,
}

Span :: struct {
	kind:             Span_Kind,
	text:             string,
	url:              string,
	style:            Style,
	field_kind:       Field_Kind,
	field_name:       string,
	field_value:      string,
	field_label:      string,
	field_width:      int,
	field_masked:     bool,
	field_prechecked: bool,
	// Raw link field list (bare names and *) for form collect on activate.
	field_spec:       string,
}

Line :: struct {
	spans:  [dynamic]Span,
	align:  Align,
	depth:  int,
	heading: bool,
}

Doc :: struct {
	lines:     [dynamic]Line,
	page_fg:   string,
	page_bg:   string,
	link_count: int,
}

Link_Hit :: struct {
	line_idx:   int,
	x0:         int,
	x1:         int,
	url:        string,
	field_spec: string,
	field_i:    int,
}

Formatting :: struct {
	bold:      bool,
	underline: bool,
	italic:    bool,
}

Parse_State :: struct {
	literal:       bool,
	depth:         int,
	fg:            string,
	bg:            string,
	default_fg:    string,
	default_bg:    string,
	formatting:    Formatting,
	align:         Align,
	default_align: Align,
	dark:          bool,
	table_mode:    bool,
	table_lines:   [dynamic]string,
	fg_scratch:    [6]u8,
	bg_scratch:    [6]u8,
}

Action_Kind :: enum {
	None,
	Page,
	File,
	Lxmf,
	External,
	Reject,
}

Action :: struct {
	kind:     Action_Kind,
	node:     [16]u8,
	has_node: bool,
	path:     string,
	peer:     [16]u8,
	url:      string,
	reason:   string,
	request:  Request_Data,
}
