# R on AlmaLinux

Copy this environment from the latest release into `ricochet-exec-env.toml`.
The calendar-versioned tag keeps the configured R and AlmaLinux versions reproducible.

```toml
[image.r-alma-9]
image = "docker.io/ricochetrs/r-alma:2026-08-9"
os = "alma-9"
arch = ["linux/amd64", "linux/arm64"]
description = "R execution environment for AlmaLinux 9"
r = [
  { version = "4.4.3", bin = "/usr/local/bin/R4.4" },
  { version = "4.5.3", bin = "/usr/local/bin/R4.5" },
  { version = "4.6.1", bin = "/usr/local/bin/R4.6" },
]
```
