#!/usr/bin/env bash

set -euo pipefail

repository_root=${RELEASE_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}
release_month=${1:-$(date -u +%Y-%m)}
docker_context=${DOCKER_CONTEXT:-default}
release_registry=${RELEASE_SOURCE_REGISTRY:-reg.ricochet.rs/exec-envs}
dry_run=${RELEASE_BUILD_DRY_RUN:-false}

if [[ ! ${release_month} =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "Release must use YYYY-MM format: ${release_month}" >&2
    exit 1
fi

for command in docker jq yq; do
    if ! command -v "${command}" >/dev/null; then
        echo "Required command is unavailable: ${command}" >&2
        exit 1
    fi
done

if [[ -d ${repository_root}/releases/${release_month} ]]; then
    echo "Release ${release_month} already exists; refusing to rebuild its immutable tags"
    exit 0
fi

inspect_manifest() {
    local image_reference=$1

    docker --context "${docker_context}" buildx imagetools inspect "${image_reference}" --format '{{json .Manifest}}' 2>/dev/null
}

while IFS= read -r environment; do
    image=$(jq -r '.image' <<<"${environment}")
    version_suffix=$(jq -r '.versionSuffix' <<<"${environment}")
    expected_platforms=$(jq -r '.platforms' <<<"${environment}")
    release_tag="${release_month}-${version_suffix}"
    release_reference="${release_registry}/${image}:${release_tag}"
    build_arguments=()

    if [[ ${dry_run} != true ]] && manifest=$(inspect_manifest "${release_reference}"); then
        platforms=$(jq -r '[.manifests[] | select(.platform.os != "unknown") | "\(.platform.os)/\(.platform.architecture)"] | unique | sort | join(",")' <<<"${manifest}")
        if [[ ${platforms} != "${expected_platforms}" ]]; then
            echo "Existing ${release_reference} has ${platforms}; expected ${expected_platforms}" >&2
            exit 1
        fi
        echo "Reusing existing calendar tag ${release_reference}"
        continue
    fi

    while IFS=$'\t' read -r argument value; do
        build_arguments+=(--build-arg "${argument}=${value}")
    done < <(jq -r '.buildArgs | to_entries[] | [.key, (.value | tostring)] | @tsv' <<<"${environment}")

    build_command=(
        docker --context "${docker_context}" buildx build
        --file "${repository_root}/${image}/Containerfile"
        --platform "${expected_platforms}"
        --provenance=true
        --sbom=true
        --tag "${release_reference}"
        --push
        "${build_arguments[@]}"
        "${repository_root}"
    )

    if [[ ${dry_run} == true ]]; then
        printf 'Would build'
        printf ' %q' "${build_command[@]}"
        printf '\n'
    else
        echo "Building calendar tag ${release_reference}"
        "${build_command[@]}"
    fi
done < <("${repository_root}/scripts/list-release-environments.sh" --json "${release_month}")
