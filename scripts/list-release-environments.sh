#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
output_format=tsv

if [[ ${1:-} == --json ]]; then
    output_format=json
    shift
fi

release_month=${1:-$(date -u +%Y-%m)}

if [[ ! ${release_month} =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "Release must use YYYY-MM format: ${release_month}" >&2
    exit 1
fi

for command in jq yq; do
    if ! command -v "${command}" >/dev/null; then
        echo "Required command is unavailable: ${command}" >&2
        exit 1
    fi
done

for definition in "${repository_root}"/release/environments/*.yaml; do
    matrix=$(yq -o=json '.' "${definition}")

    if ! jq -e '
        (.image | type == "string" and length > 0) and
        (.platforms | type == "string" and length > 0) and
        (.environments | type == "array" and length > 0)
    ' <<<"${matrix}" >/dev/null; then
        echo "Environment definition must declare an image, platforms, and environments: ${definition}" >&2
        exit 1
    fi

    if ! jq -e 'all(.environments[];
        ((.release_from // "0000-01") | test("^[0-9]{4}-(0[1-9]|1[0-2])$")) and
        ((.release_through // "9999-12") | test("^[0-9]{4}-(0[1-9]|1[0-2])$")) and
        ((.release_from // "0000-01") <= (.release_through // "9999-12"))
    )' <<<"${matrix}" >/dev/null; then
        echo "Invalid release lifecycle in ${definition}" >&2
        exit 1
    fi

    jq -r --arg output_format "${output_format}" --arg release_month "${release_month}" '
        .image as $image
        | .platforms as $platforms
        | .environments[]
        | select(
            (.release_from // "0000-01") <= $release_month and
            (.release_through // "9999-12") >= $release_month
        )
        | (
            if has("release_suffix") then
                .release_suffix
            else
                (.JULIA_VERSION + "-" + (.OS_VERSION | tostring))
            end
        ) as $version_suffix
        | {
            id: ($image + "-" + $version_suffix),
            image: $image,
            versionSuffix: $version_suffix,
            platforms: $platforms,
            buildArgs: {
                R_VERSION: .R_VERSION,
                JULIA_VERSION: .JULIA_VERSION,
                OS_VERSION: .OS_VERSION
            } | with_entries(select(.value != null))
        }
        | if $output_format == "json" then
            @json
          else
            [.id, .image, .versionSuffix, .platforms] | @tsv
          end
    ' <<<"${matrix}"
done | LC_ALL=C sort
