#!/usr/bin/env bash

set -euo pipefail

repository_root=${RELEASE_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}
release_month=${1:-$(date -u +%Y-%m)}
selected_environment=${2:-}
docker_context=${DOCKER_CONTEXT:-default}
release_registry=${RELEASE_SOURCE_REGISTRY:-reg.ricochet.rs/exec-envs}
dry_run=${RELEASE_BUILD_DRY_RUN:-false}
rebuild=${RELEASE_REBUILD:-false}

if (( $# > 2 )); then
    echo "Usage: $0 [YYYY-MM [environment-id]]" >&2
    exit 1
fi

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

manifest_platforms() {
    local image_reference=$1
    local manifest

    manifest=$(docker --context "${docker_context}" buildx imagetools inspect "${image_reference}" --format '{{json .Manifest}}' 2>/dev/null) || return 1
    jq -r '[.manifests[] | select(.platform.os != "unknown") | "\(.platform.os)/\(.platform.architecture)"] | unique | sort | join(",")' <<<"${manifest}"
}

while IFS= read -r environment; do
    image=$(jq -r '.image' <<<"${environment}")
    version_suffix=$(jq -r '.versionSuffix' <<<"${environment}")
    expected_platforms=$(jq -r '.platforms' <<<"${environment}")
    release_tag="${release_month}-${version_suffix}"
    release_reference="${release_registry}/${image}:${release_tag}"
    architecture_references=()

    while IFS= read -r platform; do
        architecture_references+=("${release_reference}-${platform#linux/}")
    done < <(tr ',' '\n' <<<"${expected_platforms}")

    if [[ ${dry_run} != true && ${rebuild} != true ]] && platforms=$(manifest_platforms "${release_reference}"); then
        if [[ ${platforms} == "${expected_platforms}" ]]; then
            echo "Reusing existing calendar tag ${release_reference}"
            continue
        fi
    fi

    merge_command=(
        docker --context "${docker_context}" buildx imagetools create
        --tag "${release_reference}"
        "${architecture_references[@]}"
    )

    if [[ ${dry_run} == true ]]; then
        printf 'Would merge'
        printf ' %q' "${merge_command[@]}"
        printf '\n'
        continue
    fi

    echo "Composing calendar tag ${release_reference}"
    "${merge_command[@]}"

    # The index is what every later step reads, so prove it advertises exactly the
    # platforms this environment promises rather than trusting the create call.
    if ! platforms=$(manifest_platforms "${release_reference}"); then
        echo "Unable to inspect ${release_reference} after composing it" >&2
        exit 1
    fi
    if [[ ${platforms} != "${expected_platforms}" ]]; then
        echo "Composed ${release_reference} has ${platforms}; expected ${expected_platforms}" >&2
        exit 1
    fi
done <"${environment_source}"
