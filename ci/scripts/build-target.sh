#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Build ren-tui for TARGET. Optionally builds librns when RNS_ROOT is set.
#
#   TARGET=linux-amd64 sh ci/scripts/build-target.sh
#   TARGET=windows-amd64 RNS_ROOT=/path/to/Reticulum-Go sh ci/scripts/build-target.sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "${ROOT}"

# shellcheck disable=SC1091
. "${ROOT}/ci/scripts/lib-env.sh"
ci_load_env

TARGET=${TARGET:-}
eval "$(sh "${ROOT}/ci/scripts/target-env.sh" "${TARGET}")"

VENDOR_RNS=${VENDOR_RNS:-${ROOT}/vendor/librns}
VENDOR_LIB=${VENDOR_RNS}/lib/${LIB_SUBDIR}
VENDOR_ODIN=${VENDOR_RNS}/odin
BIN_DIR=${ROOT}/bin
mkdir -p "${BIN_DIR}" "${VENDOR_LIB}" "${VENDOR_RNS}/include"

if [ "${TARGET}" = "linux-amd64" ] || [ "${TARGET}" = "linux-amd64-glibc" ]; then
	if [ ! -f "${VENDOR_LIB}/${LIB_NAME}" ] && [ -f "${VENDOR_RNS}/lib/librns.so" ]; then
		cp -f "${VENDOR_RNS}/lib/librns.so" "${VENDOR_LIB}/${LIB_NAME}"
	fi
fi

build_librns_for_target() {
	if [ -z "${RNS_ROOT:-}" ]; then
		return 0
	fi
	case "${TARGET}" in
	linux-amd64 | linux-amd64-glibc)
		(cd "${RNS_ROOT}" && task build-librns)
		cp -f "${RNS_ROOT}/bin/librns.so" "${VENDOR_LIB}/librns.so"
		cp -f "${RNS_ROOT}/bin/rns.h" "${VENDOR_RNS}/include/rns.h"
		;;
	linux-arm64)
		(cd "${RNS_ROOT}" && sh scripts/build-librns-targets.sh linux-arm64)
		cp -f "${RNS_ROOT}/bin/linux/arm64/librns.so" "${VENDOR_LIB}/librns.so"
		cp -f "${RNS_ROOT}/bin/linux/arm64/rns.h" "${VENDOR_RNS}/include/rns.h"
		;;
	linux-i386)
		(cd "${RNS_ROOT}" && sh scripts/build-librns-targets.sh linux-386)
		cp -f "${RNS_ROOT}/bin/linux/386/librns.so" "${VENDOR_LIB}/librns.so"
		cp -f "${RNS_ROOT}/bin/linux/386/rns.h" "${VENDOR_RNS}/include/rns.h"
		;;
	linux-armv7)
		(cd "${RNS_ROOT}" && sh scripts/build-librns-targets.sh linux-armv7)
		cp -f "${RNS_ROOT}/bin/linux/armv7/librns.so" "${VENDOR_LIB}/librns.so"
		cp -f "${RNS_ROOT}/bin/linux/armv7/rns.h" "${VENDOR_RNS}/include/rns.h"
		;;
	linux-armv6)
		(cd "${RNS_ROOT}" && sh scripts/build-librns-targets.sh linux-armv6)
		cp -f "${RNS_ROOT}/bin/linux/armv6/librns.so" "${VENDOR_LIB}/librns.so"
		cp -f "${RNS_ROOT}/bin/linux/armv6/rns.h" "${VENDOR_RNS}/include/rns.h"
		;;
	windows-amd64)
		(cd "${RNS_ROOT}" && sh scripts/build-librns-targets.sh windows)
		cp -f "${RNS_ROOT}/bin/windows/amd64/librns.dll" "${VENDOR_LIB}/librns.dll"
		cp -f "${RNS_ROOT}/bin/windows/amd64/rns.h" "${VENDOR_RNS}/include/rns.h"
		if [ -f "${RNS_ROOT}/bin/windows/amd64/librns.a" ]; then
			cp -f "${RNS_ROOT}/bin/windows/amd64/librns.a" "${VENDOR_LIB}/"
		fi
		;;
	darwin-arm64 | darwin-amd64)
		(cd "${RNS_ROOT}" && sh scripts/build-librns-targets.sh darwin)
		arch=${LIB_SUBDIR#darwin/}
		cp -f "${RNS_ROOT}/bin/darwin/${arch}/librns.dylib" "${VENDOR_LIB}/librns.dylib"
		cp -f "${RNS_ROOT}/bin/darwin/${arch}/rns.h" "${VENDOR_RNS}/include/rns.h"
		;;
	esac
	if [ -d "${RNS_ROOT}/bindings/odin/rns" ]; then
		mkdir -p "${VENDOR_ODIN}/rns"
		cp -a "${RNS_ROOT}/bindings/odin/rns/." "${VENDOR_ODIN}/rns/"
	fi
}

