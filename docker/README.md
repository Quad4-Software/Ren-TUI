# Docker

Pinned multi-stage images. Defaults live in `.github/ci.env`.

## Runtime image (glibc)

`Dockerfile` uses Debian bookworm-slim. Rootless UID 1000.

```
docker build -f docker/Dockerfile -t ren-tui .
docker run --rm -it \
  -v "$HOME/.config/ren-tui:/home/ren/.config/ren-tui" \
  -v "$HOME/.reticulum-go:/home/ren/.reticulum-go" \
  ren-tui
```

```
docker run --rm -it ren-tui --version
```

## Export binaries

```
mkdir -p out
docker build -f docker/Dockerfile.build --target export -o type=local,dest=./out .
```

Produces `out/ren-tui`, `out/ren-listen`, `out/librns.so` with `RUNPATH=$ORIGIN`.

Docker images remain **linux/amd64** (glibc default). Multi-OS binaries
(linux arm64/i386/armv6/armv7, macOS, Windows) ship from GitHub Releases via
`.github/workflows/release.yml`, not as GHCR multi-arch tags for every target.

## Alpine / musl

`Dockerfile.alpine` rebuilds a fresh musl `librns.a` from Reticulum-Go
(c-archive stage) then links ren-tui/ren-listen. The in-tree
`vendor/librns/lib-musl/librns.a` is only a fallback and can lag the ABI.

Go cgo librns currently segfaults on musl when entering the ABI so Alpine is not the default runtime image yet.
Makefile still supports `LIBC=musl` for compile checks and future use.

```
docker build -f docker/Dockerfile.alpine --target export -o type=local,dest=./out-musl .
```

## Override pins

```
docker build -f docker/Dockerfile \
  --build-arg DEBIAN_IMAGE=debian@sha256:... \
  --build-arg ODIN_VERSION=dev-2026-07a \
  --build-arg ODIN_LINUX_AMD64_SHA256=... \
  -t ren-tui .
```

## GHCR

CI publishes to `ghcr.io/<owner>/ren-tui` from `.github/ci.env`.
