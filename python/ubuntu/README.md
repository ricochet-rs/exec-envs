# Python on Ubuntu

Copy the environments you want from the latest release into `ricochet-exec-env.toml`.
The calendar-versioned tags keep the configured Python and Ubuntu versions reproducible.

```toml
[image.python-ubuntu-26-04]
image = "docker.io/ricochetrs/python-ubuntu:2026-08-26.04"
os = "ubuntu-26.04"
arch = ["linux/amd64", "linux/arm64"]
description = "Python execution environment for Ubuntu 26.04"
python = [
  { version = "3.12.13", bin = "/usr/local/bin/python3.12" },
  { version = "3.13.14", bin = "/usr/local/bin/python3.13" },
  { version = "3.14.6", bin = "/usr/local/bin/python3.14" },
]

[image.python-ubuntu-noble]
image = "docker.io/ricochetrs/python-ubuntu:2026-08-noble"
os = "ubuntu-24.04"
arch = ["linux/amd64", "linux/arm64"]
description = "Python execution environment for Ubuntu 24.04"
python = [
  { version = "3.12.13", bin = "/usr/local/bin/python3.12" },
  { version = "3.13.14", bin = "/usr/local/bin/python3.13" },
  { version = "3.14.6", bin = "/usr/local/bin/python3.14" },
]
```
