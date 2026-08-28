# Julia on Alpine Linux

Copy the environments you want from the latest release into `ricochet-exec-env.toml`.
The calendar-versioned tags keep the configured Julia and Alpine Linux versions reproducible.

```toml
[image.julia-alpine-3-23]
image = "docker.io/ricochetrs/julia-alpine:2026-08-3.23"
os = "alpine-3.23"
arch = ["linux/amd64"]
description = "Julia execution environment for Alpine Linux 3.23"
julia = [
  { version = "1.10.10", bin = "/usr/local/bin/julia1.10" },
  { version = "1.12.0-rc1", bin = "/usr/local/bin/julia1.12" },
]

[image.julia-alpine-3-24]
image = "docker.io/ricochetrs/julia-alpine:2026-08-3.24"
os = "alpine-3.24"
arch = ["linux/amd64"]
description = "Julia execution environment for Alpine Linux 3.24"
julia = [
  { version = "1.10.10", bin = "/usr/local/bin/julia1.10" },
  { version = "1.12.0-rc1", bin = "/usr/local/bin/julia1.12" },
]
```
