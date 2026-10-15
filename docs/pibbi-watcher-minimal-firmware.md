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

## Gate B2a real partition table — 2026-10-16 PASS

ESP32-S3 read-only serial dump: physical flash 0x8000..0x8FFF is a valid table. SHA256 535EA803C19353B47BACEA78DE4642692920CD925402233666FF9E7EB9189D73.

Actual layout: nvsfactory 0x9000/200KiB, nvs 0x3B000/840KiB, otadata 0x10D000/8KiB, phy_init 0x10F000/4KiB, ota_0 0x110000/12MiB, ota_1 0xD10000/12MiB, model 0x1910000/1MiB, storage 0x1A10000/6080KiB. All 8 rows match the B1b build project partition table. No unique chip identifiers or NVS payloads published.

Partition table match is not proof that replacing the active application is presently safe.

## Gate B2b — ROM security flags (READ-ONLY, pending)

The official ESP32-S3 ROM offers GET_SECURITY_INFO. The guarded PowerShell script tools/watcher/read-security.ps1 calls only esptool with --no-stub get_security_info and does not request eFuse burning, Flash writes, or factory NVS data. The serial downloader may reset Watcher.

Run from the ESP-IDF v5.2.1 PowerShell (confirmed ESP32-S3 COM31):

    cd D:\my-github\pibbi
    git pull --ff-only
    .\tools\watcher\read-security.ps1 -Port COM31

Redact device MAC/unique identifiers before sharing console output. Evaluate Secure Boot, Flash Encryption and secure-download restrictions; if fields are ambiguous, do not assume disabled. Continue separate active-OTA identification, private factory data backup and restore validation before any flash. No app-only write authorization has been given.

