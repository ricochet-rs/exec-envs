# Python on AlmaLinux

Copy this environment from the latest release into `ricochet-exec-env.toml`.
The calendar-versioned tag keeps the configured Python and AlmaLinux versions reproducible.

```toml
[image.python-alma-10]
image = "docker.io/ricochetrs/python-alma:2026-08-10"
os = "alma-10"
arch = ["linux/amd64", "linux/arm64"]
description = "Python execution environment for AlmaLinux 10"
python = [
  { version = "3.12.13", bin = "/usr/local/bin/python3.12" },
  { version = "3.13.14", bin = "/usr/local/bin/python3.13" },
  { version = "3.14.6", bin = "/usr/local/bin/python3.14" },
]
```
