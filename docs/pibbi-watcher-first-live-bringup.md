# pibbi Watcher — First Live Bring-up (OTA1-only)

**Goal:** boot the standalone B1b `pibbi_watcher_lcd_probe` image on the physical Watcher and measure `APP_ENTER`, `LOCAL_READY`, `UI_READY`, knob input, and the first visible pixel. Optimize for working pibbi firmware, **not** preserving or investigating an untouched Seeed factory installation.

## Corrected device provenance

The existing OTA0 app (`pibbi_watcher`, version `d5c414c`, compiled Oct 15 2026) is **user-built / user-flashed**, not an untouched OEM factory image. Stop referring to it as 'factory' or inventing requirements for pristine Seeed restoration. It is only a known current working/reference firmware and optional convenient fallback.

Read-only observations completed 2026-10-16:

- Security: ESP32-S3 Secure Boot disabled; Flash Encryption disabled.
- Physical 32 MiB partition layout matches the custom B1b build: `ota_0` 0x110000 / 12 MiB, `ota_1` 0xD10000 / 12 MiB.
- 32 MiB pre-change backup SHA256: `347E603A855C545541FE5FB56A1620229C4365BDD1D167B63AF00A8F945DF282`. Saved privately. This is enough for risk mitigation; **no further OEM provenance audit**.
- `ota_0` has internally valid ESP32-S3 image checksum and appended SHA256; B2e PASS.
- `ota_1` **all 0xFF** (12,582,912 bytes) in snapshot; B2f PASS.
- Serial boot log directly showed `Loaded app from partition at offset 0x110000`: current OTA0 selection confirmed.
- Existing firmware: `app_main()` 1.991 s; SPD2010 driver created at 3.028 s; PNG asset load reports continue to 31.681 s. This is *not* measured first-pixel or UI-interaction latency.
- Independent B1b 412×412 SPD2010 LCD probe build PASS on Windows ESP-IDF v5.2.1. No first pixel has been observed on real hardware yet.

## First-run scope

1. Flash **only** the B1b application BIN to `ota_1` (start **0xD10000**, maximum **0xC00000**). Never use generic `idf.py flash` / `idf.py app-flash`: their existing generated app target is 0x110000 (OTA0). Do NOT reflash bootloader, partition table, NVS, model, storage, or Himax.
2. Verify OTA1 written contents match the local B1b BIN by readback/SHA256. **Do not change OTA selection if this fails**.
3. Switch OTA selection to slot 1 using ESP-IDF v5.2.1 **official `otatool.py switch_ota_partition --slot 1`**, which handles OTA seq/CRC; keep OTA0 image untouched. The tool does write the OTA-data partition, separate from the OTA1 app write. Review invocation/version before executing.
4. Boot with UART capture. Expect an `esp_image`/bootloader line loading **0xD10000**. Then assess `BOOT_MARK stage=...` through `UI_READY`, visual first-frame rings, raw knob/button changes, and the 5s heartbeat. Check for `UI_FAIL`, restarts and power-hold failures.
5. If UI is unusable or program restarts, return ROM download mode and switch OTA selection back to slot 0 using same official OTA tool; never erase NVS or write OTA0 for a normal rollback.

**The user explicitly authorized one OTA1 application write and OTA boot-selector change on 2026-10-16.** Guarded deployment and rollback scripts are now committed; the user must still run them locally. No physical write has been executed by the assistant. The app test may fail even after Build PASS, especially the LCD/power control, so having UART and a serial recovery path is important.

## Outcome and follow-up

First metric: time from `APP_ENTER` to `UI_READY`, measured by new B1b firmware UART (provisional target <= 2.0 s, not guaranteed). Separately record power-button to first visible pixel and successful knob interaction. Only then add autonomous core, HX event handling, voice and optional network incrementally. Do not rebuild the Seeed PNG UI or cloud stack.

## Sensitive logs

Current image logs factory-like provisioning keys and identifiers at startup; redact all before public sharing. No credentials or full backups belong in this repo.

## 2026-10-16 — minimal firmware deployment (user approved, script not executed)

Minimal image source is already in firmware/watcher/lcd-probe, reusing B1a startup code; contains ONLY: ESP32-S3 board GPIO parking, I2C PCA9535 power-hold, bare SPI3/QSPI SPD2010 first frame, basic raw knob+button telemetry and BOOT_MARK timing. **No SenseCraft/Task Flow, PNG loader, LVGL, Wi-Fi, BLE, audio, cloud, HX6538 model or service init**. The existing Windows B1b build is PASS, size 297,904 B before any future rebuild.

Guarded PowerShell deploy [tools/watcher/deploy-minimal-ota1.ps1](../tools/watcher/deploy-minimal-ota1.ps1): validates private backup integrity and 12 MiB OTA1 snapshot blank, compiled BIN image header/checksum/hash and live flash partition SHA, OTA metadata/current selected OTA0, live first 4 KiB OTA1 erased; invokes only esptool `write_flash --flash_mode keep --flash_freq keep --flash_size keep --verify 0xD10000 <app>`; then separately `verify_flash 0xD10000 <app>`. **Only after verification** uses official ESP-IDF v5.2.1 `otatool.py switch_ota_partition --slot 1`, which writes OTA metadata, and rereads the metadata to check OTA1 selection. Manual explicit `-Apply` required; without it performs no writes.

Rollback [tools/watcher/restore-ota0-boot.ps1](../tools/watcher/restore-ota0-boot.ps1) uses the same partition guard, checks OTA0 image header, invokes official `otatool.py switch_ota_partition --slot 0`, verifies selection; modifies only otadata. It also requires `-Apply`. The original OTA0 user-built image is not touched by either script.

**Run from ESP-IDF v5.2.1 PowerShell, with stable power/USB and no running COM31 miniterm:**

    cd D:\my-github\pibbi
    git pull --ff-only
    .\tools\watcher\build-lcd-probe.ps1
    .\tools\watcher\deploy-minimal-ota1.ps1 -Port COM31 -BackupDir 'D:\pibbi-private-backups\watcher-private-20261016-053954-115' -Apply

Inspect the command output for `PRIVATE_BACKUP_AND_OTA1_SNAPSHOT_PASS`, `LIVE_PREFLIGHT_OTA0_SELECTED_OTA1_EMPTY_PASS`, `OTA1_APP_WRITE_VERIFY_PASS`, `OTA_BOOT_SELECTION_OTA1_PASS`, and `DEPLOY_OTA1_PASS`. After deployment, run `py -m serial.tools.miniterm COM31 115200`, restart the device, confirm boot offset **0xD10000**, then `BOOT_MARK ... UI_READY` and visible rings. If failure, close miniterm with Ctrl+] and perform:

    .\tools\watcher\restore-ota0-boot.ps1 -Port COM31 -Apply

After rollback confirm boot offset **0x110000**. The read-flash/OTA tool uses download mode; the Watcher may need manual BOOT/RESET if automatic reset cannot access the ROM. If COM31 cannot connect, **do not repeatedly flash/erase**; diagnose USB reset/boot first.

Potential unresolved runtime risks: panel DMA callbacks, PCA9535 power sequence, SPI3 QSPI timing and backlight; a Build PASS is not a hardware display PASS. Thus UI_READY and first physical pixels must be measured on-device. The goal is fast pibbi minimal functionality, NOT OEM firmware restoration.
