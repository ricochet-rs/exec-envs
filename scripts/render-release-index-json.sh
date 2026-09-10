#!/usr/bin/env bash
# Render releases/index.json, the machine-readable list of archived months Ricochet reads before fetching a catalogue.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
output=${1:-${repository_root}/releases/index.json}

if ! command -v jq >/dev/null; then
    echo "Required command is unavailable: jq" >&2
    exit 1
fi

find "${repository_root}/releases" -mindepth 2 -maxdepth 2 -name release.json -print0 \
    | sort -rz \
    | xargs -0 jq -s '
        map({
            release: .release,
            retentionUntil: .retentionUntil,
            environments: (.environments | length),
            catalogue: ("releases/" + .release + "/catalogue.toml")
        })
    ' >"${output}.tmp"
mv "${output}.tmp" "${output}"
