# librns (Reticulum-Go C ABI)

Git tracks only the ABI surface:

- `include/rns.h` C header
- `odin/rns/` Odin bindings (`collection:rns`)

Shared libraries under `lib/` and `lib-musl/` are build artifacts (gitignored).

Build glibc `librns.so` from the pinned `RNS_REF` in `.github/ci.env`:

```
make ensure-librns
```

Or from an existing Reticulum-Go tree:

```
make vendor-librns RNS_ROOT=/path/to/Reticulum-Go
```

On hosts newer than glibc 2.35, build with Zig so Ubuntu 22.04 / Debian bookworm can still link:

```
CC='zig cc -target x86_64-linux-gnu.2.35' make ensure-librns
```

Rebuild the musl static archive (needs Go + musl libc/headers):

```
make vendor-librns-musl
# or: RNS_ROOT=/path/to/Reticulum-Go make vendor-librns-musl
```

Cross / multi-OS builds (also rebuilds matching librns when `RNS_ROOT` is set):

```
make cross TARGET=windows-amd64 RNS_ROOT=/path/to/Reticulum-Go
make cross TARGET=linux-arm64 RNS_ROOT=/path/to/Reticulum-Go
make cross TARGET=linux-i386 RNS_ROOT=/path/to/Reticulum-Go
```

CI and Docker build librns from `RNS_REF` rather than committing library blobs.
