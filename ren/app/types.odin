// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Core App struct tabs and shared app types.
*/

package app

import "core:time"

import "ren:constants"
import "ren:micron"
import "ren:net"
import "ren:store"
import "ren:ui"

Tab :: enum {
	Conversations,
	Network,
	Page,
	Interfaces,
	Compose,
	Config,
	Guide,
}

Net_View :: enum {
	Lxmf,
	Nomad,
	Propagation,
}

TAB_COUNT :: 7
TAB_LABELS := [TAB_COUNT]string{
	"Conversations",
	"Network",
	"Page",
	"Interfaces",
	"Compose",
	"Config",
	"Guide",
}

NET_VIEW_LABELS := [3]string{"LXMF", "NomadNet", "Propagation"}


Config_Row :: enum {
	Name,
	Auto_Announce,
	Interval,
	Color,
	Theme,
	Mouse,
	Obfuscate_Hops,
	Download_Dir,
	Restart,
	Save,
	Count,
}

STATUS_HOLD :: constants.STATUS_HOLD_SEC * time.Second

App :: struct {
	loop:            ui.Loop,
	cfg:             store.Config,
	session:         net.Session,
	directory:       store.Directory,
	conversations:   store.Conversations,
	tab:             Tab,
	conv_list:       ui.List_State,
	net_list:        ui.List_State,
	net_peer_idx:    [dynamic]int,
	iface_scroll:    int,
	config_list:     ui.List_State,
	compose_to:      ui.Input_State,
	compose_body:    ui.Input_State,
	compose_focus:   int,
	config_edit:     ui.Input_State,
	config_editing:  bool,
	url_edit:        ui.Input_State,
	url_editing:     bool,
	net_search:      ui.Input_State,
	net_searching:   bool,
	conv_search:     ui.Input_State,
	conv_searching:  bool,
	net_view:        Net_View,
	ui_dirty:        bool,
	guide_scroll:    int,
	page_doc:        micron.Doc,
	page_hits:       [dynamic]micron.Link_Hit,
	page_link_focus: int,
	page_source:     string,
	page_path:       string,
	page_node:       [store.HASH_LEN]u8,
	page_has_node:   bool,
	page_view_raw:   bool,
	page_scroll:     int,
	page_error:      string,
	page_form:       [dynamic]Page_Form_Input,
	page_field_focus: int,
	msg_scroll:      int,
	status_left:     string,
	status_right:    string,
	status_left_buf: [256]u8,
	status_hold:     [192]u8,
	status_hold_len: int,
	status_until:    time.Tick,
	online:          bool,
	term_w:          int,
	term_h:          int,
	stderr_redir:    ui.Stderr_Redirect,
	list_rect:       ui.Rect,
	detail_rect:     ui.Rect,
	tab_rect:        ui.Rect,
	lxmf_addr_rect:  ui.Rect,
	identity_rect:   ui.Rect,
	last_announces:  int,
	recv_count:      int,
	ifaces:          [dynamic]Iface_View,
	net_dir_rev:         u64,
	net_filter_tick:     u64,
	net_filter_applied:  u64,
	poll_ticks:          u64,
}

// How many consecutive polls an interface may be missing before removal.
IFACE_MISS_LIMIT :: 3

Iface_View :: struct {
	name:       string,
	type_n:     string,
	online:     bool,
	enabled:    bool,
	rx:         u64,
	tx:         u64,
	rx_packets: u64,
	tx_packets: u64,
	miss_count: int,
}

Page_Form_Input :: struct {
	kind:    micron.Field_Kind,
	name:    string,
	value:   string,
	label:   string,
	checked: bool,
	width:   int,
	masked:  bool,
}
