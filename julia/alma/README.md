# Julia on AlmaLinux

Copy this environment from the latest release into `ricochet-exec-env.toml`.
The calendar-versioned tag keeps the configured Julia and AlmaLinux versions reproducible.

```toml
[image.julia-alma-9]
image = "docker.io/ricochetrs/julia-alma:2026-08-9"
os = "alma-9"
arch = ["linux/amd64", "linux/arm64"]
description = "Julia execution environment for AlmaLinux 9"
julia = [
  { version = "1.10.12", bin = "/usr/local/bin/julia1.10" },
  { version = "1.12.7", bin = "/usr/local/bin/julia1.12" },
]
```
