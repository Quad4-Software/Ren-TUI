#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Build deb, rpm, and Arch .pkg.tar.zst into dist/pkg.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OUT_DIR=${OUT_DIR:-"${ROOT}/dist/pkg"}
export OUT_DIR
mkdir -p "${OUT_DIR}"

ok=0
fail=0

run_one() {
	name=$1
	script=$2
	if sh "${script}"; then
		ok=$((ok + 1))
	else
		echo "skip/fail: ${name}" >&2
		fail=$((fail + 1))
	fi
}

run_one deb "${ROOT}/ci/scripts/package-deb.sh"
run_one rpm "${ROOT}/ci/scripts/package-rpm.sh"
run_one arch "${ROOT}/ci/scripts/package-arch.sh"

echo "packaged ok=${ok} fail=${fail} -> ${OUT_DIR}"
if [ "${ok}" -eq 0 ]; then
	exit 1
fi
