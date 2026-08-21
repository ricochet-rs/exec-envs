#!/usr/bin/env bash

set -euo pipefail

repository_root=${RELEASE_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}
current_month=${1:-$(date -u +%Y-%m)}
docker_context=${DOCKER_CONTEXT:-default}
alpine_mirror=${ALPINE_IMAGE_REGISTRY:-reg.ricochet.rs/docker.io/library/alpine}
r_base_registry=${R_ALPINE_BASE_REGISTRY:-reg.devxy.io/r/r-alpine}

if [[ ! ${current_month} =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "Release must use YYYY-MM format: ${current_month}" >&2
    exit 1
fi

required_commands=(jq sed yq)
if [[ -z ${ALPINE_LATEST_VERSION:-} ]]; then
    required_commands+=(docker)
fi
for command in "${required_commands[@]}"; do
    if ! command -v "${command}" >/dev/null; then
        echo "Required command is unavailable: ${command}" >&2
        exit 1
    fi
done

month_before() {
    local month=$1
    local year=${month%%-*}
    local month_number=${month##*-}

    if [[ ${month_number} == 01 ]]; then
        printf '%04d-12\n' "$((10#${year} - 1))"
    else
        printf '%04d-%02d\n' "${year}" "$((10#${month_number} - 1))"
    fi
}

month_after() {
    local month=$1
    local year=${month%%-*}
    local month_number=${month##*-}

    if [[ ${month_number} == 12 ]]; then
        printf '%04d-01\n' "$((10#${year} + 1))"
    else
        printf '%04d-%02d\n' "${year}" "$((10#${month_number} + 1))"
    fi
}

alpine_after() {
    local version=$1
    local major=${version%%.*}
    local minor=${version##*.}

    printf '%d.%d\n' "${major}" "$((10#${minor} + 1))"
}

image_exists() {
    local image_reference=$1

    docker --context "${docker_context}" buildx imagetools inspect "${image_reference}" --format '{{json .Manifest}}' >/dev/null 2>&1
}

alpine_candidate_is_ready() {
    local candidate=$1
    local r_version

    if ! image_exists "${alpine_mirror}:${candidate}"; then
        return 1
    fi

    while IFS= read -r r_version; do
        if ! image_exists "${r_base_registry}:${r_version}-${candidate}"; then
            echo "Alpine ${candidate} exists, but ${r_base_registry}:${r_version}-${candidate} is not ready" >&2
            return 1
        fi
    done < <(yq -r '.matrix.include[].R_VERSION' "${repository_root}/.crow/alpine-build-static.yaml" | sort -Vu)
}

target_month=$(month_after "${current_month}")
previous_month=$(month_before "${current_month}")
matrix_files=(
    "${repository_root}/.crow/alpine-build-static.yaml"
    "${repository_root}/.crow/julia-alpine-build-static.yaml"
)

configured_latest=$(for matrix_file in "${matrix_files[@]}"; do
    yq -r '.matrix.include[].OS_VERSION' "${matrix_file}"
done | sort -Vu | tail -n 1)
latest_alpine=${ALPINE_LATEST_VERSION:-${configured_latest}}

if [[ ! ${latest_alpine} =~ ^[0-9]+\.[0-9]+$ || ${latest_alpine##*.} == 0 ]]; then
    echo "Invalid Alpine minor version: ${latest_alpine}" >&2
    exit 1
fi

if [[ -z ${ALPINE_LATEST_VERSION:-} ]]; then
    if [[ -z ${DOCKER_CONFIG:-} ]]; then
        export DOCKER_CONFIG
        DOCKER_CONFIG=$(mktemp -d)
    fi
    candidate=$(alpine_after "${latest_alpine}")
    while alpine_candidate_is_ready "${candidate}"; do
        latest_alpine=${candidate}
        candidate=$(alpine_after "${latest_alpine}")
    done
fi

previous_alpine=${latest_alpine%%.*}.$((10#${latest_alpine##*.} - 1))

for matrix_file in "${matrix_files[@]}"; do
    matrix_latest=$(yq -r '.matrix.include[].OS_VERSION' "${matrix_file}" | sort -Vu | tail -n 1)

    if ! LATEST_ALPINE=${latest_alpine} yq -e '.matrix.include[] | select((.OS_VERSION | tostring) == strenv(LATEST_ALPINE))' "${matrix_file}" >/dev/null 2>&1; then
        # shellcheck disable=SC2016
        OLD_ALPINE=${matrix_latest} NEW_ALPINE=${latest_alpine} TARGET_MONTH=${target_month} yq -i '
            (.matrix.include | map(select((.OS_VERSION | tostring) == strenv(OLD_ALPINE)))) as $templates
            | .matrix.include = (
                [$templates[]
                    | .OS_VERSION = (strenv(NEW_ALPINE) | tonumber)
                    | .release_from = strenv(TARGET_MONTH)
                    | del(.release_through)
                    | . * (({
                        "tag_additional": (
                            (.tag_additional // "")
                            | split(",")
                            | map(
                                select(test("-[0-9]+\\.[0-9]+$"))
                                | sub("-[0-9]+\\.[0-9]+$"; "-" + strenv(NEW_ALPINE))
                            )
                            | join(",")
                        )
                      } | select(.tag_additional != "")) // {})
                ] + .matrix.include
            )
        ' "${matrix_file}"
        echo "Added Alpine ${latest_alpine} to $(basename "${matrix_file}") for ${target_month}"
    fi

    if [[ $(basename "${matrix_file}") == alpine-build-static.yaml ]]; then
        # shellcheck disable=SC2016
        LATEST_ALPINE=${latest_alpine} yq -i '
            with(.matrix.include[];
                .OS_VERSION as $os_version
                | .R_VERSION as $r_version
                | .tag_additional = (
                    (
                        ([($r_version | tostring)]
                            | select(($os_version | tostring) == strenv(LATEST_ALPINE))) // []
                    ) + [
                        .tag_additional
                        | split(",")[]
                        | select(test("-[0-9]+\\.[0-9]+$"))
                    ]
                    | join(",")
                )
            )
        ' "${matrix_file}"
    fi

    # shellcheck disable=SC2016
    LATEST_ALPINE=${latest_alpine} PREVIOUS_ALPINE=${previous_alpine} CURRENT_MONTH=${current_month} yq -i '
        with(.matrix.include[]
            | select(
                (.OS_VERSION | tostring) != strenv(LATEST_ALPINE) and
                (.OS_VERSION | tostring) != strenv(PREVIOUS_ALPINE) and
                ((.release_through // "") == "")
            );
            .release_through = strenv(CURRENT_MONTH)
        )
    ' "${matrix_file}"

    # shellcheck disable=SC2016
    PREVIOUS_MONTH=${previous_month} yq -i '
        .matrix.include |= map(
            select(
                (has("release_through") | not) or
                .release_through >= strenv(PREVIOUS_MONTH)
            )
        )
    ' "${matrix_file}"
done

for containerfile in "${repository_root}/r-alpine/Containerfile" "${repository_root}/julia-alpine/Containerfile"; do
    sed -i -E "s/^ARG OS_VERSION=.*/ARG OS_VERSION=${latest_alpine}/" "${containerfile}"
done

active_alpine_versions=$("${repository_root}/scripts/list-release-environments.sh" "${target_month}" |
    awk -F '\t' '$2 ~ /-alpine$/ {
        field_count = split($3, fields, "-")
        print fields[field_count]
    }' | sort -Vu)
if [[ ${active_alpine_versions} != "${previous_alpine}"$'\n'"${latest_alpine}" ]]; then
    echo "Prepared ${target_month} Alpine window is not ${previous_alpine} and ${latest_alpine}" >&2
    exit 1
fi

echo "Prepared ${target_month} with Alpine ${latest_alpine} and ${previous_alpine}"
