# r-alpine-3.24

This exec environment is pinned to a digest from the 2026-08 release and is retained through at least 2029-09-01.
A rebuild may move it to a digest carrying operating system security fixes, while its R, Python, Julia, and Quarto versions stay as recorded below.

| Component        | Version                  |
| ---------------- | ------------------------ |
| Operating system | Alpine Linux v3.24       |
| R                | 4.4.3; 4.5.3; 4.6.1      |
| Python           | Not installed            |
| Julia            | Not installed            |
| Quarto           | 1.10.18                  |
| Platforms        | linux/amd64; linux/arm64 |

The [Containerfile](./Containerfile) pins the current multi-platform image digest so repeated builds select the same environment.

- [Docker Hub](https://hub.docker.com/r/ricochetrs/r-alpine/tags?name=2026-08-3.24)
- [Ricochet Registry](https://reg.ricochet.rs/v2/exec-envs/r-alpine/manifests/2026-08-3.24)

Build the snapshot locally with:

```sh
docker build -t exec-env:r-alpine-3.24-2026-08 releases/2026-08/r-alpine-3.24
```
