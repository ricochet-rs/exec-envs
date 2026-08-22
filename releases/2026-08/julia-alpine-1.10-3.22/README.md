# julia-alpine-1.10-3.22

This exec environment is an immutable snapshot from the 2026-08 release and is retained through at least 2029-09-01.

| Component        | Version            |
| ---------------- | ------------------ |
| Operating system | Alpine Linux v3.22 |
| R                | Not installed      |
| Python           | Not installed      |
| Julia            | 1.10.10            |
| Quarto           | Not installed      |
| Platforms        | linux/amd64        |

The [Containerfile](./Containerfile) pins the multi-platform image digest so repeated builds select the same environment.

- [Docker Hub](https://hub.docker.com/r/ricochetrs/julia-alpine/tags?name=2026-08-1.10-3.22)
- [Ricochet Registry](https://reg.ricochet.rs/v2/exec-envs/julia-alpine/manifests/2026-08-1.10-3.22)

Build the snapshot locally with:

```sh
docker build -t exec-env:julia-alpine-1.10-3.22-2026-08 releases/2026-08/julia-alpine-1.10-3.22
```
