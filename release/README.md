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

## Per-architecture builds

These images cannot be built under emulation.
A `linux/arm64` build on an `amd64` agent gets through `dnf` and then fails in `tar` with `Cannot mkdir: Invalid argument`, and a single emulated layer takes minutes.

So `release-build-amd64` and `release-build-arm64` each build one architecture on an agent of that architecture, pushing `YYYY-MM-<version>-<os>-<arch>`.
`build-release-images.sh` takes the architecture from `RELEASE_PLATFORM`, and skips any environment that is not published for it, which is why `julia-alpine` has nothing to do on the `arm64` agent.
`merge-release-images.sh` then composes `YYYY-MM-<version>-<os>` from those tags with `docker buildx imagetools create`, and verifies the resulting index advertises exactly the platforms the environment promises.

The `arm64` agent is gaia, the only `arm64` Docker host in the fleet, deployed from `ansible/internal`.
`check-releases.sh` enforces that the `arm64` workflow pins `platform: linux/arm64`, because losing that label would silently fall back to emulation.

The two build workflows serve every release path, so the monthly cron, a manual single-environment preparation, and a rebuild all reuse them and differ only in which workflow consumes the result.
A manual run therefore selects the two build workflows alongside the one that finishes the job.
`RELEASE_REBUILD` is one pipeline input shared by all of them, and `manual-release-rebuild` refuses to continue when it is false, because the builds would then have reused the tags the rebuild exists to replace.

The publisher verifies that exact digest in the Ricochet Registry and copies it to the matching calendar tag in Docker Hub without rebuilding it.

The `manual-release-image` Crow workflow accepts `RELEASE_ENVIRONMENT` and optional `RELEASE_MONTH` pipeline variables to prepare Ricochet Registry calendar tags before the monthly release runs.
The environment value must be an exact ID from `scripts/list-release-environments.sh YYYY-MM`, or `all` to build every environment active in that month.
The month defaults to the current UTC month, and an already-archived month is refused because its calendar tags are immutable.
`all` stays an explicit word rather than an empty field, so leaving the input blank cannot start a full multi-platform build by accident.
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

Publishing is idempotent, so retrying a release reuses existing calendar tags and does not change an archived environment unless the run is an explicit rebuild.

If a monthly archive is incorrect, leave its files and tags in place for auditability, document the issue, and publish the corrected environment in the next release.
A rebuild is not a correction mechanism, because it refuses any change to the recorded software versions.

## Re-releasing a month

A rebuild deliberately cannot change a month's recorded software, so a month whose images were wrong from the start is discarded and built again instead.
`re-release.sh` removes the archive, forces every calendar tag to be rebuilt rather than reused, and inventories the month from the current build matrix.

```sh
just re-release 2026-08
just publish-rebuilt-release 2026-08
```

Publishing moves the calendar tags in both registries onto the new digests, so anyone already pulling that month receives the replacement images.

Re-releasing takes its environment list from the build matrix rather than from the archive, so it also changes which environments the month contains.
Adjust `release_from` and `release_through` in `release/environments/` before re-releasing a month whose matrix has moved on since it was archived.

## Rebuilding an archived month

The `manual-release-rebuild` Crow workflow rebuilds an archived month so its images pick up operating system security fixes.
It requires `RELEASE_MONTH` and takes `RELEASE_ENVIRONMENT` as a single ID or `all`, and it runs every release script with `RELEASE_REBUILD` enabled.

A rebuild moves the existing calendar tag onto the new digest in both registries, so consumers of `YYYY-MM-<version>-<os>` receive the patched image without changing anything.
The archive then records the new digest, the new operating system string, and an updated wrapper Containerfile.

The rebuild is refused when any environment reports a different R, Python, Julia, or Quarto version than the archive records.
The failure names every environment and component that moved, and the archive is left untouched.
A distro Python patch bump is enough to trigger this, which is intended: a month's recorded software stays fixed, and changed software belongs in the next month.

The environment list for a rebuild comes from the archive rather than the build matrix, so a month keeps every environment it was released with.
An environment that has since left the matrix cannot be rebuilt, because its build arguments are gone, so it keeps its original digest and passes through unchanged.

The monthly cron never rebuilds, and `check-releases.sh` enforces that it never runs with `RELEASE_REBUILD` set.

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
