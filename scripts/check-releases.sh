#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
environment_catalog="${repository_root}/release/environments.tsv"
check_remote=false
docker_context=${DOCKER_CONTEXT:-default}

if [[ ${1:-} == --remote ]]; then
    check_remote=true
elif [[ -n ${1:-} ]]; then
    echo "Usage: $0 [--remote]" >&2
    exit 1
fi

expected_environment_count=$(awk -F '\t' '$1 !~ /^#/ && NF {count++} END {print count + 0}' "${environment_catalog}")
release_count=0

for command in jq yq; do
    if ! command -v "${command}" >/dev/null; then
        echo "Required command is unavailable: ${command}" >&2
        exit 1
    fi
done

catalog_sources=$(mktemp)
pipeline_sources=$(mktemp)
awk -F '\t' '$1 !~ /^#/ && NF {print $2 "\t" $3}' "${environment_catalog}" | sort -u >"${catalog_sources}"
for pipeline in "${repository_root}"/.crow/*-build-static.yaml; do
    yq -o=json '.matrix.include' "${pipeline}" | jq -r '.[] | [
        .name,
        (if has("tag_additional") then (.tag_additional | split(",")[-1]) else (.JULIA_VERSION + "-" + (.OS_VERSION | tostring)) end)
    ] | @tsv'
done | sort -u >"${pipeline_sources}"

if ! cmp -s "${catalog_sources}" "${pipeline_sources}"; then
    echo "release/environments.tsv does not match the exact tags in the Crow build matrices" >&2
    diff -u "${pipeline_sources}" "${catalog_sources}" >&2 || true
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

while IFS= read -r release_metadata; do
    release_count=$((release_count + 1))
    release_directory=$(dirname "${release_metadata}")
    release_month=$(basename "${release_directory}")
    metadata_month=$(jq -r '.release' "${release_metadata}")
    retention_until=$(jq -r '.retentionUntil' "${release_metadata}")
    release_year=${release_month%%-*}
    release_month_number=${release_month##*-}
    if [[ ${release_month_number} == 12 ]]; then
        expected_retention="$((10#${release_year} + 4))-01-01"
    else
        expected_retention=$(printf '%04d-%02d-01' "$((10#${release_year} + 3))" "$((10#${release_month_number} + 1))")
    fi
    environment_count=$(jq '.environments | length' "${release_metadata}")

    if [[ ${metadata_month} != "${release_month}" ]]; then
        echo "Release directory and metadata month differ: ${release_directory}" >&2
        exit 1
    fi
    if [[ ${retention_until} != "${expected_retention}" ]]; then
        echo "Release ${release_month} must be retained through ${expected_retention}, found ${retention_until}" >&2
        exit 1
    fi
    if [[ ${environment_count} != "${expected_environment_count}" ]]; then
        echo "Release ${release_month} has ${environment_count} environments; expected ${expected_environment_count}" >&2
        exit 1
    fi

    while IFS=$'\t' read -r environment_id _image _source_tag _platforms; do
        if [[ -z ${environment_id} || ${environment_id} == \#* ]]; then
            continue
        fi
        if ! jq -e --arg id "${environment_id}" 'any(.environments[]; .id == $id)' "${release_metadata}" >/dev/null; then
            echo "Release ${release_month} is missing ${environment_id}" >&2
            exit 1
        fi
    done <"${environment_catalog}"

    jq -c '.environments[]' "${release_metadata}" | while IFS= read -r environment; do
        environment_id=$(jq -r '.id' <<<"${environment}")
        digest=$(jq -r '.digest' <<<"${environment}")
        docker_hub_reference=$(jq -r '.images.dockerHub' <<<"${environment}")
        registry_reference=$(jq -r '.images.ricochetRegistry' <<<"${environment}")
        containerfile="${release_directory}/${environment_id}/Containerfile"
        environment_readme="${release_directory}/${environment_id}/README.md"
        expected_from="FROM ${docker_hub_reference}@${digest}"

        if [[ $(cat "${containerfile}") != "${expected_from}" ]]; then
            echo "Containerfile is not pinned to its recorded digest: ${containerfile}" >&2
            exit 1
        fi
        if [[ ! -f ${environment_readme} ]]; then
            echo "Environment description is missing: ${environment_readme}" >&2
            exit 1
        fi
        if ! grep -Fq "releases/${release_month}/${environment_id}/Containerfile" "${repository_root}/README.md"; then
            echo "README.md does not link ${environment_id} from release ${release_month}" >&2
            exit 1
        fi

        today=$(date -u +%F)
        if [[ ${check_remote} == true && (${retention_until} == "${today}" || ${retention_until} > "${today}") ]]; then
            for release_reference in "${docker_hub_reference}" "${registry_reference}"; do
                remote_digest=$(inspect_digest "${release_reference}")
                if [[ ${remote_digest} != "${digest}" ]]; then
                    echo "Retained image mismatch for ${release_reference}: expected ${digest}, found ${remote_digest}" >&2
                    exit 1
                fi
            done
        fi
    done
done < <(find "${repository_root}/releases" -mindepth 2 -maxdepth 2 -name release.json -print | sort)

if [[ ${release_count} == 0 ]]; then
    echo "No monthly releases were found" >&2
    exit 1
fi

echo "Validated ${release_count} monthly release(s)"
