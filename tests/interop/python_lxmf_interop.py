#!/usr/bin/env python3
"""Interop checks: Python LXMF packing vs ren-tui Odin expectations."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

try:
    import RNS
    import LXMF
except ImportError as e:
    print("skip: RNS/LXMF not installed:", e)
    sys.exit(0)


def main() -> int:
    storage = Path(tempfile.mkdtemp(prefix="ren-lxmf-"))
    identity_path = storage / "identity"
    rns = RNS.Reticulum(str(storage), loglevel=RNS.LOG_NONE)

    identity = RNS.Identity()
    identity.to_file(str(identity_path))

    dest = RNS.Destination(
        identity,
        RNS.Destination.IN,
        RNS.Destination.SINGLE,
        "lxmf",
        "delivery",
    )
    delivery_hash = bytes(dest.hash)
    assert len(delivery_hash) == 16

    msg = LXMF.LXMessage(
        destination=dest,
        source=dest,
        content="interop-ping",
        title="",
        desired_method=LXMF.LXMessage.OPPORTUNISTIC,
    )
    msg.pack()
    packed = bytes(msg.packed)
    assert packed[:16] == delivery_hash
    assert packed[16:32] == delivery_hash
    wire = packed[16:]
    rebuilt = delivery_hash + wire
    assert rebuilt == packed

    out = LXMF.LXMessage.unpack_from_bytes(rebuilt)
    assert out is not None
    content = out.content
    if isinstance(content, bytes):
        content = content.decode("utf-8", errors="replace")
    assert str(content) == "interop-ping"
    assert bytes(out.source_hash) == delivery_hash

    print("ok python lxmf opportunistic roundtrip")
    print("delivery_hash", delivery_hash.hex())
    print("packed_len", len(packed))
    print("wire_len", len(wire))
    _ = rns
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
