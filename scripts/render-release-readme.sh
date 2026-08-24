#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
release_month=${1:-$(date -u +%Y-%m)}
release_directory="${repository_root}/releases/${release_month}"
release_metadata="${release_directory}/release.json"
rendered_readme=$(mktemp)

if [[ ! -f ${release_metadata} ]]; then
    echo "Release metadata does not exist: ${release_metadata}" >&2
    exit 1
fi

retention_until=$(jq -r '.retentionUntil' "${release_metadata}")

{
    printf '# %s exec environments\n\n' "${release_month}"
    printf 'This release is retained through at least %s.\n\n' "${retention_until}"
    echo '| Environment | Operating system | R | Python | Julia | Quarto |'
    echo '| --- | --- | --- | --- | --- | --- |'
    jq -r 'def version_list: if type == "array" then join(", ") else tostring end;
        .environments[] | "| [\(.id)](./\(.id)/) | \(.versions.os) | \(.versions.r | version_list) | \(.versions.python | version_list) | \(.versions.julia) | \(.versions.quarto) |"' \
        "${release_metadata}"
} >"${rendered_readme}"

mv "${rendered_readme}" "${release_directory}/README.md"
