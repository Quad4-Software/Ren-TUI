// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Full Micron markup parser for display-only NomadNet pages.
Never runs scripts, shell, or external fetches.
*/

package micron

import "core:strings"
import "core:unicode/utf8"

import "ren:constants"

parse :: proc(src: string, allocator := context.allocator) -> Doc {
	return parse_limited(src, constants.PAGE_MAX_LINES, constants.PAGE_MAX_LINE_LEN, allocator)
}

parse_limited :: proc(
	src: string,
	max_lines: int,
	max_line_len: int,
	allocator := context.allocator,
) -> Doc {
	doc: Doc
	doc.lines = make([dynamic]Line, 0, min(64, max(1, max_lines)), allocator)

	pc_fg, pc_bg := parse_header_colors(src)
	dark := true
	def_fg, def_bg := plain_defaults(dark)
	if pc_fg != "" {
		def_fg = pc_fg
		doc.page_fg = strings.clone(pc_fg, allocator)
	}
	if pc_bg != "" {
		def_bg = pc_bg
		doc.page_bg = strings.clone(pc_bg, allocator)
	}

	st := Parse_State{
		fg = def_fg,
		bg = def_bg,
		default_fg = def_fg,
		default_bg = def_bg,
		align = .Left,
		default_align = .Left,
		dark = dark,
	}

	line_count := 0
	truncated := false
	start := 0
	for start <= len(src) {
		next_rel := strings.index_byte(src[start:], '\n')
		line: string
		if next_rel < 0 {
			line = src[start:]
			start = len(src) + 1
		} else {
			next := start + next_rel
			line = src[start:next]
			start = next + 1
		}
		if line_count >= max_lines {
			truncated = true
			break
		}
		if parse_line_into(&doc, line, &st, max_line_len, allocator) {
			line_count += 1
		}
	}
	if st.table_mode {
		flush_table_plain(&doc, &st, max_line_len, allocator)
	}
	if truncated {
		append_text_line(&doc, "[truncated: page too long]", Style{fg = "888"}, .Left, 0, false, allocator)
	}
	delete(st.table_lines)
	return doc
}

parse_header_colors :: proc(markup: string) -> (fg, bg: string) {
	start := 0
	for start <= len(markup) {
		next_rel := strings.index_byte(markup[start:], '\n')
		line: string
		if next_rel < 0 {
			line = markup[start:]
			start = len(markup) + 1
		} else {
			next := start + next_rel
			line = markup[start:next]
			start = next + 1
		}
		t := trim_ascii_spaces(line)
		if t == "" {
			continue
		}
		if !strings.has_prefix(t, "#!") {
			break
		}
		if strings.has_prefix(t, "#!fg=") {
			c := trim_ascii_spaces(t[5:])
			if len(c) == 3 || len(c) == 6 {
				fg = c
			}
			continue
		}
		if strings.has_prefix(t, "#!bg=") {
			c := trim_ascii_spaces(t[5:])
			if len(c) == 3 || len(c) == 6 {
				bg = c
			}
		}
	}
	return
}

