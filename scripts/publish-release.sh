#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
release_month=${1:-$(date -u +%Y-%m)}
release_metadata="${repository_root}/releases/${release_month}/release.json"
docker_context=${DOCKER_CONTEXT:-default}
source_registry=${RELEASE_SOURCE_REGISTRY:-reg.ricochet.rs/exec-envs}
rebuild=${RELEASE_REBUILD:-false}

if [[ ! -f ${release_metadata} ]]; then
    echo "Release metadata does not exist: ${release_metadata}" >&2
    exit 1
fi

inspect_digest() {
    local image_reference=$1
    local inspect_attempt
    local manifest

    for inspect_attempt in 1 2 3; do
        if manifest=$(docker --context "${docker_context}" buildx imagetools inspect "${image_reference}" --format '{{json .Manifest}}'); then
            jq -r '.digest' <<<"${manifest}"
            return
        fi
        echo "Retrying ${image_reference} after inspect attempt ${inspect_attempt}" >&2
    done

    echo "Unable to inspect ${image_reference} after ${inspect_attempt} attempts" >&2
    return 1
}

jq -c '.environments[]' "${release_metadata}" | while IFS= read -r environment; do
    image=$(jq -r '.image' <<<"${environment}")
    digest=$(jq -r '.digest' <<<"${environment}")
    docker_hub_reference=$(jq -r '.images.dockerHub' <<<"${environment}")
    registry_reference=$(jq -r '.images.ricochetRegistry' <<<"${environment}")
    source_reference="${source_registry}/${image}@${digest}"

    for release_reference in "${docker_hub_reference}" "${registry_reference}"; do
        if published_digest=$(inspect_digest "${release_reference}" 2>/dev/null); then
            if [[ ${published_digest} == "${digest}" ]]; then
                echo "Calendar tag already published: ${release_reference}"
                continue
            fi
            if [[ ${rebuild} != true ]]; then
                echo "Existing calendar tag mismatch for ${release_reference}: expected ${digest}, found ${published_digest}" >&2
                exit 1
            fi
            echo "Moving ${release_reference} from ${published_digest} to the rebuilt digest"
        fi

        echo "Publishing ${release_reference}"
        docker --context "${docker_context}" buildx imagetools create --tag "${release_reference}" "${source_reference}"
        published_digest=$(inspect_digest "${release_reference}")
        if [[ ${published_digest} != "${digest}" ]]; then
            echo "Published digest mismatch for ${release_reference}: expected ${digest}, found ${published_digest}" >&2
            exit 1
        fi
    done
done
