#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Fetch Reticulum-Go at RNS_REF and build glibc librns into vendor/librns.
# Requires go, gcc/clang, and git on PATH.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
. "${ROOT}/ci/scripts/lib-env.sh"
ci_load_env

eval "$(sh "${ROOT}/ci/scripts/fetch-rns.sh")"
if [ -z "${RNS_ROOT:-}" ] || [ ! -d "${RNS_ROOT}" ]; then
	echo "error: RNS_ROOT missing after fetch-rns" >&2
	exit 1
fi

if ! command -v go >/dev/null 2>&1; then
	echo "error: go is required to build librns (install Go 1.26+)" >&2
	exit 1
fi

echo "building glibc librns from ${RNS_ROOT} (${RNS_REF:-})"
mkdir -p "${RNS_ROOT}/bin"
(
	cd "${RNS_ROOT}"
	if command -v task >/dev/null 2>&1; then
		task build-librns
	else
		CGO_ENABLED=1 go build -buildmode=c-shared -o bin/librns.so ./cmd/librns
		cp -f include/rns.h bin/rns.h
	fi
)

make -C "${ROOT}" vendor-librns RNS_ROOT="${RNS_ROOT}"
echo "RNS_ROOT=${RNS_ROOT}"
