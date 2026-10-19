#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Clone or update Reticulum-Go for librns builds.
# Prints RNS_ROOT=<path>.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

DEST=${RNS_ROOT:-${ROOT}/.deps/Reticulum-Go}
REPO=${RNS_REPO:-https://github.com/Quad4-Software/Reticulum-Go.git}
REF=${RNS_REF:-v1.4.1}

mkdir -p "$(dirname "${DEST}")"
if [ -d "${DEST}/.git" ]; then
	git -C "${DEST}" fetch --depth 1 origin "${REF}" || true
	git -C "${DEST}" checkout -q FETCH_HEAD 2>/dev/null || git -C "${DEST}" checkout -q "${REF}" || true
else
	if ! git clone --depth 1 --branch "${REF}" "${REPO}" "${DEST}" 2>/dev/null; then
		git clone --depth 1 "${REPO}" "${DEST}"
	fi
fi

echo "RNS_ROOT=${DEST}"
