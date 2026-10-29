#!/usr/bin/env bash

set -euo pipefail

current_month=${1:-$(date -u +%Y-%m)}

if [[ ! ${current_month} =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "Release must use YYYY-MM format: ${current_month}" >&2
    exit 1
fi

year=${current_month%%-*}
month=${current_month##*-}
if [[ ${month} == 12 ]]; then
    printf '%04d-01\n' "$((10#${year} + 1))"
else
    printf '%04d-%02d\n' "${year}" "$((10#${month} + 1))"
fi
