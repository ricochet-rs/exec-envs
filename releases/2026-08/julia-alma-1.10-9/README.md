# julia-alma-1.10-9

This exec environment is an immutable snapshot from the 2026-08 release and is retained through at least 2029-09-01.

| Component        | Version                      |
| ---------------- | ---------------------------- |
| Operating system | AlmaLinux 9.8 (Olive Jaguar) |
| R                | Not installed                |
| Python           | 3.9.25                       |
| Julia            | 1.10.11                      |
| Quarto           | Not installed                |
| Platforms        | linux/amd64; linux/arm64     |

The [Containerfile](./Containerfile) pins the multi-platform image digest so repeated builds select the same environment.

- [Docker Hub](https://hub.docker.com/r/ricochetrs/julia-alma/tags?name=2026-08-1.10-9)
- [Ricochet Registry](https://reg.ricochet.rs/v2/exec-envs/julia-alma/manifests/2026-08-1.10-9)

Build the snapshot locally with:

```sh
docker build -t exec-env:julia-alma-1.10-9-2026-08 releases/2026-08/julia-alma-1.10-9
```
