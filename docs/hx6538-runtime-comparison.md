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

## Update: a historically matched legacy SSCMA source pair was located

The source gap is caused by an **API-generation mismatch**, not evidence that the Watcher WE2 port is unpublished.

- `sscma-example-we2/1.0.x` at `3ac4e9f5...` retains an older SSCMA application: `sscma.cpp` includes `sscma/main_task.hpp`, and `sscma.mk` includes `porting/himax/we2` and `sscma/callback`.
- Its recorded SSCMA-Micro gitlink, `c7ed52af...`, comes from the **new** API generation (commit dated 2025-10-27), where the matching legacy paths are absent.
- `SSCMA-Micro/1.0.x` at `ff48a1c0...` (2025-01-02) **does** contain those legacy paths and a SenseCAP Watcher WE2 board port.
- More compelling: [`sscma-example-we2/b/1.0.x`](https://github.com/Seeed-Studio/sscma-example-we2/tree/b/1.0.x) at `37fed7a8e27b9d50f64b6784c3aff7bbf04cf70d` pins `SSCMA-Micro` at `c90065ddd2d763728b0aa24902af9337922b94fb`. Its `sscma.cpp` is the **exact same Git blob SHA** as `sscma-example-we2/1.0.x` (`894a84e490b6499fde89ad96ece9b9559bfce01b`). The legacy submodule contains the missing header, WE2 port, and callbacks.
- These are **source-level compatibility indicators only**. They do not prove the older pair builds, runs on Watcher, or produces behavior/performance equivalent to factory 2024.08.16 SSCMA.

### Isolated source-only checkout (safe, no flash)

Run in `D:\my-github\pibbi` from the pibbi research branch:

```powershell
git pull --ff-only
.\tools\hx6538\prepare-sscma-legacy.ps1
py .\tools\hx6538\audit-build-matrix.py `
  --sdk-root .\.tools\work\hx6538-sscma-legacy `
  --output .\artifacts\hx6538\analysis\legacy-sscma-audit.json
```

The helper validates the currently pinned SDK HEAD and clean working tree, fetches the historical Seeed branch, then creates a *separate detached Git worktree* under ignored `.tools/work/` with its matching historical SSCMA-Micro submodule. It fails closed if reviewed upstream branch or submodule commits do not match, does not build or flash anything, and never changes the original SDK source files.

Expected result is that the legacy **source dependency check** becomes READY. The native ELF remains independently verified in the current pinned SDK, not the historical worktree. An actual comparative benchmark must still be conducted at one controlled SDK revision.

**Do not** run `git -C third_party/sscma-example-we2 submodule checkout ...` against the original SDK, as that would change the provenance and violate the clean-tree invariant used by `build.ps1`.


### Windows result: source-only audit PASS

The user ran `prepare-sscma-legacy.ps1` and the `--sdk-root` audit on Windows:

- Isolated SDK worktree: `37fed7a8e27b9d50f64b6784c3aff7bbf04cf70d`
- SSCMA-Micro: `c90065ddd2d763728b0aa24902af9337922b94fb`
- **SSCMA source READY**, no firmware build or flash.
- Legacy worktree reports Native BLOCKED / ELF NOT_FOUND as expected: these are distinct SDK revisions. The separate current Native baseline remains ELF VERIFIED.

### Next gate: guarded SSCMA Watcher compile/link (ELF only)

The research branch includes `tools/hx6538/build-sscma-legacy.ps1`. From the project root:

```powershell
git pull --ff-only
.\tools\hx6538\build-sscma-legacy.ps1
```

The wrapper refuses to run unless the primary Native SDK, isolated SSCMA SDK and SSCMA-Micro checkout match their reviewed Git SHA values and are clean. It then runs clean/build in the isolated legacy SDK with explicit `TARGET=SENSECAP_WATCHER`, `APP_TYPE=sscma`, GNU toolchain, `OLEVEL=O2`, `MAP=1` and Watcher-target C/C++ defines.

**Outputs if successful** (in a new ignored run directory `artifacts/hx6538/build-sscma-legacy/<run-id>/`):

- `sscma-watcher.elf`, `sscma-watcher.elf.map`
- `sections-size.txt`, `sections-readelf.txt`
- `build.log`, `build-manifest.json` (SHA provenance)

This script **does not** generate or flash a signed image, or touch COM32. It is not a firmware compatibility or performance test. Compile failures are valuable evidence: retain the log, do not change SDK versions or libraries ad hoc. Newly added script is pending execution on the user's Windows machine.

### Important comparison qualification

Even if this older SSCMA firmware builds, it is paired to a **different SDK revision** from the verified Native ELF. An absolute code/RAM size comparison at this stage would confound different library, compiler option, workload and linker choices. It establishes build feasibility; a controlled same-revision benchmark would require a subsequent matched experiment.


## Verified Windows build: legacy SSCMA Watcher ELF + MAP PASS

User ran `tools/hx6538/build-sscma-legacy.ps1` successfully with the isolated historically paired sources (target `SENSECAP_WATCHER`). Output recorded by the user:

```text
CM55M_S_APP_ROM:   207416 B / 256 KiB (79.12%)
CM55M_S_APP_DATA:  198728 B / 256 KiB (75.81%)
CM55M_S_SRAM:      336 KiB / 336 KiB (100.00%)
CM55M_S_EL_ALLOC: 1112 KiB /1112 KiB (100.00%)

arm-none-eabi-size
text     data     bss      dec
376005   2676     1510191  1888872
```

Artefacts exist on the user's Windows computer at:
`artifacts/hx6538/build-sscma-legacy/20261014T212931104Z-ad823da6/`, including:
`sscma-watcher.elf`, `sscma-watcher.elf.map`, `sections-size.txt`,
`sections-readelf.txt`, `build.log`, `build-manifest.json`.

### Interpretation and limitations

- **Build/link PASS** confirms the legacy source pair is compilers/linker-compatible with the pinned Arm GNU environment and Watcher-target build definition. It does **not** establish a flash-safe image or running firmware.
- The `watcher.ld` linker places section `.elHeap` in `CM55M_S_EL_ALLOC` and `.ucHeap` in `CM55M_S_SRAM`. Both regions reporting **100%** is **statically reserved address space**, not proof that runtime allocations exhausted the respective pools. The former is 1112 KiB; the latter 336 KiB. The legacy WE2 `el_config_porting.h` configures `CONFIG_SSCMA_TENSOR_ARENA_SIZE (1110 * 1024)`; allocation details and `elHeap` symbol ownership must be verified from the generated MAP rather than inferred solely from the name. Legacy FreeRTOS NTZ config declares `configTOTAL_HEAP_SIZE (336 * 1024)`; confirm the effective selected OS build configuration and heap symbol in the MAP before asserting the live RTOS heap size.
- `watcher.ld` also routes `.text.ext` (selected library code) to `CM55M_S_APP_DATA`, **not just ROM**. Consequently, raw ELF `text=376005` must not be compared directly against the 256 KiB `CM55M_S_APP_ROM` capacity.
- ROM headroom by the linker report is **54728 B (53.45 KiB)**; APP_DATA headroom is **63416 B (61.93 KiB)**. These are *linker-region* margins, not a safe guarantee of extra runtime allocations.
- 336 KiB + 1112 KiB = **1482752 B** reserved in the two named SRAM regions, accounting for most of the aggregate `bss=1510191 B`; remaining BSS and section accounting must be read from the MAP.
- Native ELF passed hash verification under the **different** SDK revision `3ac4e9f5...`; legacy SSCMA ELF is under `37fed7a8...`. Treat this as *two independently buildable applications*, not controlled evidence that SSCMA uses more RAM or is slower.

### Next source/ELF-only diagnostics

Without flashing anything, inspect the locally generated `sections-size.txt` and MAP:

```powershell
$run = '.\artifacts\hx6538\build-sscma-legacy\20261014T212931104Z-ad823da6'
Select-String -Path "$run\sections-size.txt" -Pattern 'elHeap|ucHeap|text.ext|\.text|\.bss|\.data|rodata'
Select-String -Path "$run\sscma-watcher.elf.map" -Pattern '^\.(elHeap|ucHeap|text.ext|text|bss|data)\b' -Context 0,3
```

Use the MAP and `arm-none-eabi-nm --print-size --size-sort` (or readelf symbol table) to find the exact backing symbols and top static-memory consumers. Later, collect runtime heap free/min-ever-free and stack high-water data on a recovery-safe deployment; no inferences about runtime RAM from this link output.

### Status gates

| Gate | State |
|---|---|
| Current Native ELF build + manifest | **VERIFIED** |
| Historical SSCMA source pairing | **VERIFIED** |
| Historical Watcher SSCMA compile + link | **PASS (user Windows build)** |
| Matched-revision memory/perf comparison | **NOT DONE** |
| Watcher custom firmware boot / crash recovery | **NOT DONE** |
| HX6538 hardware MVE / NPU / CDM runtime benchmark | **NOT DONE** |
| Flashing | **NOT AUTHORIZED / NOT DONE** |

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
