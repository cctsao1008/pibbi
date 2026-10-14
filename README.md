# pibbi

`pibbi` is an embedded/physical-AI software project built on the SenseCAP Watcher platform. It reuses Seeed's factory firmware while adding pibbi-owned application modules without changing vendor checkouts.

The existing toolchain infrastructure remains in place; the ESP32-S3 project now directly builds pibbi-owned firmware functionality on top of Seeed sources.

## Current platform baseline

- ESP32-S3: system, connectivity, UI, audio, and host-side control
- Himax HX6538 / WiseEye2: vision and endpoint-AI side
- SenseCAP Watcher hardware

## Repository direction

```text
pibbi/
├─ firmware/                  # pibbi-owned firmware/application code
│  └─ esp32s3/               # ESP-IDF app + sensor component
├─ third_party/               # external SDK/source checkouts; not vendored into Git
├─ tools/
│  ├─ setup/                  # reproducible development environments
│  ├─ hx6538/                 # HX6538 build/image workflow
│  └─ esp32s3/                # ESP32-S3 build/inspect/backup/flash workflow
└─ .tools/                    # repository-local host tools; ignored by Git
```

## Development environment on Windows

Bootstrap both firmware environments from a fresh clone:

```powershell
.\tools\setup\bootstrap.ps1
.\tools\setup\check-env.ps1
```

The two firmware sides can also be provisioned independently.

HX6538:

```powershell
.\tools\setup\bootstrap-hx6538.ps1
.\tools\setup\check-hx6538-env.ps1
```

ESP32-S3:

```powershell
.\tools\setup\bootstrap-esp32s3.ps1
.\tools\setup\check-esp32s3-env.ps1
```

The aggregate bootstrap/check entry points also accept a platform selector:

```powershell
.\tools\setup\bootstrap.ps1 -Platform hx6538
.\tools\setup\bootstrap.ps1 -Platform esp32s3
.\tools\setup\check-env.ps1 -Platform hx6538
.\tools\setup\check-env.ps1 -Platform esp32s3
```

Interactive shell activation affects only the current PowerShell session:

```powershell
. .\tools\setup\activate-hx6538.ps1
# or
. .\tools\setup\activate-esp32s3.ps1
```

The HX6538 flow uses a repository-local Arm GNU Toolchain and GNU Make. The ESP32-S3 flow pins the upstream-documented ESP-IDF `v5.2.1` release and directs Espressif-managed tools into `.tools/esp-idf` instead of the user's machine-wide/default tool location.

See [`tools/setup/README.md`](tools/setup/README.md) for versioning and dependency policy.

## HX6538 build and image generation

Use pibbi wrappers instead of invoking the vendor flow manually:

```powershell
.\tools\hx6538\build.ps1
.\tools\hx6538\image.ps1
```

The build wrapper records the exact SDK/toolchain identity and ELF SHA-256. The image wrapper isolates the upstream image generator, preserves each signed image run, and records exact image provenance without assuming byte-for-byte determinism of the vendor secure-boot output.

See [`tools/hx6538/README.md`](tools/hx6538/README.md).

## ESP32-S3 / Watcher workflow

The Watcher factory firmware contains a critical `nvsfactory` partition. Preserve it before the first flash:

```powershell
.\tools\esp32s3\inspect-device.ps1 -Port COM31
.\tools\esp32s3\backup-nvsfactory.ps1 -Port COM31
.\tools\esp32s3\backup-flash.ps1 -Port COM31
```

Build the pibbi application, reusing upstream factory firmware modules:

```powershell
.\tools\esp32s3\build.ps1
```

Then flash the verified **application only** and monitor it:

```powershell
.\tools\esp32s3\flash.ps1 -Port COM31
.\tools\esp32s3\monitor.ps1 -Port COM31
```

`build.ps1` and `flash.ps1` now default to `pibbi`, which mirrors the upstream factory partition layout. The flash wrapper still writes the application only, not the bootloader, partition table, or factory-data partition.

Build/flash/backup evidence is stored under `artifacts/` and ignored by Git.

See [`tools/esp32s3/README.md`](tools/esp32s3/README.md).

## Development policy

Build software directly with the mature Seeed firmware, ESP-IDF and existing
drivers. Build, flash, execution and debugging are regular software-development
steps rather than separate feasibility or hardware-validation milestones.

- pibbi-owned source is tracked in `firmware/esp32s3/`.
- Vendor checkouts remain in the ignored `third_party/` directory.
- The initial Sensor Service inventories the five Waveshare HAT I2C endpoints
  and publishes device-set changes through ESP-IDF events.
- Measurement drivers, observation transport and the LSMM adapter are the
  next software features (not yet implemented).
- Factory data was backed up separately on 2026-10-14. Keep it private and
  continue using application-only flashing.
- The W1-A ESP32-S3 appeared as COM31 on the current PC; ports can change.

See [firmware/esp32s3/README.md](firmware/esp32s3/README.md) for integration.
