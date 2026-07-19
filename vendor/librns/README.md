# Vendored librns (Reticulum-Go C ABI)

Contents:

- `lib/librns.so` host Linux shared library (glibc amd64 default)
- `lib-musl/librns.a` optional musl static archive
- `lib/<os>/<arch>/` optional multi-arch outputs from CI / `make cross`
- `include/rns.h` C header
- `odin/rns/` Odin bindings (`collection:rns`)

Rebuild host library from an external Reticulum-Go tree:

```
make vendor-librns RNS_ROOT=/path/to/Reticulum-Go
```

Cross / multi-OS builds (also rebuilds matching librns when `RNS_ROOT` is set):

```
make cross TARGET=windows-amd64 RNS_ROOT=/path/to/Reticulum-Go
make cross TARGET=linux-arm64 RNS_ROOT=/path/to/Reticulum-Go
make cross TARGET=linux-i386 RNS_ROOT=/path/to/Reticulum-Go
```

Release CI builds per-target librns with Zig (Windows / 32-bit Linux) or native
toolchains (linux-arm64, macOS) rather than committing every shared library blob.
