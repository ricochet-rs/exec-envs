#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
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
    platforms=$(jq -r '.steps["Build and publish image (cron)"].settings.platforms' <<<"${workflow}")

    if ! jq -e 'all(.matrix.include[];
        ((.release_from // "0000-01") | test("^[0-9]{4}-(0[1-9]|1[0-2])$")) and
        ((.release_through // "9999-12") | test("^[0-9]{4}-(0[1-9]|1[0-2])$")) and
        ((.release_from // "0000-01") <= (.release_through // "9999-12"))
    )' <<<"${workflow}" >/dev/null; then
        echo "Invalid release lifecycle in ${pipeline}" >&2
        exit 1
    fi

    jq -r --arg platforms "${platforms}" --arg release_month "${release_month}" '
        .matrix.include[]
        | select(
            (.release_from // "0000-01") <= $release_month and
            (.release_through // "9999-12") >= $release_month
        )
        | (
            if has("tag_additional") then
                (.tag_additional | split(",")[-1])
            else
                (.JULIA_VERSION + "-" + (.OS_VERSION | tostring))
            end
        ) as $source_tag
        | [(.name + "-" + $source_tag), .name, $source_tag, $platforms]
        | @tsv
    ' <<<"${workflow}"
done | LC_ALL=C sort
