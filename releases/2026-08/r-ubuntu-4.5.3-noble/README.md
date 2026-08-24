# r-ubuntu-4.5.3-noble

This exec environment is pinned to a digest from the 2026-08 release and is retained through at least 2029-09-01.
A rebuild may move it to a digest carrying operating system security fixes, while its R, Python, Julia, and Quarto versions stay as recorded below.

| Component        | Version                  |
| ---------------- | ------------------------ |
| Operating system | Ubuntu 24.04.4 LTS       |
| R                | 4.5.3                    |
| Python           | 3.12.3                   |
| Julia            | Not installed            |
| Quarto           | 1.10.18                  |
| Platforms        | linux/amd64; linux/arm64 |

The [Containerfile](./Containerfile) pins the current multi-platform image digest so repeated builds select the same environment.

- [Docker Hub](https://hub.docker.com/r/ricochetrs/r-ubuntu/tags?name=2026-08-4.5.3-noble)
- [Ricochet Registry](https://reg.ricochet.rs/v2/exec-envs/r-ubuntu/manifests/2026-08-4.5.3-noble)

Build the snapshot locally with:

```sh
docker build -t exec-env:r-ubuntu-4.5.3-noble-2026-08 releases/2026-08/r-ubuntu-4.5.3-noble
```
