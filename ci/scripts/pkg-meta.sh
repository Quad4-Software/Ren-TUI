#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Shared package metadata from ren/constants.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)

pkg_version() {
	sed -n 's/^VERSION :: "\(.*\)"/\1/p' "${ROOT}/ren/constants/constants.odin" | head -n 1
}

pkg_name() {
	echo "ren-tui"
}

pkg_summary() {
	echo "Terminal LXMF / NomadNet client for Reticulum"
}

pkg_description() {
	printf '%s\n' \
		"Ren TUI is a terminal LXMF client for the Reticulum network." \
		"It includes NomadNet-style page browsing and LXMF messaging on librns."
}

pkg_maintainer() {
	echo "Quad4 <legal@quad4.io>"
}

pkg_license() {
	echo "0BSD"
}

pkg_url() {
	echo "https://github.com/Quad4-Software/Ren-TUI"
}
