#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
release_month=${1:-$(date -u +%Y-%m)}
release_directory="${repository_root}/releases/${release_month}"

if [[ ! -d ${release_directory} ]]; then
    echo "Release does not exist: ${release_directory}" >&2
    exit 1
fi

cd "${repository_root}"
bunx prettier@3.2.5 --write --ignore-unknown \
    README.md \
    r/*/README.md \
    python/*/README.md \
    julia/*/README.md \
    release/environments/r-alpine.yaml \
    release/environments/julia-alpine.yaml \
    "releases/${release_month}"
