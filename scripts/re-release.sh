#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
release_month=${1:-}

if [[ ! ${release_month} =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "Usage: $0 YYYY-MM" >&2
    exit 1
fi

# Discarding the archive is what separates a re-release from a rebuild: create-release.sh
# then inventories the month from scratch instead of holding it to the versions it recorded.
rm -rf "${repository_root:?}/releases/${release_month}"

# RELEASE_REBUILD stops the merge reusing a calendar tag that already exists, which
# would otherwise reproduce the index this run exists to replace. The images behind it
# come from the release-build-amd64 and release-build-arm64 workflows, which must have
# run for this month with RELEASE_REBUILD=true first.
RELEASE_REBUILD=true "${repository_root}/scripts/merge-release-images.sh" "${release_month}"
"${repository_root}/scripts/create-release.sh" "${release_month}"

echo "Re-created release ${release_month}; publish it with RELEASE_REBUILD=true to move its calendar tags"
