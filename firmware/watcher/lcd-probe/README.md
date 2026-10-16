# Watcher B1b / pibbi v0.1 — First Behavior

Status: B1b's underlying Watcher power, LCD, RGB and touch-shutdown hardware has **already been verified by the user**. The new **v0.1 face and behavior changes are source-only**, with host-only Behavior Engine tests passed; ESP-IDF rebuild and v0.1 on-device validation remain pending. The existing guarded OTA1 updater is the only intended application-write path.

## Target and design

- ESP32-S3 + factory-Watcher board wiring from pinned Seeed `SenseCAP-Watcher-Firmware` commit `8e37f7ccd3d836bb99f483e0f6e74e8252406644`.
- LCD controller SPD2010; 412×412 RGB565, SPI3 QSPI, GPIO7 clock / GPIO9,1,14,13 data / GPIO45 chip-select / GPIO8 PWM backlight.
- SPI Mode 3, 40 MHz, 32-bit command + 8-bit parameter framing; component `espressif/esp_lcd_spd2010` **exact 1.0.1** matching Seeed's factory BSP dependency.
- Reuses B1a `minimal/main/main.c` directly as its power/knob bootstrap, compiled with `PIBBI_LCD_PROBE`. B1a itself is unaffected and should continue to build independently.
- No LVGL, UI assets, large framebuffer, PSRAM, networking, factory Task Flow, SenseCraft, Cloud, audio or HX6538 firmware changes.
- Uses a single 412×16 pixel DMA-capable RGB565 stripe buffer (~12.9 KiB). All 27 stripe transfers are callback/timeout synchronized before enabling PWM backlight. The last stripe draws 12 rows.
- The 0-to-412 X address range satisfies SPD2010's documented 4-pixel horizontal alignment requirement.
- The first-boot diagnostic concentric rings have been replaced in **v0.1 source** by pibbi eyes, a tiny fixed `PIBBI` title and preserved `OFF` -> `POWER OFF?` -> YES/NO touchscreen confirmation.
- A pure C Behavior Engine produces Idle/Engaged/Rest, blink and gaze changes from actual local inputs. **Only the face rectangle is DMA-refreshed** for pose changes; see [v0.1 behavior plan](../../../docs/pibbi-first-behavior-v01.md).

## Boot marks

Common code emits `APP_ENTER`, `EXTERNAL_IO_PARKED`, `I2C_READY`, `POWER_HOLD`, `POWER_PERIPHERALS`, `LOCAL_READY`. When B1b is built with the LCD hook enabled, it additionally emits `LCD_INIT_START` and (only after all stripe DMA transfers and backlight enable succeed) `UI_READY`, or `UI_FAIL` on a returned error. These are source-defined checkpoints, not measured logs.

Note: `LOCAL_READY` in B1a/B1b currently means local power/input telemetry exists; actual UI readiness is separately `UI_READY`. Knob signals are raw pins, not yet implemented as a rendered UI selection.

## Build B1b on Windows

Require ESP-IDF **v5.2.1** activated (same toolchain family as the earlier B1a Windows PASS), plus Internet access for one-time managed component download:

```powershell
cd D:\my-github\pibbi
git switch research/hx6538-runtime-baseline-audit-20261015
git pull --ff-only
.\tools\watcher\build-lcd-probe.ps1
```

The script executes only `idf.py build` and prints an ELF SHA-256 when successful. Expected files are within `firmware/watcher/lcd-probe/build/` and remain ignored by Git:

```text
pibbi_watcher_lcd_probe.elf
pibbi_watcher_lcd_probe.bin
```

**Do not execute ESP-IDF's generic `idf.py flash` / `app-flash` commands.** For the already-running OTA1 user device, use only the guarded `tools/watcher/update-minimal-ota1.ps1` after a successful build and an explicit local `-Apply`. This script targets `0xD10000` and does not touch OTA metadata.

## Verification boundaries

- The user's **B1a build PASS** provides no proof B1b compiles or controls the actual LCD. B1b is a separate build target.
- Physical OTA1 B1b startup was verified by UART (`UI_READY` at 1.075 s), and the user confirmed LCD, RGB and touch shutdown behavior. **The newer v0.1 behavior source has not yet been built or flashed.**
- A build PASS validates compilation/linking and component compatibility, not DMA transfer completion timing, display colors, touch, power latch stability, or cold-boot performance.
- For first hardware bring-up after B2, use UART logging and conservative brightness to distinguish `LCD_INIT_START`, `UI_READY` and `UI_FAIL`. Three cold starts and comparison to original factory image are required.

Track work in [Issue #5](https://github.com/cctsao1008/pibbi/issues/5). No PR.
