#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Stage a FHS tree with make install for packaging.
# Usage: sh ci/scripts/package-stage.sh /path/to/stage

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
STAGE=${1:-}

if [ -z "${STAGE}" ]; then
	echo "usage: $0 STAGE_DIR" >&2
	exit 2
fi

rm -rf "${STAGE}"
mkdir -p "${STAGE}"

# glibc packages only (musl + Go cgo librns is not a supported runtime).
make -C "${ROOT}" install DESTDIR="${STAGE}" PREFIX=/usr LIBC=glibc

install -d "${STAGE}/usr/share/doc/ren-tui"
install -m 644 "${ROOT}/LICENSE" "${STAGE}/usr/share/doc/ren-tui/LICENSE"
install -m 644 "${ROOT}/README.md" "${STAGE}/usr/share/doc/ren-tui/README.md"
install -m 644 "${ROOT}/CHANGELOG.md" "${STAGE}/usr/share/doc/ren-tui/CHANGELOG.md"

echo "${STAGE}"
