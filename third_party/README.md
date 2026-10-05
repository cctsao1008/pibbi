# Third-party dependencies

External source trees are checked out here by pibbi tooling and are not vendored into this repository.

Current dependency:

- `sscma-example-we2/` — Seeed/Himax HX6538 (WiseEye2) SDK/examples.

The checkout location, tracking branch, and eventual pinned commit are defined in `tools/setup/hx6538-tools.psd1`.

Do not make pibbi-owned feature changes directly inside third-party trees. If an upstream modification becomes unavoidable, document the reason and carry it as an explicit patch or fork decision rather than allowing an untracked local SDK mutation to become part of the build process.
