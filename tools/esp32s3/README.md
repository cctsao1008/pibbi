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

The pibbi baseline pins ESP-IDF `v5.2.1` at its exact release commit because the upstream Watcher factory-firmware documentation explicitly requires that version. The Watcher firmware checkout intentionally tracks `main` until one exact revision has passed real-hardware build/flash/smoke validation.

## Important factory-data rule

Seeed's Watcher factory-firmware documentation identifies the `nvsfactory` partition as critical device factory data and recommends backing it up before any flash operation. It also recommends application-only flashing to avoid rewriting that partition.

pibbi therefore treats the safe default as:

1. inspect the device;
2. back up `nvsfactory`;
3. preferably preserve a complete flash image as an additional recovery artifact;
4. build `factory_firmware`;
5. flash **application only**.

Do not erase the whole device as a normal bring-up step.

## Inspect a connected Watcher

Before changing flash, inspect the ESP32-S3 non-destructively:

```powershell
.\tools\esp32s3\inspect-device.ps1 -Port COM14
```

The script queries:

- chip ID;
- SPI flash ID/size;
- ESP32 security information.

## Back up critical factory data

Back up the upstream-documented `nvsfactory` region before the first flash:

```powershell
.\tools\esp32s3\backup-nvsfactory.ps1 -Port COM14
```

The script follows Seeed's documented factory layout (`0x9000`, 200 KiB), calculates SHA-256, and stores the result under:

```text
artifacts/esp32s3/nvsfactory-backup/<utc-run-id>/
├─ nvsfactory.bin
└─ backup-manifest.json
```

For stronger recovery coverage, also preserve the complete SPI flash:

```powershell
.\tools\esp32s3\backup-flash.ps1 -Port COM14
```

The full backup detects the SPI flash size, reads the complete device image, verifies output length, calculates SHA-256, and stores:

```text
artifacts/esp32s3/factory-backup/<utc-run-id>/
├─ flash.bin
└─ backup-manifest.json
```

Both backup scripts default to 2,000,000 baud. Override with `-Baud` if the host/USB-UART path is unstable. If full-flash size detection is unavailable, specify it explicitly, for example 32 MiB:

```powershell
.\tools\esp32s3\backup-flash.ps1 -Port COM14 -SizeBytes 33554432
```

## Build

Build the upstream factory-compatible firmware:

```powershell
.\tools\esp32s3\build.ps1
```

The default example is `factory_firmware`. Other examples can still be used for host/toolchain experimentation:

```powershell
.\tools\esp32s3\build.ps1 -Example helloworld
```

Do not assume another example's partition layout is safe to flash onto a factory Watcher.

Build output and provenance are stored under:

```text
artifacts/esp32s3/build/<watcher-short-sha>/<example>/
├─ build/
└─ build-manifest.json
```

The manifest records the exact Watcher source commit, ESP-IDF commit, target, application ELF/BIN size, and SHA-256.

## Flash a verified build

Safe default:

```powershell
.\tools\esp32s3\flash.ps1 -Port COM14
```

`flash.ps1` defaults to `factory_firmware`, verifies the build manifest and ELF/BIN hashes, and consumes ESP-IDF's generated `flash_app_args`. This writes the application only; it does not intentionally rewrite the bootloader, partition table, or `nvsfactory` partition.

A non-factory example is rejected unless explicitly overridden:

```powershell
.\tools\esp32s3\flash.ps1 -Port COM14 -Example helloworld -AllowNonFactoryExample
```

Use that override only after checking that the generated application offset is compatible with the actual device layout.

After a successful flash, the exact application artifact and operation are recorded in `flash-manifest.json`.

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
4. `backup-nvsfactory.ps1`
5. `backup-flash.ps1`
6. `build.ps1` (`factory_firmware` by default)
7. verify the build manifest/SHA
8. `flash.ps1` (application only)
9. `monitor.ps1`
10. run the hardware smoke test
11. only after validation, pin the exact Watcher firmware commit in `tools/setup/esp32s3-tools.psd1`

This keeps host setup, source revision, generated binaries, factory data, device state, and hardware validation independently traceable.
