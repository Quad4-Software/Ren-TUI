# Changelog

New work goes under the `[draft]` section only. Do not edit `[released]` sections after a tag ships.

## 0.2.0 - 2026-07-19 [draft]

- Fix NomadNet links with backtick request vars (hash:/page/x`a=1|b=2) so var_* reaches the node
- Keep last page request vars for URL bar and identify reload
- Fix Conversations open/chat: filtered list indexing, unread clear, reply in-tab, Network LXMF opens conversation
- Persist LXMF NomadNet and propagation peers across reboot via peers.msgpack hydrate/save
- Custom contact names in Conversations (r rename) with announce-name fallback
- NomadNet /file/ downloads with footer filename percent and speed feedback
- Version stamps via compile -define (no sed of tracked version.odin on make)
- Fix inbound LXMF from Python clients (opportunistic try-both unpack, refresh conversations on receive)
- Python LXMF fixture interop feeds packed bytes into Odin message_unpack
- Keep Network selection and scroll on the same peer when LXMF NomadNet or propagation announces reorder the list
- Loading panel clips wide names and emojis so the outer box borders stay intact
- Propagation node support: select from Network > Propagation, show selected node and sync status
- Compose send methods Direct / Opportunistic / Propagate, plus try_propagation_on_send_fail
- librns PacketSend and DestinationEncrypt for opportunistic and propagate delivery
- Expand prop coverage across unit smoke property acceptance e2e chaos mutation oracle and blackbox suites
- Fix prop bugs found by failing tests: case-insensitive send method and NONE, clear stale prop node on bad hex, reject empty propagate ciphertext, do not commit failover wire until encrypt succeeds, ignore sync Request_Response before /get id

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
