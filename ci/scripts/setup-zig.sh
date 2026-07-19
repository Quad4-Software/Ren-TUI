#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Pin Zig for cross builds. Usage: sh ci/scripts/setup-zig.sh [version]

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
. "${ROOT}/ci/scripts/lib-env.sh"
ci_load_env

VERSION=${1:-${ZIG_VERSION:-0.16.0}}
INSTALL_DIR=${ZIG_INSTALL_DIR:-$HOME/.local/zig}
ARCH=$(uname -m)

case "${ARCH}" in
x86_64 | amd64) ASSET_ARCH=x86_64 ;;
aarch64 | arm64) ASSET_ARCH=aarch64 ;;
*)
	echo "unsupported arch: ${ARCH}" >&2
	exit 1
	;;
esac

OS=$(uname -s)
case "${OS}" in
Linux) ASSET="zig-${ASSET_ARCH}-linux-${VERSION}.tar.xz" ;;
Darwin) ASSET="zig-${ASSET_ARCH}-macos-${VERSION}.tar.xz" ;;
*)
	echo "unsupported OS for Zig setup: ${OS}" >&2
	exit 1
	;;
esac

URL="https://ziglang.org/download/${VERSION}/${ASSET}"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT INT TERM HUP

echo "Downloading ${URL}"
curl -fsSL --retry 3 --retry-delay 2 -o "${TMP}/zig.tar.xz" "${URL}"
mkdir -p "${INSTALL_DIR}"
tar -xJf "${TMP}/zig.tar.xz" -C "${TMP}"

FOUND=$(find "${TMP}" -type f -name zig | head -n 1)
if [ -z "${FOUND}" ]; then
	echo "zig binary not found in archive" >&2
	exit 1
fi

SRC_DIR=$(CDPATH= cd -- "$(dirname "${FOUND}")" && pwd)
rm -rf "${INSTALL_DIR}"
mkdir -p "$(dirname "${INSTALL_DIR}")"
cp -a "${SRC_DIR}" "${INSTALL_DIR}"

BIN_DIR=${HOME}/.local/bin
mkdir -p "${BIN_DIR}"
ln -sfn "${INSTALL_DIR}/zig" "${BIN_DIR}/zig"

if [ -n "${GITHUB_PATH:-}" ]; then
	echo "${BIN_DIR}" >>"${GITHUB_PATH}"
	echo "${INSTALL_DIR}" >>"${GITHUB_PATH}"
fi

PATH="${BIN_DIR}:${INSTALL_DIR}:${PATH}"
export PATH
zig version
