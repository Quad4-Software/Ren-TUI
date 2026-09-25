#!/usr/bin/env python3
"""Live LXMF roundtrip between a Python LXMRouter and ren's session stack.

Covers both directions, small packets, and payloads large enough to
force a link resource. Isolated localhost TCP, no user reticulum config.
"""

from __future__ import annotations

import hashlib
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
PEER = ROOT / "bin" / "ren-live-peer"

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


def body_hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def wait_path(dest_hash: bytes, timeout: float = 40.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if RNS.Transport.has_path(dest_hash):
            return True
        RNS.Transport.request_path(dest_hash)
        time.sleep(0.25)
    return False


def wait_identity(dest_hash: bytes, timeout: float = 40.0):
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
        sys.stdout.write("ren: " + line)
        sys.stdout.flush()


def wait_line(lines: list[str], prefix: str, timeout: float) -> str:
    deadline = time.time() + timeout
    while time.time() < deadline:
        for line in lines:
            if line.startswith(prefix):
                return line.strip()
        time.sleep(0.05)
    raise AssertionError(f"timed out waiting for {prefix!r}")


def content_bytes(message) -> bytes:
    raw = message.content
    if isinstance(raw, str):
        return raw.encode("utf-8")
    return bytes(raw)


class Inbox:
    def __init__(self) -> None:
        self.items: list[tuple[bytes, str]] = []

    def on_delivery(self, message) -> None:
        self.items.append((content_bytes(message), body_hash(content_bytes(message))))

    def wait_hash(self, digest: str, timeout: float = 45.0) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            for _body, got in self.items:
                if got == digest:
                    return
            time.sleep(0.1)
        seen = [item[1] for item in self.items]
        raise AssertionError(f"python did not receive {digest}, saw {seen}")


def wait_ren_rx(lines: list[str], digest: str, start: int, timeout: float = 45.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        for line in lines[start:]:
            parts = line.strip().split()
            if len(parts) == 3 and parts[0] == "rx" and parts[2] == digest:
                return
            if line.startswith("error "):
                raise AssertionError(line.strip())
        time.sleep(0.05)
    raise AssertionError(f"ren did not print rx for {digest}")


def wait_ren_tx(lines: list[str], start: int, timeout: float = 50.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        for line in lines[start:]:
            text = line.strip()
            if text == "tx ok":
                return
            if text.startswith("tx fail"):
                raise AssertionError(text)
        time.sleep(0.05)
    raise AssertionError("ren send did not finish")


def wait_delivered(message, timeout: float = 45.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if message.state == LXMF.LXMessage.DELIVERED:
            return
        if message.state == LXMF.LXMessage.FAILED:
            raise AssertionError("python message FAILED")
        time.sleep(0.1)
    raise AssertionError(
        f"python state={message.state} progress={getattr(message, 'progress', None)}"
    )


def make_body(label: str, size: int) -> bytes:
    if size <= len(label):
        return label.encode("utf-8")
    raw = bytearray(size)
    prefix = label.encode("utf-8")
    raw[: len(prefix)] = prefix
    for i in range(len(prefix), size):
        raw[i] = (i * 17 + 3) & 0xFF
    return bytes(raw)


def main() -> None:
    if not PEER.is_file():
        raise SystemExit(f"missing {PEER}")

    port = free_port()
    work = Path(tempfile.mkdtemp(prefix="ren-lxmf-live-"))
    py_home = work / "py"
    ren_home = work / "ren"
    py_home.mkdir()
    ren_home.mkdir()
    write_rns_config(py_home / "config", server=True, port=port, name="tcp_server", instance=f"py-live-{port}")
    write_rns_config(ren_home / "config", server=False, port=port, name="tcp_client", instance=f"ren-live-{port}")
    ren_data = ren_home / "data"
    ren_data.mkdir()
    bodies = work / "bodies"
    bodies.mkdir()
    commands = work / "commands"
    commands.write_text("")

    env = os.environ.copy()
    env["HOME"] = str(ren_home)
    env["LD_LIBRARY_PATH"] = str(ROOT / "bin") + (
        ":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else ""
    )

    rns = RNS.Reticulum(str(py_home), loglevel=RNS.LOG_ERROR)
    identity = RNS.Identity()
    identity.to_file(str(py_home / "identity"))
    router = LXMF.LXMRouter(storagepath=str(py_home / "lxmf"))
    inbox = Inbox()
    router.register_delivery_callback(inbox.on_delivery)
    local = router.register_delivery_identity(identity, display_name="py-live")
    router.announce(local.hash)
    py_hash = bytes(local.hash).hex()

    peer = subprocess.Popen(
        [
            str(PEER),
            "-t",
            "240",
            "-c",
            str(ren_home / "config"),
            "--data-dir",
            str(ren_data),
            "--commands",
            str(commands),
        ],
        cwd=str(ROOT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    lines: list[str] = []
    pump = threading.Thread(target=pump_stdout, args=(peer, lines), daemon=True)
    pump.start()

    try:
        delivery_line = wait_line(lines, "delivery ", 30)
        ren_hex = delivery_line.split()[1].strip()
        wait_line(lines, "ready", 15)
        ren_hash = bytes.fromhex(ren_hex)
        if not wait_path(ren_hash, timeout=40):
            raise AssertionError("no path to ren delivery destination")
        peer_id = wait_identity(ren_hash, timeout=40)
        if peer_id is None:
            raise AssertionError("could not recall ren identity")
        dest = RNS.Destination(
            peer_id,
            RNS.Destination.OUT,
            RNS.Destination.SINGLE,
            "lxmf",
            "delivery",
        )
        if bytes(dest.hash) != ren_hash:
            raise AssertionError("destination hash mismatch")

        cases = [
            ("py-small-direct", 24, LXMF.LXMessage.DIRECT, "direct", True),
            ("py-small-opp", 24, LXMF.LXMessage.OPPORTUNISTIC, "opportunistic", False),
            ("py-big-direct", 2048, LXMF.LXMessage.DIRECT, "direct", True),
            ("py-bigger-direct", 32768, LXMF.LXMessage.DIRECT, "direct", True),
            ("ren-small-direct", 24, None, "direct", False),
            ("ren-small-opp", 24, None, "opportunistic", False),
            ("ren-big-direct", 2048, None, "direct", False),
            ("ren-bigger-direct", 32768, None, "direct", False),
            ("ren-oversize-opp", 800, None, "opportunistic", False),
        ]

        for label, size, py_method, ren_method, expect_delivered in cases:
            payload = make_body(label, size)
            digest = body_hash(payload)
            if py_method is not None:
                cursor = len(lines)
                msg = LXMF.LXMessage(
                    destination=dest,
                    source=local,
                    content=payload,
                    title=label,
                    desired_method=py_method,
                )
                router.handle_outbound(msg)
                wait_ren_rx(lines, digest, cursor)
                if expect_delivered:
                    wait_delivered(msg)
                print(f"ok python -> ren {label} ({size} bytes)")
            else:
                path = bodies / f"{label}.bin"
                path.write_bytes(payload)
                cursor = len(lines)
                with commands.open("a", encoding="utf-8") as fh:
                    fh.write(f"send {ren_method} {py_hash} {path}\n")
                    fh.flush()
                wait_ren_tx(lines, cursor)
                inbox.wait_hash(digest)
                print(f"ok ren -> python {label} ({size} bytes)")

        with commands.open("a", encoding="utf-8") as fh:
            fh.write("quit\n")
            fh.flush()
        wait_line(lines, "bye", 15)
        print("ok live lxmf roundtrip")
    finally:
        if peer.poll() is None:
            peer.send_signal(signal.SIGTERM)
            try:
                peer.wait(timeout=5)
            except subprocess.TimeoutExpired:
                peer.kill()
        pump.join(timeout=2)
        shutil.rmtree(work, ignore_errors=True)
        _ = rns


if __name__ == "__main__":
    main()
