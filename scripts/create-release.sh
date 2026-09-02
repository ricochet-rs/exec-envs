#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
release_month=${1:-$(date -u +%Y-%m)}
docker_context=${DOCKER_CONTEXT:-default}
source_registry=${RELEASE_SOURCE_REGISTRY:-reg.ricochet.rs/exec-envs}
cleanup_images=${RELEASE_CLEANUP_IMAGES:-false}
rebuild=${RELEASE_REBUILD:-false}
ci_pipeline_url=${CI_PIPELINE_URL:-}

if [[ -z ${DOCKER_CONFIG:-} ]]; then
    export DOCKER_CONFIG
    DOCKER_CONFIG=$(mktemp -d)
fi

if [[ ! ${release_month} =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "Release must use YYYY-MM format: ${release_month}" >&2
    exit 1
fi

if [[ -n ${ci_pipeline_url} && ! ${ci_pipeline_url} =~ ^https:// ]]; then
    echo "CI pipeline URL must use HTTPS: ${ci_pipeline_url}" >&2
    exit 1
fi

for command in docker jq yq; do
    if ! command -v "${command}" >/dev/null; then
        echo "Required command is unavailable: ${command}" >&2
        exit 1
    fi
done

release_directory="${repository_root}/releases/${release_month}"
archived_metadata=$(mktemp)
version_changes=$(mktemp)
remove_working_files() {
    rm -f "${archived_metadata}" "${version_changes}"
    if [[ -n ${temporary_release:-} ]]; then
        rm -rf "${temporary_release}"
    fi
}
trap remove_working_files EXIT

if [[ -d ${release_directory} && ${rebuild} != true ]]; then
    echo "Release ${release_month} already exists; leaving its pinned digests unchanged"
    "${repository_root}/scripts/render-release-readme.sh" "${release_month}"
    "${repository_root}/scripts/render-release-index.sh"
    "${repository_root}/scripts/render-environment-readmes.sh"
    "${repository_root}/scripts/render-preview-values.sh"
    exit 0
fi

if [[ ${rebuild} == true ]]; then
    if [[ ! -f ${release_directory}/release.json ]]; then
        echo "Release ${release_month} is not archived, so there is nothing to rebuild" >&2
        exit 1
    fi
    cp "${release_directory}/release.json" "${archived_metadata}"
fi

release_year=${release_month%%-*}
release_month_number=${release_month##*-}
if [[ ${release_month_number} == 12 ]]; then
    retention_until="$((10#${release_year} + 4))-01-01"
else
    retention_until=$(printf '%04d-%02d-01' "$((10#${release_year} + 3))" "$((10#${release_month_number} + 1))")
fi
mkdir -p "${repository_root}/releases"
temporary_release=$(mktemp -d "${repository_root}/releases/.${release_month}.tmp.XXXXXX")
environment_records=$(mktemp)
printf '[]\n' >"${environment_records}"

inspect_image() {
    local image_reference=$1
    local inspect_attempt
    local manifest
    local manifest_digest
    local repository
    local repository_digest

    repository=${image_reference%:*}

    for inspect_attempt in 1 2 3; do
        if manifest=$(docker --context "${docker_context}" manifest inspect "${image_reference}") &&
            docker --context "${docker_context}" pull "${image_reference}" >/dev/null &&
            repository_digest=$(docker --context "${docker_context}" image inspect "${image_reference}" --format '{{json .RepoDigests}}' |
                jq -r --arg repository "${repository}" '.[] | select(startswith($repository + "@sha256:"))' | head -n 1); then
            manifest_digest=${repository_digest##*@sha256:}
            jq --arg digest "sha256:${manifest_digest}" '. + {digest: $digest}' <<<"${manifest}"
            return
        fi
        echo "Retrying ${image_reference} after inspect attempt ${inspect_attempt}" >&2
    done

    echo "Unable to inspect ${image_reference} after ${inspect_attempt} attempts" >&2
    return 1
}

probe_image() {
    local image_reference=$1
    local pull_attempt

    for pull_attempt in 1 2 3; do
        if docker --context "${docker_context}" pull --platform linux/amd64 "${image_reference}"; then
            break
        fi
        if [[ ${pull_attempt} == 3 ]]; then
            echo "Unable to pull ${image_reference} after ${pull_attempt} attempts" >&2
            return 1
        fi
        echo "Retrying ${image_reference} after pull attempt ${pull_attempt}" >&2
    done

    docker --context "${docker_context}" run --rm --pull never --platform linux/amd64 --entrypoint /bin/sh "${image_reference}" -c '
        os_version="Not installed"
        if [ -r /etc/os-release ]; then
            . /etc/os-release
            os_version=${PRETTY_NAME:-${NAME:-Unknown}}
        fi

        r_versions=""
        for executable in R4.4 R4.5 R4.6; do
            if command -v "${executable}" >/dev/null 2>&1; then
                version=$("${executable}" --version | sed -n "1s/^R version \([^ ]*\).*/\1/p")
                case ",${r_versions}," in
                    *",${version},"*) ;;
                    *)
                        if [ -n "${r_versions}" ]; then
                            r_versions="${r_versions},${version}"
                        else
                            r_versions=${version}
                        fi
                        ;;
                esac
            fi
        done
        if [ -z "${r_versions}" ] && command -v R >/dev/null 2>&1; then
            r_versions=$(R --version | sed -n "1s/^R version \([^ ]*\).*/\1/p")
        fi
        if [ -z "${r_versions}" ]; then
            r_versions="Not installed"
        fi

        python_versions=""
        # Only the interpreters an image links into /usr/local/bin are offered runtimes.
        # A base image such as AlmaLinux 9 carries its own python3.9 on PATH, and
        # recording it would publish a runtime that has no /usr/local/bin/python3.9.
        for executable in python3.8 python3.9 python3.10 python3.11 python3.12 python3.13 python3.14 python3.15; do
            if [ -x "/usr/local/bin/${executable}" ]; then
                version=$("/usr/local/bin/${executable}" --version 2>&1 | awk "{print \$2}")
                case ",${python_versions}," in
                    *",${version},"*) ;;
                    *)
                        if [ -n "${python_versions}" ]; then
                            python_versions="${python_versions},${version}"
                        else
                            python_versions=${version}
                        fi
                        ;;
                esac
            fi
        done
        if [ -z "${python_versions}" ]; then
            python_versions="Not installed"
        fi

        julia_version=""
        for executable in julia1.10 julia1.12; do
            if command -v "${executable}" >/dev/null 2>&1; then
                version=$("${executable}" --version | awk "{print \$3}")
                if [ -n "${julia_version}" ]; then
                    julia_version="${julia_version},${version}"
                else
                    julia_version=${version}
                fi
            fi
        done
        if [ -z "${julia_version}" ] && command -v julia >/dev/null 2>&1; then
            julia_version=$(julia --version | awk "{print \$3}")
        fi
        if [ -z "${julia_version}" ]; then
            julia_version="Not installed"
        fi

        quarto_version="Not installed"
        if command -v quarto >/dev/null 2>&1; then
            quarto_version=$(quarto --version)
        fi

        printf "os\t%s\nr\t%s\npython\t%s\njulia\t%s\nquarto\t%s\n" \
            "${os_version}" "${r_versions}" "${python_versions}" "${julia_version}" "${quarto_version}"
    '
}

while IFS=$'\t' read -r environment_id image version_suffix expected_platforms; do
    if [[ -z ${environment_id} || ${environment_id} == \#* ]]; then
        continue
    fi

    release_tag="${release_month}-${version_suffix}"
    source_reference="${source_registry}/${image}:${release_tag}"
    echo "Freezing ${source_reference}"
    manifest=$(inspect_image "${source_reference}")
    digest=$(jq -r '.digest' <<<"${manifest}")
    platforms=$(jq -r '[.manifests[] | select(.platform.os != "unknown") | "\(.platform.os)/\(.platform.architecture)"] | unique | sort | join(",")' <<<"${manifest}")

    if [[ ! ${digest} =~ ^sha256:[a-f0-9]{64}$ ]]; then
        echo "Registry returned an invalid digest for ${source_reference}: ${digest}" >&2
        exit 1
    fi
    if [[ ${platforms} != "${expected_platforms}" ]]; then
        echo "Platform mismatch for ${source_reference}: expected ${expected_platforms}, found ${platforms}" >&2
        exit 1
    fi

    probe=$(probe_image "${source_reference}@${digest}")
    os_version=""
    r_versions=""
    python_versions=""
    julia_version=""
    quarto_version=""
    while IFS=$'\t' read -r key value; do
        case "${key}" in
            os) os_version=${value} ;;
            r) r_versions=${value} ;;
            python) python_versions=${value} ;;
            julia) julia_version=${value} ;;
            quarto) quarto_version=${value} ;;
        esac
    done <<<"${probe}"

    if [[ ${rebuild} == true ]]; then
        jq -r --arg id "${environment_id}" \
            --arg r "${r_versions}" \
            --arg julia "${julia_version}" \
            --arg quarto "${quarto_version}" \
            --arg python "${python_versions}" \
            '.environments[]
                | select(.id == $id)
                | {r: ($r | split(",") | map(gsub("^ +| +$"; ""))), julia: ($julia | split(",") | map(gsub("^ +| +$"; ""))), quarto: $quarto, python: ($python | split(",") | map(gsub("^ +| +$"; "")))} as $current
                | (.versions
                    | .r = (if .r | type == "array" then .r else [.r] end)
                    | .julia = (if .julia | type == "array" then .julia else [.julia] end)
                  ) as $recorded
                | [
                    (if $recorded.r != $current.r then "  \($id) R \($recorded.r | join(", ")) became \($current.r | join(", "))" else empty end),
                    (if $recorded.julia != $current.julia then "  \($id) Julia \($recorded.julia | join(", ")) became \($current.julia | join(", "))" else empty end),
                    (if $recorded.quarto != $current.quarto then "  \($id) Quarto \($recorded.quarto) became \($current.quarto)" else empty end),
                    (if $recorded.python != $current.python then "  \($id) Python \($recorded.python | join(", ")) became \($current.python | join(", "))" else empty end)
                  ][]' "${archived_metadata}" >>"${version_changes}"
    fi

    if [[ ${cleanup_images} == true ]]; then
        docker --context "${docker_context}" image rm "${source_reference}@${digest}" >/dev/null || \
            echo "Unable to remove the local probe image ${source_reference}@${digest}" >&2
    fi

    docker_hub_reference="docker.io/ricochetrs/${image}:${release_tag}"
    registry_reference="reg.ricochet.rs/exec-envs/${image}:${release_tag}"
    environment_directory="${temporary_release}/${environment_id}"
    mkdir -p "${environment_directory}"

    printf 'FROM %s@%s\n' "${docker_hub_reference}" "${digest}" >"${environment_directory}/Containerfile"

    r_versions_json=$(jq -Rn --arg versions "${r_versions}" '$versions | split(",") | map(gsub("^ +| +$"; ""))')
    python_versions_json=$(jq -Rn --arg versions "${python_versions}" '$versions | split(",") | map(gsub("^ +| +$"; ""))')
    julia_versions_json=$(jq -Rn --arg versions "${julia_version}" '$versions | split(",") | map(gsub("^ +| +$"; ""))')
    environment_record=$(jq -n \
        --arg id "${environment_id}" \
        --arg image "${image}" \
        --arg sourceTag "${release_tag}" \
        --arg releaseTag "${release_tag}" \
        --arg digest "${digest}" \
        --arg platforms "${platforms}" \
        --arg os "${os_version}" \
        --argjson r "${r_versions_json}" \
        --argjson python "${python_versions_json}" \
        --argjson julia "${julia_versions_json}" \
        --arg quarto "${quarto_version}" \
        --arg dockerHub "${docker_hub_reference}" \
        --arg registry "${registry_reference}" \
        '{
            id: $id,
            image: $image,
            sourceTag: $sourceTag,
            releaseTag: $releaseTag,
            digest: $digest,
            platforms: ($platforms | split(",")),
            versions: {os: $os, r: $r, python: $python, julia: $julia, quarto: $quarto},
            images: {dockerHub: $dockerHub, ricochetRegistry: $registry}
        }')

    jq --argjson environment "${environment_record}" '. + [$environment]' "${environment_records}" >"${environment_records}.next"
    mv "${environment_records}.next" "${environment_records}"

    cat >"${environment_directory}/README.md" <<EOF
