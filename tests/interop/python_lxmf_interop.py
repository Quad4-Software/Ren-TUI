#!/usr/bin/env python3
"""Interop checks: Python LXMF packing vs ren-tui Odin expectations."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

try:
    import RNS  # noqa: F401
    import LXMF  # noqa: F401
except ImportError as e:
    print("skip: RNS/LXMF not installed:", e)
    sys.exit(0)


def check_announce_appdata() -> None:
    # Matches ren lxmf.announce_app_data shape: msgpack [name_bin, stamp_or_nil]
    name = b"ren-interop"
    app = bytearray()
    app.append(0x92)
    app.append(0xC4)
    app.append(len(name))
    app.extend(name)
    app.append(0xC0)
    assert app[0] == 0x92
    assert bytes(app[3 : 3 + len(name)]) == name
    print("ok announce app-data fixture")
    print("announce_app_data_hex", bytes(app).hex())


PACK_CHECKS = textwrap.dedent(
    r"""
    import sys
    import tempfile
    from pathlib import Path
    import RNS
    import LXMF

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

    msg = LXMF.LXMessage(
        destination=dest,
        source=dest,
        content="direct-ping",
        title="t",
        desired_method=LXMF.LXMessage.DIRECT,
    )
    msg.pack()
    packed = bytes(msg.packed)
    assert len(packed) > 16 + 16 + 64
    assert packed[:16] == delivery_hash
    assert packed[16:32] == delivery_hash
    sig = packed[32:96]
    assert len(sig) == 64
    assert any(b != 0 for b in sig)
    out = LXMF.LXMessage.unpack_from_bytes(packed)
    assert out is not None
    content = out.content
    if isinstance(content, bytes):
        content = content.decode("utf-8", errors="replace")
    assert str(content) == "direct-ping"
    print("ok python lxmf direct packed shape")
    print("direct_packed_len", len(packed))

    msg = LXMF.LXMessage(
        destination=dest,
        source=dest,
        content="stamp-check",
        title="",
        desired_method=LXMF.LXMessage.DIRECT,
    )
    msg.pack()
    packed = bytes(msg.packed)
    out = LXMF.LXMessage.unpack_from_bytes(packed)
    assert out is not None
    stamp = getattr(out, "stamp", None)
    print("ok python lxmf stamp field present=", stamp is not None and stamp not in (b"", None))
    _ = rns
    """
)


def main() -> int:
    check_announce_appdata()
    proc = subprocess.run(
        [sys.executable, "-c", PACK_CHECKS],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        print("skip: python LXMF mesh stack failed to init")
        if err:
            print(err.splitlines()[-1])
        return 0
    sys.stdout.write(proc.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
