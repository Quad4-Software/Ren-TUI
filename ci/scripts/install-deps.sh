#!/bin/sh
# Install host packages needed to build and test ren-tui.
# Uses apk on Alpine/musl and apt-get on Debian/Ubuntu.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
LIBC=$("${ROOT}/ci/scripts/detect-libc.sh")

if [ "${LIBC}" = "musl" ] || command -v apk >/dev/null 2>&1; then
	if [ "$(id -u)" -eq 0 ]; then
		apk add --no-cache clang curl ca-certificates make patchelf
	else
		sudo apk add --no-cache clang curl ca-certificates make patchelf
	fi
	exit 0
fi

if command -v apt-get >/dev/null 2>&1; then
	if [ "$(id -u)" -eq 0 ]; then
		apt-get update
		apt-get install -y --no-install-recommends clang curl ca-certificates make patchelf zip git gcc
	else
		sudo apt-get update
		sudo apt-get install -y --no-install-recommends clang curl ca-certificates make patchelf zip git gcc
	fi
	exit 0
fi

echo "no supported package manager (need apk or apt-get)" >&2
exit 1
