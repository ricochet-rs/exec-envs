#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
release_month=${1:-$(date -u +%Y-%m)}
docker_context=${DOCKER_CONTEXT:-default}
source_registry=${RELEASE_SOURCE_REGISTRY:-reg.ricochet.rs/exec-envs}
cleanup_images=${RELEASE_CLEANUP_IMAGES:-false}

if [[ -z ${DOCKER_CONFIG:-} ]]; then
    export DOCKER_CONFIG
    DOCKER_CONFIG=$(mktemp -d)
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

release_directory="${repository_root}/releases/${release_month}"
if [[ -d ${release_directory} ]]; then
    echo "Release ${release_month} already exists; leaving its pinned digests unchanged"
    "${repository_root}/scripts/render-release-index.sh"
    exit 0
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

    for inspect_attempt in 1 2 3; do
        if manifest=$(docker --context "${docker_context}" buildx imagetools inspect "${image_reference}" --format '{{json .Manifest}}'); then
            printf '%s\n' "${manifest}"
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

        r_version="Not installed"
        if command -v R >/dev/null 2>&1; then
            r_version=$(R --version | sed -n "1s/^R version \([^ ]*\).*/\1/p")
        fi

        python_versions=""
        for executable in python3.8 python3.9 python3.10 python3.11 python3.12 python3.13 python3.14 python3.15; do
            if command -v "${executable}" >/dev/null 2>&1; then
                version=$("${executable}" --version 2>&1 | awk "{print \$2}")
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

        julia_version="Not installed"
        if command -v julia >/dev/null 2>&1; then
            julia_version=$(julia --version | awk "{print \$3}")
        fi

        quarto_version="Not installed"
        if command -v quarto >/dev/null 2>&1; then
            quarto_version=$(quarto --version)
        fi

        printf "os\t%s\nr\t%s\npython\t%s\njulia\t%s\nquarto\t%s\n" \
            "${os_version}" "${r_version}" "${python_versions}" "${julia_version}" "${quarto_version}"
    '
}

while IFS=$'\t' read -r environment_id image source_tag expected_platforms; do
    if [[ -z ${environment_id} || ${environment_id} == \#* ]]; then
        continue
    fi

    source_reference="${source_registry}/${image}:${source_tag}"
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
    r_version=""
    python_versions=""
    julia_version=""
    quarto_version=""
    while IFS=$'\t' read -r key value; do
        case "${key}" in
            os) os_version=${value} ;;
            r) r_version=${value} ;;
            python) python_versions=${value} ;;
            julia) julia_version=${value} ;;
            quarto) quarto_version=${value} ;;
        esac
    done <<<"${probe}"

    if [[ ${cleanup_images} == true ]]; then
        docker --context "${docker_context}" image rm "${source_reference}@${digest}" >/dev/null || \
            echo "Unable to remove the local probe image ${source_reference}@${digest}" >&2
    fi

    release_tag="${release_month}-${source_tag}"
    docker_hub_reference="docker.io/ricochetrs/${image}:${release_tag}"
    registry_reference="reg.ricochet.rs/exec-envs/${image}:${release_tag}"
    environment_directory="${temporary_release}/${environment_id}"
    mkdir -p "${environment_directory}"

    printf 'FROM %s@%s\n' "${docker_hub_reference}" "${digest}" >"${environment_directory}/Containerfile"

    python_versions_json=$(jq -Rn --arg versions "${python_versions}" '$versions | split(",") | map(gsub("^ +| +$"; ""))')
    environment_record=$(jq -n \
        --arg id "${environment_id}" \
        --arg image "${image}" \
        --arg sourceTag "${source_tag}" \
        --arg releaseTag "${release_tag}" \
        --arg digest "${digest}" \
        --arg platforms "${platforms}" \
        --arg os "${os_version}" \
        --arg r "${r_version}" \
        --argjson python "${python_versions_json}" \
        --arg julia "${julia_version}" \
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

This exec environment is an immutable snapshot from the ${release_month} release and is retained through at least ${retention_until}.

| Component | Version |
| --- | --- |
| Operating system | ${os_version} |
| R | ${r_version} |
| Python | ${python_versions//,/; } |
| Julia | ${julia_version} |
| Quarto | ${quarto_version} |
| Platforms | ${platforms//,/; } |

The [Containerfile](./Containerfile) pins the multi-platform image digest so repeated builds select the same environment.

- [Docker Hub](https://hub.docker.com/r/ricochetrs/${image}/tags?name=${release_tag})
- [Ricochet Registry](https://reg.ricochet.rs/v2/exec-envs/${image}/manifests/${release_tag})

Build the snapshot locally with:

\`\`\`sh
docker build -t exec-env:${environment_id}-${release_month} releases/${release_month}/${environment_id}
\`\`\`
EOF
done < <("${repository_root}/scripts/list-release-environments.sh" "${release_month}")

jq -n \
    --arg release "${release_month}" \
    --arg retentionUntil "${retention_until}" \
    --slurpfile environments "${environment_records}" \
    '{release: $release, retentionUntil: $retentionUntil, environments: $environments[0]}' \
    >"${temporary_release}/release.json"

{
    printf '# %s exec environments\n\n' "${release_month}"
    printf 'This release is retained through at least %s.\n\n' "${retention_until}"
    echo '| Environment | R | Python | Julia | Quarto | Platforms |'
    echo '| --- | --- | --- | --- | --- | --- |'
    jq -r '.environments[] | "| [\(.id)](./\(.id)/) | \(.versions.r) | \(.versions.python | join(", ")) | \(.versions.julia) | \(.versions.quarto) | \(.platforms | join(", ")) |"' \
        "${temporary_release}/release.json"
} >"${temporary_release}/README.md"

mv "${temporary_release}" "${release_directory}"
"${repository_root}/scripts/render-release-index.sh"
echo "Created release ${release_month}; its immutable registry tags have not been published"