See [Espressif ROM serial protocol](https://docs.espressif.com/projects/esptool/en/release-v4/esp32s3/advanced-topics/serial-protocol.html) and [Flash Encryption restrictions](https://docs.espressif.com/projects/esp-idf/en/v5.2.1/esp32s3/security/flash-encryption.html).

## Gate B2b actual security result — 2026-10-16 PASS

User ran the ESP32-S3 ROM-only get_security_info command on COM31. Flags 0x00000000, Secure Boot **Disabled**, Flash Encryption **Disabled**, SPI_BOOT_CRYPT_CNT 0x0. The queried key-purpose names were not secret key bytes. This status removes the two common ESP32 image signing/encryption obstacles for this particular device at inspection time. No eFuse write, Flash write, or chip-unique identifier has been committed.

**B2b security result is NOT permission to flash.** Factory/OTA image contents, private factory identity, and rollback must still be safeguarded.

## Gate B2c — verified private full ESP32-S3 backup (READ-ONLY; pending on device)

Script: [tools/watcher/backup-esp32s3-readonly.ps1](../tools/watcher/backup-esp32s3-readonly.ps1) — safe only for the ESP32-S3 (does not access/backup Himax). It is a full **32 MiB** raw ESP32-S3 Flash read with SHA-256; it also rereads the 4 KiB partition table, 200 KiB factory NVS, and 8 KiB OTA metadata, comparing samples byte-for-byte against the full image. The known partition table hash is a device-layout guard (not unique device authentication). No erase/write commands.

Store the resulting files **outside the Git repository and any cloud-sync folders**, preferably on a BitLocker-encrypted local drive. These binary files contain actual factory credentials/EUI and potentially Wi-Fi/network secrets. Never attach them to Issues, ChatGPT or commit them.

Run after the current factory boot timing baseline has been recorded where possible, in the activated ESP-IDF v5.2.1 PowerShell:

    cd D:\my-github\pibbi
    git pull --ff-only
    .\tools\watcher\backup-esp32s3-readonly.ps1 -Port COM31 -OutputDir 'D:\pibbi-private-backups'

Change the output folder to a **private encrypted local drive** appropriate for your system. The script will create a unique timestamped subfolder and may take minutes; keep USB power/cable stable. It prints only file metadata/hash, but esptool may also report device identifiers in the console: redact before sharing. On success it prints READ_ONLY_BACKUP_PASS and INDEPENDENT_REGION_COMPARE_PASS plus full image SHA-256. If a checksum or read fails, STOP; do not try flash or erase.

**Success means backup integrity, not restore proven.** Before app-only flash: separately decode active OTA slot from the private backup; confirm original factory app/bootloader are recoverable, plan and test a rollback procedure without touching protected partitions, check readiness of minimal LCD probe's actual runtime constraints, and obtain an explicit user approval for hardware writes. No ESP32 backup can substitute for HX6538 firmware backup if we later modify Himax.

## Gate B2c result — physical backup PASS (2026-10-16)

The user's B2c read-only 32 MiB full ESP32-S3 Flash backup finished successfully. Size 33,554,432 bytes, SHA-256 `347E603A855C545541FE5FB56A1620229C4365BDD1D167B63AF00A8F945DF282`. The complete image was read in 852.7 s. Independently reread partition table (4096 B), nvsfactory (204,800 B) and otadata (8192 B), matching the same offsets byte-for-byte in the full image. Returned READ_ONLY_BACKUP_PASS and INDEPENDENT_REGION_COMPARE_PASS. These are **backup integrity evidence**, not proof of restoration or that HX6538 has been backed up.

Sensitive backup files stay ONLY in the user's private Windows folder. Do not upload NVS or full image to this repository, GitHub issues, chat or online virus scanners.

## Gate B2d — OFFLINE backup/OTA selection inspection

Read-only local script: [tools/watcher/inspect-backup-offline.py](../tools/watcher/inspect-backup-offline.py); tests in [tests/test_watcher_ota_offline.py](../tests/test_watcher_ota_offline.py). Python standard library only, no COM or network, no file writes. The program checks full-flash hash against the private manifest, physical partition SHA, and byte equality with separately read NVS/OTA files. It displays only OTA sequence/state/CRC validity and whether each app slot has a plausible ESP image header; private partition contents remain opaque.

Run from pibbi root in Windows PowerShell:

    cd D:\my-github\pibbi
    git pull --ff-only
    py -m unittest discover -s .\tests -p 'test_watcher_ota_offline.py' -v
    py .\tools\watcher\inspect-backup-offline.py --backup-dir 'D:\pibbi-private-backups\watcher-private-20261016-053954-115'

The output's inferred_boot_candidate is a **prediction from OTA metadata**, NOT a proven active/running partition. It follows ESP-IDF v5.2.1's `esp_ota_select_entry_t` 32-byte structure (two 4 KiB-separated records), CRC with `binascii.crc32(pack('<I', ota_seq), 0xffffffff)`, invalid/aborted states, and sequence-to-slot mapping `(ota_seq-1)%2`. Rollback, bootloader image validity and possible custom boot behavior can change the actual running image. ESP image header detection is only a quick plausibility check; a header is not enough to establish image validity.

Vendor references: [ESP-IDF v5.2.1 esp_flash_partitions.h](https://github.com/espressif/esp-idf/blob/v5.2.1/components/bootloader_support/include/esp_flash_partitions.h), [bootloader_common_loader.c](https://github.com/espressif/esp-idf/blob/v5.2.1/components/bootloader_support/src/bootloader_common_loader.c), [bootloader_utility.c](https://github.com/espressif/esp-idf/blob/v5.2.1/components/bootloader_support/src/bootloader_utility.c), [otatool.py](https://github.com/espressif/esp-idf/blob/v5.2.1/components/app_update/otatool.py).

Report the sanitized JSON only; never share the backup or manifest. B2 remains OPEN until an independent factory rollback route and first-write approval exist.

## Gate B2d physical-unit backup's offline inspection — PASS, 2026-10-16

User executed the B2d script on their private Windows backup. OFFLINE_BACKUP_INTEGRITY_PASS: full 32 MiB SHA `347E603A855C545541FE5FB56A1620229C4365BDD1D167B63AF00A8F945DF282`, partition SHA `535EA803C19353B47BACEA78DE4642692920CD925402233666FF9E7EB9189D73`, independent local copies MATCH.

OTA metadata: sector 0: seq=1, state VALID, CRC true, selectable; sector 1: erased/UNDEFINED/nonselectable. **Candidate ota_0**, offset 0x110000; `ota_0` has image magic E9, 6 segments. `ota_1` at 0xD10000 has **no plausible ESP image header**. This is NOT proof the entire ota_1 partition is erased. OTA candidate from backup is not conclusive proof of the running app. Image header alone does not verify the whole factory app image.

### Deployment design — not yet authorized

- Reserve ota_0 exclusively for the factory firmware and preserve nvsfactory, nvs, model, storage, bootloader, partition table, phy_init and factory otadata snapshot.
- Future pibbi image target should be ota_1 at physical 0xD10000 (12 MiB). First independently verify full factory image, confirm current running slot in boot logs, prove manual recovery to factory via serial downloader, and review OTA metadata update/rollback strategy. The current 32 MiB private backup is not itself a proven restoration.
- **Never run idf.py flash or idf.py app-flash using the current B1b build defaults**: the ESP-IDF generated commands use app target 0x110000 (ota_0) and full-flash commands additionally modify bootloader/partition table/OTA metadata. A direct app write to 0xD10000 alone would not automatically select ota_1 for boot.
- Do not write to any device until a separately explicit approval for specific protected scope, offset and fallback exists.

## Gate B2e — offline factory ota_0 full-image integrity, pending

Source: [tools/watcher/verify-ota0-image-offline.py](../tools/watcher/verify-ota0-image-offline.py); [six parser tests](../tests/test_watcher_image_info_offline.py). This validates B2c complete backup hashes first, then runs locally installed Espressif esptool v4 `image_info --version 2` against a **temporary private ota_0 slice**. It reports only ESP32-S3 chip ID match, segment count, checksum validity, optional appended SHA-256 validity and status; it does not output app version, image data, credentials or private file paths. Temporary file is removed on normal exit. The vendor command does not use serial port.

Run in ESP-IDF v5.2.1 PowerShell at repository root:

    git pull --ff-only
    py -m unittest discover -s .\tests -p 'test_watcher_image_info_offline.py' -v
    python .\tools\watcher\verify-ota0-image-offline.py --backup-dir 'D:\pibbi-private-backups\watcher-private-20261016-053954-115'

Expected success marker: IMAGE_CHECK_PASS with checksum_valid=true and appended_sha256 VALID, or NOT_APPENDED if a valid image explicitly states it has no appended SHA-256. Since the tool is new and not executed on the user's actual backup, no such result is claimed yet. If it returns IMAGE_CHECK_INCOMPLETE_OR_FAIL, STOP and do not flash; inspect failure locally. This is only static image integrity, not restored boot success.

Source: [esptool v4.12.0 image_info implementation](https://github.com/espressif/esptool/blob/v4.12.0/esptool/cmds.py) and [CLI image_info regression tests](https://github.com/espressif/esptool/blob/v4.12.0/test/test_image_info.py).

## B2e result — original ota_0 image integrity PASS (2026-10-16)

Actual user's offline `verify-ota0-image-offline.py` returned IMAGE_CHECK_PASS. esptool exit code 0; chip ID 9 verified ESP32-S3; 6 segments; image checksum valid; appended SHA-256 valid. This proves saved factory Application image bytes are internally valid. Not a live running-slot proof, boot validation, or restore test.

## B2f offline ota_1 occupancy gate (PENDING)

B2d reported that ota_1 lacks an ESP32 application header. That alone does not mean the whole OTA1 region is blank. The new offline-only [inspect-ota1-occupancy-offline.py](../tools/watcher/inspect-ota1-occupancy-offline.py) checks **every byte** in the backed-up 12 MiB ota_1 region 0xD10000..0x1910000; prints only number of non-FF bytes and their first/last offsets, never the content. It rechecks the private backup integrity first. Five synthetic regression tests in [test_watcher_ota1_occupancy_offline.py](../tests/test_watcher_ota1_occupancy_offline.py). User test run and occupancy output pending.

    cd D:\my-github\pibbi
    git pull --ff-only
    py -m unittest discover -s .\tests -p 'test_watcher_ota1_occupancy_offline.py' -v
    py .\tools\watcher\inspect-ota1-occupancy-offline.py --backup-dir 'D:\pibbi-private-backups\watcher-private-20261016-053954-115'

If fully_erased_all_ff is false, STOP and review before declaring ota_1 safe to overwrite. If true, it is evidence about the **snapshot**, not guarantee of current device state; deployment still needs boot log and explicit user write consent.

## B2g factory boot log confirmation (PENDING)

Only serial monitor is needed; no flashing. The user's confirmed ESP32-S3 programming UART is COM31, but serial logging may differ by firmware. With pyserial installed, try `py -m serial.tools.miniterm COM31 115200`, then use the normal factory power cycling or restart procedure. Serial tools may toggle RTS/DTR and reset the board when opening; ensure factory timing baseline is captured before disruptive steps. Exit with Ctrl+].

Capture an unmodified *local* full boot log for your own comparison; share only redacted lines that show bootloader OTA selection/app partition offset, errors, and early initialization timestamps. Do NOT upload Wi-Fi passwords, SSID, MAC, EUI, API tokens, private logs or raw NVS. If UART stays silent, verify correct debug port and baud before drawing conclusions. A bootloader line selecting ota_0 plus normal factory UI operation confirms original slot more strongly than metadata alone.

### Non-negotiable deployment gate

Do not use generic `idf.py flash`, `idf.py app-flash`, or copy the ESP-IDF printed `write_flash 0x110000` command: **that address is currently factory ota_0**. The only proposed pibbi target is ota_1 (0xD10000), but no write command or flash approval has been granted. Serial recovery and conservative OTA selection have not yet been demonstrated.
