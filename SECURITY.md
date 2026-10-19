# Security Policy

## Reporting a vulnerability

If you believe you have found a security vulnerability in Ren TUI, please report it privately so it can be fixed before wider disclosure.

Preferred contact (in order):

1. LXMF: `f489752fbef161c64d65e385a4e9fc74`

Include enough detail to reproduce or understand the issue (what version or build you used, what you expected, what happened). Do not open a public issue for unfixed vulnerabilities.

Not security (legal, licensing, general questions): see [`LEGAL.md`](LEGAL.md).

---

Ren TUI is an early terminal LXMF client. Treat it as experimental. Do not rely on it for sensitive messaging until you have reviewed the code and threat model for your own use.

It is meant to run on systems and networks you trust (for example your own machine, a LAN, or a VPN you control).

### Trust boundaries

- The TUI talks to Reticulum through vendored `librns`. Mesh peers, interfaces, and destinations come from your Reticulum config (defaults prefer `~/.reticulum-go/config`).
- Application config and conversations live under `~/.config/ren-tui/` as plaintext INI and msgpack. Protect that directory like any other local message store.
- There is no remote admin API and no built-in cloud sync. Risk is mainly local compromise, malicious mesh peers, and bugs in pack/unpack or UI handling of untrusted content.
- Micron pages and announce streams are untrusted input. Treat remote content as hostile until proven otherwise.

### Source builds only

There are no official binaries. Build from source with `make ensure-librns && make`, and pin your clone to a commit you trust (or the rngit remote listed in the README).

### Practical tips

- Prefer the official RNGit remote for your copy of the app.
- Keep `librns.so` next to portable glibc binaries when using `RUNPATH=$ORIGIN` builds.
- Musl/Alpine builds may compile, but calling into Go cgo `librns` on musl is currently unsafe. Prefer glibc builds until that is fixed upstream.
- If something claims to be Ren TUI but is not built from source you can audit, treat it as untrusted.

---

## For security professionals and auditors

### Product controls (high level)

- Terminal UI only. No embedded webview, no plugin host, no in-app browser for clearnet HTTP.
- Wire codec and on-disk conversations use a small custom msgpack/LXMF stack under `ren/lxmf/` with explicit size and depth limits.
- Announce peers are hot-capped in memory with overflow to disk. Page viewing is isolated from the announce stream.
- No telemetry, analytics, or crash-reporting services are included in this tree.

### External network connections

Ren TUI does not open clearnet HTTP(S) by itself for browsing or updates. Outbound reachability is through Reticulum transports you configure (TCP, and other interfaces in your Reticulum config). Peers and destinations are mesh hashes, not hardcoded internet URLs.

Optional local tooling (the `scripts/` helpers that clone Reticulum-Go and build `librns`) runs at build time only, not in the interactive TUI.

### Build, supply chain, and transparency

- `make ensure-librns` clones Reticulum-Go at the pinned `RNS_REF` and builds `librns` locally; override `RNS_REF` / `RNS_REPO` if you audit your own fork.
- POSIX helpers live under `scripts/` to keep build logic reviewable without opaque third-party installers where practical.
