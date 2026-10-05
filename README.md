# pibbi

`pibbi` is an early-stage embedded/physical-AI project built around the SenseCAP Watcher platform.

The repository is intentionally starting with reproducible development infrastructure before product firmware diverges from upstream vendor code.

## Current platform baseline

- ESP32-S3: system/connectivity/UI side
- Himax HX6538 / WiseEye2: vision and endpoint-AI side
- SenseCAP Watcher hardware

## Repository direction

```text
pibbi/
├─ firmware/                  # pibbi-owned firmware/application code (planned)
│  ├─ hx6538/
│  └─ esp32s3/
├─ third_party/               # external SDK checkouts; not vendored into Git
├─ tools/
│  ├─ setup/                  # reproducible development environment
│  └─ hx6538/                 # vendor-safe build/image/flash workflow
└─ .tools/                    # local pinned host tools; ignored by Git
```

## HX6538 setup on Windows

From a fresh clone:

```powershell
.\tools\setup\bootstrap-hx6538.ps1
.\tools\setup\check-env.ps1
```

For an interactive shell that uses pibbi's pinned HX6538 compiler and GNU Make without changing the machine-wide environment:

```powershell
. .\tools\setup\activate-hx6538.ps1
```

The HX6538 environment is deliberately isolated from other firmware projects. In particular, pibbi uses the upstream-documented Arm GNU Toolchain 13.2.Rel1 locally instead of replacing newer system installations.

See [`tools/setup/README.md`](tools/setup/README.md) for versioning, bootstrap, and SDK pinning policy.

## HX6538 build and image generation

Use pibbi wrappers instead of invoking the vendor flow manually:

```powershell
.\tools\hx6538\build.ps1
.\tools\hx6538\image.ps1
```

`build.ps1` performs a clean upstream build with the pinned local toolchain, validates the expected ELF, records build provenance under `artifacts/`, and restores the vendor SDK's known build-generated changes to tracked prebuilt `.a` archives.

`image.ps1` verifies that ELF against the build manifest, exports the image-generator files from the exact SDK commit into an isolated staging directory, runs the upstream Windows image generator there, and records the resulting `output.img` plus its provenance under `artifacts/`. The live vendor checkout remains untouched.

See [`tools/hx6538/README.md`](tools/hx6538/README.md) for details.

## Bring-up policy

The first milestone is not a custom feature. It is a reproducible known-good baseline:

1. bootstrap a clean host environment;
2. build the unmodified upstream HX6538 example;
3. generate the HX6538 firmware image;
4. flash and boot it on the Watcher;
5. validate the camera and host interface;
6. pin the exact validated upstream SDK commit;
7. only then begin pibbi-specific firmware changes.

This keeps vendor integration risk separate from application-development risk.
