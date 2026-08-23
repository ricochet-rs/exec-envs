#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
github_repository=${RELEASE_GITHUB_REPOSITORY:-ricochet-rs/exec-envs}
dry_run=${RELEASE_NOTES_DRY_RUN:-false}
selected_month=${1:-}

if [[ -n ${selected_month} && ! ${selected_month} =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "Release must use YYYY-MM format: ${selected_month}" >&2
    exit 1
fi

if [[ ${dry_run} != true ]] && ! command -v gh >/dev/null; then
    echo "Required command is unavailable: gh" >&2
    exit 1
fi

archived_months=$(find "${repository_root}/releases" -mindepth 2 -maxdepth 2 -name release.json -print |
    while IFS= read -r archived_metadata; do basename "$(dirname "${archived_metadata}")"; done |
    LC_ALL=C sort)
newest_month=$(tail -n 1 <<<"${archived_months}")

if [[ -n ${selected_month} ]]; then
    if ! grep -Fxq "${selected_month}" <<<"${archived_months}"; then
        echo "Release is not archived: ${selected_month}" >&2
        exit 1
    fi
    archived_months=${selected_month}
fi

notes=$(mktemp)
trap 'rm -f "${notes}"' EXIT

while IFS= read -r release_month; do
    "${repository_root}/scripts/render-release-notes.sh" "${release_month}" >"${notes}"
    latest=false
    if [[ ${release_month} == "${newest_month}" ]]; then
        latest=true
    fi

    if [[ ${dry_run} == true ]]; then
        echo "Would publish ${github_repository} release ${release_month} (latest=${latest})"
        continue
    fi

    if published_notes=$(gh release view "${release_month}" --repo "${github_repository}" --json body --jq .body 2>/dev/null); then
        if [[ $(tr -d '\r' <<<"${published_notes}") == "$(cat "${notes}")" ]]; then
            echo "Release notes are already published: ${release_month}"
            continue
        fi
        echo "Updating release notes: ${release_month}"
        gh release edit "${release_month}" \
            --repo "${github_repository}" \
            --title "${release_month}" \
            --notes-file "${notes}" \
            --latest="${latest}"
        continue
    fi

    # Point the tag at the commit that archived the month rather than at the current branch head.
    archive_commit=$(git -C "${repository_root}" log -1 --format=%H -- "releases/${release_month}")
    if [[ -z ${archive_commit} ]]; then
        archive_commit=$(git -C "${repository_root}" rev-parse HEAD)
    fi
    echo "Publishing release notes: ${release_month}"
    gh release create "${release_month}" \
        --repo "${github_repository}" \
        --target "${archive_commit}" \
        --title "${release_month}" \
        --notes-file "${notes}" \
        --latest="${latest}"
done <<<"${archived_months}"
