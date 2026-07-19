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

// Display columns available for a peer name inside a network list row.
peer_name_cols :: proc(list_w: int) -> int {
	// "> " + spaces + 32 hex + hops/cost trailer
	overhead := 2 + 2 + 32 + 14
	return max(8, list_w - overhead)
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
