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

for pipeline in "${repository_root}"/.crow/*-build-static.yaml; do
    workflow=$(yq -o=json '.' "${pipeline}")
    platforms=$(jq -r '[.steps[].settings.platforms // empty] | unique | if length == 1 then .[0] else empty end' <<<"${workflow}")

    if [[ -z ${platforms} ]]; then
        echo "Build validation steps disagree on platforms in ${pipeline}" >&2
        exit 1
    fi

    if ! jq -e 'all(.matrix.include[];
        ((.release_from // "0000-01") | test("^[0-9]{4}-(0[1-9]|1[0-2])$")) and
        ((.release_through // "9999-12") | test("^[0-9]{4}-(0[1-9]|1[0-2])$")) and
        ((.release_from // "0000-01") <= (.release_through // "9999-12"))
    )' <<<"${workflow}" >/dev/null; then
        echo "Invalid release lifecycle in ${pipeline}" >&2
        exit 1
    fi

    jq -r --arg output_format "${output_format}" --arg platforms "${platforms}" --arg release_month "${release_month}" '
        .matrix.include[]
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
            id: (.name + "-" + $version_suffix),
            image: .name,
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
    ' <<<"${workflow}"
done | LC_ALL=C sort
