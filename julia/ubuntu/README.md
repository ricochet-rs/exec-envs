# Julia on Ubuntu

Copy the environments you want from the latest release into `ricochet-exec-env.toml`.
The calendar-versioned tags keep the configured Julia and Ubuntu versions reproducible.

```toml
[image.julia-ubuntu-1-10-noble]
image = "docker.io/ricochetrs/julia-ubuntu:2026-08-1.10-noble"
os = "ubuntu-24.04"
arch = ["linux/amd64", "linux/arm64"]
description = "Julia 1.10 execution environment for Ubuntu 24.04"
julia = [{ version = "1.10.12", bin = "/opt/julia/bin/julia" }]

[image.julia-ubuntu-1-12-noble]
image = "docker.io/ricochetrs/julia-ubuntu:2026-08-1.12-noble"
os = "ubuntu-24.04"
arch = ["linux/amd64", "linux/arm64"]
description = "Julia 1.12 execution environment for Ubuntu 24.04"
julia = [{ version = "1.12.7", bin = "/opt/julia/bin/julia" }]
```
