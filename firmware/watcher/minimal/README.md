# pibbi Watcher — Minimal ESP32-S3 Firmware (B1a)

**Status: source available, firmware BUILD NOT YET VERIFIED, NO FLASH AUTHORIZED.**

Independent ESP-IDF project for Watcher. Avoids the factory SenseCraft application, cloud binding, BLE provisioning, MQTT, Task Flow, OTA service, LVGL hierarchy, audio processing and AI model loading. No original Seeed SDK source is modified.

## Scope: first milestone only

Functional code in `main/main.c`:

- Preserve Seeed's early external LCD/touch GPIO-low parking sequence, then initialize ESP32-S3 I2C0 on GPIO47 (SDA), GPIO48 (SCL), 400 kHz.
- Address PCA9535 at I2C 0x21 and match Seeed's startup expander direction/output order.
- Assert SYSTEM power hold first, then the original peripheral STARTUP mask with original 100 ms + 50 ms waits. The first build deliberately does **not** optimize the power-latch sequence.
- Print `BOOT_MARK` records with `boot_us` (**microseconds since ESP timer initialization, not from power-button press**) and `app_elapsed_us` (since app_main); checkpoints: `APP_ENTER`, `EXTERNAL_IO_PARKED`, `I2C_READY`, `POWER_HOLD`, `POWER_PERIPHERALS`, `LOCAL_READY`, periodic `HEARTBEAT`.
- Poll raw quadrature inputs GPIO41/GPIO42 and expander pin P0.3; log changes only. Raw input changes are **not** calibrated knob direction or button active level.

**Not in B1a:** LCD initialization / first pixel, full knob UI, autonomous core on ESP32, Himax AI pipeline, microphones, speech, WLAN or Ethernet, factory firmware restoration. `LOCAL_READY` currently means **minimal power/input task ready**, not display ready. These are separate milestones.

## Vendor provenance

Seeed upstream `Seeed-Studio/SenseCAP-Watcher-Firmware` commit `8e37f7ccd3d836bb99f483e0f6e74e8252406644`, specifically:

- `components/sensecap-watcher/include/sensecap-watcher.h` — GPIO, expander bits, LCD, Himax.
- `components/sensecap-watcher/sensecap-watcher.c` — `bsp_io_expander_init()` startup power-hold behavior.
- `components/esp_io_expander_pca95xx_16bit/esp_io_expander_pca95xx_16bit.c` — PCA9535 16-bit 0x02 output / 0x06 direction register format.
- `examples/factory_firmware/partitions.csv` — 32 MB, 200 KiB factory NVS and two 12 MB OTA slots.
- `examples/factory_firmware/docs/installation.md` — factory example uses **ESP-IDF v5.2.1** and warns to preserve factory NVS/EUI.

The upstream main branch might evolve. Code/pins are pinned to the referenced commit; **not verified against the user's physical hardware revision yet**.

## Build-only — Windows ESP-IDF v5.2.1 PowerShell

Prerequisite: install and activate official [ESP-IDF v5.2.1](https://docs.espressif.com/projects/esp-idf/en/v5.2.1/esp32s3/get-started/index.html) in a separate terminal. This ESP project deliberately has **no dependency on the upstream factory application**.

From `D:\my-github\pibbi`:

```powershell
git switch research/hx6538-runtime-baseline-audit-20261015
git pull --ff-only

# Use an ESP-IDF v5.2.1 PowerShell with idf.py in PATH.
.\tools\watcher\build-minimal.ps1
```

Expected build-only artifacts (if the IDF environment is correct and compilation succeeds):

```text
firmware/watcher/minimal/build/pibbi_watcher_minimal.elf
firmware/watcher/minimal/build/pibbi_watcher_minimal.bin
firmware/watcher/minimal/build/partition_table/partition-table.bin
```

Never run `idf.py flash`, `erase-flash`, `write_flash`, or `idf.py app-flash` merely because the build passes. The generated partition CSV is the vendor SOURCE layout, not yet independently checked against the actual unit. Do not build/flash with a different IDF version without review.

## B0 — obtain the existing factory boot baseline (read-only)

Before replacing anything, record at least **three cold boots**, preferably on camera with stopwatch/video. Record these intervals separately:

1. Power-button pressing/hold duration, including boot-button policy.
2. Power on to factory logo or first display pixel.
3. Power on to first successful knob interaction.
4. Optional: power on to HX6538 recognition/response ready.

Optionally identify ESP32-S3 UART among the two presented by Watcher's correct **data-capable** USB-C port:

```powershell
py -m serial.tools.list_ports
# If pyserial is installed, try one candidate COM port:
py -m serial.tools.miniterm COMxx 115200
```

Use the correct UART; do not change baud or flash settings speculatively. Some serial adapters toggle boot/reset with DTR/RTS; collect three distinct cold boots after opening the terminal. Keep raw logs private: vendor code may log device identity, network configuration, or Wi-Fi passwords. Redact before sharing.

## B2 — prerequisite for any future flash

**STOP:** no actual device write until the unit's 32 MB flash/partition table and ESP secure boot/flash encryption state have been read and reviewed, the factory NVS/EUI and other unique data backed up and hash-verified, a working recovery procedure documented, and the user separately approves flashing.

The Seeed source backup example uses `nvsfactory` offset `0x9000`, size `204800`, but these numbers cannot be assumed for the current device without observing its partition table. Do not publish binary backups of unique factory data. Never full-chip erase or replace Himax firmware for B1a.

## Next bring-up stage B1b (after B1a build feedback)

Add **minimal SPD2010 LCD pixel path and input**, with `UI_READY` separate from `LOCAL_READY`, without LVGL/sensecraft/voice/network. Measure physical first-pixel time after separate authorization and recovery gate. Display ready within 2 s of app_main is an **engineering target**, not a measured result or guarantee.

Track [Issue #5](https://github.com/cctsao1008/pibbi/issues/5). Direct commits only. No PR.
