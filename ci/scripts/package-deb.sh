#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Build a .deb from a staged FHS tree (needs dpkg-deb).

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
. "${ROOT}/ci/scripts/pkg-meta.sh"

OUT_DIR=${OUT_DIR:-"${ROOT}/dist/pkg"}
ARCH=${ARCH:-$(dpkg --print-architecture 2>/dev/null || uname -m)}
case "${ARCH}" in
x86_64 | amd64) ARCH=amd64 ;;
aarch64 | arm64) ARCH=arm64 ;;
i386 | i686) ARCH=i386 ;;
armv7* | armhf) ARCH=armhf ;;
esac

VERSION=$(pkg_version)
NAME=$(pkg_name)
STAGE="${OUT_DIR}/stage-deb"
DEB_ROOT="${OUT_DIR}/deb-root"

rm -rf "${DEB_ROOT}"
mkdir -p "${OUT_DIR}"
sh "${ROOT}/ci/scripts/package-stage.sh" "${STAGE}" >/dev/null

mkdir -p "${DEB_ROOT}/DEBIAN"
cp -a "${STAGE}/." "${DEB_ROOT}/"

SIZE=$(du -sk "${DEB_ROOT}" | awk '{print $1}')

cat >"${DEB_ROOT}/DEBIAN/control" <<EOF
Package: ${NAME}
Version: ${VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Maintainer: $(pkg_maintainer)
Installed-Size: ${SIZE}
Depends: libc6
Homepage: $(pkg_url)
Description: $(pkg_summary)
$(pkg_description | sed 's/^/ /')
EOF

if ! command -v dpkg-deb >/dev/null 2>&1; then
	echo "dpkg-deb required to build .deb" >&2
	exit 1
fi

OUT="${OUT_DIR}/${NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "${DEB_ROOT}" "${OUT}"
echo "${OUT}"