// Returns true when a visible line was appended.
parse_line_into :: proc(
	doc: ^Doc,
	line_in: string,
	s: ^Parse_State,
	max_line_len: int,
	allocator := context.allocator,
) -> bool {
	line := line_in
	if len(line) == 0 {
		if s.bg != s.default_bg && s.bg != "default" && micron_color_token(s.bg) {
			append_text_line(doc, "", state_style(s), s.align, s.depth, false, allocator)
			return true
		}
		append_text_line(doc, "", Style{}, s.align, s.depth, false, allocator)
		return true
	}

	if is_literal_toggle_line(line) {
		s.literal = !s.literal
		return false
	}

	pre_escape := false
	if !s.literal {
		if line[0] == '>' && strings.contains(line, "`<") {
			k := 0
			for k < len(line) && line[k] == '>' {
				k += 1
			}
			line = line[k:]
			if len(line) == 0 {
				return parse_line_into(doc, "", s, max_line_len, allocator)
			}
		}
		if line[0] == '\\' {
			line = line[1:]
			pre_escape = true
		} else if line[0] == '#' {
			return false
		} else if len(line) >= 2 && line[0] == '`' && line[1] == 't' {
			if s.table_mode {
				flush_table_plain(doc, s, max_line_len, allocator)
			} else {
				s.table_mode = true
				if s.table_lines == nil {
					s.table_lines = make([dynamic]string, allocator)
				} else {
					clear(&s.table_lines)
				}
			}
			return false
		} else if s.table_mode {
			append(&s.table_lines, strings.clone(line, allocator))
			return false
		} else if len(line) >= 2 && line[0] == '`' && line[1] == '{' {
			return append_partial_line(doc, line[2:], s, allocator)
		} else if line[0] == '<' {
			s.depth = 0
			if len(line) == 1 {
				return false
			}
			return parse_line_into(doc, line[1:], s, max_line_len, allocator)
		} else if line[0] == '>' {
			i := 0
			for i < len(line) && line[i] == '>' {
				i += 1
			}
			s.depth = i
			heading_line := trim_ascii_spaces(line[i:])
			if heading_line == "" {
				return false
			}
			style := heading_style(i, s.dark)
			latched := state_style(s)
			apply_style_to_state(style, s)
			parts := make_output(s, heading_line, false, max_line_len, allocator)
			apply_style_to_state(latched, s)
			if !parts_have_content(parts[:]) {
				spans_destroy(parts[:])
				delete(parts)
				return false
			}
			append_parts_line(doc, parts, .Left, i, true, allocator)
			doc.link_count += count_links(parts[:])
			return true
		} else if line[0] == '-' {
			if len(line) == 1 {
				append_hr_line(doc, s, allocator)
				return true
			}
			_, first_size := utf8.decode_rune_in_string(line)
			r, _ := utf8.decode_rune_in_string(line[first_size:])
			enc, enc_n := utf8.encode_rune(r)
			one := string(enc[:enc_n])
			rep, _ := strings.repeat(one, 64, context.temp_allocator)
			if max_line_len > 0 && len(rep) > max_line_len {
				rep = rep[:max_line_len]
			}
			append_text_line(doc, rep, state_style(s), s.align, s.depth, false, allocator)
			return true
		}
	}

	if s.literal {
		text := line
		if line == "\\`=" {
			text = "`="
		}
		if max_line_len > 0 && len(text) > max_line_len {
			text = text[:max_line_len]
		}
		append_text_line(doc, text, state_style(s), s.align, s.depth, false, allocator)
		return true
	}

	parts := make_output(s, line, pre_escape, max_line_len, allocator)
	if !parts_have_content(parts[:]) {
		spans_destroy(parts[:])
		delete(parts)
		append_text_line(doc, "", state_style(s), s.align, s.depth, false, allocator)
		return true
	}
	doc.link_count += count_links(parts[:])
	append_parts_line(doc, parts, s.align, s.depth, false, allocator)
	return true
}

flush_table_plain :: proc(doc: ^Doc, s: ^Parse_State, max_line_len: int, allocator := context.allocator) {
	for tl in s.table_lines {
		text := tl
		if max_line_len > 0 && len(text) > max_line_len {
			text = text[:max_line_len]
		}
		append_text_line(doc, text, state_style(s), .Left, s.depth, false, allocator)
		delete(tl)
	}
	clear(&s.table_lines)
	s.table_mode = false
}

append_partial_line :: proc(doc: ^Doc, rest: string, s: ^Parse_State, allocator := context.allocator) -> bool {
	before, _, ok := cut_once(rest, '}')
	if !ok || before == "" {
		return false
	}
	parts := strings.split(before, "`", context.temp_allocator)
	if len(parts) > 3 || len(parts) < 1 {
		return false
	}
	url_part := trim_ascii_spaces(parts[0])
	if url_part == "" {
		return false
	}
	url := format_nomadnetwork_url(url_part, allocator)
	label := strings.concatenate({"[partial ", url_part, "]"}, allocator)
	st := clone_style(state_style(s), allocator)
	spans := make([dynamic]Span, 0, 1, allocator)
	append(&spans, Span{kind = .Partial, text = label, url = url, style = st})
	doc.link_count += 1
	append_parts_line(doc, spans, s.align, s.depth, false, allocator)
	return true
}

append_hr_line :: proc(doc: ^Doc, s: ^Parse_State, allocator := context.allocator) {
	st := clone_style(state_style(s), allocator)
	spans := make([dynamic]Span, 0, 1, allocator)
	append(&spans, Span{kind = .HR, text = strings.clone("────────────────────────────────", allocator), style = st})
	line := Line{spans = spans, align = s.align, depth = s.depth, heading = false}
	append(&doc.lines, line)
}

