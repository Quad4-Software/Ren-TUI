# Multi-stage Debian slim runtime (glibc).
# Alpine/musl images are blocked until Go cgo librns runs on musl (see docker/README.md).
# Builds librns from RNS_REF (not committed in git).

ARG DEBIAN_IMAGE=debian@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818
ARG GOLANG_IMAGE=golang:1.26-bookworm
ARG RNS_REPO=https://github.com/Quad4-Software/Reticulum-Go.git
ARG RNS_REF=v1.1.0

FROM ${GOLANG_IMAGE} AS librns
ARG RNS_REPO
ARG RNS_REF

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates git gcc libc6-dev \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /rns
RUN git clone --depth 1 --branch "${RNS_REF}" "${RNS_REPO}" . \
	|| git clone --depth 1 "${RNS_REPO}" .

RUN mkdir -p /out \
	&& CGO_ENABLED=1 go build -mod=vendor -buildmode=c-shared -o /out/librns.so ./cmd/librns \
	&& cp include/rns.h /out/rns.h

FROM ${DEBIAN_IMAGE} AS builder

ARG ODIN_VERSION=dev-2026-08
ARG ODIN_LINUX_AMD64_SHA256=d858c0a182bb28d7b04b04dbb8aed592a9c96c84e4400ee917c74b45848a4d87

ENV DEBIAN_FRONTEND=noninteractive \
	ODIN_VERSION=${ODIN_VERSION} \
	ODIN_LINUX_AMD64_SHA256=${ODIN_LINUX_AMD64_SHA256} \
	LIBC=glibc

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		clang \
		curl \
		make \
		patchelf \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

COPY --from=librns /out/librns.so vendor/librns/lib/librns.so
COPY --from=librns /out/rns.h vendor/librns/include/rns.h

RUN sh ci/scripts/install-odin.sh \
	&& make install PREFIX=/usr/local DESTDIR=/out RPATH=/usr/local/lib/ren-tui LIBC=glibc

FROM ${DEBIAN_IMAGE} AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates \
	&& rm -rf /var/lib/apt/lists/* \
	&& groupadd --gid 1000 ren \
	&& useradd --uid 1000 --gid 1000 --create-home --home-dir /home/ren --shell /usr/sbin/nologin ren \
	&& mkdir -p /home/ren/.config/ren-tui /home/ren/.reticulum-go \
	&& chown -R ren:ren /home/ren

COPY --from=builder /out/usr/local/bin/ren-tui /usr/local/bin/ren-tui
COPY --from=builder /out/usr/local/bin/ren-listen /usr/local/bin/ren-listen
COPY --from=builder /out/usr/local/lib/ren-tui/librns.so /usr/local/lib/ren-tui/librns.so

USER ren
WORKDIR /home/ren

ENV HOME=/home/ren \
	TERM=xterm-256color \
	LD_LIBRARY_PATH=/usr/local/lib/ren-tui

VOLUME ["/home/ren/.config/ren-tui", "/home/ren/.reticulum-go"]

ENTRYPOINT ["ren-tui"]
