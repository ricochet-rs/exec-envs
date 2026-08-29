# R on Alpine Linux

Copy the environments you want from the latest release into `ricochet-exec-env.toml`.
The calendar-versioned tags keep the configured R and Alpine Linux versions reproducible.

```toml
[image.r-alpine-3-23]
image = "docker.io/ricochetrs/r-alpine:2026-08-3.23"
os = "alpine-3.23"
arch = ["linux/amd64", "linux/arm64"]
description = "R execution environment for Alpine Linux 3.23"
r = [
  { version = "4.4.3", bin = "/opt/R/4.4.3/bin/R" },
  { version = "4.5.3", bin = "/opt/R/4.5.3/bin/R" },
  { version = "4.6.1", bin = "/opt/R/4.6.1/bin/R" },
]

[image.r-alpine-3-24]
image = "docker.io/ricochetrs/r-alpine:2026-08-3.24"
os = "alpine-3.24"
arch = ["linux/amd64", "linux/arm64"]
description = "R execution environment for Alpine Linux 3.24"
r = [
  { version = "4.4.3", bin = "/opt/R/4.4.3/bin/R" },
  { version = "4.5.3", bin = "/opt/R/4.5.3/bin/R" },
  { version = "4.6.1", bin = "/opt/R/4.6.1/bin/R" },
]
```
