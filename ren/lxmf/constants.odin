// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
LXMF field ids aspects lengths and enums.
*/

package lxmf

HASH_LEN :: 16
SIGNATURE_LEN :: 64
MESSAGE_ID_LEN :: 32
STAMP_LEN :: 32
NAME_HASH_LEN :: 10

APP_NAME :: "lxmf"
ASPECT_DELIVERY :: "delivery"
ASPECT_PROPAGATION :: "propagation"

FIELD_EMBEDDED_LXMS :: 0x01
FIELD_TELEMETRY :: 0x02
FIELD_TELEMETRY_STREAM :: 0x03
FIELD_ICON_APPEARANCE :: 0x04
FIELD_FILE_ATTACHMENTS :: 0x05
FIELD_IMAGE :: 0x06
FIELD_AUDIO :: 0x07
FIELD_THREAD :: 0x08
FIELD_COMMANDS :: 0x09
FIELD_RESULTS :: 0x0A
FIELD_GROUP :: 0x0B
FIELD_TICKET :: 0x0C
FIELD_EVENT :: 0x0D
FIELD_RNR_REFS :: 0x0E
FIELD_RENDERER :: 0x0F
FIELD_CUSTOM_TYPE :: 0xFB
FIELD_CUSTOM_DATA :: 0xFC
FIELD_CUSTOM_META :: 0xFD
FIELD_NON_SPECIFIC :: 0xFE
FIELD_DEBUG :: 0xFF

RENDERER_PLAIN :: 0x00
RENDERER_MICRON :: 0x01
RENDERER_MARKDOWN :: 0x02
RENDERER_BBCODE :: 0x03

Method :: enum u8 {
	Unknown      = 0x00,
	Opportunistic = 0x01,
	Direct       = 0x02,
	Propagated   = 0x03,
	Paper        = 0x05,
}

State :: enum u8 {
	Draft,
	Outbound,
	Sending,
	Sent,
	Delivered,
	Failed,
	Incoming,
}

Unverified_Reason :: enum {
	None,
	Source_Unknown,
	Signature_Invalid,
}
