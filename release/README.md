# Monthly release process

The first successful cron pipeline in each UTC month creates a `releases/YYYY-MM` archive from every entry in `environments.tsv`.

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
