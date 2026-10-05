# Third-party dependencies

External source trees are checked out here by pibbi tooling and are not vendored into this repository.

Current managed dependencies:

- `sscma-example-we2/` — Seeed/Himax HX6538 (WiseEye2) SDK/examples.
- `esp-idf/` — Espressif ESP-IDF pinned for the Watcher ESP32-S3 flow.
- `SenseCAP-Watcher-Firmware/` — upstream Seeed ESP32-S3 firmware/examples for SenseCAP Watcher.

The checkout locations and revision policies are defined in:

- `tools/setup/hx6538-tools.psd1`
- `tools/setup/esp32s3-tools.psd1`

Do not make pibbi-owned feature changes directly inside third-party trees. If an upstream modification becomes unavoidable, document the reason and carry it as an explicit patch or fork decision rather than allowing an untracked local SDK mutation to become part of the build process.
