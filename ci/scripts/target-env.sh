#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Resolve TARGET into ODIN_TARGET, LIB_SUBDIR, LIB_NAME, PACKAGE_EXT.
# Usage: eval "$(sh ci/scripts/target-env.sh linux-amd64)"

set -eu

TARGET=${1:-}
if [ -z "${TARGET}" ]; then
	# Host default
	OS=$(uname -s)
	ARCH=$(uname -m)
	case "${OS}" in
	Linux) OS_TAG=linux ;;
	Darwin) OS_TAG=darwin ;;
	MINGW* | MSYS* | CYGWIN* | Windows_NT) OS_TAG=windows ;;
	*)
		echo "unsupported host OS: ${OS}" >&2
		exit 1
		;;
	esac
	case "${ARCH}" in
	x86_64 | amd64) ARCH_TAG=amd64 ;;
	aarch64 | arm64) ARCH_TAG=arm64 ;;
	i386 | i686) ARCH_TAG=i386 ;;
	armv7* | armv6* | arm) ARCH_TAG=armv7 ;;
	*)
		echo "unsupported host arch: ${ARCH}" >&2
		exit 1
		;;
	esac
	TARGET="${OS_TAG}-${ARCH_TAG}"
fi

case "${TARGET}" in
linux-amd64 | linux-amd64-glibc)
	ODIN_TARGET=linux_amd64
	LIB_SUBDIR=linux/amd64
	LIB_NAME=librns.so
	EXE_SUFFIX=
	PACKAGE_KIND=tar
	CROSS=
	;;
linux-amd64-musl)
	ODIN_TARGET=linux_amd64
	LIB_SUBDIR=linux/amd64-musl
	LIB_NAME=librns.so
	EXE_SUFFIX=
	PACKAGE_KIND=tar
	CROSS=
	;;
linux-arm64)
	ODIN_TARGET=linux_arm64
	LIB_SUBDIR=linux/arm64
	LIB_NAME=librns.so
	EXE_SUFFIX=
	PACKAGE_KIND=tar
	CROSS=
	;;
linux-i386)
	ODIN_TARGET=linux_i386
	LIB_SUBDIR=linux/386
	LIB_NAME=librns.so
	EXE_SUFFIX=
	PACKAGE_KIND=tar
	CROSS=zig
	ZIG_TARGET=x86-linux-gnu
	;;
linux-armv7)
	ODIN_TARGET=linux_arm32
	LIB_SUBDIR=linux/armv7
	LIB_NAME=librns.so
	EXE_SUFFIX=
	PACKAGE_KIND=tar
	CROSS=zig
	ZIG_TARGET=arm-linux-gnueabihf
	;;
linux-armv6)
	ODIN_TARGET=linux_arm32
	LIB_SUBDIR=linux/armv6
	LIB_NAME=librns.so
	EXE_SUFFIX=
	PACKAGE_KIND=tar
	CROSS=zig
	ZIG_TARGET=arm-linux-gnueabi
	;;
darwin-arm64)
	ODIN_TARGET=darwin_arm64
	LIB_SUBDIR=darwin/arm64
	LIB_NAME=librns.dylib
	EXE_SUFFIX=
	PACKAGE_KIND=tar
	CROSS=
	;;
darwin-amd64)
	ODIN_TARGET=darwin_amd64
	LIB_SUBDIR=darwin/amd64
	LIB_NAME=librns.dylib
	EXE_SUFFIX=
	PACKAGE_KIND=tar
	CROSS=
	;;
windows-amd64)
	ODIN_TARGET=windows_amd64
	LIB_SUBDIR=windows/amd64
	LIB_NAME=librns.dll
	EXE_SUFFIX=.exe
	PACKAGE_KIND=zip
	CROSS=zig
	ZIG_TARGET=x86_64-windows-gnu
	;;
*)
	echo "unknown TARGET=${TARGET}" >&2
	exit 1
	;;
esac

printf 'TARGET=%s\n' "${TARGET}"
printf 'ODIN_TARGET=%s\n' "${ODIN_TARGET}"
printf 'LIB_SUBDIR=%s\n' "${LIB_SUBDIR}"
printf 'LIB_NAME=%s\n' "${LIB_NAME}"
printf 'EXE_SUFFIX=%s\n' "${EXE_SUFFIX}"
printf 'PACKAGE_KIND=%s\n' "${PACKAGE_KIND}"
printf 'CROSS=%s\n' "${CROSS}"
if [ -n "${ZIG_TARGET:-}" ]; then
	printf 'ZIG_TARGET=%s\n' "${ZIG_TARGET}"
fi
