# R on Ubuntu

Copy the environments you want from the latest release into `ricochet-exec-env.toml`.
The calendar-versioned tags keep the configured R and Ubuntu versions reproducible.

```toml
[image.r-ubuntu-noble]
image = "docker.io/ricochetrs/r-ubuntu:2026-08-noble"
os = "ubuntu-24.04"
arch = ["linux/amd64", "linux/arm64"]
description = "R execution environment for Ubuntu 24.04"
r = [
  { version = "4.4.3", bin = "/usr/local/bin/R4.4" },
  { version = "4.5.3", bin = "/usr/local/bin/R4.5" },
  { version = "4.6.1", bin = "/usr/local/bin/R4.6" },
]

[image.r-ubuntu-resolute]
image = "docker.io/ricochetrs/r-ubuntu:2026-08-resolute"
os = "ubuntu-26.04"
arch = ["linux/amd64", "linux/arm64"]
description = "R execution environment for Ubuntu 26.04"
r = [
  { version = "4.4.3", bin = "/usr/local/bin/R4.4" },
  { version = "4.5.3", bin = "/usr/local/bin/R4.5" },
  { version = "4.6.1", bin = "/usr/local/bin/R4.6" },
]
```
