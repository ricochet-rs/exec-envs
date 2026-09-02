#!/usr/bin/env bash

set -euo pipefail

repository_root=${RELEASE_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}
current_month=${1:-$(date -u +%Y-%m)}

if [[ ! ${current_month} =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "Release must use YYYY-MM format: ${current_month}" >&2
    exit 1
fi

year=${current_month%%-*}
month=${current_month##*-}
if [[ ${month} == 12 ]]; then
    next_month=$(printf '%04d-01' "$((10#${year} + 1))")
else
    next_month=$(printf '%04d-%02d' "${year}" "$((10#${month} + 1))")
fi

printf '%s\n' "${next_month}" >"${repository_root}/release/next-month"
NEXT_RELEASE_MONTH=${next_month} yq -i '
    .variables.RELEASE_MONTH.default = strenv(NEXT_RELEASE_MONTH)
    | del(.variables.RELEASE_MONTH.required)
' "${repository_root}/.crow/monthly-release.yaml"
"${repository_root}/scripts/render-release-workflows.sh"

echo "Prepared scheduled release workflows for ${next_month}"
