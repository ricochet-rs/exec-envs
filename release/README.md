# Monthly release process

The first successful cron pipeline in each UTC month builds and creates a `releases/YYYY-MM` archive from every active entry in the Crow build matrices.

Each image is published only under its immutable `YYYY-MM-<version>-<os>` tag in the Ricochet Registry and Docker Hub.

Legacy non-calendar tags may remain in the registries, but no workflow creates or updates them.

The static build workflows perform dry-run validation without publishing tags.

Alpine releases keep exactly two OS minor versions active each month, so each May and November rollover adds the new minor, removes the oldest minor after its final archive, and preserves that archive for three years.

`prepare-next-release.sh` checks the official Alpine image and every required R base image before adding a new minor to both Alpine matrices for the next month.

The same rollover removes expired matrix entries immediately and updates both Alpine Containerfile defaults.

Renovate ignores `releases/**` and follows one `julia-current` marker per Julia matrix, while the Alpine rollover moves that marker to the newest monthly environment and leaves older definitions fixed.

The monthly builder publishes the Ricochet Registry calendar tag, and the generator resolves it to a digest, verifies its advertised platforms, runs its `amd64` variant to inventory installed software, and writes an immutable wrapper Containerfile.

The publisher verifies that exact digest in the Ricochet Registry and copies it to the matching calendar tag in Docker Hub without rebuilding it.

The `manual-release-image` Crow workflow accepts `RELEASE_ENVIRONMENT` and optional `RELEASE_MONTH` pipeline variables to prepare one Ricochet Registry calendar tag before the monthly release runs.
The environment value must be an exact ID from `scripts/list-release-environments.sh YYYY-MM`, and the month defaults to the current UTC month.
The manual workflow never publishes a rolling tag or bypasses the monthly scan, promotion, and archive steps.

The release pipeline scans every pinned Ricochet Registry digest for fixable critical vulnerabilities before promotion to Docker Hub.

Every later cron run verifies that both registry copies still resolve to the recorded digest until the release's three-year retention date.

The Crow project must provide an `exec_envs_release_token` secret with permission to push the generated archive commit to the default branch.

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
