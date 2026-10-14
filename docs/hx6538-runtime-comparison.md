# HX6538 Native vs SSCMA — baseline feasibility audit

Status: **source-level audit / no firmware flashing / no on-device benchmark**

## Scope and provenance

- Target: SenseCAP Watcher, HX6538 + OV5647.
- SDK: [Seeed `sscma-example-we2`](https://github.com/Seeed-Studio/sscma-example-we2), branch `1.0.x`, observed revision `3ac4e9f557f09fbe4e62806c2a19b5e8a23a9a70` (verify local HEAD before comparing).
- SDK's `SSCMA-Micro` submodule gitlink observed at `c7ed52af5da9fbac2ad1573c85b30d4ab4220b3f`.
- Existing `pibbi` build wrapper: `tools/hx6538/build.ps1` (default upstream makefile selects `tflm_face_embedding`).
- Reference: [Himax Grove Vision AI V2 examples](https://github.com/HimaxWiseEyePlus/Seeed_Grove_Vision_AI_Module_V2).

Do **not** infer that the reference Himax Grove firmware, the independent native example, and the factory Watcher SSCMA firmware are interchangeable.

## Readiness matrix

| Aspect | Native: `tflm_face_embedding` | SSCMA: `sscma` / `SENSECAP_WATCHER` |
|---|---|---|
| Source/build entry | `EPII_CM55M_APP_S/makefile` defaults to native app | `APP_TYPE=sscma TARGET=SENSECAP_WATCHER` is represented by `sscma.mk` |
| Platform scheduling | Bare-metal native application | FreeRTOS application using SSCMA-Micro abstractions |
| AI integration | Direct TFLite Micro / Ethos-U55 | SSCMA Engine, ModelFactory, AT Server, TFLM |
| Linker | `tflm_face_embedding.ld` | `sscma/linker/watcher.ld` |
| Source completeness | Existing successful local ELF build reported | **Blocked**: required source paths absent from the SDK-pinned SSCMA-Micro gitlink |
| Build evidence | ELF from prior local native build; validate manifest and hash before comparison | **No valid matched ELF** at this SDK revision |
| Watcher boot/runtime evidence | **Not verified** for custom native image | Only **factory 2024.08.16 SSCMA** verified via UART and camera; not evidence that this source builds or boots |

### Blocking evidence for SSCMA

The SDK source file
[`sscma/sscma.cpp`](https://github.com/Seeed-Studio/sscma-example-we2/blob/3ac4e9f557f09fbe4e62806c2a19b5e8a23a9a70/EPII_CM55M_APP_S/app/scenario_app/sscma/sscma.cpp)
includes `sscma/main_task.hpp`. That header is absent from the tree of the SDK-pinned
[`SSCMA-Micro` commit](https://github.com/Seeed-Studio/SSCMA-Micro/tree/c7ed52af5da9fbac2ad1573c85b30d4ab4220b3f).
The
[`sscma.mk`](https://github.com/Seeed-Studio/sscma-example-we2/blob/3ac4e9f557f09fbe4e62806c2a19b5e8a23a9a70/EPII_CM55M_APP_S/app/scenario_app/sscma/sscma.mk)
also references `porting/himax/we2` and older `core/algorithm` paths missing from that gitlink.
The absence is a **source dependency issue**, not a proven compiler issue. A clean SSCMA build at these exact revisions has **not** been demonstrated.

Do not replace the gitlink with current `SSCMA-Micro/main` and present the outcome as a same-revision comparison: the current upstream API differs and also does not expose the missing legacy WE2 platform directories.

## Linker inspection (static capacities, not actual occupancy)

- Native: CM55M ROM 256 KiB, APP_DATA 256 KiB; dynamic SRAM span is defined in the linker by `BOOT2NDLOADER_BASE` and `BASE_ADDR_SRAM0_ALIAS`, so check the actual expanded address rather than assuming 2 MiB are all available. Native linker reserves `0x1C000` (112 KiB) heap and `0x8000` (32 KiB) stack.
- SSCMA Watcher linker: ROM 256 KiB, APP_DATA 256 KiB, `CM55M_S_SRAM` 336 KiB, `CM55M_S_EL_ALLOC` 1112 KiB; linker reserves heap `0x4000` (16 KiB), stack `0x2000` (8 KiB). The comment calling `0x2000` "16 KB" is inconsistent with the hexadecimal constant. This is **not** total FreeRTOS stack/heap consumption.
- In `watcher.ld`, some library code is explicitly directed to APP_DATA. Section placement, not raw ELF file length, must be compared.

**A linker MEMORY region definition is a capacity, not a measured footprint.** Raw ELF byte length includes debug/symbol contents and is unsuitable as flash/RAM occupancy.

## Safe local preflight

From `D:\my-github\pibbi`:

```powershell
py .\tools\hx6538\audit-build-matrix.py
```

This reads the local SDK, its submodule gitlink, the source requirements, and the existing native build manifest, then writes `artifacts/hx6538/analysis/build-matrix-audit.json`. It **does not compile, generate firmware images, reset the Watcher, or write flash**.

For an independently verified native build with the existing wrapper:

```powershell
.\tools\hx6538\build.ps1
```

Do not try to force a SSCMA image build by swapping arbitrary submodule versions until the source dependency is resolved and the target-specific board port is reviewed.

## Proposed *actual* comparison after repairing SSCMA dependencies

Use the same checkout commit, Arm GNU Toolchain, optimization settings, clock, selected target package, and measurement conditions. Build configurations must have distinct artifact directories and hashes, with a clean rebuild between them; never overwrite the native `build-manifest.json` used by `image.ps1`.

Record separately:

1. **Source/build:** SDK SHA, submodule SHA, scenario, `TARGET`, flags, toolchain, ELF SHA, MAP SHA.
2. **Memory:** section VMA/LMA, ROM/TCM/SRAM usage, static vs dynamic heap, stack high-water mark; avoid comparing raw ELF sizes.
3. **M55:** disassembly evidence of MVE instructions; scalar/CMSIS-DSP/MVE cycles, data placement and cache state.
4. **NPU:** preprocess, `Invoke()`, postprocess, driver overhead, cache-maintenance costs, correctness.
5. **CDM/PMU:** selected camera datapath, CDM event validity, motion-detection precision/recall, power state, wakeup latency, measured power.
6. **End-to-end:** latency P50/P95, effective FPS, power and event accuracy under equivalent workloads.

Comparison status remains **BLOCKED** until the same-revision SSCMA dependency and target build are reproducible.

## Device safety

- Watcher factory HX6538 image `2024.08.16` and UART capture are the current functional baseline.
- Generated `output.img` is not equivalent to tested Watcher firmware; the secure-boot generator may produce differing signatures/certificates across runs.
- **No flashing** until the exact Watcher recovery route has been validated, and firmware hashes and boot/camera/host smoke tests are recorded.

## Decision

Use native Himax/WE2 SDK applications for HX6538 performance experiments and keep SSCMA as a **protocol/application reference**, not a required dependency in the hot path. Revisit a full SSCMA comparison only after restoring a complete, buildable, target-matched source tree.
