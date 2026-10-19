#!/bin/sh
# Detect host libc family. Prints glibc or musl.

set -eu

if [ -n "${LIBC:-}" ] && [ "${LIBC}" != "auto" ]; then
	printf '%s\n' "${LIBC}"
	exit 0
fi

if [ -e /lib/ld-musl-x86_64.so.1 ] || [ -e /lib/ld-musl-aarch64.so.1 ]; then
	printf 'musl\n'
	exit 0
fi

if command -v ldd >/dev/null 2>&1; then
	if ldd --version 2>&1 | grep -qi musl; then
		printf 'musl\n'
		exit 0
	fi
fi

printf 'glibc\n'
