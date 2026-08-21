# Monthly release process

The first successful cron pipeline in each UTC month creates a `releases/YYYY-MM` archive from every active entry in the Crow build matrices.

Matrix entries are rebuilt weekly while present, and `release_from` or `release_through` limits which monthly archives include them.

After an entry's final monthly release, it may remain in the matrix for one additional month of weekly security rebuilds before validation requires its removal.

Alpine releases keep exactly two OS minor versions active each month, so each May and November rollover adds the new minor, schedules the oldest minor's final release, and preserves its existing archives for three years.

`prepare-next-release.sh` checks the official Alpine image and every required R base image before adding a new minor to both Alpine matrices for the next month.

The same rollover marks the outgoing minor's final monthly release, keeps it rebuilding for one grace month, removes expired matrix entries, moves unqualified R tags to the newest minor, and updates both Alpine Containerfile defaults.

The generator resolves the source image index to a digest, verifies its advertised platforms, runs its `amd64` variant to inventory installed software, and writes an immutable wrapper Containerfile.

The publisher copies that exact digest to month-specific tags in Docker Hub and the Ricochet Registry without rebuilding it.

The release pipeline scans every pinned digest for fixable critical vulnerabilities before publication.

Every later cron run verifies that both registry copies still resolve to the recorded digest until the release's three-year retention date.

The Crow project must provide an `exec_envs_release_token` secret with permission to push the generated archive commit to the default branch.

Publishing is additive and idempotent, so retrying a release is safe and does not change an archived environment.

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