# ${environment_id}

This exec environment is pinned to a digest from the ${release_month} release and is retained through at least ${retention_until}.
A rebuild may move it to a digest carrying operating system security fixes, while its R, Python, Julia, and Quarto versions stay as recorded below.

| Component | Version |
| --- | --- |
| Operating system | ${os_version} |
| R | ${r_versions//,/; } |
| Python | ${python_versions//,/; } |
| Julia | ${julia_version} |
| Quarto | ${quarto_version} |
| Platforms | ${platforms//,/; } |

The [Containerfile](./Containerfile) pins the current multi-platform image digest so repeated builds select the same environment.

- [Docker Hub](https://hub.docker.com/r/ricochetrs/${image}/tags?name=${release_tag})
- [Ricochet Registry](https://reg.ricochet.rs/v2/exec-envs/${image}/manifests/${release_tag})

Build the snapshot locally with:

\`\`\`sh
docker build -t exec-env:${environment_id}-${release_month} releases/${release_month}/${environment_id}
\`\`\`
EOF
done < <(
    if [[ ${rebuild} == true ]]; then
        jq -r --arg month "${release_month}" '.environments[]
            | [.id, .image, (.sourceTag | ltrimstr($month + "-")), (.platforms | join(","))]
            | @tsv' "${archived_metadata}"
    else
        "${repository_root}/scripts/list-release-environments.sh" "${release_month}"
    fi
)

if [[ ${rebuild} == true && -s ${version_changes} ]]; then
    echo "Rebuild of ${release_month} changes component versions that must stay fixed:" >&2
    cat "${version_changes}" >&2
    exit 1
fi

jq -n \
    --arg release "${release_month}" \
    --arg retentionUntil "${retention_until}" \
    --arg ciPipelineUrl "${ci_pipeline_url}" \
    --slurpfile environments "${environment_records}" \
    '{release: $release, retentionUntil: $retentionUntil, environments: $environments[0]}
        + if $ciPipelineUrl == "" then {} else {ci: {status: "passed", url: $ciPipelineUrl}} end' \
    >"${temporary_release}/release.json"

if [[ -d ${release_directory} ]]; then
    replaced_release=$(mktemp -d "${repository_root}/releases/.${release_month}.replaced.XXXXXX")
    mv "${release_directory}" "${replaced_release}/archive"
    mv "${temporary_release}" "${release_directory}"
    rm -rf "${replaced_release}"
else
    mv "${temporary_release}" "${release_directory}"
fi
"${repository_root}/scripts/render-release-readme.sh" "${release_month}"
"${repository_root}/scripts/render-release-index.sh"
"${repository_root}/scripts/render-environment-readmes.sh"
"${repository_root}/scripts/render-preview-values.sh"
if [[ ${rebuild} == true ]]; then
    echo "Rebuilt release ${release_month}; its Docker Hub calendar tags have not been moved"
else
    echo "Created release ${release_month}; its Docker Hub calendar tags have not been published"
fi
