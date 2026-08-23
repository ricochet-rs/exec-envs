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

validate_release_only_builds() {
    local pipeline
    local workflow
    local builder

    for pipeline in "${repository_root}"/.crow/*.yaml; do
        workflow=$(yq -o=json '.' "${pipeline}")
        if jq -e 'any(.steps[]?; .settings.dockerfile? != null)' <<<"${workflow}" >/dev/null; then
            echo "${pipeline} must not build a Containerfile outside the monthly release" >&2
            exit 1
        fi
    done

    while IFS= read -r builder; do
        case $(basename "${builder}") in
            release-build-amd64.yaml | release-build-arm64.yaml) ;;
            *)
                echo "${builder} must not run scripts/build-release-images.sh" >&2
                exit 1
                ;;
        esac
    done < <(grep -rl 'scripts/build-release-images.sh' "${repository_root}/.crow")
}

validate_architecture_builds() {
    local architecture
    local pipeline
    local workflow

    for architecture in amd64 arm64; do
        pipeline="${repository_root}/.crow/release-build-${architecture}.yaml"
        workflow=$(yq -o=json '.' "${pipeline}")
        # The labels are the load-bearing part. An arm64 build that lands on an amd64
        # agent falls back to emulation, which cannot build these images, and one that
        # lands on a local-backend agent execs the image field as a command.
        if ! jq -e --arg platform "linux/${architecture}" --arg architecture "${architecture}" '
            (.when.event | index("cron")) and
            (.when.event | index("manual")) and
            (.labels.backend == "docker") and
            (if $architecture == "arm64" then .labels.platform == "linux/arm64" else true end) and
            all(.steps[]; .environment.RELEASE_PLATFORM == $platform) and
            any(.steps[].commands[]?; contains("scripts/build-release-images.sh"))
        ' <<<"${workflow}" >/dev/null; then
            echo "${pipeline} must build ${architecture} images on a matching agent for cron and manual runs" >&2
            exit 1
        fi
    done
}

validate_release_triggers() {
    local manual_workflow
    local monthly_workflow
    local rebuild_workflow

    monthly_workflow=$(yq -o=json '.' "${repository_root}/.crow/monthly-release.yaml")
    if ! jq -e '
        all(.when.event[]; . != "manual") and
        all(.steps[].when.event[]?; . != "manual") and
        ([.steps[].environment.RELEASE_REBUILD? // empty] | length == 0)
    ' <<<"${monthly_workflow}" >/dev/null; then
        echo ".crow/monthly-release.yaml must reserve full releases for cron events and never rebuild an archived month" >&2
        exit 1
    fi

    rebuild_workflow=$(yq -o=json '.' "${repository_root}/.crow/manual-release-rebuild.yaml")
    if ! jq -e '
        (.when.event == ["manual"]) and
        (.when.branch == ["main"]) and
        (.variables.RELEASE_MONTH.required == true) and
        (.variables | has("RELEASE_REBUILD")) and
        (.depends_on | index("release-build-amd64")) and
        (.depends_on | index("release-build-arm64")) and
        any(.steps[].commands[]?; contains("scripts/merge-release-images.sh")) and
        any(.steps[].commands[]?; contains("RELEASE_REBUILD"))
    ' <<<"${rebuild_workflow}" >/dev/null; then
        echo ".crow/manual-release-rebuild.yaml must merge a required month and refuse to run without RELEASE_REBUILD" >&2
        exit 1
    fi

    manual_workflow=$(yq -o=json '.' "${repository_root}/.crow/manual-release-image.yaml")
    if ! jq -e '
        (.when.event == ["manual"]) and
        (.when.branch == ["main"]) and
        any(.steps[].commands[]?; contains("RELEASE_ENVIRONMENT")) and
        any(.steps[].commands[]?; contains("scripts/merge-release-images.sh"))
    ' <<<"${manual_workflow}" >/dev/null; then
        echo ".crow/manual-release-image.yaml must compose one calendar tag through Crow variables" >&2
        exit 1
    fi
}

validate_renovate_targets() {
    local definition
    local marked_entries
    local marked_entry_count
    local marked_julia
    local latest_julia
    local marked_os
    local latest_os

    for definition in "${repository_root}"/release/environments/julia-*.yaml; do
        marked_entries=$(mktemp)
        yq -r '.environments[]
            | select((.JULIA_VERSION | line_comment) == "renovate: julia-current")
            | [.JULIA_VERSION, .OS_VERSION]
            | @tsv' "${definition}" >"${marked_entries}"
        marked_entry_count=$(awk 'END {print NR + 0}' "${marked_entries}")
        latest_julia=$(yq -r '.environments[].JULIA_VERSION' "${definition}" | sort -Vu | tail -n 1)
        marked_julia=$(cut -f1 "${marked_entries}")

        if [[ ${marked_entry_count} != 1 || ${marked_julia} != "${latest_julia}" ]]; then
            echo "${definition} must mark exactly its newest Julia definition as renovate: julia-current" >&2
            exit 1
        fi

        if [[ $(basename "${definition}") == julia-alpine.yaml ]]; then
            latest_os=$(yq -r '.environments[].OS_VERSION' "${definition}" | sort -Vu | tail -n 1)
            marked_os=$(cut -f2 "${marked_entries}")
            if [[ ${marked_os} != "${latest_os}" ]]; then
                echo "${definition} must restrict Renovate to its newest Alpine definition" >&2
                exit 1
            fi
        fi
    done
}

list_release_metadata() {
    if [[ -d ${repository_root}/releases ]]; then
        find "${repository_root}/releases" -mindepth 2 -maxdepth 2 -name release.json -print
    fi
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

validate_release_only_builds
validate_architecture_builds
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
    if ! "${repository_root}/scripts/render-release-notes.sh" "${release_month}" | grep -Fq '## Environments'; then
        echo "Release notes do not render for ${release_month}" >&2
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
done < <(list_release_metadata | sort)

if [[ ${release_count} == 0 ]]; then
    echo "No monthly releases are archived yet"
    exit 0
fi

echo "Validated ${release_count} monthly release(s)"
