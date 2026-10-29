#!/usr/bin/env bash

set -euo pipefail

repository_root=${RELEASE_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}
next_month=$("${repository_root}/scripts/next-release-month.sh" "$@")

printf '%s\n' "${next_month}" >"${repository_root}/release/next-month"
NEXT_RELEASE_MONTH=${next_month} yq -i '
    .variables.RELEASE_MONTH.default = strenv(NEXT_RELEASE_MONTH)
    | del(.variables.RELEASE_MONTH.required)
' "${repository_root}/.crow/monthly-release.yaml"
"${repository_root}/scripts/render-release-workflows.sh"

echo "Prepared scheduled release workflows for ${next_month}"