append_text_line :: proc(
	doc: ^Doc,
	text: string,
	style: Style,
	align: Align,
	depth: int,
	heading: bool,
	allocator := context.allocator,
) {
	spans := make([dynamic]Span, 0, 1, allocator)
	append(&spans, Span{
		kind = .Text,
		text = sanitize_text_runes(text, allocator),
		style = clone_style(style, allocator),
	})
	append(&doc.lines, Line{spans = spans, align = align, depth = depth, heading = heading})
}

append_parts_line :: proc(
	doc: ^Doc,
	parts: [dynamic]Span,
	align: Align,
	depth: int,
	heading: bool,
	allocator := context.allocator,
) {
	_ = allocator
	append(&doc.lines, Line{spans = parts, align = align, depth = depth, heading = heading})
}

parts_have_content :: proc(parts: []Span) -> bool {
	for p in parts {
		if p.kind == .Link || p.kind == .Field || p.kind == .Partial || p.kind == .HR {
			return true
		}
		if p.text != "" {
			return true
		}
	}
	return false
}

count_links :: proc(parts: []Span) -> int {
	n := 0
	for p in parts {
		if p.kind == .Link || p.kind == .Partial {
			n += 1
		}
	}
	return n
}

spans_destroy :: proc(parts: []Span) {
	for p in parts {
		if p.text != "" {
			delete(p.text)
		}
		if p.url != "" {
			delete(p.url)
		}
		if p.field_name != "" {
			delete(p.field_name)
		}
		if p.field_value != "" {
			delete(p.field_value)
		}
		if p.field_label != "" {
			delete(p.field_label)
		}
		if p.field_spec != "" {
			delete(p.field_spec)
		}
		style_destroy(p.style)
	}
}

style_destroy :: proc(st: Style) {
	if st.fg != "" {
		delete(st.fg)
	}
	if st.bg != "" {
		delete(st.bg)
	}
}

clone_style :: proc(st: Style, allocator := context.allocator) -> Style {
	return Style{
		fg = strings.clone(st.fg, allocator) if st.fg != "" else "",
		bg = strings.clone(st.bg, allocator) if st.bg != "" else "",
		bold = st.bold,
		underline = st.underline,
		italic = st.italic,
	}
}

backslash_escapes_only_micron_special :: proc(line: string, pos: int) -> bool {
	if pos >= len(line) {
		return false
	}
	switch line[pos] {
	case '`', '\\', '[':
		return true
	}
	return false
}

