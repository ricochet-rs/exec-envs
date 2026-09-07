# julia-ubuntu-noble

This exec environment is pinned to a digest from the 2026-09 release and is retained through at least 2029-10-01.
A rebuild may move it to a digest carrying operating system security fixes, while its R, Python, Julia, Quarto, Pandoc, and Typst versions stay as recorded below.

| Component        | Version                  |
| ---------------- | ------------------------ |
| Operating system | Ubuntu 24.04.4 LTS       |
| R                | Not installed            |
| Python           | Not installed            |
| Julia            | 1.10.12,1.12.7           |
| Quarto           | 1.10.18                  |
| Pandoc           | 3.10                     |
| Typst            | 0.15.1                   |
| Platforms        | linux/amd64; linux/arm64 |

The [Containerfile](./Containerfile) pins the current multi-platform image digest so repeated builds select the same environment.

- [Docker Hub](https://hub.docker.com/r/ricochetrs/julia-ubuntu/tags?name=2026-09-noble)
- [Ricochet Registry](https://reg.ricochet.rs/v2/exec-envs/julia-ubuntu/manifests/2026-09-noble)

Build the snapshot locally with:

```sh
docker build -t exec-env:julia-ubuntu-noble-2026-09 releases/2026-09/julia-ubuntu-noble
```
