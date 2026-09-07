# R system dependencies

The R images install the union of the applicable rules in [rstudio/r-system-requirements](https://github.com/rstudio/r-system-requirements), plus the existing image tools and baseline libraries.
The upstream rule data is covered by its [MIT license](UPSTREAM-LICENSE).
This covers known system requirements broadly, but does not guarantee that every CRAN package builds.
The catalog is curated, and some requirements have no mapping for a particular distribution.

## Updating

The upstream commit, target platforms, baseline packages, exclusions, and overrides live in [config.json](config.json).
Change `revision` to a reviewed full upstream commit, then regenerate from the repository root:

```sh
scripts/update-r-sysreqs.sh
scripts/update-r-sysreqs.sh --check
scripts/test-r-sysreqs.sh
```

The updater requires Bash, curl, tar, and jq; image builds do not fetch the database or need R tooling to resolve requirements.
Each target directory contains a generated `manifest.json` with rule-to-package mappings, unmapped rules, exclusions, overrides, and pre/post-install commands, alongside the `install.sh` used by its Containerfile.
Review both outputs when updating, especially new setup commands and changes to the unmapped list.
Upstream script actions deliberately stop generation for review instead of being silently omitted.
Regenerate checked-in files rather than editing them directly.

Build from the repository root so the generated installer is in the build context:

```sh
docker build -f r/ubuntu/Containerfile --build-arg OS_VERSION=noble -t r-sysreqs:noble .
docker build -f r/alma/Containerfile --build-arg OS_VERSION=9 -t r-sysreqs:alma-9 .
docker build -f r/alpine/Containerfile --build-arg OS_VERSION=3.24 -t r-sysreqs:alpine-3.24 .
```

Validate package resolution and installation for both published architectures whenever the rules or target versions change.
Package availability and installation size depend on the distribution repositories at build time; the pinned rules do not pin OS package versions.

## Policy

The exclusion list omits heavyweight applications and dedicated runtimes such as Blender, Chrome, CUDA, .NET, TeX, and desktop GIS tools.
Every exclusion and override carries a reason in the configuration.
Rust comes from distro packages instead of installing rustup under the build user's home.
Java configuration runs for every R installation under `/opt/R`.
Python executables installed as dependencies remain available because build tools may need them.

AlmaLinux uses the matching Rocky Linux major-version rules, with overrides for AlmaLinux package differences.
Generated AlmaLinux setup commands use `dnf` because the R base images do not provide the `yum` alias.
Alpine 3.24 temporarily uses the Alpine 3.23 mappings and must be checked against the actual 3.24 repositories.
Unmapped rules are reported explicitly rather than treated as satisfied; baseline packages may still cover some of them.
The broad package union adds several gigabytes to a minimal base image, so review size alongside coverage when adjusting exclusions.
