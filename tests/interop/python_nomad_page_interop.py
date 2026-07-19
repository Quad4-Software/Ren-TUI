#!/usr/bin/env python3
"""Interop: NomadNet page request payload shape vs ren-tui / librns."""

from __future__ import annotations

import struct
import sys
from pathlib import Path

try:
    import msgpack
except ImportError:
    print("skip: msgpack not installed")
    sys.exit(0)

try:
    import RNS  # noqa: F401
except ImportError as e:
    print("skip: RNS not installed:", e)
    sys.exit(0)


DEST_HASH_LEN = 16


def pack_map_str_str(pairs: dict[str, str]) -> bytes:
    """Msgpack map of UTF-8 strings (matches ren micron.encode_request_data)."""
    items = list(pairs.items())
    n = len(items)
    if n < 16:
        out = bytearray([0x80 | n])
    else:
        out = bytearray([0xDE]) + struct.pack(">H", n)
    for k, v in items:
        kb = k.encode("utf-8")
        vb = v.encode("utf-8")
        for b in (kb, vb):
            if len(b) < 32:
                out.append(0xA0 | len(b))
            else:
                out.append(0xD9)
                out.append(len(b))
            out.extend(b)
    return bytes(out)


def check_dest_hash_len() -> None:
    assert DEST_HASH_LEN == 16
    assert RNS.Reticulum.TRUNCATED_HASHLENGTH // 8 == DEST_HASH_LEN
    print("ok dest hash length", DEST_HASH_LEN)


def check_request_map_keys() -> None:
    # Same keys NomadNet Node.py expects when data is a dict.
    payload = {
        "var_name": "alice",
        "field_user": "bob",
    }
    packed = pack_map_str_str(payload)
    decoded = msgpack.unpackb(packed, raw=False)
    assert isinstance(decoded, dict)
    assert decoded["var_name"] == "alice"
    assert decoded["field_user"] == "bob"
    print("ok request map keys var_/field_")
    print("request_map_hex", packed.hex())


def check_link_request_third_element_is_dict() -> None:
    """
    Link.Request wire shape is msgpack [path, timeout, data].
    If data is already bytes (double-packed), NomadNet sees bytes not dict
    and drops var_/field_. Decode-before-Request must yield a dict third elem.
    """
    path = "/page/index.mu"
    timeout = 30.0
    inner = pack_map_str_str({"var_x": "1", "field_y": "2"})

    # Bug shape: third element is raw msgpack bytes
    buggy = msgpack.packb([path, timeout, inner], use_bin_type=True)
    buggy_arr = msgpack.unpackb(buggy, raw=False)
    assert isinstance(buggy_arr[2], (bytes, bytearray)), "fixture expects bytes third"

    # Fixed shape: decode map then pack once
    decoded_map = msgpack.unpackb(inner, raw=False)
    assert isinstance(decoded_map, dict)
    fixed = msgpack.packb([path, timeout, decoded_map], use_bin_type=True)
    fixed_arr = msgpack.unpackb(fixed, raw=False)
    assert isinstance(fixed_arr[2], dict)
    assert fixed_arr[2]["var_x"] == "1"
    assert fixed_arr[2]["field_y"] == "2"
    print("ok link request third element is dict after decode")
    print("fixed_request_hex", fixed.hex())


def check_empty_payload_is_nil() -> None:
    # Empty page fetch: third element absent / nil, not empty bytes.
    packed = msgpack.packb(["/page/index.mu", 30.0, None], use_bin_type=True)
    arr = msgpack.unpackb(packed, raw=False)
    assert arr[2] is None
    print("ok empty page request payload is nil")


def check_destination_backtick_request_vars() -> None:
    """NomadNet destination form hash:/path`a=1|b=2 → path + var_* map."""
    url = "c1c4d4deec691ad364853ff6c06879ff:/page/read_board.mu`board_name=all|key=anonymous"
    bt = url.find("`")
    assert bt > 0
    base, spec = url[:bt], url[bt + 1 :]
    assert base.endswith("/page/read_board.mu")
    assert "`" not in base
    request_data = {}
    for e in spec.split("|"):
        if "=" in e:
            k, v = e.split("=", 1)
            request_data["var_" + k] = v
    assert request_data == {"var_board_name": "all", "var_key": "anonymous"}
    packed = pack_map_str_str(request_data)
    decoded = msgpack.unpackb(packed, raw=False)
    assert decoded == request_data
    print("ok destination backtick request vars")
    print("cicada_read_board_hex", packed.hex())


def main() -> int:
    check_dest_hash_len()
    check_request_map_keys()
    check_link_request_third_element_is_dict()
    check_empty_payload_is_nil()
    check_destination_backtick_request_vars()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