build_librns_for_target

if [ ! -f "${VENDOR_LIB}/${LIB_NAME}" ]; then
	echo "missing ${VENDOR_LIB}/${LIB_NAME} (set RNS_ROOT to build it)" >&2
	exit 1
fi

cp -f "${VENDOR_LIB}/${LIB_NAME}" "${BIN_DIR}/${LIB_NAME}"

COLLECTION="-collection:ren=${ROOT}/ren -collection:rns=${VENDOR_ODIN}"
ODIN=${ODIN:-odin}

make -C "${ROOT}" git-commit >/dev/null

build_one() {
	cmd="$1"
	out_base="$2"
	out="${BIN_DIR}/${out_base}${EXE_SUFFIX}"

	case "${CROSS}" in
	zig)
		if ! command -v zig >/dev/null 2>&1; then
			echo "zig required for TARGET=${TARGET}" >&2
			exit 1
		fi
		obj_prefix="${BIN_DIR}/${out_base}"
		rm -f "${BIN_DIR}/${out_base}"*.o "${BIN_DIR}/${out_base}"*.obj
		LIBRARY_PATH="${VENDOR_LIB}:${LIBRARY_PATH:-}" \
			${ODIN} build "cmd/${cmd}" \
			-target:"${ODIN_TARGET}" \
			-build-mode:obj \
			-out:"${obj_prefix}.o" \
			${COLLECTION}

		objs=$(find "${BIN_DIR}" -maxdepth 1 -name "${out_base}-*.o" -print)
		if [ -z "${objs}" ]; then
			objs=$(find "${BIN_DIR}" -maxdepth 1 \( -name "${out_base}.o" -o -name "${out_base}.obj" \) -print)
		fi
		if [ -z "${objs}" ]; then
			echo "no object files from odin for ${out_base}" >&2
			exit 1
		fi

		# shellcheck disable=SC2086
		case "${TARGET}" in
		windows-*)
			zig build-exe ${objs} \
				"${ROOT}/ci/windows/_fltused.c" \
				"${VENDOR_LIB}/${LIB_NAME}" \
				-target "${ZIG_TARGET}" \
				-femit-bin="${out}" \
				-L"${VENDOR_LIB}" \
				-lc \
				-lbcrypt \
				-lkernel32 \
				-ladvapi32 \
				-lntdll
			;;
		*)
			zig build-exe ${objs} \
				"${VENDOR_LIB}/${LIB_NAME}" \
				-target "${ZIG_TARGET}" \
				-femit-bin="${out}" \
				-L"${VENDOR_LIB}" \
				-lc
			;;
		esac
		# shellcheck disable=SC2086
		rm -f ${objs}
		;;
	*)
		link_flags="-L${VENDOR_LIB}"
		case "${TARGET}" in
		darwin-*)
			link_flags="${link_flags} -lrns -Wl,-rpath,@loader_path"
			;;
		linux-*)
			link_flags="${link_flags} -Wl,-rpath,${BIN_DIR}"
			;;
		esac
		LIBRARY_PATH="${VENDOR_LIB}:${LIBRARY_PATH:-}" \
			${ODIN} build "cmd/${cmd}" \
			-target:"${ODIN_TARGET}" \
			-out:"${out}" \
			${COLLECTION} \
			-extra-linker-flags:"${link_flags}"
		;;
	esac
}

build_one ren-tui ren-tui
build_one ren-listen ren-listen

case "${TARGET}" in
linux-*)
	if command -v patchelf >/dev/null 2>&1; then
		patchelf --set-rpath '$ORIGIN' "${BIN_DIR}/ren-tui${EXE_SUFFIX}" "${BIN_DIR}/ren-listen${EXE_SUFFIX}" || true
	fi
	;;
esac

echo "built TARGET=${TARGET} -> ${BIN_DIR}/ren-tui${EXE_SUFFIX} ${BIN_DIR}/ren-listen${EXE_SUFFIX} ${BIN_DIR}/${LIB_NAME}"
