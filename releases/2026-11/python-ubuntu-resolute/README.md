# python-ubuntu-resolute

This exec environment is pinned to a digest from the 2026-11 release and is retained through at least 2029-12-01.
A rebuild may move it to a digest carrying operating system security fixes, while its R, Python, Julia, Quarto, Pandoc, and Typst versions stay as recorded below.

| Component        | Version                   |
| ---------------- | ------------------------- |
| Operating system | Ubuntu 26.04.1 LTS        |
| R                | Not installed             |
| Python           | 3.12.16; 3.13.18; 3.14.10 |
| Julia            | Not installed             |
| Quarto           | 1.10.19                   |
| Pandoc           | 3.10                      |
| Typst            | 0.15.1                    |
| Platforms        | linux/amd64; linux/arm64  |

The [Containerfile](./Containerfile) pins the current multi-platform image digest so repeated builds select the same environment.

- [Docker Hub](https://hub.docker.com/r/ricochetrs/python-ubuntu/tags?name=2026-11-resolute)
- [Ricochet Registry](https://reg.ricochet.rs/v2/exec-envs/python-ubuntu/manifests/2026-11-resolute)

Build the snapshot locally with:

```sh
docker build -t exec-env:python-ubuntu-resolute-2026-11 releases/2026-11/python-ubuntu-resolute
```
