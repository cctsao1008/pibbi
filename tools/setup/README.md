# Development Environment Setup

This directory owns reproducible host-side setup for pibbi's HX6538 and ESP32-S3 development flows.

## Design principles

- Do not require machine-wide toolchain replacement.
- Keep project-managed host tools under the repository-local `.tools/` directory.
- Keep vendor SDK/source checkouts under `third_party/` and outside pibbi source ownership.
- Pin tool versions in platform-specific `.psd1` files instead of scattering versions through scripts.
- Make bootstrap scripts idempotent and environment checks non-destructive.
- Keep interactive activation scoped to the current PowerShell session.
- Treat upstream revision changes as explicit dependency upgrades after a known-good hardware baseline is established.

## Aggregate check

Run both platform checks:

```powershell
.\tools\setup\check-env.ps1
```

Or select one:

```powershell
.\tools\setup\check-env.ps1 -Platform hx6538
.\tools\setup\check-env.ps1 -Platform esp32s3
```

`check-env.ps1` is only an aggregator. Platform-specific checks remain usable independently.

---

## HX6538

### `hx6538-tools.psd1`

Single source of truth for HX6538 host-tool and SDK versions. It currently defines:

- Python minimum version: 3.8
- Arm GNU Toolchain: 13.2.Rel1
- xPack Windows Build Tools: 4.4.1-3 / GNU Make 4.4.1
- Seeed `sscma-example-we2` tracking branch: `1.0.x`

The SDK commit is intentionally not pinned yet. The first exact pin should be made only after a clean upstream build, image generation, and Watcher smoke test pass.

### `bootstrap-hx6538.ps1`

```powershell
.\tools\setup\bootstrap-hx6538.ps1
```

It provisions the repository-local Arm toolchain and GNU Make, verifies downloaded archives, clones the Seeed/Himax SDK recursively, and runs `check-hx6538-env.ps1`.

Use `-UpdateSdk` only when intentionally advancing the still-unpinned SDK tracking branch.

### `activate-hx6538.ps1`

```powershell
. .\tools\setup\activate-hx6538.ps1
```

Adds the pibbi-local Arm compiler and GNU Make to the current shell only and defines `SSCMA_WE2_ROOT`.

### `check-hx6538-env.ps1`

Checks Git, Python/pip, GNU Make, Arm GNU Toolchain, the managed `sscma-example-we2` checkout, SDK revision/pin state, and working-tree cleanliness.

---

## ESP32-S3 / SenseCAP Watcher

### `esp32s3-tools.psd1`

Single source of truth for the ESP32-S3 environment. It currently defines:

- Python minimum version: 3.8
- ESP-IDF release: `v5.2.1`
- exact ESP-IDF release commit: `a322e6bdad4b6675d4597fb2722eea2851ba88cb`
- target: `esp32s3`
- repository-local ESP-IDF tools directory: `.tools/esp-idf`
- Seeed `SenseCAP-Watcher-Firmware` tracking branch: `main`

ESP-IDF is pinned immediately because the upstream Watcher firmware explicitly documents `v5.2.1`. The Watcher firmware commit is intentionally left unpinned until one exact revision passes real-hardware build/flash/smoke validation.

### `bootstrap-esp32s3.ps1`

```powershell
.\tools\setup\bootstrap-esp32s3.ps1
```

It:

1. validates Git and Python prerequisites;
2. clones ESP-IDF recursively and checks out the exact pinned release commit;
3. sets `IDF_TOOLS_PATH` to `.tools/esp-idf` for provisioning;
4. uses Espressif's `idf_tools.py` to install the `esp32s3` toolset and ESP-IDF Python environment;
5. clones `Seeed-Studio/SenseCAP-Watcher-Firmware` recursively;
6. runs `check-esp32s3-env.ps1`.

It does not permanently modify the system/user `PATH` or `IDF_TOOLS_PATH`.

Use `-UpdateWatcher` only when intentionally advancing the still-unpinned Watcher firmware tracking branch. `-Force` removes and reprovisions only the repository-local ESP-IDF tool installation; it does not delete source checkouts.

### `activate-esp32s3.ps1`

```powershell
. .\tools\setup\activate-esp32s3.ps1
```

Defines repository-local `IDF_PATH`, `IDF_TOOLS_PATH`, `PIBBI_ESP32_TARGET`, and `PIBBI_WATCHER_ROOT`, then dot-sources the pinned ESP-IDF `export.ps1` into the current shell.

Opening a new shell restores the machine's normal environment.

### `check-esp32s3-env.ps1`

Checks:

- Git
- Python and pip
- exact ESP-IDF commit
- ESP-IDF working-tree cleanliness
- ESP-IDF submodule state
- repository-local `IDF_TOOLS_PATH`
- Espressif-managed tool installation through `idf_tools.py check`
- target `esp32s3`
- managed SenseCAP Watcher firmware checkout
- Watcher revision/pin status and working-tree cleanliness

A missing required dependency returns a non-zero exit code. An intentionally unpinned Watcher revision is reported as a warning rather than a failure.

## Dependency lifecycle

For either processor, the revision promoted to a pibbi baseline should be the exact revision that passed the complete relevant chain: build, image generation where applicable, flash, boot, and hardware/interface smoke validation.

After pinning, dependency changes are deliberate upgrades and should be revalidated before merge.
