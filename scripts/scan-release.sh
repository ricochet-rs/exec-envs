#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
release_month=${1:-$(date -u +%Y-%m)}
release_metadata="${repository_root}/releases/${release_month}/release.json"
source_registry=${RELEASE_SOURCE_REGISTRY:-reg.ricochet.rs/exec-envs}
scanner_image=${RELEASE_SCANNER_IMAGE:-reg.ricochet.rs/docker.io/aquasec/trivy:0.73.0}

if [[ ! -f ${release_metadata} ]]; then
    echo "Release metadata does not exist: ${release_metadata}" >&2
    exit 1
fi

jq -c '.environments[]' "${release_metadata}" | while IFS= read -r environment; do
    image=$(jq -r '.image' <<<"${environment}")
    digest=$(jq -r '.digest' <<<"${environment}")
    source_reference="${source_registry}/${image}@${digest}"

    docker run --rm \
        --volume exec-envs-trivy-cache:/root/.cache/trivy \
        "${scanner_image}" image \
        --exit-code 1 \
        --ignore-unfixed \
        --scanners vuln \
        --severity CRITICAL \
        --skip-dirs '/opt/julia/share/julia/base/JuliaSyntax/docs' \
        --skip-dirs '/opt/julia/share/julia/stdlib/*/*/test' \
        --skip-dirs '/opt/julia/share/julia/test' \
        "${source_reference}"
done
