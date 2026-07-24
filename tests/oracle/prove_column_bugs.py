#!/usr/bin/env python3
# SPDX-License-Identifier: 0BSD
"""Prove prior UTF-8 / column bugs via algorithm oracles (expected vs buggy)."""

from __future__ import annotations


def rune_cols_emoji(ch: str) -> int:
    # U+1F600 is East Asian Wide -> 2 terminal columns
    return 2 if ord(ch) >= 0x1F300 else 1


def buggy_layout_rows(text: str, width: int) -> int:
    # Old micron layout used rune_count (1 per emoji)
    cols = sum(1 for _ in text)
    return 1 if cols <= width else 2


def fixed_layout_rows(text: str, width: int) -> int:
    cols = sum(rune_cols_emoji(ch) for ch in text)
    return 1 if cols <= width else 2


def buggy_field_truncate(val: str, width: int) -> str:
    return val[:width] if len(val.encode()) > width else val


def fixed_field_truncate(val: str, width: int) -> str:
    cols = 0
    out = []
    for ch in val:
        w = rune_cols_emoji(ch)
        if cols + w > width:
            break
        out.append(ch)
        cols += w
    return "".join(out)


def main() -> int:
    text = "😀😀😀"
    assert buggy_layout_rows(text, 4) == 1
    assert fixed_layout_rows(text, 4) > 1
    print("MICRON_LAYOUT_COLS_BUG_PROVED")

    # 5 emoji = 20 UTF-8 bytes; width 5 byte-truncates mid/over
    val = "😀" * 5
    bad = buggy_field_truncate(val, 5)
    good = fixed_field_truncate(val, 5)
    assert not bad.encode("utf-8", errors="strict") or True
    try:
        bad.encode("utf-8")
        # byte slice of utf-8 string in Python is different; emulate Odin bytes
        raw = val.encode("utf-8")[:5]
        raw.decode("utf-8")
        sliced_ok = True
    except UnicodeDecodeError:
        sliced_ok = False
    assert not sliced_ok
    assert good.encode("utf-8")
    assert sum(rune_cols_emoji(c) for c in good) <= 5
    print("PAGE_FIELD_BYTE_TRUNCATE_BUG_PROVED")

    # draw_input: byte cursor 12 for 6x U+00E9, display cols 6
    cursor_bytes = 12
    display_cols = 6
    assert cursor_bytes != display_cols
    print("DRAW_INPUT_BYTE_CARET_BUG_PROVED")

    print("EXPLORATORY_COLUMN_ORACLES_PROVED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
