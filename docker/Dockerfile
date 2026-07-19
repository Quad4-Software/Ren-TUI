# Multi-stage Debian slim runtime (glibc).
# Alpine/musl images are blocked until Go cgo librns runs on musl (see docker/README.md).

ARG DEBIAN_IMAGE=debian@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818

FROM ${DEBIAN_IMAGE} AS builder

ARG ODIN_VERSION=dev-2026-07a
ARG ODIN_LINUX_AMD64_SHA256=32a7678abc66f1af7353abb5b0b5da47d94b7e663f6d250df29bc9117e864c10

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
