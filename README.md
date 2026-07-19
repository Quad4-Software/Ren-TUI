# Ren TUI

This project is an early prototype. Behavior may be wrong, incomplete, or unsafe.
Do not rely on it for sensitive messaging. Use at your own risk.

Ren TUI is a terminal LXMF client for [Reticulum](https://reticulum.network/) built with Odin on librns (Reticulum-Go). It aims for NomadNet-like messaging/browsing without urwid or ncurses.

## Design

Custom TUI, not a curses wrapper. Raw terminal I/O, cell buffer, and a small widget set.

Tabs:

| Tab | Role |
|-----|------|
| Conversations | Message threads (persisted under `~/.config/ren-tui/conversations/`) |
| Network | Peers grouped LXMF / NomadNet / Propagation (announce stream) |
| Page | Full-screen NomadNet micron viewer (isolated from announces) |
| Interfaces | Sorted interface cards with status |
| Compose | Send to an LXMF address |
| Config | Name, announce, color mode, theme, restart, addresses |
| Guide | Short in-app notes |

Config is plaintext at `~/.config/ren-tui/config` (NomadNet-style INI). Conversations are stored as msgpack per peer (atomic write), similar in spirit to NomadNet's on-disk approach.

### TUI renderer

Immediate-mode drawing into a retained cell buffer, then a full-frame present.

```
each tick:
  resize buffer if needed
  clear cells
  draw(app) -> widgets write into Buffer
  term_present -> emit ANSI for every cell
  poll input (short timeout)
```

| Piece | Role |
|-------|------|
| `ren/ui/loop.odin` | Frame loop: clear -> draw -> present -> poll |
| `ren/ui/buffer.odin` | Flat `[]Cell` (rune + RGB + style) |
| `ren/ui/widgets.odin` | Stateless list / input / box / tabs painters |
| `ren/ui/term.odin` | Raw mode, alt screen, SGR walk of the buffer |
| `ren/app/` | Tab layouts call widgets each frame |

There is no widget tree and no retained scene graph. App state lives in `App`, the screen is rebuilt from that state every frame (classic immediate-mode UI). The buffer is only retained between draw and present within a tick. `Term.prev` exists but is not used for dirty-cell diff yet, so presents are full redraws.

### LXMF and msgpack

Ren does **not** use a third-party msgpack library or Python LXMF bindings at runtime. Wire codec and conversation storage are a small custom stack under `ren/lxmf/`:

| File | Role |
|------|------|
| `msgpack.odin` | Encoder/decoder subset (nil/bool/int/uint/float/bin/str/array/map) |
| `message.odin` | LXMF pack/unpack, Ed25519 sign/verify |
| `identity.odin` | 64-byte identity material, hashes, sign |
| `stamp.odin` | Workfactor / ticket stamps |
| `announce.odin` | Announce app-data parse |
| `router.odin` | Compose + inbound stamp checks |
| `constants.odin` | Field ids, renderer ids, aspect names |

**Why custom msgpack:** LXMF payloads and on-disk conversations share one codec, size/depth limits are explicit (`MSGPACK_MAX_DEPTH`, `MSGPACK_MAX_ITEMS`, `MSGPACK_MAX_BYTES`), and there is no C/Go msgpack dependency beside librns for the network stack.

**Packed LXMF message (direct):**

```
[ destination_hash 16 ]
[ source_hash      16 ]   # lxmf.delivery hash of sender, not raw identity hash
[ signature        64 ]   # Ed25519 over dest|source|payload_core|message_id
[ msgpack payload       ]
```

**Msgpack payload** is an array:

```
[ timestamp f64,
  title     bin,
  content   bin,
  fields    map[int -> value],
  stamp     bin? ]          # optional 5th element
```

`message_id` is SHA-256 of `dest|source|payload_without_stamp`, truncated/full per LXMF rules in code. Signing covers that id as well. Field maps are encoded with **sorted keys** so pack/unpack/verify hashes stay stable.

**Opportunistic path:** peers may strip the leading destination hash on the wire. Receive path prepends the local delivery hash before `message_unpack(..., .Opportunistic)`.

**Conversations on disk:** per-peer msgpack under `~/.config/ren-tui/conversations/<peerhex>/messages.msgpack` (atomic `.tmp` + rename), using the same writer/reader.

Schema version `CONVERSATIONS_SCHEMA_VERSION` (currently 1) is the first array element on write. Readers still accept the older 4-element layout without a version field.

Supported msgpack subset for wire and storage: nil, bool, int, uint, float, bin, str, array, map, with explicit depth and size caps in `ren/lxmf/msgpack.odin`.

Interop with Python RNS/LXMF is checked in `tests/interop/` (optional if those packages are installed). Covers opportunistic and direct packed shapes, stamp presence, and an announce app-data fixture.

### Theme and colors

Presets under `[ui] theme = ...`:

- `field` (default)
- `slate`
- `amber`
- `mono`

Cycle Theme in the Config tab, or set it in the config file. Optional `[theme]` section overrides any slot with `#RRGGBB` hex:

```
[ui]
color = auto
theme = field
mouse = yes

[theme]
accent = #c4783a
bg = #0c1218
fg = #d8d0c0
```

Slots: `bg`, `fg`, `muted`, `border`, `accent`, `accent_dim`, `highlight_bg`, `highlight_fg`, `warn`, `ok`, `error`, `title`, `status_bg`, `status_fg`, `input_bg`, `tab_active`, `tab_idle`.

`color` / `REN_UI` still selects terminal color capability (`auto` / `256` / `full` / `compat` / `dumb`). Theme picks the RGB palette painted into that capability.

## Binaries

Odin emits **one ELF executable per target** (`ren-tui`, `ren-listen`). That is a single file, but it is **not fully static**.

Runtime needs:

- vendored `librns.so` (copied to `bin/` on build, rpath points at `bin/`)
- system `libc` / `libm` (and usually `libresolv`)

`vendor/librns/` ships the shared library, C header, and Odin bindings. Refresh with Make:

```
make vendor-librns RNS_ROOT=/path/to/Reticulum-Go
```

(That target builds librns in the upstream tree, then copies artifacts here.)

## Current Supported Platforms

| OS | Arch | Libc / notes | Status |
|----|------|--------------|--------|
| Linux | x86_64 (amd64) | glibc | Supported (`make`, Docker, releases) |
| Linux | x86_64 (amd64) | musl | Compiles (`LIBC=musl`) Go cgo runtime blocked |
| Linux | aarch64 (arm64) | glibc | Release matrix (`ubuntu-24.04-arm`) |
| Linux | i386 | glibc | Release matrix (Zig cross) |
| Linux | armv7 | glibc hard-float | Release matrix (Zig cross) |
| Linux | armv6 | glibc | Experimental release matrix (Zig cross) |
| macOS | arm64 | system | Release matrix (`macos-15`) |
| macOS | amd64 | system | Release matrix (`macos-15-intel`) |
| Windows | amd64 | MinGW via Zig | Zig-cross from Linux + `windows-2025` smoke |

Config directory defaults:

- Unix / macOS: `~/.config/ren-tui`
- Windows: `%APPDATA%\ren-tui`

Cross-compile (needs Odin, Zig, and `RNS_ROOT` for librns):

```
make cross TARGET=windows-amd64 RNS_ROOT=/path/to/Reticulum-Go
make cross TARGET=linux-i386 RNS_ROOT=/path/to/Reticulum-Go
make cross TARGET=linux-armv7 RNS_ROOT=/path/to/Reticulum-Go
```

Set `LIBC=glibc` or `LIBC=musl` to force a library set on host Linux. Default is auto-detect.
CI covers Ubuntu 22.04/24.04 (glibc) plus an Alpine musl compile check. Multi-OS release archives are produced on tag pushes.

## Requirements

- Odin compiler
- Vendored librns (already in-tree under `vendor/librns`)
- A Reticulum config (defaults prefer `~/.reticulum-go/config`)
- Linux terminal with reasonable Unicode support recommended

## Build

```
make
make help
make test
make run
make install PREFIX=/usr/local
```

Optional:

```
make listen LIVE_SECS=30
man man/ren-tui.1
```

### CLI

```
ren-tui -h | --help
ren-tui -v | -V | --version
ren-tui --paths
ren-tui --config PATH --data-dir PATH -c/--rns-config PATH
ren-tui --reset | --reset-config | --reset-conversations | --reset-identity

ren-listen -h --help -v --version --paths -t SECONDS -c PATH
```

Environment:

- `REN_RNS_CONFIG` override Reticulum config path
- `REN_UI` force `full` / `256` / `compat` / `dumb`
- `NO_COLOR` disable color

## Tests

```
make test                 # all suites below
make test-smoke           # fast gate
make test-unit
make test-property
make test-fuzz
make test-acceptance
make test-e2e
make test-cross-terminal  # caps modes / glyphs / sanitize
make test-mutation        # bit-flips and bad inputs
make test-race            # threaded pack/unpack and theme reads
make test-chaos           # random op storm + depth limits
make test-interop         # Python LXMF (skips if missing)
```

Test Layout:

```
tests/smoke/            quick API/link gate
tests/unit/             focused package checks
tests/property/         encode/decode invariants
tests/fuzz/             seeded random bytes
tests/acceptance/       persistence and wire behaviors
tests/e2e/              multi-step flows without live mesh
tests/cross_terminal/   full/256/compat/dumb capability matrix
tests/mutation/         corrupted messages and codec edges
tests/race/             concurrent pack/unpack
tests/chaos/            randomized op sequences
tests/interop/          Python LXMF opportunistic roundtrip
```

Suites that touch process-global caps/theme run single-threaded.

## Keys

- `1`-`7` or Tab: sections (Page is its own screen)
- Network `l` / `n` / `p`: LXMF / NomadNet / Propagation views
- Network or Conversations `/`: search
- Ctrl+R: announce now
- Ctrl+Q: quit
- Enter: send / open NomadNet node on Page / toggle config
- Network `Enter`: fetch node page onto Page screen
- Page `g`: page URL (`hash:/path` or `/path`)
- Page `s`: toggle rendered vs raw micron source
- Page `[` `]` or PgUp/PgDn: scroll page
- Page Esc: back to Network (or cancel in-progress fetch)
- Esc: cancel in-progress page fetch
- Click Your LXMF Address in Config to copy (OSC 52)

Announce peers are hot-capped (256 in RAM). Overflow goes to `~/.config/ren-tui/peers.msgpack`. Network list rebuilds only on identity/name changes (not hops). TUI redraws only when dirty. Page stays isolated from the announce stream.

## Docker

Debian slim (glibc) images. See [docker/README.md](docker/README.md).

```
docker build -f docker/Dockerfile -t ren-tui .
docker run --rm -it ren-tui --version
```

Alpine musl builds exist as `docker/Dockerfile.alpine` but are not the default runtime yet (Go cgo librns crashes on musl).

## CI

Workflows under `.github/workflows/`. POSIX helpers live in `ci/scripts/` (curl + sha256 for Odin).

| Workflow | Role |
|----------|------|
| `ci.yml` | Matrix tests and glibc builds on Ubuntu 22.04 / 24.04, plus Alpine musl compile check |
| `release.yml` | Tag or manual draft-then-publish (immutable releases) |
| `docker.yml` | Build and push the Debian slim runtime image to GHCR |

Forks change pins in `.github/ci.env`. Actions are pinned to full commit SHAs.

## License

0BSD. Copyright (c) 2026 Quad4.

See [LICENSE](LICENSE). Provided as-is, without warranty of any kind.