make_output :: proc(
	s: ^Parse_State,
	line: string,
	pre_escape: bool,
	max_line_len: int,
	allocator := context.allocator,
) -> [dynamic]Span {
	out := make([dynamic]Span, 0, 8, allocator)
	if s.literal {
		text := line
		if line == "\\`=" {
			text = "`="
		}
		if max_line_len > 0 && len(text) > max_line_len {
			text = text[:max_line_len]
		}
		append(&out, Span{
			kind = .Text,
			text = sanitize_text_runes(text, allocator),
			style = clone_style(state_style(s), allocator),
		})
		return out
	}

	if strings.index_byte(line, '`') < 0 && !pre_escape {
		text := line
		if max_line_len > 0 && len(text) > max_line_len {
			text = text[:max_line_len]
		}
		append(&out, Span{
			kind = .Text,
			text = sanitize_text_runes(text, allocator),
			style = clone_style(state_style(s), allocator),
		})
		return out
	}

	part: strings.Builder
	strings.builder_init(&part, allocator = context.temp_allocator)
	mode_text := true
	escape := pre_escape
	skip := 0
	i := 0
	total := 0

	for i < len(line) {
		if max_line_len > 0 && total >= max_line_len {
			break
		}
		if skip > 0 {
			skip -= 1
			i += 1
			continue
		}
		if !mode_text {
			c := line[i]
			if c == '\\' {
				if backslash_escapes_only_micron_special(line, i + 1) {
					mode_text = true
					escape = true
					i += 1
					continue
				}
				strings.write_byte(&part, '\\')
				mode_text = true
				i += 1
				continue
			}
			switch c {
			case '_':
				s.formatting.underline = !s.formatting.underline
			case '!':
				s.formatting.bold = !s.formatting.bold
			case '*':
				s.formatting.italic = !s.formatting.italic
			case 'F':
				if i + 1 < len(line) && line[i + 1] == 'T' && len(line) >= i + 8 {
					s.fg = line[i + 2:i + 8]
					skip = 7
				} else if len(line) >= i + 9 && line[i + 4] == '`' && line[i + 5] == 'F' {
					s.fg_scratch[0] = line[i + 6]
					s.fg_scratch[1] = line[i + 1]
					s.fg_scratch[2] = line[i + 7]
					s.fg_scratch[3] = line[i + 2]
					s.fg_scratch[4] = line[i + 8]
					s.fg_scratch[5] = line[i + 3]
					s.fg = string(s.fg_scratch[:])
					skip = 8
				} else if len(line) >= i + 4 {
					s.fg = line[i + 1:i + 4]
					skip = 3
				}
			case 'f':
				s.fg = s.default_fg
			case 'B':
				flush_text_part(&out, &part, s, allocator)
				if i + 1 < len(line) && line[i + 1] == 'T' && len(line) >= i + 8 {
					s.bg = line[i + 2:i + 8]
					skip = 7
				} else if len(line) >= i + 9 && line[i + 4] == '`' && line[i + 5] == 'B' {
					s.bg_scratch[0] = line[i + 6]
					s.bg_scratch[1] = line[i + 1]
					s.bg_scratch[2] = line[i + 7]
					s.bg_scratch[3] = line[i + 2]
					s.bg_scratch[4] = line[i + 8]
					s.bg_scratch[5] = line[i + 3]
					s.bg = string(s.bg_scratch[:])
					skip = 8
				} else if len(line) >= i + 4 {
					s.bg = line[i + 1:i + 4]
					skip = 3
				}
			case 'b':
				flush_text_part(&out, &part, s, allocator)
				s.bg = s.default_bg
			case '`':
				s.formatting.bold = false
				s.formatting.underline = false
				s.formatting.italic = false
				s.fg = s.default_fg
				s.bg = s.default_bg
				s.align = s.default_align
				mode_text = true
			case 'c':
				s.align = .Center
			case 'l':
				s.align = .Left
			case 'r':
				s.align = .Right
			case 'a':
				s.align = s.default_align
			case '<':
				flush_text_part(&out, &part, s, allocator)
				st := clone_style(state_style(s), allocator)
				sk, span, ok := parse_field(line, i, st, allocator)
				if ok {
					append(&out, span)
					i += sk
					mode_text = true
					continue
				}
				style_destroy(st)
			case '[':
				flush_text_part(&out, &part, s, allocator)
				st := clone_style(state_style(s), allocator)
				sk, span, ok := parse_link(line, i, st, allocator)
				if ok {
					append(&out, span)
					i += sk
					mode_text = true
					continue
				}
				style_destroy(st)
			}
			mode_text = true
			i += 1
			continue
		}

		c := line[i]
		if escape {
			strings.write_byte(&part, c)
			total += 1
			escape = false
			i += 1
			continue
		}
		if c == '\\' {
			if !backslash_escapes_only_micron_special(line, i + 1) {
				strings.write_byte(&part, '\\')
				total += 1
				i += 1
				continue
			}
			escape = true
			i += 1
			continue
		}
		if c == '`' {
			if i + 1 < len(line) && line[i + 1] == '`' {
				flush_text_part(&out, &part, s, allocator)
				s.formatting.bold = false
				s.formatting.underline = false
				s.formatting.italic = false
				s.fg = s.default_fg
				s.bg = s.default_bg
				s.align = s.default_align
				i += 2
				continue
			}
			flush_text_part(&out, &part, s, allocator)
			mode_text = false
			i += 1
			continue
		}
		strings.write_byte(&part, c)
		total += 1
		i += 1
	}
	flush_text_part(&out, &part, s, allocator)
	return out
}

flush_text_part :: proc(out: ^[dynamic]Span, part: ^strings.Builder, s: ^Parse_State, allocator := context.allocator) {
	if strings.builder_len(part^) == 0 {
		return
	}
	raw := strings.to_string(part^)
	append(out, Span{
		kind = .Text,
		text = sanitize_text_runes(raw, allocator),
		style = clone_style(state_style(s), allocator),
	})
	strings.builder_reset(part)
}

doc_destroy :: proc(doc: ^Doc) {
	if doc == nil {
		return
	}
	for &line in doc.lines {
		spans_destroy(line.spans[:])
		delete(line.spans)
	}
	delete(doc.lines)
	delete(doc.page_fg)
	delete(doc.page_bg)
	doc^ = {}
}
