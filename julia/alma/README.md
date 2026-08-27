# Julia on AlmaLinux

Copy the environments you want from the latest release into `ricochet-exec-env.toml`.
The calendar-versioned tags keep the configured Julia and AlmaLinux versions reproducible.

```toml
[image.julia-alma-1-10-9]
image = "docker.io/ricochetrs/julia-alma:2026-08-1.10-9"
os = "alma-9"
arch = ["linux/amd64", "linux/arm64"]
description = "Julia 1.10 execution environment for AlmaLinux 9"
julia = [{ version = "1.10.12", bin = "/opt/julia/bin/julia" }]

[image.julia-alma-1-12-9]
image = "docker.io/ricochetrs/julia-alma:2026-08-1.12-9"
os = "alma-9"
arch = ["linux/amd64", "linux/arm64"]
description = "Julia 1.12 execution environment for AlmaLinux 9"
julia = [{ version = "1.12.7", bin = "/opt/julia/bin/julia" }]
```
