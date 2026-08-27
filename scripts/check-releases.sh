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

# Each matrix names the Containerfile the build workflows hand to buildx, so an
# environment that moved without its declaration fails here, not in a monthly build.
validate_environment_containerfiles() {
    local definition
    local containerfile

    for definition in "${repository_root}"/release/environments/*.yaml; do
        containerfile=$(yq -r '.containerfile // ""' "${definition}")
        if [[ -z ${containerfile} ]]; then
            echo "$(basename "${definition}") does not declare a containerfile" >&2
            exit 1
        fi
        if [[ ! -f ${repository_root}/${containerfile} ]]; then
            echo "$(basename "${definition}") declares a missing Containerfile: ${containerfile}" >&2
            exit 1
        fi
    done
}

# The build and merge workflows are generated, so drift means someone edited one by
# hand and forgot the generator.
validate_generated_workflows() {
    local rendered
    local generated
    local existing

    rendered=$(mktemp -d)
    "${repository_root}/scripts/render-release-workflows.sh" "${rendered}" >/dev/null

    for generated in "${rendered}"/*.yaml; do
        if ! cmp -s "${generated}" "${repository_root}/.crow/$(basename "${generated}")"; then
            echo ".crow/$(basename "${generated}") does not match scripts/render-release-workflows.sh" >&2
            rm -rf "${rendered}"
            exit 1
        fi
    done

    for existing in "${repository_root}"/.crow/build-*.yaml "${repository_root}"/.crow/merge-*.yaml \
        "${repository_root}"/.crow/publish.yaml; do
        if [[ ! -f ${rendered}/$(basename "${existing}") ]]; then
            echo "$(basename "${existing}") is not produced by scripts/render-release-workflows.sh" >&2
            rm -rf "${rendered}"
            exit 1
        fi
    done

    rm -rf "${rendered}"
}

validate_generated_environment_readmes() {
    local definition
    local rendered
    local relative_readme

    rendered=$(mktemp -d)
    "${repository_root}/scripts/render-environment-readmes.sh" "" "${rendered}"

    for definition in "${repository_root}"/release/environments/*.yaml; do
        relative_readme=$(dirname "$(yq -r '.containerfile' "${definition}")")/README.md
        if ! cmp -s "${rendered}/${relative_readme}" "${repository_root}/${relative_readme}"; then
            echo "${relative_readme} does not match scripts/render-environment-readmes.sh" >&2
            rm -rf "${rendered}"
            exit 1
        fi
    done

    rm -rf "${rendered}"
}

# Images must reach the registry through the plugin, and an arm64 build must stay on
# an arm64 Docker agent: losing the platform label falls back to emulation these
# images cannot survive, and losing the backend label lands on an agent that execs
# the image field as a command.
validate_plugin_builds() {
    local pipeline
    local workflow
    local architecture

    for pipeline in "${repository_root}"/.crow/build-*.yaml "${repository_root}"/.crow/merge-*.yaml \
        "${repository_root}"/.crow/publish.yaml; do
        workflow=$(yq -o=json '.' "${pipeline}")
        architecture=$(basename "${pipeline}" .yaml)
        architecture=${architecture##*-}
        if ! jq -e --arg name "$(basename "${pipeline}" .yaml)" '
            (.labels.backend == "docker") and
            (.variables.RELEASE_MONTH.required == true) and
            (.variables.RELEASE_REBUILD.default == "false") and
            all(.steps[]; .image | startswith("codefloe.com/crow-plugins/docker-buildx:")) and
            all(.steps[]; .when.evaluate | contains("release_from") and contains("release_through")) and
            (if $name == "build-arm64" then .labels.platform == "linux/arm64" else true end)
        ' <<<"${workflow}" >/dev/null; then
            echo "${pipeline} must build through the buildx plugin on a matching Docker agent for a required month" >&2
            exit 1
        fi
    done

    if grep -rlq 'docker buildx build' "${repository_root}/.crow" ||
        grep -rlq 'imagetools create' "${repository_root}/.crow"; then
        echo ".crow must not drive buildx directly; the plugin owns building and merging" >&2
        exit 1
    fi

    # Keep the Docker Hub token limited to publishing and release verification.
    while IFS= read -r consumer; do
        case $(basename "${consumer}") in
            manual-release-rebuild.yaml | monthly-release.yaml | publish.yaml) ;;
            *)
                echo "${consumer} must not use ricochet_dockerhub_token; only release publishing and verification may" >&2
                exit 1
                ;;
        esac
    done < <(grep -rl 'ricochet_dockerhub_token' "${repository_root}/.crow")
}

validate_release_triggers() {
    local monthly_workflow
    local rebuild_workflow

    # Crow cron cannot pass a variable and offers no date, so a release states its
    # month explicitly rather than deriving it from the clock.
    monthly_workflow=$(yq -o=json '.' "${repository_root}/.crow/monthly-release.yaml")
    if ! jq -e '
        (.when.event == ["manual"]) and
        (.when.branch == ["main"]) and
        (.variables.RELEASE_MONTH.required == true) and
        (.variables.RELEASE_REBUILD.default == "false") and
        (.variables.RELEASE_RERELEASE.default == "false") and
        (.depends_on | index("publish")) and
        all(.steps[]; .when.evaluate | contains("RELEASE_RERELEASE")) and
        any(.steps[].commands[]?; contains("scripts/re-release.sh"))
    ' <<<"${monthly_workflow}" >/dev/null; then
        echo ".crow/monthly-release.yaml must release a stated month and isolate explicit re-releases" >&2
        exit 1
    fi

    rebuild_workflow=$(yq -o=json '.' "${repository_root}/.crow/manual-release-rebuild.yaml")
    if ! jq -e '
        (.when.event == ["manual"]) and
        (.when.branch == ["main"]) and
        (.variables.RELEASE_MONTH.required == true) and
        (.variables | has("RELEASE_REBUILD")) and
        (.variables.RELEASE_RERELEASE.default == "false") and
        (.depends_on | index("publish")) and
        all(.steps[]; .when.evaluate | contains("RELEASE_RERELEASE")) and
        any(.steps[].commands[]?; contains("RELEASE_REBUILD"))
    ' <<<"${rebuild_workflow}" >/dev/null; then
        echo ".crow/manual-release-rebuild.yaml must rebuild a stated month and refuse to run without RELEASE_REBUILD" >&2
        exit 1
    fi
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

validate_environment_containerfiles
validate_generated_workflows
validate_generated_environment_readmes
validate_plugin_builds
validate_release_triggers

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
    local manifest_digest

    for inspect_attempt in 1 2 3; do
        if manifest=$(docker --context "${docker_context}" buildx imagetools inspect --raw "${image_reference}"); then
            manifest_digest=$(printf '%s' "${manifest}" | sha256sum | cut -d' ' -f1)
            printf 'sha256:%s\n' "${manifest_digest}"
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
    rendered_release_notes=$(mktemp)
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
    if ! "${repository_root}/scripts/render-release-notes.sh" "${release_month}" >"${rendered_release_notes}"; then
        echo "Release notes fail to render for ${release_month}" >&2
        exit 1
    fi
    if ! grep -Fq '## Environments' "${rendered_release_notes}"; then
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
