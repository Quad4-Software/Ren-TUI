# Changelog

## 0.1.2 - 2026-07-19

- Footer shows context keybinds (Page, Conversations, and other tabs)
- Interfaces cards stay stable across partial/empty polls (miss grace, name order)
- Micron form fields (text/check/radio) with Tab focus and link field collect
- Loading panel shows node name when known, full hash below
- Clear fail panel when link/page fetch cannot complete
- Daemon mode with -d/--daemon (headless background session on POSIX)
- Nix flake uses nixos-unstable so Odin is new enough to build

## 0.1.1 - 2026-07-19

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

## 0.1.0 - 2026-07-19

- First tagged release
