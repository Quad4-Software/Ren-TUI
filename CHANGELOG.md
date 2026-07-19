# Changelog

New work goes under the `[draft]` section only. Do not edit `[released]` sections after a tag ships.

## 0.1.3 - 2026-07-19 [draft]

- Fix inbound LXMF from Python clients (opportunistic try-both unpack, refresh conversations on receive)
- Python LXMF fixture interop feeds packed bytes into Odin message_unpack
- Keep Network selection and scroll on the same peer when LXMF NomadNet or propagation announces reorder the list
- Loading panel clips wide names and emojis so the outer box borders stay intact

## 0.1.2 - 2026-07-19 [released]

- Footer shows context keybinds (Page, Conversations, and other tabs)
- Interfaces cards stay stable across partial/empty polls (miss grace, name order)
- Micron form fields (text/check/radio) with Tab focus and link field collect
- Loading panel shows node name when known, full hash below
- Clear fail panel when link/page fetch cannot complete
- Daemon mode with -d/--daemon (headless background session on POSIX)
- Nix flake uses nixos-unstable so Odin is new enough to build

## 0.1.1 - 2026-07-19 [released]

- Cut temp-arena memory growth that could push RSS past 200MB
- Footer shows Ren TUI, hops, and page size
- Unknown hops show as hops=? instead of hops=0
- Page download with d, configurable download directory
- Cancel in-flight page fetch when opening another node
- Interfaces list no longer flickers empty on refresh
- Crash banner with version and terminal hints
- Supported terminals documented in the README
- Chaos and bench suites for browse, conversations, and UI
- Docker and CI link fix for Odin debug/trace on slim images

## 0.1.0 - 2026-07-19 [released]

- First tagged release
