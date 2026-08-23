# Monthly release process

The first successful cron pipeline in each UTC month builds and creates a `releases/YYYY-MM` archive from every active entry in the build matrices under `release/environments/`.
Each matrix file describes one image: its name, the platforms its calendar tags must advertise, and the environments it contributes, with optional `release_from` and `release_through` bounds.
The main README lists each available month with its retention date, environment count, and recorded creation pipeline, while the monthly README contains the detailed component inventory.

Each image is published only under its immutable `YYYY-MM-<version>-<os>` tag in the Ricochet Registry and Docker Hub.

Legacy non-calendar tags may remain in the registries, but no workflow creates or updates them.

No workflow builds a Containerfile outside the release path.
Pull requests lint the Containerfiles, and only `monthly-release` and `manual-release-image` run `scripts/build-release-images.sh`, which `check-releases.sh` enforces.

Alpine releases keep exactly two OS minor versions active each month, so each May and November rollover adds the new minor, removes the oldest minor after its final archive, and preserves that archive for three years.

`prepare-next-release.sh` checks the official Alpine image and every required R base image before adding a new minor to both Alpine matrices for the next month.

The same rollover removes expired matrix entries immediately and updates both Alpine Containerfile defaults.

Renovate ignores `releases/**` and follows one `julia-current` marker per Julia matrix, while the Alpine rollover moves that marker to the newest monthly environment and leaves older definitions fixed.

The monthly builder publishes the Ricochet Registry calendar tag, and the generator resolves it to a digest, verifies its advertised platforms, runs its `amd64` variant to inventory installed software, and writes an immutable wrapper Containerfile.

The publisher verifies that exact digest in the Ricochet Registry and copies it to the matching calendar tag in Docker Hub without rebuilding it.

The `manual-release-image` Crow workflow accepts `RELEASE_ENVIRONMENT` and optional `RELEASE_MONTH` pipeline variables to prepare one Ricochet Registry calendar tag before the monthly release runs.
The environment value must be an exact ID from `scripts/list-release-environments.sh YYYY-MM`, and the month defaults to the current UTC month.
Both are declared in the workflow's `variables` block, which is what makes them appear as inputs in the manual-run dialog and injects them into the step.
The manual workflow never publishes a rolling tag or bypasses the monthly scan, promotion, and archive steps.

The release pipeline scans every pinned Ricochet Registry digest for fixable critical vulnerabilities before promotion to Docker Hub.
New release metadata records the successful Crow pipeline URL so the main release index links each month to its creation status.

Every later cron run verifies that both registry copies still resolve to the recorded digest until the release's three-year retention date.

After the archive commit lands, `publish-release-notes.sh` creates a GitHub release tagged with the month, pointing the tag at the commit that archived it.
The notes compare the month against the previous archive and classify every environment as added, removed, updated, or rebuilt with unchanged component versions.
The script runs over every archived month, so it backfills a missing release and refreshes notes that no longer match the archive.

The Crow project must provide an `exec_envs_release_token` secret with permission to push the generated archive commit to the default branch and to create GitHub releases.
The token must belong to `ricochet-bot`, because a GitHub release carries the identity of the token that creates it.
`publish-release-notes.sh` refuses to publish under any other account, so a local run needs the bot token.
`RELEASE_GITHUB_ACTOR` retargets that check at a different account and cannot switch it off.

Publishing is additive and idempotent, so retrying a release reuses existing calendar tags and does not change an archived environment.

If a monthly archive is incorrect, leave its immutable files and tags in place for auditability, document the issue, and publish the corrected environment in the next release.

Create and validate a release locally with:

```sh
RELEASE_CLEANUP_IMAGES=true just release 2026-09
just check-releases
```

Publishing requires authenticated Docker clients for both registries:

```sh
just publish-release 2026-09
just check-releases-remote
```

Preview the GitHub release notes for a month, then publish or refresh every archived month:

```sh
just release-notes 2026-09
just publish-release-notes
```
