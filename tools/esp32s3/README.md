# ESP32-S3 / SenseCAP Watcher Tools

This directory owns pibbi's host-side ESP32-S3 build, inspection, backup, flashing, and monitoring workflow for the SenseCAP Watcher.

The vendor firmware source remains under `third_party/SenseCAP-Watcher-Firmware`; ESP-IDF remains under `third_party/esp-idf`; Espressif-managed host tools are installed under `.tools/esp-idf`.

## Setup

From the pibbi repository root on Windows:

```powershell
.\tools\setup\bootstrap-esp32s3.ps1
.\tools\setup\check-esp32s3-env.ps1
```

For an interactive ESP-IDF shell without changing the machine-wide environment:

```powershell
. .\tools\setup\activate-esp32s3.ps1
```

The pibbi baseline pins ESP-IDF `v5.2.1` at its exact release commit because that is the version documented by the upstream SenseCAP Watcher firmware. The Watcher firmware checkout intentionally tracks `main` until one exact revision has passed real-hardware build/flash/smoke validation.

## Build

Build the smallest upstream example first:

```powershell
.\tools\esp32s3\build.ps1
```

The default example is `helloworld`. Another upstream example can be selected explicitly:

```powershell
.\tools\esp32s3\build.ps1 -Example factory_firmware
```

Build output and provenance are stored under:

```text
artifacts/esp32s3/build/<watcher-short-sha>/<example>/
├─ build/
└─ build-manifest.json
```

The manifest records the exact Watcher source commit, ESP-IDF commit, target, application ELF/BIN size, and SHA-256.

## Inspect a connected Watcher

Before changing flash, inspect the ESP32-S3 non-destructively:

```powershell
.\tools\esp32s3\inspect-device.ps1 -Port COM14
```

The script queries:

- chip ID;
- SPI flash ID/size;
- ESP32 security information.

## Back up factory flash

Before the first experimental flash, preserve the complete ESP32-S3 flash contents:

```powershell
.\tools\esp32s3\backup-flash.ps1 -Port COM14
```

The script detects the SPI flash size from `esptool`, reads the full device image, verifies the output length, calculates SHA-256, and stores the image plus a manifest under:

```text
artifacts/esp32s3/factory-backup/<utc-run-id>/
├─ flash.bin
└─ backup-manifest.json
```

If automatic flash-size detection is unavailable, specify the size explicitly:

```powershell
.\tools\esp32s3\backup-flash.ps1 -Port COM14 -SizeBytes 33554432
```

## Flash a verified build

```powershell
.\tools\esp32s3\flash.ps1 -Port COM14
```

Or for another example:

```powershell
.\tools\esp32s3\flash.ps1 -Port COM14 -Example factory_firmware
```

`flash.ps1` verifies the build manifest and ELF/BIN hashes before writing. It invokes `esptool` directly with the ESP-IDF-generated `flash_args`, so flashing does not implicitly rebuild the application.

After a successful flash it records `flash-manifest.json` alongside the build evidence.

## Monitor

```powershell
.\tools\esp32s3\monitor.ps1 -Port COM14
```

Use `Ctrl+]` to exit the ESP-IDF monitor.

## Bring-up order

For a new Watcher, use this order:

1. `bootstrap-esp32s3.ps1`
2. `check-esp32s3-env.ps1`
3. `inspect-device.ps1`
4. `backup-flash.ps1`
5. `build.ps1`
6. verify the build manifest/SHA
7. `flash.ps1`
8. `monitor.ps1`
9. run the hardware smoke test
10. only after validation, pin the exact Watcher firmware commit in `tools/setup/esp32s3-tools.psd1`

This keeps host setup, source revision, generated binaries, device state, and hardware validation independently traceable.
