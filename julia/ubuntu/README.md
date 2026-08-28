# Julia on Ubuntu

Copy the environments you want from the latest release into `ricochet-exec-env.toml`.
The calendar-versioned tags keep the configured Julia and Ubuntu versions reproducible.

```toml
[image.julia-ubuntu-noble]
image = "docker.io/ricochetrs/julia-ubuntu:2026-08-noble"
os = "ubuntu-24.04"
arch = ["linux/amd64", "linux/arm64"]
description = "Julia execution environment for Ubuntu 24.04"
julia = [
  { version = "1.10.12", bin = "/usr/local/bin/julia1.10" },
  { version = "1.12.7", bin = "/usr/local/bin/julia1.12" },
]

[image.julia-ubuntu-resolute]
image = "docker.io/ricochetrs/julia-ubuntu:2026-08-resolute"
os = "ubuntu-26.04"
arch = ["linux/amd64", "linux/arm64"]
description = "Julia execution environment for Ubuntu 26.04"
julia = [
  { version = "1.10.12", bin = "/usr/local/bin/julia1.10" },
  { version = "1.12.7", bin = "/usr/local/bin/julia1.12" },
]
```
