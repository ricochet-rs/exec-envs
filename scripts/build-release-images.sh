#!/usr/bin/env bash

set -euo pipefail

repository_root=${RELEASE_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}
release_month=${1:-$(date -u +%Y-%m)}
selected_environment=${2:-}
docker_context=${DOCKER_CONTEXT:-default}
release_registry=${RELEASE_SOURCE_REGISTRY:-reg.ricochet.rs/exec-envs}
dry_run=${RELEASE_BUILD_DRY_RUN:-false}
rebuild=${RELEASE_REBUILD:-false}
build_platform=${RELEASE_PLATFORM:-}

if (( $# > 2 )); then
    echo "Usage: $0 [YYYY-MM [environment-id]]" >&2
    exit 1
fi

if [[ ! ${release_month} =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "Release must use YYYY-MM format: ${release_month}" >&2
    exit 1
fi

# Each architecture is built on an agent of that architecture, because emulating a
# foreign one fails: under qemu-aarch64 these images clear dnf and then die
# extracting the Julia tarball. One run therefore produces one architecture, and
# merge-release-images.sh composes the calendar tag from the results.
if [[ ! ${build_platform} =~ ^linux/(amd64|arm64)$ ]]; then
    echo "Set RELEASE_PLATFORM to linux/amd64 or linux/arm64: ${build_platform:-unset}" >&2
    exit 1
fi
build_architecture=${build_platform#linux/}

for command in docker jq yq; do
    if ! command -v "${command}" >/dev/null; then
        echo "Required command is unavailable: ${command}" >&2
        exit 1
    fi
done

if [[ -d ${repository_root}/releases/${release_month} && ${rebuild} != true ]]; then
    echo "Release ${release_month} already exists; set RELEASE_REBUILD=true to rebuild its calendar tags"
    exit 0
fi

all_environments=$(mktemp)
selected_environments=$(mktemp)
trap 'rm -f "${all_environments}" "${selected_environments}"' EXIT

"${repository_root}/scripts/list-release-environments.sh" --json "${release_month}" >"${all_environments}"
environment_source=${all_environments}

if [[ -n ${selected_environment} ]]; then
    jq -c --arg environment_id "${selected_environment}" 'select(.id == $environment_id)' \
        "${all_environments}" >"${selected_environments}"
    if [[ ! -s ${selected_environments} ]]; then
        echo "Unknown environment for ${release_month}: ${selected_environment}" >&2
        echo "Available environment IDs:" >&2
        jq -r '.id' "${all_environments}" >&2
        exit 1
    fi
    environment_source=${selected_environments}
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
    architecture_reference="${release_registry}/${image}:${release_tag}-${build_architecture}"
    build_arguments=()

    # An environment can be published for fewer platforms than the fleet offers, so
    # julia-alpine simply has nothing to do on the arm64 agent.
    if [[ ",${expected_platforms}," != *",${build_platform},"* ]]; then
        echo "Skipping ${release_tag}: not published for ${build_platform}"
        continue
    fi

    if [[ ${dry_run} != true && ${rebuild} != true ]] && manifest=$(inspect_manifest "${architecture_reference}"); then
        platforms=$(jq -r '[.manifests[] | select(.platform.os != "unknown") | "\(.platform.os)/\(.platform.architecture)"] | unique | sort | join(",")' <<<"${manifest}")
        if [[ -n ${platforms} && ${platforms} != "${build_platform}" ]]; then
            echo "Existing ${architecture_reference} has ${platforms}; expected ${build_platform}" >&2
            exit 1
        fi
        echo "Reusing existing architecture tag ${architecture_reference}"
        continue
    fi

    while IFS=$'\t' read -r argument value; do
        build_arguments+=(--build-arg "${argument}=${value}")
    done < <(jq -r '.buildArgs | to_entries[] | [.key, (.value | tostring)] | @tsv' <<<"${environment}")

    build_command=(
        docker --context "${docker_context}" buildx build
        --file "${repository_root}/${image}/Containerfile"
        --platform "${build_platform}"
        --provenance=true
        --sbom=true
        --tag "${architecture_reference}"
        --push
        "${build_arguments[@]}"
        "${repository_root}"
    )

    if [[ ${dry_run} == true ]]; then
        printf 'Would build'
        printf ' %q' "${build_command[@]}"
        printf '\n'
    else
        echo "Building ${build_architecture} image ${architecture_reference}"
        "${build_command[@]}"
    fi
done <"${environment_source}"
