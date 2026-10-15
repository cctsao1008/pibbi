# pibbi Watcher Minimal Firmware — Boot-Time and Bring-up Plan

Status: design/static vendor-source audit; **no device backup, flashing, erase, or runtime boot measurement performed**. Direct research-branch commits, no PR.

## Architecture decision

Build an independent ESP32-S3 ESP-IDF application for pibbi rather than a new SenseCraft task or a reduced factory Task Flow. Reuse Seeed's open BSP only as reference/selected drivers. **Do not erase the whole flash** or replace HX6538 firmware to begin. Initial milestones do not require NPU, networks, cloud account, model loading, or LLM.

Read-only source reviewed: Seeed-Studio/SenseCAP-Watcher-Firmware `main` at `8e37f7ccd3d836bb99f483e0f6e74e8252406644` (2026-07-16 commit); do not claim this is the exact device binary. Reference files:

- `examples/factory_firmware/main/main.c`: `board_init` (storage/factory_info, SPIFFS, I/O expander, optional SD, LVGL display, RGB, codec, SSCMA client, RTC) and `app_init` (audio player/recorder, RGB, device info, SenseCraft, OTA, taskflow, voice, Wi-Fi, time, AT, BLE, commands, sensors).
- `components/sensecap-watcher/sensecap-watcher.c`: I/O expander and power rails, LCD/SPI, RTC, SSCMA, codec.
- `components/sensecap-watcher/include/sensecap-watcher.h`: ESP32-S3 GPIOs, display 412×412, HX6538 reset/SPI wiring and I/O expander power bits.
- `examples/factory_firmware/partitions.csv`: custom 32 MB layout with `nvsfactory` 200K, `nvs` 840K, OTA data, two 12M app slots, model and storage. **Actual device partition table not yet read.**
- `examples/factory_firmware/docs/installation.md`: original factory example documents IDF v5.2.1 and first backing up `nvsfactory` with `esptool` `read_flash 0x9000 204800`; **these addresses are source-specific, not automatically verified on every device firmware revision**.
- OSHW-SenseCAP-Watcher `Firmware/README.md`: preserving factory EUI/credentials critical; Himax modification discouraged. Bundled factory binaries exist, but compatibility/restorability with the user's specific unit is not established.

## What to delete from pibbi firmware v0

- SenseCraft/cloud binding, MQTT, original taskflow/module engine, factory task templates, factory UI hierarchy, unrelated app update/control services.
- Do **not** initialize Wi-Fi, BLE, NPU model, microphone, speaker, touch, SD, SPIFFS, or network at early boot unless proven essential. Optional capabilities become later-phase asynchronous services.

## What MUST remain

- Minimal I/O expander and system-power-hold path. The BSP `bsp_io_expander_init()` manipulates `BSP_PWR_SYSTEM`, `BSP_PWR_START_UP` and delays 100ms + 50ms; power rails and power-button policy require review rather than unconditionally removing this code.
- Working ESP32-S3 console/debug path and reset/recovery path. Keep RTC/watchdog/safe button controls only as requirements are verified.
- LCD bus/brightness control and at least one user input (knob/button) in v0, but no heavyweight factory LVGL UI hierarchy.
- A minimal optional HX6538 SPI reset/command path after first responsive display. Do not flash or rewrite Himax on first bring-up.
- Factory `nvsfactory`, partition table/OTA metadata protection, full restoration data/credentials under private storage.

## Gate B0 — measure present system before changing code

Record 3 or more repeat cold starts on actual Watcher **without flashing**. Use a phone video and ESP32 UART boot log (correct USB-C data port and chip COM identification; Seeed warns the two UART ports can swap enumeration). Separate:

1. `T_hold`: start pressing power button to release; factory quick-start instructs ~3 seconds hold; hardware/button policy is not application boot latency.
2. `T_rom`: ESP boot ROM/second-stage bootloader to `app_main` entry (serial timestamps; earliest ROM/bootloader logs may need independent capture).
3. `T_ui`: `app_main` to first visible pibbi/factory pixel and first knob response.
4. `T_perception`: `app_main` to HX6538 command readiness / real event available (only if measurable on current firmware).
5. `T_network`: `app_main` to Wi-Fi/remote readiness, independent of local UI; report but never gate local interaction.

Capture: factory firmware version, partition layout when safely obtainable, 3 boot logs and wall-clock elapsed time. Do not claim any one component is the dominant delay without measured checkpoints.

## Gate B1 — code-only minimal ESP32-S3 app, no device writes

