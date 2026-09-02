# python-alma-9

This exec environment is pinned to a digest from the 2026-08 release and is retained through at least 2029-09-01.
A rebuild may move it to a digest carrying operating system security fixes, while its R, Python, Julia, and Quarto versions stay as recorded below.

| Component        | Version                      |
| ---------------- | ---------------------------- |
| Operating system | AlmaLinux 9.8 (Olive Jaguar) |
| R                | Not installed                |
| Python           | 3.12.13; 3.13.14; 3.14.6     |
| Julia            | Not installed                |
| Quarto           | 1.10.18                      |
| Platforms        | linux/amd64; linux/arm64     |

The [Containerfile](./Containerfile) pins the current multi-platform image digest so repeated builds select the same environment.

- [Docker Hub](https://hub.docker.com/r/ricochetrs/python-alma/tags?name=2026-08-9)
- [Ricochet Registry](https://reg.ricochet.rs/v2/exec-envs/python-alma/manifests/2026-08-9)

Build the snapshot locally with:

```sh
docker build -t exec-env:python-alma-9-2026-08 releases/2026-08/python-alma-9
```
