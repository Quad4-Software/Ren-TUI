#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Build an .rpm from a staged FHS tree (needs rpmbuild).

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
armv7*) ARCH=armv7hl ;;
esac

VERSION=$(pkg_version)
NAME=$(pkg_name)
STAGE="${OUT_DIR}/stage-rpm"
SPEC_DIR="${OUT_DIR}/rpmbuild"
SPEC="${SPEC_DIR}/SPECS/${NAME}.spec"

if ! command -v rpmbuild >/dev/null 2>&1; then
	echo "rpmbuild required to build .rpm" >&2
	exit 1
fi

rm -rf "${SPEC_DIR}"
mkdir -p "${OUT_DIR}" "${SPEC_DIR}/BUILD" "${SPEC_DIR}/RPMS" "${SPEC_DIR}/SOURCES" "${SPEC_DIR}/SPECS" "${SPEC_DIR}/SRPMS"
sh "${ROOT}/ci/scripts/package-stage.sh" "${STAGE}" >/dev/null

# Map staged tree into buildroot via install in %install using the stage snapshot.
STAGE_ABS=$(CDPATH= cd -- "${STAGE}" && pwd)

cat >"${SPEC}" <<EOF
Name: ${NAME}
Version: ${VERSION}
Release: 1%{?dist}
Summary: $(pkg_summary)
License: $(pkg_license)
URL: $(pkg_url)
BuildArch: ${ARCH}
AutoReqProv: no

%description
$(pkg_description)

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a ${STAGE_ABS}/. %{buildroot}/

%files
/usr/bin/ren-tui
/usr/bin/ren-listen
/usr/lib/ren-tui/librns.so
/usr/share/man/man1/ren-tui.1*
/usr/share/man/man1/ren-listen.1*
%doc /usr/share/doc/ren-tui/LICENSE
%doc /usr/share/doc/ren-tui/README.md
%doc /usr/share/doc/ren-tui/CHANGELOG.md

%changelog
* $(date '+%a %b %d %Y') Quad4 <legal@quad4.io> - ${VERSION}-1
- Package ${VERSION}
EOF

rpmbuild \
	--define "_topdir ${SPEC_DIR}" \
	--define "_rpmdir ${OUT_DIR}" \
	--define "_build_name_fmt %%{NAME}-%%{VERSION}-%%{RELEASE}.%%{ARCH}.rpm" \
	-bb "${SPEC}"

OUT=$(ls -1 "${OUT_DIR}/${NAME}-${VERSION}"-*."${ARCH}".rpm 2>/dev/null | head -n 1)
if [ -z "${OUT}" ]; then
	OUT=$(find "${OUT_DIR}" -name "${NAME}-${VERSION}*.rpm" | head -n 1)
fi
echo "${OUT}"
