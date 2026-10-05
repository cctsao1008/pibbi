# pibbi

`pibbi` is an early-stage embedded/physical-AI project built around the SenseCAP Watcher platform.

The repository intentionally starts with reproducible development infrastructure before pibbi-owned firmware diverges from upstream vendor code.

## Current platform baseline

- ESP32-S3: system, connectivity, UI, audio, and host-side control
- Himax HX6538 / WiseEye2: vision and endpoint-AI side
- SenseCAP Watcher hardware

## Repository direction

```text
pibbi/
├─ firmware/                  # pibbi-owned firmware/application code (planned)
│  ├─ hx6538/
│  └─ esp32s3/
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

Build the smallest upstream Watcher example first:

```powershell
.\tools\esp32s3\build.ps1
```

Before the first experimental flash on a physical Watcher, inspect and preserve its factory flash:

```powershell
.\tools\esp32s3\inspect-device.ps1 -Port COM14
.\tools\esp32s3\backup-flash.ps1 -Port COM14
```

Then flash a previously verified build and monitor it:

```powershell
.\tools\esp32s3\flash.ps1 -Port COM14
.\tools\esp32s3\monitor.ps1 -Port COM14
```

Build/flash/backup evidence is stored under `artifacts/` and ignored by Git.

See [`tools/esp32s3/README.md`](tools/esp32s3/README.md).

## Bring-up policy

The first milestone is not a custom feature. It is a controlled, traceable known-good baseline for both processors:

1. bootstrap the required host environment(s);
2. validate dependency versions and source revisions;
3. build unmodified upstream firmware;
4. preserve exact generated artifacts and SHA-256 evidence;
5. inspect and back up the factory ESP32-S3 flash before modification;
6. flash one exact artifact set and record what reached the hardware;
7. boot the Watcher and validate the relevant camera/UI/audio/host interfaces;
8. pin the exact upstream revision that passed hardware validation;
9. only then begin pibbi-specific firmware changes.

This keeps host-tool risk, vendor-integration risk, hardware bring-up risk, and pibbi application changes separated enough to debug independently.
