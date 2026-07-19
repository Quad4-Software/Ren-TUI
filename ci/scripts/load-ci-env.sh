#!/bin/sh
# Load .github/ci.env into GITHUB_ENV (CI) and print KEY=VAL lines.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
. "${ROOT}/ci/scripts/lib-env.sh"
CI_LOAD_ENV_PRINT=1
ci_load_env
