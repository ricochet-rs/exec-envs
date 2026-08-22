#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
check_remote=false
docker_context=${DOCKER_CONTEXT:-default}

if [[ ${1:-} == --remote ]]; then
    check_remote=true
elif [[ -n ${1:-} ]]; then
    echo "Usage: $0 [--remote]" >&2
    exit 1
fi

release_count=0
first_readme_heading=$(awk '/^## / { print; exit }' "${repository_root}/README.md")

if [[ ${first_readme_heading} != "## Monthly releases" ]]; then
    echo "README.md must present Monthly releases as its first section" >&2
    exit 1
fi
if ! grep -Eq '^\| Release +\| Retained through +\| Environments +\| CI +\|$' "${repository_root}/README.md"; then
    echo "README.md must use the compact monthly release index" >&2
    exit 1
fi

for command in jq yq; do
    if ! command -v "${command}" >/dev/null; then
        echo "Required command is unavailable: ${command}" >&2
        exit 1
    fi
done

validate_static_builds() {
    local pipeline
    local workflow

    for pipeline in "${repository_root}"/.crow/*-build-static.yaml; do
        workflow=$(yq -o=json '.' "${pipeline}")
        if ! jq -e '
            all(.when.event[]; . != "cron" and . != "manual") and
            all(.steps[]; .settings.dry_run == true) and
            all(.matrix.include[]; has("tag_additional") | not)
        ' <<<"${workflow}" >/dev/null; then
            echo "${pipeline} must validate builds without publishing non-calendar tags" >&2
            exit 1
        fi
    done
}

validate_release_triggers() {
    local manual_workflow
    local monthly_workflow

    monthly_workflow=$(yq -o=json '.' "${repository_root}/.crow/monthly-release.yaml")
    if ! jq -e '
        all(.when.event[]; . != "manual") and
        all(.steps[].when.event[]?; . != "manual")
    ' <<<"${monthly_workflow}" >/dev/null; then
        echo ".crow/monthly-release.yaml must reserve full releases for cron events" >&2
        exit 1
    fi

    manual_workflow=$(yq -o=json '.' "${repository_root}/.crow/manual-release-image.yaml")
    if ! jq -e '
        (.when.event == ["manual"]) and
        (.when.branch == ["main"]) and
        any(.steps[].commands[]?; contains("RELEASE_ENVIRONMENT")) and
        any(.steps[].commands[]?; contains("scripts/build-release-images.sh"))
    ' <<<"${manual_workflow}" >/dev/null; then
        echo ".crow/manual-release-image.yaml must select one calendar build through Crow variables" >&2
        exit 1
    fi
}

validate_renovate_targets() {
    local pipeline
    local marked_entries
    local marked_entry_count
    local marked_julia
    local latest_julia
    local marked_os
    local latest_os

    for pipeline in "${repository_root}"/.crow/julia-*-build-static.yaml; do
        marked_entries=$(mktemp)
        yq -r '.matrix.include[]
            | select((.JULIA_VERSION | line_comment) == "renovate: julia-current")
            | [.JULIA_VERSION, .OS_VERSION]
            | @tsv' "${pipeline}" >"${marked_entries}"
        marked_entry_count=$(awk 'END {print NR + 0}' "${marked_entries}")
        latest_julia=$(yq -r '.matrix.include[].JULIA_VERSION' "${pipeline}" | sort -Vu | tail -n 1)
        marked_julia=$(cut -f1 "${marked_entries}")

        if [[ ${marked_entry_count} != 1 || ${marked_julia} != "${latest_julia}" ]]; then
            echo "${pipeline} must mark exactly its newest Julia definition as renovate: julia-current" >&2
            exit 1
        fi

        if [[ $(basename "${pipeline}") == julia-alpine-build-static.yaml ]]; then
            latest_os=$(yq -r '.matrix.include[].OS_VERSION' "${pipeline}" | sort -Vu | tail -n 1)
            marked_os=$(cut -f2 "${marked_entries}")
            if [[ ${marked_os} != "${latest_os}" ]]; then
                echo "${pipeline} must restrict Renovate to its newest Alpine definition" >&2
                exit 1
            fi
        fi
    done
}

validate_release_policy() {
    local release_month=$1
    local environments
    local environment_count
    local unique_environment_count
    local alpine_versions
    local alpine_version_count
    local image

    environments=$(mktemp)
    "${repository_root}/scripts/list-release-environments.sh" "${release_month}" >"${environments}"
    environment_count=$(awk 'END {print NR + 0}' "${environments}")
    unique_environment_count=$(cut -f1 "${environments}" | sort -u | awk 'END {print NR + 0}')

    if [[ ${environment_count} == 0 || ${unique_environment_count} != "${environment_count}" ]]; then
        echo "Release policy for ${release_month} must contain unique environments" >&2
        exit 1
    fi

    for image in r-alpine julia-alpine; do
        alpine_versions=$(mktemp)
        awk -F '\t' -v image="${image}" '$2 == image {
            field_count = split($3, fields, "-")
            print fields[field_count]
        }' "${environments}" | sort -Vu >"${alpine_versions}"
        alpine_version_count=$(awk 'END {print NR + 0}' "${alpine_versions}")
        if [[ ${alpine_version_count} != 2 ]]; then
            echo "Release policy for ${release_month} must contain exactly two ${image} OS versions" >&2
            exit 1
        fi
    done
}

validate_static_builds
validate_release_triggers
validate_renovate_targets

current_month=$(date -u +%Y-%m)
current_year=${current_month%%-*}
current_month_number=${current_month##*-}
if [[ ${current_month_number} == 12 ]]; then
    next_month="$((10#${current_year} + 1))-01"
else
    next_month=$(printf '%04d-%02d' "${current_year}" "$((10#${current_month_number} + 1))")
fi
validate_release_policy "${next_month}"

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
    if ! jq -e '
        (.ci == null) or
        ((.ci.status == "passed") and (.ci.url | type == "string" and startswith("https://")))
    ' "${release_metadata}" >/dev/null; then
        echo "Release ${release_month} contains invalid CI run metadata" >&2
        exit 1
    fi
    if ! jq -e --arg release_month "${release_month}" '
        all(.environments[];
            .releaseTag as $release_tag
            | ($release_tag | startswith($release_month + "-")) and
              (.images.dockerHub | endswith(":" + $release_tag)) and
              (.images.ricochetRegistry | endswith(":" + $release_tag))
        )
    ' "${release_metadata}" >/dev/null; then
        echo "Release ${release_month} contains a non-calendar registry tag" >&2
        exit 1
    fi
    unique_environment_count=$(jq '[.environments[].id] | unique | length' "${release_metadata}")
    containerfile_count=$(find "${release_directory}" -mindepth 2 -maxdepth 2 -name Containerfile -print | awk 'END {print NR + 0}')
    if [[ ${environment_count} == 0 || ${unique_environment_count} != "${environment_count}" || ${containerfile_count} != "${environment_count}" ]]; then
        echo "Release ${release_month} must contain matching unique metadata and Containerfiles" >&2
        exit 1
    fi
    if ! grep -Fq "[${release_month}](releases/${release_month}/)" "${repository_root}/README.md"; then
        echo "README.md does not link release ${release_month}" >&2
        exit 1
    fi
    if grep -Fq '| Platforms |' "${release_directory}/README.md"; then
        echo "Release summary must omit its redundant Platforms column: ${release_directory}/README.md" >&2
        exit 1
    fi

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
        if ! grep -Fq "[${environment_id}](./${environment_id}/)" "${release_directory}/README.md"; then
            echo "Release README does not link ${environment_id}: ${release_directory}/README.md" >&2
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
