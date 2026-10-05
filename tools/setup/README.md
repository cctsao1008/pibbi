# HX6538 Development Environment

This directory owns the reproducible host-side setup for pibbi's HX6538 development flow.

## Design principles

- Do not modify the machine-wide `PATH` for HX6538.
- Do not remove or downgrade newer Arm toolchains used by other firmware projects.
- Keep HX6538-required tools under the repository-local `.tools/` directory.
- Keep the Seeed/Himax SDK under `third_party/` and outside pibbi source ownership.
- Pin tool versions in `hx6538-tools.psd1` rather than scattering versions through scripts.
- Verify downloaded tool archives before use.
- Treat SDK revision changes as explicit dependency upgrades after the first known-good baseline is established.

## Files

### `hx6538-tools.psd1`

Single source of truth for host-tool and SDK versions.

Currently it defines:

- Python minimum version: 3.8
- Arm GNU Toolchain: 13.2.Rel1
- xPack Windows Build Tools: 4.4.1-3 / GNU Make 4.4.1
- Seeed `sscma-example-we2` tracking branch: `1.0.x`

The SDK commit is intentionally not pinned yet. The first exact pin should be made only after pibbi completes a clean upstream build and a Watcher smoke test with that revision.

### `bootstrap-hx6538.ps1`

Idempotent bootstrap for a Windows development machine. It:

1. creates `.tools/` and `third_party/` as needed;
2. downloads Arm GNU Toolchain 13.2.Rel1 from Arm;
3. verifies its pinned SHA-256 before extraction;
4. downloads xPack Windows Build Tools and validates the archive against the release checksum;
5. clones `Seeed-Studio/sscma-example-we2` recursively;
6. runs the full environment check.

It does **not** change the system or user `PATH`.

Run from the repository root:

```powershell
.\tools\setup\bootstrap-hx6538.ps1
```

Use `-UpdateSdk` only when intentionally advancing the unpinned SDK tracking branch during bring-up:

```powershell
.\tools\setup\bootstrap-hx6538.ps1 -UpdateSdk
```

### `activate-hx6538.ps1`

Adds the repository-local Arm compiler and GNU Make to the **current PowerShell session only**, and defines `SSCMA_WE2_ROOT`.

It must be dot-sourced:

```powershell
. .\tools\setup\activate-hx6538.ps1
```

Opening a new shell restores the machine's normal toolchain selection.

### `check-env.ps1`

Non-destructive validation. It prefers project-local pinned tools and falls back to `PATH` only when necessary.

```powershell
.\tools\setup\check-env.ps1
```

Checks include:

- Git
- Python and pip
- GNU Make
- Arm GNU Toolchain 13.2.Rel1
- managed `sscma-example-we2` checkout
- SDK revision/pin status
- SDK working-tree cleanliness

A missing required build dependency returns a non-zero exit code. The still-unpinned SDK baseline is reported as a warning, not a failure.

## Dependency lifecycle

During initial bring-up, `sscma-example-we2` tracks upstream `1.0.x`. Once a specific revision has passed:

1. clean upstream build;
2. HX6538 image generation;
3. Watcher boot/smoke test;
4. camera/interface sanity test;

record that exact commit in `hx6538-tools.psd1`. From that point onward, changing the SDK commit is a deliberate dependency upgrade and should be validated before merge.
