#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Build an Arch Linux .pkg.tar.zst from a staged FHS tree (tar + zstd).

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
. "${ROOT}/ci/scripts/pkg-meta.sh"

OUT_DIR=${OUT_DIR:-"${ROOT}/dist/pkg"}
ARCH=${ARCH:-$(uname -m)}
case "${ARCH}" in
x86_64 | amd64) ARCH=x86_64 ;;
aarch64 | arm64) ARCH=aarch64 ;;
i386 | i686) ARCH=i686 ;;
armv7*) ARCH=armv7h ;;
esac

VERSION=$(pkg_version)
NAME=$(pkg_name)
PKGREL=${PKGREL:-1}
STAGE="${OUT_DIR}/stage-arch"
PKG_ROOT="${OUT_DIR}/arch-root"

if ! command -v zstd >/dev/null 2>&1; then
	echo "zstd required to build .pkg.tar.zst" >&2
	exit 1
fi
if ! command -v tar >/dev/null 2>&1; then
	echo "tar required to build .pkg.tar.zst" >&2
	exit 1
fi

rm -rf "${PKG_ROOT}"
mkdir -p "${OUT_DIR}" "${PKG_ROOT}"
sh "${ROOT}/ci/scripts/package-stage.sh" "${STAGE}" >/dev/null
cp -a "${STAGE}/." "${PKG_ROOT}/"

SIZE=$(du -sb "${PKG_ROOT}" | awk '{print $1}')

cat >"${PKG_ROOT}/.PKGINFO" <<EOF
pkgname = ${NAME}
pkgbase = ${NAME}
pkgver = ${VERSION}-${PKGREL}
pkgdesc = $(pkg_summary)
url = $(pkg_url)
builddate = $(date +%s)
packager = $(pkg_maintainer)
size = ${SIZE}
arch = ${ARCH}
license = $(pkg_license)
EOF

OUT="${OUT_DIR}/${NAME}-${VERSION}-${PKGREL}-${ARCH}.pkg.tar.zst"

(
	cd "${PKG_ROOT}"
	# shellcheck disable=SC2035
	tar --format=gnu --owner=0 --group=0 --numeric-owner \
		-cf - .PKGINFO usr \
		| zstd -c -T0 -19 >"${OUT}"
)

echo "${OUT}"
