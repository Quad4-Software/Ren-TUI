#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Build a musl-linked librns.a into vendor/librns/lib-musl for Alpine compile checks.
# Requires: go with cgo, musl toolchain (Alpine: go musl-dev), git.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
. "${ROOT}/ci/scripts/lib-env.sh"
ci_load_env 2>/dev/null || true

OUT_DIR=${OUT_DIR:-${ROOT}/vendor/librns/lib-musl}
DEST=${RNS_ROOT:-${ROOT}/.deps/Reticulum-Go}
REPO=${RNS_REPO:-https://github.com/Quad4-Software/Reticulum-Go.git}
REF=${RNS_REF:-dev}

mkdir -p "${OUT_DIR}" "$(dirname "${DEST}")"

if [ -d "${DEST}/.git" ]; then
	git -C "${DEST}" fetch --depth 1 origin "${REF}" || true
	git -C "${DEST}" checkout -q FETCH_HEAD 2>/dev/null || git -C "${DEST}" checkout -q "${REF}" || true
else
	if ! git clone --depth 1 --branch "${REF}" "${REPO}" "${DEST}" 2>/dev/null; then
		git clone --depth 1 "${REPO}" "${DEST}"
	fi
fi

echo "building musl librns.a from ${DEST}"
(
	cd "${DEST}"
	CGO_ENABLED=1 go build -mod=vendor -buildmode=c-archive -o "${OUT_DIR}/librns.a" ./cmd/librns
)
# c-archive also writes a companion .h next to the .a; drop it so only the archive is kept.
rm -f "${OUT_DIR}/librns.h" "${OUT_DIR}/librns.so"
cp -f "${DEST}/include/rns.h" "${ROOT}/vendor/librns/include/rns.h"

if ! nm "${OUT_DIR}/librns.a" 2>/dev/null | grep -q 'T rns_destination_encrypt'; then
	echo "error: librns.a missing rns_destination_encrypt (ABI too old? use RNS_REF=dev)" >&2
	exit 1
fi
if ! nm "${OUT_DIR}/librns.a" 2>/dev/null | grep -q 'T rns_packet_send'; then
	echo "error: librns.a missing rns_packet_send (ABI too old? use RNS_REF=dev)" >&2
	exit 1
fi

echo "wrote ${OUT_DIR}/librns.a"
