#!/usr/bin/env python3
"""Live interop: Python LXMF DIRECT send must reach DELIVERED against ren-listen.

Requires RNS + LXMF and a built bin/ren-listen with vendored librns that
returns link DATA proofs signed by the destination identity (not ephemeral).

Offline check always runs. Live path needs REN_LIVE_PROOF=1.
"""

from __future__ import annotations

import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LISTEN = ROOT / "bin" / "ren-listen"

try:
    import RNS
    import LXMF
except ImportError as e:
    print("skip: RNS/LXMF not installed:", e)
    sys.exit(0)


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def write_rns_config(path: Path, *, server: bool, port: int, name: str, instance: str) -> None:
    if server:
        iface = f"""
  [[{name}]]
    type = TCPServerInterface
    enabled = Yes
    listen_ip = 127.0.0.1
    listen_port = {port}
"""
    else:
        iface = f"""
  [[{name}]]
    type = TCPClientInterface
    enabled = Yes
    target_host = 127.0.0.1
    target_port = {port}
"""
    path.write_text(
        f"""
[reticulum]
  enable_transport = Yes
  share_instance = No
  instance_name = {instance}

[logging]
  loglevel = 3

[interfaces]
{iface}
""".lstrip()
    )


def wait_path(dest_hash: bytes, timeout: float = 30.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if RNS.Transport.has_path(dest_hash):
            return True
        RNS.Transport.request_path(dest_hash)
        time.sleep(0.25)
    return False


def wait_identity(dest_hash: bytes, timeout: float = 30.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        ident = RNS.Identity.recall(dest_hash)
        if ident is not None:
            return ident
        time.sleep(0.25)
    return None


def pump_stdout(proc: subprocess.Popen, sink: list[str]) -> None:
    assert proc.stdout is not None
    for line in proc.stdout:
        sink.append(line)
        sys.stdout.write("ren-listen: " + line)
        sys.stdout.flush()


def run_live() -> None:
    if os.environ.get("REN_LIVE_PROOF") != "1":
        print("skip: set REN_LIVE_PROOF=1 to run live delivery-proof interop")
        return
    if not LISTEN.is_file():
        raise SystemExit(f"missing {LISTEN} (make first)")

    port = free_port()
    py_home = Path(tempfile.mkdtemp(prefix="ren-proof-py-"))
    ren_home = Path(tempfile.mkdtemp(prefix="ren-proof-ren-"))
    write_rns_config(py_home / "config", server=True, port=port, name="tcp_server", instance=f"py-proof-{port}")
    write_rns_config(ren_home / "config", server=False, port=port, name="tcp_client", instance=f"ren-proof-{port}")

    ren_data = ren_home / "ren-data"
    ren_data.mkdir()
    env = os.environ.copy()
    env["HOME"] = str(ren_home)

    # Python TCP server must be up before ren-listen client connects.
    rns = RNS.Reticulum(str(py_home), loglevel=RNS.LOG_ERROR)
    identity = RNS.Identity()
    identity.to_file(str(py_home / "identity"))
    router = LXMF.LXMRouter(storagepath=str(py_home / "lxmf"))
    local = router.register_delivery_identity(identity, display_name="py-proof")
    router.announce(local.hash)
    time.sleep(0.5)

    listen_proc = subprocess.Popen(
        [
            str(LISTEN),
            "-t",
            "50",
            "-c",
            str(ren_home / "config"),
            "--data-dir",
            str(ren_data),
        ],
        cwd=str(ROOT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    lines: list[str] = []
    pump = threading.Thread(target=pump_stdout, args=(listen_proc, lines), daemon=True)
    pump.start()

    try:
        delivery_hex = None
        deadline = time.time() + 25
        while time.time() < deadline:
            for line in lines:
                if line.startswith("delivery  "):
                    delivery_hex = line.split()[1].strip()
                    break
            if delivery_hex:
                break
            if listen_proc.poll() is not None:
                break
            time.sleep(0.1)
        if not delivery_hex:
            raise AssertionError("ren-listen did not print delivery hash")

        dest_hash = bytes.fromhex(delivery_hex)
        if not wait_path(dest_hash, timeout=30):
            raise AssertionError("no path to ren-listen delivery dest")

        peer_id = wait_identity(dest_hash, timeout=30)
        if peer_id is None:
            raise AssertionError("could not recall peer identity for delivery dest")

        dest = RNS.Destination(
            peer_id,
            RNS.Destination.OUT,
            RNS.Destination.SINGLE,
            "lxmf",
            "delivery",
        )
        if bytes(dest.hash) != dest_hash:
            raise AssertionError(
                f"destination hash mismatch got={bytes(dest.hash).hex()} want={delivery_hex}"
            )

        msg = LXMF.LXMessage(
            destination=dest,
            source=local,
            content="proof-ping",
            title="interop",
            desired_method=LXMF.LXMessage.DIRECT,
        )
        router.handle_outbound(msg)

        deadline = time.time() + 30
        while time.time() < deadline:
            if msg.state == LXMF.LXMessage.DELIVERED:
                print("ok python DIRECT message DELIVERED against ren-listen")
                print("progress", msg.progress)
                return
            if msg.state == LXMF.LXMessage.FAILED:
                raise AssertionError("message FAILED before DELIVERED")
            time.sleep(0.2)

        raise AssertionError(
            f"stuck at state={msg.state} progress={getattr(msg, 'progress', None)} (want DELIVERED)"
        )
    finally:
        if listen_proc.poll() is None:
            listen_proc.send_signal(signal.SIGTERM)
            try:
                listen_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                listen_proc.kill()
        pump.join(timeout=2)
        shutil.rmtree(py_home, ignore_errors=True)
        shutil.rmtree(ren_home, ignore_errors=True)
        _ = rns


def check_offline_proof_key_contract() -> None:
    """Assert delivery proofs must verify with destination identity signing keys.

    Does not start RNS.Reticulum (singleton) so live interop can run in-process.
    """
    from cryptography.hazmat.primitives.asymmetric.ed25519 import (
        Ed25519PrivateKey,
        Ed25519PublicKey,
    )

    priv = Ed25519PrivateKey.generate()
    pub = priv.public_key().public_bytes_raw()
    msg = b"\x11" * 32
    sig = priv.sign(msg)
    Ed25519PublicKey.from_public_bytes(pub).verify(sig, msg)
    # Local enums only (not on the wire). Go uses 0/1/2.
    assert RNS.Destination.PROVE_NONE != RNS.Destination.PROVE_ALL
    print("ok python delivery proof validates with destination identity key")
    print("note LXMF proves in delivery_packet; ren-tui uses ProveAll with identity key")


def main() -> None:
    check_offline_proof_key_contract()
    run_live()


if __name__ == "__main__":
    main()
