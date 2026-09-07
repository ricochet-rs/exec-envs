#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary=$(mktemp -d)
trap 'rm -rf "${temporary}"' EXIT
export SYSREQS_TEST_STATE="${temporary}/state"
export SYSREQS_TEST_REVISION=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
mkdir -p "${temporary}/bin" "${SYSREQS_TEST_STATE}" "${temporary}/seed/scripts" "${temporary}/seed/r/sysreqs/test" "${temporary}/seed/.crow"

cat >"${temporary}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  'pr list')
    if [[ -f ${SYSREQS_TEST_STATE}/pr ]]; then cat "${SYSREQS_TEST_STATE}/pr"; fi ;;
  'auth setup-git') ;;
  'api repos/rstudio/r-system-requirements/commits/main') printf '%s\n' "${SYSREQS_TEST_REVISION}" ;;
  'pr create')
    while [[ $# -gt 0 ]]; do
      if [[ $1 == --body-file ]]; then cp "$2" "${SYSREQS_TEST_STATE}/body.md"; break; fi
      shift
    done
    echo 'https://github.com/example/test/pull/1' | tee "${SYSREQS_TEST_STATE}/pr" ;;
  *) echo "Unexpected gh command: $*" >&2; exit 1 ;;
esac
EOF
cat >"${temporary}/bin/bunx" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
export PATH="${temporary}/bin:${PATH}"
cp "${repository_root}/scripts/prepare-r-sysreqs-update.sh" "${temporary}/seed/scripts/"
cat >"${temporary}/seed/scripts/update-r-sysreqs.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${SYSREQS_TEST_FAIL:-false} == true ]]; then exit 1; fi
EOF
cp "${temporary}/bin/bunx" "${temporary}/seed/scripts/test-r-sysreqs.sh"
chmod +x "${temporary}"/bin/* "${temporary}"/seed/scripts/*
printf '{"revision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}\n' >"${temporary}/seed/r/sysreqs/config.json"
printf '{"platform":{"id":"test"},"packages":[],"unmapped":[]}\n' >"${temporary}/seed/r/sysreqs/test/manifest.json"
printf '# Fixture\n' >"${temporary}/seed/.crow/r-sysreqs-build-amd64.yaml"
git init -q -b main "${temporary}/seed"
git -C "${temporary}/seed" config user.name Test
git -C "${temporary}/seed" config user.email test@example.com
git -C "${temporary}/seed" add .
git -C "${temporary}/seed" commit -qm 'test: initialize fixture'
git init -q --bare "${temporary}/remote.git"
git -C "${temporary}/seed" remote add origin "${temporary}/remote.git"
git -C "${temporary}/seed" push -q origin main

checkout() {
  git clone -q --branch main "${temporary}/remote.git" "${temporary}/$1"
}

checkout update
"${temporary}/update/scripts/prepare-r-sysreqs-update.sh" 2026-09
test "$(git --git-dir="${temporary}/remote.git" show chore/r-sysreqs-2026-09:r/sysreqs/config.json | jq -r .revision)" = "${SYSREQS_TEST_REVISION}"
rg -q 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\.\.\.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' "${SYSREQS_TEST_STATE}/body.md"
commit=$(git --git-dir="${temporary}/remote.git" rev-parse refs/heads/chore/r-sysreqs-2026-09)

# A repeat run preserves an existing PR and its branch.
"${temporary}/update/scripts/prepare-r-sysreqs-update.sh" 2026-09
test "${commit}" = "$(git --git-dir="${temporary}/remote.git" rev-parse refs/heads/chore/r-sysreqs-2026-09)"

# Recover PR creation after the branch was pushed successfully.
rm "${SYSREQS_TEST_STATE}/pr"
checkout recovery
"${temporary}/recovery/scripts/prepare-r-sysreqs-update.sh" 2026-09
test -s "${SYSREQS_TEST_STATE}/pr"
test "${commit}" = "$(git --git-dir="${temporary}/remote.git" rev-parse refs/heads/chore/r-sysreqs-2026-09)"

# An unchanged upstream revision creates no remote branch or PR.
rm "${SYSREQS_TEST_STATE}/pr"
checkout unchanged
SYSREQS_TEST_REVISION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "${temporary}/unchanged/scripts/prepare-r-sysreqs-update.sh" 2026-10
test ! -f "${SYSREQS_TEST_STATE}/pr"
test -z "$(git --git-dir="${temporary}/remote.git" for-each-ref refs/heads/chore/r-sysreqs-2026-10)"

# A failed generator must never publish a partial update.
checkout failure
if SYSREQS_TEST_FAIL=true "${temporary}/failure/scripts/prepare-r-sysreqs-update.sh" 2026-11; then
  echo "Expected generation failure" >&2
  exit 1
fi
test ! -f "${SYSREQS_TEST_STATE}/pr"
test -z "$(git --git-dir="${temporary}/remote.git" for-each-ref refs/heads/chore/r-sysreqs-2026-11)"
echo "Scheduled R dependency update tests passed"
