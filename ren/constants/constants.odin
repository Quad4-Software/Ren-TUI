// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Shared app names paths timeouts and size limits.
*/

package constants

// App identity
APP_NAME :: "ren-tui"
VERSION :: "0.2.0"

// Config directory under $HOME/.config
CONFIG_DIR_NAME :: "ren-tui"
IDENTITY_FILE :: "identity"
CONFIG_FILE :: "config"
LIBRNS_LOG_FILE :: "librns.log"
DAEMON_PID_FILE :: "ren-tui.pid"
DAEMON_LOG_FILE :: "daemon.log"

CONVERSATIONS_DIR :: "conversations"
DOWNLOADS_DIR :: "pages"
MESSAGES_FILE :: "messages.msgpack"
PEERS_FILE :: "peers.msgpack"
RNS_LOCAL_DIR :: "rns"

// Directory / announce stream caps (hot RAM, cold on disk)
PEERS_HOT_MAX :: 256
PEERS_SPILL_MAX :: 2048

// On-disk conversation msgpack schema version (2 adds custom_name)
CONVERSATIONS_SCHEMA_VERSION :: 2

// Defaults
DEFAULT_DISPLAY_NAME :: "Anonymous"
DEFAULT_COLOR_MODE :: "auto"
DEFAULT_THEME :: "field"
DEFAULT_MOUSE :: true
DEFAULT_AUTO_ANNOUNCE :: true
DEFAULT_ANNOUNCE_INTERVAL_SEC :: 360
MIN_ANNOUNCE_INTERVAL_SEC :: 30

// Timeouts (seconds)
STATUS_HOLD_SEC :: 8
LINK_TIMEOUT_SEC :: 30
PAGE_TIMEOUT_SEC :: 90
LISTEN_DEFAULT_SEC :: 30

// NomadNet page fetch / render guards
DEFAULT_PAGE_PATH :: "/page/index.mu"
PAGE_MAX_BYTES :: 256 * 1024
PAGE_MAX_LINES :: 2000
PAGE_MAX_LINE_LEN :: 512
FILE_MAX_BYTES :: 16 * 1024 * 1024

// Path finder: keep recent destinations hot for link open
PATH_CACHE_MAX :: 15
PATH_TTL_SEC :: 90
PATH_FIND_TIMEOUT_SEC :: 45
PATH_RETRY_SEC :: 3
PATH_TABLE_CAP :: 512

// Environment
ENV_RNS_CONFIG :: "REN_RNS_CONFIG"
ENV_UI :: "REN_UI"
ENV_KEEP_STDERR :: "REN_KEEP_STDERR"

// Preferred RNS config path segments under $HOME (checked in order)
RNS_CONFIG_GO :: ".reticulum-go/config"
RNS_CONFIG_PY :: ".reticulum/config"
