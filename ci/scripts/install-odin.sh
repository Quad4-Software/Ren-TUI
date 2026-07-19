#!/bin/sh
# Fetch a pinned Odin release with curl and sha256 verification.
# Supports Linux, macOS, and Windows host installers.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
. "${ROOT}/ci/scripts/lib-env.sh"
ci_load_env

ODIN_VERSION=${ODIN_VERSION:-dev-2026-07a}
ARCH=$(uname -m)
OS=$(uname -s)

case "${OS}" in
Linux) ODIN_OS=linux ;;
Darwin) ODIN_OS=macos ;;
MINGW* | MSYS* | CYGWIN*) ODIN_OS=windows ;;
*)
	echo "unsupported OS: ${OS}" >&2
	exit 1
	;;
esac

case "${ARCH}" in
x86_64 | amd64)
	ODIN_ARCH=amd64
	;;
aarch64 | arm64)
	ODIN_ARCH=arm64
	;;
*)
	echo "unsupported arch: ${ARCH}" >&2
	exit 1
	;;
esac

case "${ODIN_OS}-${ODIN_ARCH}" in
linux-amd64) ODIN_SHA256=${ODIN_LINUX_AMD64_SHA256:-} ;;
linux-arm64) ODIN_SHA256=${ODIN_LINUX_ARM64_SHA256:-} ;;
macos-amd64) ODIN_SHA256=${ODIN_MACOS_AMD64_SHA256:-} ;;
macos-arm64) ODIN_SHA256=${ODIN_MACOS_ARM64_SHA256:-} ;;
windows-amd64) ODIN_SHA256=${ODIN_WINDOWS_AMD64_SHA256:-} ;;
*)
	echo "no pinned sha for ${ODIN_OS}/${ODIN_ARCH}" >&2
	exit 1
	;;
esac

if [ -z "${ODIN_SHA256}" ]; then
	echo "missing sha256 for ${ODIN_OS}/${ODIN_ARCH}" >&2
	exit 1
fi

PREFIX=${ODIN_PREFIX:-/opt/odin}
if [ "${ODIN_OS}" = "windows" ]; then
	ASSET="odin-windows-${ODIN_ARCH}-${ODIN_VERSION}.zip"
else
	ASSET="odin-${ODIN_OS}-${ODIN_ARCH}-${ODIN_VERSION}.tar.gz"
fi
URL="https://github.com/odin-lang/Odin/releases/download/${ODIN_VERSION}/${ASSET}"

tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT INT TERM HUP

curl -fsSL --retry 3 --retry-delay 2 -o "${tmpdir}/${ASSET}" "${URL}"
if command -v sha256sum >/dev/null 2>&1; then
	echo "${ODIN_SHA256}  ${tmpdir}/${ASSET}" | sha256sum -c -
else
	echo "${ODIN_SHA256}  ${tmpdir}/${ASSET}" | shasum -a 256 -c -
fi

rm -rf "${PREFIX}"
mkdir -p "${PREFIX}"
case "${ASSET}" in
*.zip)
	unzip -q "${tmpdir}/${ASSET}" -d "${PREFIX}"
	;;
*)
	tar -xzf "${tmpdir}/${ASSET}" -C "${PREFIX}"
	;;
esac

ODIN_BIN=$(find "${PREFIX}" -type f \( -name odin -o -name odin.exe \) | head -n 1)
if [ -z "${ODIN_BIN}" ]; then
	echo "odin binary not found under ${PREFIX}" >&2
	exit 1
fi
chmod +x "${ODIN_BIN}" || true

ODIN_DIR=$(CDPATH= cd -- "$(dirname "${ODIN_BIN}")" && pwd)

LINK_PATH=${ODIN_LINK:-/usr/local/bin/odin}
if [ "${ODIN_OS}" != "windows" ]; then
	mkdir -p "$(dirname "${LINK_PATH}")"
	ln -sfn "${ODIN_BIN}" "${LINK_PATH}"
fi

if [ -n "${GITHUB_PATH:-}" ]; then
	echo "${ODIN_DIR}" >>"${GITHUB_PATH}"
fi
PATH="${ODIN_DIR}:${PATH}"
export PATH

echo "ODIN_ROOT=${ODIN_DIR}"
odin version