- Pin ESP-IDF and Seeed BSP commit in a separate **isolated** workspace; preserve vendor original source. Initial build target `esp32s3`; prove `idf.py build` without flashing.
- Minimal startup: `esp_timer_get_time()` checkpoints, initialize only power-hold/I2C expander; initialize LCD to a single frame; enable knob/button; report measured `T_app_ui`. Never include SenseCraft/Taskflow or forced online activation.
- Important: IDF v5.2.1 is stated for the original factory example, while vendor `main` evolves; pin a compatible SDK/version for the chosen commit, not blindly latest HEAD.
- Define three separate ready signals: `LOCAL_READY`, `PERCEPTION_READY`, `NETWORK_READY`. UI and local state never wait for the latter two.
- Initial acceptance: build PASS, no upstream mutation, no new flash image written to hardware, no unexpected factory partition references.

## Gate B2 — backup and recovery verification before *any* flash

STOP until the user explicitly approves writing the ESP32-S3 application and the device's actual partition map has been verified. The source's `nvsfactory` backup command is a **reference only** until version/partition offsets are checked.

- Identify correct ESP32-S3 USB UART. Read/record firmware and partition metadata without erase.
- Backup the complete ESP32-S3 flash or the required partitions (especially `nvsfactory`), validate byte size and SHA-256 locally, and secure factory secrets. Never upload factory NVS to public GitHub/issues/chat.
- Obtain verified matching factory images and document a testable restore procedure; confirm Flash Encryption / Secure Boot / anti-rollback and OTA metadata state before choosing a new app image layout.
- If feasible, use a non-destructive app-only update that retains partition table, bootloader, factory data; full-chip erase is forbidden.
- If recovery cannot be assured, NO-GO on flashing. Build and static review may continue.

## Gate B3 — physical bring-up only after explicit authorization

Sequentially test: (a) power-hold + UART heartbeat, (b) LCD first frame and knob, (c) local decision core, (d) Himax SSCMA client command/event, (e) optional audio and network. For each, log boot stage and compare three cold starts against factory baseline. If a stage fails, recover through the verified app rollback path.

**Initial engineering targets (not promises/observed results):** first local display/knob response ≤2.0 s after `app_main`, and no network dependency to reach `LOCAL_READY`; report from power key press separately. Do not optimize ROM/PSRAM time without observed logs.

## Decision

The new architectural priority is a small pibbi-first Watcher firmware; the previous Watcher HTTP Push G1 path is optional historical integration, not required critical path. This is not a claim that custom firmware will definitely solve slow boot. Gate B0 provides causality evidence; B1 proves build feasibility; B2 prevents irreversible loss of factory data; B3 measures actual improvement.


## Windows gated builds — 2026-10-15

**B1a:** Windows ESP-IDF v5.2.1 BUILD_PASS, BIN 0x3B420 = 242,720 B; ELF SHA256 092976B9CFC152F5F47E747219E6A76D06BE7254CDD16920DE870AFA570E808D.

**B1b:** Windows ESP-IDF v5.2.1 BUILD_PASS_B1B, BIN 0x48BB0 = 297,904 B; ELF SHA256 12AEEAE96AEA53652DA76F2F12870495017E9B583A9B7C36328960678B096F55. The build had one harmless vendor_config const-qualification warning at lcd_first_frame.c:160; source fix committed d42c2593, but **corrected image has not yet been rebuilt**.

The generated images fit the build project's *source-selected* 12 MiB app partition, NOT verified device layout. Neither has been flashed; no physical boot/UI/latency measurements.

## Gate B2a — read-only actual device partition inspection

New read-only script: tools/watcher/read-partitions.ps1. It invokes Espressif esptool v4 read_flash for exactly 4096 B starting at 0x8000 (expected factory partition-table location) and converts binary to CSV with the activated ESP-IDF gen_esp32part.py. It never reads factory NVS, writes flash, erases flash or burns eFuses; **the ROM loader connection can reset the device**.

From ESP-IDF v5.2.1 PowerShell with the CONFIRMED ESP32-S3 USB data/programming port (not HX6538):

    cd D:\my-github\pibbi
    git pull --ff-only
    .\tools\watcher\read-partitions.ps1 -Port COMxx

Replace COMxx with actual ESP32-S3 serial COM name. If two ports exist and device identity is uncertain, identify the correct port before running the script. Successful output: READ_ONLY_PARTITION_PASS, actual partition metadata and binary SHA-256. Files saved under ignored private artifacts/pibbi/watcher-b2-readonly/<timestamp>. Share partition table and hash only; do NOT share unique MAC, EUI, factory NVS, credential backups, bootloader binaries, or private logs.

Documented Espressif commands: [read_flash](https://docs.espressif.com/projects/esptool/en/release-v4/esp32s3/esptool/basic-commands.html), [binary partition decoding](https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/api-guides/partition-tables.html).

A valid partition table is B2a evidence ONLY. B2b: check Secure Boot / Flash Encryption security status read-only, safeguard NVS and other unique factory data, verify available recovery binaries, restore viability and receive **separate explicit authorization** before ANY application flash. If reading/decode fails, STOP instead of trying erase, forced flash, or a guessed partition offset.
