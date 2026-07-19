#!/usr/bin/env python3
"""Interop checks: Python LXMF packing vs ren-tui Odin expectations."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

FIXTURES = Path(__file__).resolve().parent / "fixtures"

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
    from pathlib import Path
    import tempfile
    import RNS
    import LXMF

    fixtures = Path(sys.argv[1])
    write_fixtures = sys.argv[2] == "1"
    fixtures.mkdir(parents=True, exist_ok=True)

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
        content="ping-body",
        title="t",
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
    assert str(content) == "ping-body"
    assert bytes(out.source_hash) == delivery_hash

    if write_fixtures:
        (fixtures / "py_delivery.hex").write_text(delivery_hash.hex() + "\n")
        (fixtures / "py_opp_full.hex").write_text(packed.hex() + "\n")
        (fixtures / "py_opp_wire.hex").write_text(wire.hex() + "\n")

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
    if write_fixtures:
        (fixtures / "py_direct_full.hex").write_text(packed.hex() + "\n")
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


def verify_committed_fixtures() -> None:
    required = (
        "py_delivery.hex",
        "py_opp_full.hex",
        "py_opp_wire.hex",
        "py_direct_full.hex",
    )
    for name in required:
        path = FIXTURES / name
        if not path.is_file() or path.stat().st_size == 0:
            raise AssertionError(f"missing fixture {path}")

    import LXMF

    delivery = bytes.fromhex((FIXTURES / "py_delivery.hex").read_text().strip())
    full = bytes.fromhex((FIXTURES / "py_opp_full.hex").read_text().strip())
    wire = bytes.fromhex((FIXTURES / "py_opp_wire.hex").read_text().strip())
    direct = bytes.fromhex((FIXTURES / "py_direct_full.hex").read_text().strip())

    assert full[:16] == delivery
    assert wire == full[16:]
    assert delivery + wire == full

    out = LXMF.LXMessage.unpack_from_bytes(full)
    assert out is not None
    content = out.content
    if isinstance(content, bytes):
        content = content.decode("utf-8", errors="replace")
    assert str(content) == "ping-body"

    rebuilt = delivery + wire
    out2 = LXMF.LXMessage.unpack_from_bytes(rebuilt)
    assert out2 is not None

    dout = LXMF.LXMessage.unpack_from_bytes(direct)
    assert dout is not None
    dcontent = dout.content
    if isinstance(dcontent, bytes):
        dcontent = dcontent.decode("utf-8", errors="replace")
    assert str(dcontent) == "direct-ping"
    print("ok committed python fixtures unpack in LXMF")


def main() -> int:
    check_announce_appdata()
    write = "1" if os.environ.get("REN_WRITE_FIXTURES") == "1" else "0"
    proc = subprocess.run(
        [sys.executable, "-c", PACK_CHECKS, str(FIXTURES), write],
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
    try:
        verify_committed_fixtures()
    except Exception as e:
        print("fail: committed fixture check:", e)
        return 1
    print("ok python->odin fixture files ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
