# python-ubuntu-26.04

This exec environment is an immutable snapshot from the 2026-08 release and is retained through at least 2029-09-01.

| Component        | Version                  |
| ---------------- | ------------------------ |
| Operating system | Ubuntu 26.04 LTS         |
| R                | Not installed            |
| Python           | 3.12.13; 3.13.14; 3.14.6 |
| Julia            | Not installed            |
| Quarto           | Not installed            |
| Platforms        | linux/amd64; linux/arm64 |

The [Containerfile](./Containerfile) pins the multi-platform image digest so repeated builds select the same environment.

- [Docker Hub](https://hub.docker.com/r/ricochetrs/python-ubuntu/tags?name=2026-08-26.04)
- [Ricochet Registry](https://reg.ricochet.rs/v2/exec-envs/python-ubuntu/manifests/2026-08-26.04)

Build the snapshot locally with:

```sh
docker build -t exec-env:python-ubuntu-26.04-2026-08 releases/2026-08/python-ubuntu-26.04
```
