#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repository_root}"
month=${1:-$(date -u +%Y-%m)}
if [[ ! ${month} =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
  echo "Month must use YYYY-MM format: ${month}" >&2
  exit 1
fi
if [[ -n $(git status --porcelain) ]]; then
  echo "Run scheduled dependency updates in a clean checkout" >&2
  exit 1
fi
branch="chore/r-sysreqs-${month}"
base=${CI_REPO_DEFAULT_BRANCH:-main}
existing_pr=$(gh pr list --head "${branch}" --state all --json url --jq '.[0].url // empty')
if [[ -n ${existing_pr} ]]; then
  echo "Monthly dependency update already has a PR: ${existing_pr}"
  exit 0
fi

temporary=$(mktemp -d)
trap 'rm -rf "${temporary}"' EXIT
gh auth setup-git
git fetch origin "${base}"
# Recover a push that succeeded before a previous PR creation attempt failed.
remote_branch=$(git ls-remote --heads origin "refs/heads/${branch}")
if [[ -n ${remote_branch} ]]; then
  git fetch origin "${branch}"
  git switch -c "${branch}" FETCH_HEAD
else
  git switch -c "${branch}" "origin/${base}"
  revision=$(gh api repos/rstudio/r-system-requirements/commits/main --jq .sha)
  if [[ ! ${revision} =~ ^[a-f0-9]{40}$ ]]; then
    echo "Upstream returned an invalid commit SHA" >&2
    exit 1
  fi
  if [[ ${revision} == "$(jq -r .revision r/sysreqs/config.json)" ]]; then
    echo "R system requirements already use the latest upstream revision"
    exit 0
  fi
  jq --arg revision "${revision}" '.revision = $revision' r/sysreqs/config.json >"${temporary}/config.json"
  mv "${temporary}/config.json" r/sysreqs/config.json
  scripts/update-r-sysreqs.sh
  bunx prettier@3.9.6 --write r/sysreqs/config.json r/sysreqs/*/manifest.json .crow/r-sysreqs-build-*.yaml
  scripts/test-r-sysreqs.sh
  scripts/update-r-sysreqs.sh --check
  git add r/sysreqs .crow/r-sysreqs-build-*.yaml
  git config user.name ricochet-bot
  git config user.email droid@ricochet.rs
  git commit -m "chore(r): update system requirements for ${month}"
  git push origin "HEAD:refs/heads/${branch}"
fi

previous=$(git show "origin/${base}:r/sysreqs/config.json" | jq -r .revision)
revision=$(jq -r .revision r/sysreqs/config.json)
{
  cat <<'EOF'
Refresh the pinned R system requirements catalog and generated installers for the next monthly release.

<details>
<summary>AI Summary</summary>

EOF
  printf 'Review the [upstream changes](https://github.com/rstudio/r-system-requirements/compare/%s...%s) alongside the generated package and setup-command diffs.\n\n' "${previous}" "${revision}"
  cat <<'EOF'
Exclusions and overrides stay explicit in `r/sysreqs/config.json`.
Requirements without platform mappings remain listed in the manifests.
Generator tests and regeneration checks pass before this PR is opened.
The R image validation workflows build every configured target on native AMD64 and ARM64 workers without publishing images.
Review new setup commands, coverage exceptions, package availability, and image size before merging; this PR does not enable automerge.

| Target | Explicit system packages | Unmapped rules |
| --- | --- | --- |
EOF
  for manifest in r/sysreqs/*/manifest.json; do
    jq -r '"| \(.platform.id) | \(.packages | length) | \(.unmapped | length) |"' "${manifest}"
  done
  printf '\n</details>\n'
} >"${temporary}/body.md"
gh pr create --base "${base}" --head "${branch}" \
  --title "chore(r): update system requirements for ${month}" --body-file "${temporary}/body.md"
