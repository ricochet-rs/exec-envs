# R on AlmaLinux

Copy the environments you want from the latest release into `ricochet-exec-env.toml`.
The calendar-versioned tags keep the configured R and AlmaLinux versions reproducible.

```toml
[image.r-alma-10]
image = "docker.io/ricochetrs/r-alma:2026-08-10"
os = "alma-10"
arch = ["linux/amd64", "linux/arm64"]
description = "R execution environment for AlmaLinux 10"
r = [
  { version = "4.4.3", bin = "/opt/R/4.4.3/bin/R" },
  { version = "4.5.3", bin = "/opt/R/4.5.3/bin/R" },
  { version = "4.6.1", bin = "/opt/R/4.6.1/bin/R" },
]

[image.r-alma-9]
image = "docker.io/ricochetrs/r-alma:2026-08-9"
os = "alma-9"
arch = ["linux/amd64", "linux/arm64"]
description = "R execution environment for AlmaLinux 9"
r = [
  { version = "4.4.3", bin = "/opt/R/4.4.3/bin/R" },
  { version = "4.5.3", bin = "/opt/R/4.5.3/bin/R" },
  { version = "4.6.1", bin = "/opt/R/4.6.1/bin/R" },
]
```
