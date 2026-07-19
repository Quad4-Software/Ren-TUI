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

### What you download should match what we built

Official release binaries are intended to be built in automation on GitHub, not by hand. Tagged releases should ship:

- Linux archives for supported targets from that tag
- Checksum files (SHA-256) for release assets when the release workflow publishes them

Docker images published to GitHub Container Registry are built in CI with build provenance and an SBOM when the Docker workflow enables those options.

Prefer images referenced by digest (`@sha256:...`) once you trust a given build, not only by a moving tag.

### Practical tips

- Prefer official RNGit, GitHub Releases or GHCR digests for your copy of the app.
- Keep `librns.so` next to portable glibc binaries when using `RUNPATH=$ORIGIN` archives.
- Musl/Alpine builds may compile, but calling into Go cgo `librns` on musl is currently unsafe. Prefer glibc builds and the Debian-based Docker image until that is fixed upstream.
- If something claims to be Ren TUI but does not match published checksums or verification steps, treat it as untrusted.

---

## For security professionals and auditors

### Product controls (high level)

- Terminal UI only. No embedded webview, no plugin host, no in-app browser for clearnet HTTP.
- Wire codec and on-disk conversations use a small custom msgpack/LXMF stack under `ren/lxmf/` with explicit size and depth limits.
- Announce peers are hot-capped in memory with overflow to disk. Page viewing is isolated from the announce stream.
- No telemetry, analytics, or crash-reporting services are included in this tree.

### External network connections

Ren TUI does not open clearnet HTTP(S) by itself for browsing or updates. Outbound reachability is through Reticulum transports you configure (TCP, and other interfaces in your Reticulum config). Peers and destinations are mesh hashes, not hardcoded internet URLs.

Optional local tooling (CI scripts that fetch Odin or Go toolchains, Docker builds that pull base images) runs only in build/CI environments, not in the interactive TUI.

### Build, supply chain, and transparency

- CI workflows under `.github/workflows/` run tests and builds. Fork-friendly pins live in `.github/ci.env`.
- Third-party GitHub Actions should be referenced with pinned full commit SHAs.
- Odin compiler downloads in `ci/scripts/install-odin.sh` are fetched with `curl` and checked with `sha256sum`.
- Docker base images are pinned by digest. See `docker/README.md`.
- POSIX helpers live under `ci/scripts/` to keep CI logic reviewable without opaque third-party installers where practical.
