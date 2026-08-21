# r-alma-4.5.3-9

This exec environment is an immutable snapshot from the 2026-08 release and is retained through at least 2029-09-01.

| Component        | Version                      |
| ---------------- | ---------------------------- |
| Operating system | AlmaLinux 9.8 (Olive Jaguar) |
| R                | 4.5.3                        |
| Python           | 3.9.25                       |
| Julia            | Not installed                |
| Quarto           | Not installed                |
| Platforms        | linux/amd64; linux/arm64     |

The [Containerfile](./Containerfile) pins the multi-platform image digest so repeated builds select the same environment.

- [Docker Hub](https://hub.docker.com/r/ricochetrs/r-alma/tags?name=2026-08-4.5.3-9)
- [Ricochet Registry](https://reg.ricochet.rs/v2/exec-envs/r-alma/manifests/2026-08-4.5.3-9)

Build the snapshot locally with:

```sh
docker build -t exec-env:r-alma-4.5.3-9-2026-08 releases/2026-08/r-alma-4.5.3-9
```
