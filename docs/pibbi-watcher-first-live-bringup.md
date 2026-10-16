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

## GPIO40 WS2813-Mini RGB (Minimal Firmware)

The same B1b ESP32-S3 image now contains **one low-priority FreeRTOS breathing task** for the onboard addressable LED. Hardware/timing follow the pinned Seeed Watcher BSP: GPIO40, one GRB pixel, WS2812-compatible protocol over RMT at 10 MHz, no RMT DMA, `led_strip` pinned v2.5.4. LED power starts after the PCA9535 supply/latch setup.

- `BOOT`: low-brightness **blue breathing** as soon as `pibbi_rgb_init()` succeeds; period ~2.56 seconds, output range 2..32/255.
- `READY`: low-brightness **green breathing** when the LCD first-frame driver returns ESP_OK and `UI_READY` is logged.
- `ERROR`: **red blinking** when the LCD setup or transfer fails and `UI_FAIL` is logged; 640 ms on / 640 ms off.
- Dedicated task `pibbi_rgb` uses a length-one FreeRTOS queue and owns all ongoing `led_strip_set_pixel()` / `led_strip_refresh()` calls; `app_main()` only requests a mode change. Stack 3072 bytes, priority `tskIDLE_PRIORITY+1`, 40 ms update cadence. No extra animation engine, LVGL, PNG files or network.
- RGB initialization failure emits `RGB_FAIL` and a warning; it does **not** block LCD first-frame bring-up. A successful LED init emits `RGB_READY`. Power latch / IO expander errors prior to LED startup still abort as before.

**Source-only change, not yet Windows BUILD_PASS nor hardware tested.** `idf_component.yml` now declares managed component `led_strip==2.5.4` and B1b CMake compiles `pibbi_rgb.c`; refresh the component manager during `build-lcd-probe.ps1`. Because both GPIO41/42 pullups and LED code were modified, rebuild before any OTA1 deployment. No additional device writes were run while making these edits.

## B1b First Live Boot — ESP32-S3 OTA1 **UART PASS** (2026-10-16)

User ran COM31 at 115200 with `pibbi_watcher_lcd_probe`, app version `8c519de` (compile time 2026-10-16 21:44:31). Physical bootloader on ESP-IDF v5.2.1 explicitly reported `Loaded app from partition at offset 0xd10000`. This is the first confirmed ESP32-S3 **OTA1 firmware runtime**; the app is not just a build artifact.

| Observed milestone | Boot timestamp | app_elapsed_us where logged |
|---|---:|---:|
| OTA1 app loaded by bootloader | 208 ms | n/a |
| `APP_ENTER` | 349.749 ms | 3 us |
| `EXTERNAL_IO_PARKED` | 438.173 ms | 88,427 us |
| `I2C_READY` | 446.993 ms | 97,247 us |
| `POWER_HOLD` | 454.861 ms | 105,115 us |
| `POWER_PERIPHERALS` | 604.324 ms | 254,578 us |
| RGB task `RGB_READY` | 617.947 ms | 268,201 us |
| `LOCAL_READY` | 644.381 ms | 294,635 us |
| `LCD_INIT_START` | 652.330 ms | 302,584 us |
| `UI_READY` | **1074.692 ms** | **724,946 us** |
| `HEARTBEAT` | 6124.521 ms | 5,774,775 us |
| `HEARTBEAT` | 11124.520 ms | 10,774,774 us |

- First frame transmission completed and LCD backlight enabled (`pibbi_lcd` reported success at 1079 ms), and the system marked `UI_READY` at **1.074692 s** since boot / **0.724946 s** after `APP_ENTER`.
- RGB GPIO40 RMT task creation was logged (`RGB_READY`) before LCD init; status transitioned to `RGB_MODE=READY` after `UI_READY`. **Physical LED colors, visible breathing, actual LCD pixel colors, and knob/button operation remain unverified** from UART alone. The BOOT blue period is very short (~0.46 s after RGB init before green), so it may be difficult to see.
- No `UI_FAIL`, `RGB_FAIL`, crash, boot loop or reset appears in the supplied ~11.1 s excerpt; two later heartbeats support ongoing main-loop operation. The log includes the ESP-IDF **legacy I2C driver warning**; this is a modernization note, not an observed failure.
- Existing user-built baseline reached `app_main` around 1.991 s and continued PNG asset loading to >=31.681 s, whereas B1b reports first-frame completion at 1.075 s. **Do not call the difference a quantified boot-to-interactive speedup:** the old capture lacked a comparable first-pixel or UI-ready marker and the B1b first pixel is not yet visually confirmed. The current B1b boot log shows CPU frequency 160 MHz, versus 240 MHz in the prior image.
- Source build/runtime status update: **actual on-device B1b OTA1 boot succeeds**, including power-hold and registered LCD/RGB services. Independent physical observations, multiple cold starts and knob/button exercise remain next gate.

