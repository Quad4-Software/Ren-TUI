#!/bin/sh
# Smoke-check built binaries.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "${ROOT}"

LIBC=$("${ROOT}/ci/scripts/detect-libc.sh")

test -x bin/ren-tui
test -x bin/ren-listen

if [ "${LIBC}" != "musl" ]; then
	test -f bin/librns.so
fi

./bin/ren-tui --version
./bin/ren-listen --version
./bin/ren-tui --help >/dev/null
./bin/ren-listen --help >/dev/null

echo "smoke ok"
