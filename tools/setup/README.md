# Development Environment Setup

This directory contains host-side setup and validation tools for the `pibbi` development environment.

The setup scripts are intentionally kept separate from day-to-day build and flash tools:

- `tools/setup/` — bootstrap and validate a development machine.
- `tools/hx6538/` — build, package, detect, and flash HX6538 firmware (planned).
- `firmware/hx6538/` — pibbi-specific HX6538 source/configuration (planned).
- `firmware/esp32s3/` — pibbi-specific ESP32-S3 source/configuration (planned).
- `third_party/sscma-example-we2/` — pinned Seeed/Himax SDK dependency (planned).

## Current tool

### `check-env.ps1`

Performs a non-destructive validation of the Windows HX6538 development environment.

It checks:

- Git
- Python 3.8 or newer
- pip
- GNU Make
- Arm GNU Toolchain (`arm-none-eabi-gcc`)
- expected Arm GNU Toolchain release (`13.2.Rel1`)
- presence of an `sscma-example-we2` checkout

The script does **not** install packages, modify `PATH`, clone repositories, or flash hardware.

Run from the repository root:

```powershell
.\tools\setup\check-env.ps1
```

A missing `sscma-example-we2` checkout is reported as a warning because SDK acquisition will be handled by a later bootstrap step. Missing required host tools cause the script to return a non-zero exit code.

## Design rule

Environment provisioning and environment validation should remain reproducible and non-destructive by default. SDK/toolchain versions should be pinned explicitly before automated installation is introduced.
