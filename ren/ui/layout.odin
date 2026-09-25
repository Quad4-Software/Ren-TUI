// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Pure layout math for TUI budgets (status, lists, iface cards).
*/

package ui

import "ren:constants"

// Columns left for the right status segment after left text and gaps.
status_right_cols :: proc(total_w, left_cols: int) -> int {
	if total_w <= 0 {
		return 0
	}
	left := max(0, left_cols)
	// margins: 1 left pad + 1 right pad + 1 gap between segments
	return max(0, total_w - 2 - left - 1)
}

// How many peer rows to keep in the network list widget for a given height.
network_list_row_cap :: proc(list_h: int) -> int {
	visible := max(1, list_h)
	cap_n := visible * 6
	if cap_n < 24 {
		cap_n = 24
	}
	if cap_n > constants.PEERS_HOT_MAX {
		cap_n = constants.PEERS_HOT_MAX
	}
	return cap_n
}

// Columns that are not the peer name: cursor prefix, mark, gaps, full hash.
PEER_ROW_CHROME :: 2 + 1 + 1 + 2 + 32 + 1

// Display columns for a peer name so the hash and the trailing text stay on
// the row. extra is the display width of the stamp cost and hops strings.
peer_name_cols_for :: proc(list_w, extra: int) -> int {
	room := list_w - PEER_ROW_CHROME - extra
	if room < 1 {
		return 1
	}
	return room
}

// Worst case used when the row's cost and hops text are not known yet.
// " cost=65535" is 11 columns and "hops=255" is 8.
peer_name_cols :: proc(list_w: int) -> int {
	return peer_name_cols_for(list_w, 11 + 8)
}

// Interface card rows that fit in the interfaces pane.
iface_cards_per_page :: proc(inner_h: int) -> int {
	card_h := 4
	gap := 1
	return max(1, (max(0, inner_h) + gap) / (card_h + gap))
}

// Hot peer RAM budget scaled to terminal size (never above PEERS_HOT_MAX).
peers_hot_cap_for_term :: proc(term_h, term_w: int) -> int {
	rows := max(8, term_h - 4)
	cols := max(40, term_w)
	cap_n := rows * 4 + cols / 8
	if cap_n < 32 {
		cap_n = 32
	}
	if cap_n > constants.PEERS_HOT_MAX {
		cap_n = constants.PEERS_HOT_MAX
	}
	return cap_n
}