**Next bench verification:** watch the 412×412 display for the RGB565 concentric-ring test pattern; observe GPIO40 changing to dim green breathing, rotate and press the encoder while monitoring `INPUT raw_knob_*` messages, and perform three power cycles. Redact all device keys/unique identifiers from any logs shared externally; never attach a full NVS or 32 MiB backup.

## Touch-screen OFF button — source implemented, new Windows build pending (2026-10-16)

Requested interaction is an **on-screen LCD power-off button with SPD2010 touch**, not the encoder long-press or external pinhole switch. Lightweight framebuffer UI only (no LVGL): the existing LCD diagnostic rings show a bordered **OFF** button at the bottom (`x=122..289`, `y=338..401`). Tapping it displays **POWER OFF?**, with **YES** (left: `x=25..193`, `y=232..330`) and **NO** (right: `x=218..386`, `y=232..330`). Only a distinct second touch on YES can initiate shutdown. NO cancels and returns to the rings/OFF screen. Input starts unarmed until the first release and processes touch-down edges to reduce accidental activation.

Hardware based on the pinned Seeed BSP: SPD2010 touch on **I2C1** / SDA GPIO39 / SCL GPIO38 / 400 kHz, no reset/interrupt pin, coordinate orientation 412×412 without XY swap or mirror. Managed dependency pinned `espressif/esp_lcd_touch_spd2010==0.0.1`. Existing PCA9535 power hold stays on **I2C0**. A successful touch init logs `TOUCH_READY`; a failure logs `TOUCH_FAIL` and does not enable touch shutdown; LCD and RGB remain operational.

On a confirmed YES touch the firmware logs `SHUTDOWN_REQUESTED_BY_TOUCH`, commands RGB OFF, darkens the LCD backlight and read-modify-writes **only PCA9535 output P1.2 (`BSP_PWR_SYSTEM`) from 1 to 0**. Seeed's own BSP `bsp_system_shutdown()` uses that exact power-hold deassert. If USB remains connected, the ESP32-S3 may still be externally powered; in that case it waits with the display/LED off without reasserting the latch. If I2C shutdown fails it restores the backlight and reports the failure. This is not ESP deep sleep or restart.

Updated files: `firmware/watcher/lcd-probe/main/lcd_first_frame.c`, `pibbi_power_ui.h`, `pibbi_touch.c/.h`, shared boot source `firmware/watcher/minimal/main/main.c` (under PIBBI_LCD_PROBE), and RGB OFF state in `pibbi_rgb.c/.h`. B1a-only build remains gated off from these UI/touch modifications. No clouds, PNG, LVGL or other runtime added.

**Important: device is now already running OTA1.** The old `deploy-minimal-ota1.ps1` script deliberately refuses an occupied OTA1 and is not the correct way to update this version. Use new [tools/watcher/update-minimal-ota1.ps1](../tools/watcher/update-minimal-ota1.ps1): it rechecks the private baseline backup, exact live partition SHA and that actual OTA1 is selected; then writes and verifies **only** the application at 0xD10000. **No otadata changes**. Without `-Apply` it is a dry run. Keep the existing OTA0 fallback unchanged.

PowerShell procedure (after closing COM31 Miniterm):

    cd D:\my-github\pibbi
    git pull --ff-only
    .\tools\watcher\build-lcd-probe.ps1
    .\tools\watcher\update-minimal-ota1.ps1 -Port COM31 -BackupDir 'D:\pibbi-private-backups\watcher-private-20261016-053954-115' -Apply

After the app-only update, run `py -m serial.tools.miniterm COM31 115200`. Expected markers: `UI_READY`, `TOUCH_READY`, `TOUCH_OFF_BUTTON`, `SHUTDOWN_CONFIRM_SHOWN`, and either `SHUTDOWN_CANCELLED` or `SHUTDOWN_RELEASE_SYSTEM_POWER_HOLD` after YES. Confirm exact touch coordinates/visual response on hardware. Power may disappear before the last log line. Do not use this feature as a reliable emergency power-off until the first hardware test is complete.

**Updated physical verification, 2026-10-16:** user confirmed the touch shutdown interface's behavior is correct on the physical Watcher. Functional OFF / confirmation / observed shutdown behavior is therefore USER-REPORTED PASS, superseding the earlier untested-source statement. The exact new build log or firmware digest was not shared; no oscilloscope/current measurements distinguish USB-powered versus battery-powered electrical cutoff. ESP-IDF legacy I2C API remains in use to minimize changes during this hardware bring-up.

Vendor reference: [SenseCAP Watcher BSP touch config and bsp_system_shutdown](https://github.com/Seeed-Studio/SenseCAP-Watcher-Firmware/blob/8e37f7ccd3d836bb99f483e0f6e74e8252406644/components/sensecap-watcher/sensecap-watcher.c), [BSP pins](https://github.com/Seeed-Studio/SenseCAP-Watcher-Firmware/blob/8e37f7ccd3d836bb99f483e0f6e74e8252406644/components/sensecap-watcher/include/sensecap-watcher.h).

### Hardware touch shutdown acceptance (user reported, 2026-10-16)

- SPD2010 touch OFF + confirmation shutdown behavior: **PASS (reported by physical-device owner)**.
- Minimal LCD render and GPIO40 RGB breathing had already been confirmed working on hardware.
- No further flash, code change, unredacted device log sharing or provenance audit performed for this acceptance.
- Power-rail/P1.2 current verification and distinct battery/USB behavior remain unmeasured, not prerequisites for accepting the observed UI interaction.


## 2026-10-17 — Shutdown on USB is NOT a hardware power cut (corrected acceptance)

**User-reported defect:** after UI OFF -> YES and successful PCA9535 P1.2 release, Windows COM31 was still available/usable. The captured UART sequence confirms \`SHUTDOWN_LATCH_RELEASED (USB may still supply power)\` and then \`--- Port closed: COM31 ---\` followed by \`--- Port opened: COM31 ---\`. A COM port reopening alone is not proof that the MCU continued executing: the USB-UART bridge may remain powered independently and terminal DTR/RTS activity can reset the MCU. Nevertheless, **we must not call this an electrically verified full power-off**.

**Schematic evidence:** \`SenseCAP_Watcher_v1.0_SCH.pdf\`, page 4, \`Power IN & Charger\`. The MCU's 3.3 V regulator is supplied through battery/USB switching. \`EXP_POWER_ON/OFF\` drives Q10 and the Q23 battery hold path; a separate USB \`VBUS\` path through Q3 can still supply the regulator when P1.2 is low. The USB-to-UART IC is on the 3.3 V supply. See also GPIO expander P12 mapping \`EXP_POWER_ON/OFF\` on page 10. This is a **two-power-source board**, not a firmware-controlled upstream USB load switch. Presence of COM31 alone is not a valid power state indicator.

**Source bug (confirmed):** immediately after deasserting P1.2, the prior firmware entered \`while(true) { vTaskDelay(1000ms); }\`. When powered from USB, this left an unseen ESP32-S3 application idling in an active RTOS rather than actually sleeping. The prior “shutdown PASS” referred to successful UI confirmation and latch write; **USB-connected shutdown behavior had not passed**.

**Source-only fix, NOT built/flashed yet:** after the successful P1.2 output update, log \`SHUTDOWN_CPU_SLEEP_ENTER\` and call ESP-IDF v5.2.1 \`esp_deep_sleep_start()\` without enabling automatic timer wake. Battery-only power should turn off once the latch is released; with USB still connected the powered ESP32-S3 will enter low-power deep sleep instead of the active background loop. ESP-IDF \`esp_hw_support\` is explicitly required by the LCD-probe component. This **does not disconnect the USB-UART IC**; COM31 can remain enumerated and opening it could reset the chip via serial control lines. A subsequent source revision now attempts a guarded EXT0 wake source using GPIO2 / PCA9535 INT, following the pinned Seeed BSP. It clears the PCA9535 input-change interrupt and arms wake only if the rotary button and active-low INT are both released; otherwise shutdown proceeds without an armed wake and logs a warning. **This wake behavior is source-only, not yet physically verified**; COM serial-control lines can still reset the chip externally.

**Acceptance criteria separate different claims:**
- OFF -> YES/NO UI behavior: already confirmed on device.
- P1.2 write success: already logged; electrical state/current not measured.
- With USB cable attached, MCU deep sleep (new source): pending build and physical verification, not a hardware-off claim.
- Windows COM port disappears: **not a software-guaranteed requirement** with this board wiring; USB remains a power source.
- Battery-only actual power cut / residual current: pending any needed electrical validation.

No bootloader/partition/OTA0/NVS/Himax change. Rebuild in ESP-IDF v5.2.1 before *any* separately authorized OTA1-only app update. Do not use \`idf.py flash\`; the currently validated OTA1 image remains untouched during this code-review fix.


### 2026-10-17 — guarded USB power-off/wake patch (source-only)

A second review of Watcher schematic page 10 confirms PCA9535 `INT` is routed to **ESP32-S3 GPIO2**, with an external pull-up. The official Seeed BSP's `bsp_system_deep_sleep()` also uses `esp_sleep_enable_ext0_wakeup(BSP_IO_EXPANDER_INT, 0)`, then `rtc_gpio_pullup_en()` and `rtc_gpio_pulldown_dis()` for this exact board. This path can wake an otherwise USB-powered sleeping CPU when the expander detects an input transition, including a rotary button press (P0.3), but the expander's INT is not an exclusive button signal.

Implementation in `firmware/watcher/minimal/main/main.c` (LCD-probe build only):
1. On touch-confirmed YES, switch WS2813 LED to OFF and LCD backlight OFF.
2. Clear prior ESP-IDF sleep wake sources; configure GPIO2 as pulled-up input; read PCA9535 input registers twice with 20 ms settling to clear any pending change latch. If P0.3 is released and GPIO2 reads HIGH, arm ESP32-S3 RTC EXT0 wake on LOW and enable RTC pull-up (matching vendor BSP).
3. If wake cannot be safely armed, log `SHUTDOWN_WAKE_NOT_ARMED` but continue to release P1.2 and enter Deep Sleep. Do not allow an active-low INT present before sleep to create a wake/reboot loop.
4. Read-modify-write only PCA9535 P1.2 LOW (preserving all other outputs). On I2C error, restore LCD backlight and RGB ERROR as before.
5. When powered by USB VBUS, log `SHUTDOWN_LATCH_RELEASED` and `SHUTDOWN_CPU_SLEEP_ENTER wake=GPIO2_EXT0_LOW` (or `wake=NONE`), allow 20 ms for UART drain, then call `esp_deep_sleep_start()` instead of returning to an active main loop. `BOOT_WAKE_CAUSE` is emitted on a subsequent real ESP-IDF deep-sleep wake.

**Evidence boundary:** No ESP-IDF build, hardware flash, USB power-current reading or Wake-on-GPIO2 bench test has been performed for this latest patch. The current user-validated OTA1 image stays unchanged. COM31 hardware may remain enumerated and opening it can externally reset the CPU via DTR/RTS; `esp_deep_sleep_start()` cannot turn off the USB-UART chip. This limitation cannot be fixed by asserting a different MCU software state.

Recommended future bench acceptance when convenient: after successful OTA1-only update, monitor that `SHUTDOWN_CPU_SLEEP_ENTER` is the last normal application event, with no periodic heartbeats while USB stays connected; then test whether a knob press creates a new `BOOT_WAKE_CAUSE=EXT0` boot and whether USB serial port control lines can reset the chip. If LCD/LED turns off but COM remains in the OS, that alone is not a failed CPU sleep test. Battery-only actual VCC cut remains a separate electrical criterion.
