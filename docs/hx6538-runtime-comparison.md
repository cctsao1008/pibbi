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

## 2026-10-15: SSCMA heap backing traced to historical source

The historically paired sources give stronger, **source-level** backing evidence, although the user's generated ELF/MAP is still local and has not yet been independently parsed here:

1. `sscma/linker/watcher.ld` places `.ucHeap` at `0x34000000` (336 KiB) and `.elHeap` at `0x34054000` (1112 KiB). In APP_DATA it also reserves `__HEAP_SIZE=0x4000` and `__STACK_SIZE=0x2000` using COPY output sections. Do not treat the linker reported APP_DATA remaining bytes as a directly allocatable runtime free-heap figure.
2. `os/freertos_10_5_1/NTZ/config/FreeRTOSConfig.h` declares `configTOTAL_HEAP_SIZE=(336*1024)`; FreeRTOS `heap_4.c` has a corresponding static `ucHeap[configTOTAL_HEAP_SIZE]`. Confirm selected build object/configuration and the final `.ucHeap` backing symbol from the generated MAP/ELF; the repository has more than one FreeRTOS configuration.
3. Historical SSCMA-Micro `porting/himax/we2/el_misc_we2.cpp` defines `static uint8_t elHeap[1112 * 1024]` in `el_aligned_malloc_once()`. This is a monotonically advancing allocator, not a general free-list heap.
4. `porting/himax/we2/el_config_porting.h` defines `CONFIG_SSCMA_TENSOR_ARENA_SIZE=(1110*1024)`. `sscma/callback/model.hpp` statically requests the arena once with 32-byte alignment, zeroes it on model change, and passes it to `EngineTFLite::init(pool, size)`. The 2 KiB pool-to-arena difference is nominal slack before alignment, **not** a measured runtime free-memory counter.
5. The reported `bss=1510191 B` versus `336 KiB + 1112 KiB=1482752 B` leaves 27439 B of size accounting outside those two nominal pools. Do not label this remainder SSCMA framework overhead without per-section and symbol proof.

### Read-only ELF/MAP analysis — next local evidence gate

From the research branch on Windows, in a PowerShell session (does **not** build or flash):

```powershell
git pull --ff-only
. .\tools\setup\activate-hx6538.ps1
py .\tools\hx6538\analyze-sscma-memory.py `
  --run-dir .\artifacts\hx6538\build-sscma-legacy\20261014T212931104Z-ad823da6
```

The audit *requires* the original `build-manifest.json`, `sscma-watcher.elf` and `sscma-watcher.elf.map`, validates both SHA-256 hashes and the reviewed legacy SDK SHA, and writes derivative files to `<run-dir>/memory-audit/`:

- `memory-report.md` and `memory-report.json`: ELF section VMA/LMA, SHF_ALLOC-like section flags, exact heap candidate symbols, MAP sections, linker heap/stack gap, top-size symbols.
- `objdump-sections.txt`, `nm-symbols.txt`, `readelf-program-headers.txt`: raw tool output for independent reproduction.

The script does not change source, compile, generate an image, access a serial port, or flash the Watcher. The parser has been exercised using a local synthetic ELF/MAP and simulated special-section layout; the actual Windows artifact remains **NOT YET ANALYZED**. Inspect the report, especially `.text.ext`, `.elHeap`, `.ucHeap`, `.heap`, `.stack`, `__HeapLimit`, `__StackLimit` and ELF VMA/LMA, before moving on to M55/MVE performance tests. For exact runtime heap/stack high water, a recovery-safe hardware execution gate is still required.

### Source-defined SRAM allocations outside ELF `.bss` (additional audit requirement)

Legacy SSCMA-Micro `porting/himax/we2/drivers/drv_shared_cfg.h` partitions additional SRAM with literal address macros; these ranges may never appear in the linker MAP as `SHF_ALLOC` sections.

| Source-defined range | Address interval (end-exclusive) | Size |
|---|---|---:|
| YUV422 frame, 640x480x2 | `0x3416A000–0x34200000` | 600 KiB |
| SRAM2 JPEG workspace | `0x36000000–0x36025A90` | 154256 B |
| alignment gap | `0x36025A90–0x36025AA0` | 16 B |
| JPEG fill | `0x36025AA0–0x36026AA0` | 4 KiB |
| SPI TX / RX | `0x36026AA0–0x36038AA0` | 64 KiB + 8 KiB |
| Serial1 TX / RX | `0x36038AA0–0x360432A0` | 36 KiB + 6 KiB |
| source-defined shared/free SRAM2 | `0x360432A0–0x36060000` | 118112 B (~115.34 KiB) |

The `el_config_porting.h` definitions `SSCMA_SHARED_BASE64_BUFFER_BASE` / `_SIZE` point to that residual SRAM2 region; it is **not** uncommitted general-purpose heap. The 2,048 KiB first SRAM partition (336 + 1112 + 600) and 384 KiB SRAM2 cover the 2432 KiB configurable system SRAM budget described in the HX6538 datasheet, separate from the Big M55 256 KiB ITCM and 256 KiB DTCM capabilities. Exact device-specific memory aliasing and boot-copy behavior remain to be validated.

### Dynamic RTOS stack allocations cannot be read from `bss`

Legacy app source `sscma.cpp` creates the initial FreeRTOS task with depth 20480; `sscma/main_task.hpp` creates the listener with depth 4096, then deletes the initial task. `sscma/definations.hpp`, `sscma/static_resource.hpp` and `sscma/repl/supervisor.hpp` configure/create an executor task with depth 20480 and supervisor depth 6144. The NTZ ARM M55 FreeRTOS port typedefs `StackType_t` to `uint32_t`, so stack **requests** are respectively 80, 16, 80 and 24 KiB. If all four are briefly allocated during the handoff, the stack requests total 200 KiB (plus TCB, fragmentation and other allocations); after the initial app task has actually been reclaimed, the three remaining requests total 120 KiB. This is a source-level budget, **not** evidence of actual boot execution or measured peak heap usage. The runtime allocation/reclamation timing has not been observed.

**Next gate remains unchanged:** run the verified ELF/MAP analyzer on the actual Windows build, reconcile linker sections with fixed-address source-defined buffers, and only then plan hardware-level M55/Helium/Ethos-U55 benchmarking. Do not merge or flash.

## 2026-10-15: Windows SSCMA ELF/MAP audit result (user-provided report)

Evidence: the user ran `tools/hx6538/analyze-sscma-memory.py` over run `20261014T212931104Z-ad823da6`; tool confirmed **ELF/MAP SHA-256 VERIFIED** against the preserved build manifest and produced `memory-report.md`. The memory report was inspected first; a subsequent audit also inspected the user's original `objdump-sections.txt` and `readelf-program-headers.txt`.

**Heap symbol attribution now verified at ELF level:**

| Symbol | VMA | ELF symbol size | Linker output |
|---|---|---:|---|
| `ucHeap` | `0x34000000` | 344064 B | `.ucHeap`, CM55M_S_SRAM |
| `el_aligned_malloc_once::elHeap` | `0x34054000` | 1138688 B | `.elHeap`, CM55M_S_EL_ALLOC |
| `set_model()::tensor_arena` | `0x3002D0F8` | 4 B | APP_DATA (`static` arena pointer; **not** a second arena) |
| `guard variable for set_model()::tensor_arena` | `0x3002D0F4` | 4 B | APP_DATA (static-initialization guard; **not** a pool) |

The 1482752 B `.ucHeap + .elHeap` static reservations plus the `27432 B` ordinary `.bss` match **1510184 B** of the previously reported `size` total `bss=1510191`; the remaining **7 B are now accounted for** as `.persistent` (3 B) and `.jcr` (4 B), both reported `ALLOC` without `CONTENTS` in `objdump -h`.

**APP_DATA section addresses from the verified user's report** (intervals end-exclusive):

| Item | Address interval | Bytes | Interpretation |
|---|---|---:|---|
| `.text.ext` | `0x30000000–0x30022F88` | 143240 | code routed to APP_DATA |
| `.rodata` | `0x30022F88–0x300292A9` | 25377 | constants |
| `.persistent` and `.jcr` | `0x300292A9–0x300292B0` | 3 + 4 | `ALLOC` sections with no `CONTENTS` (not generic padding) |
| `.data` | `0x300292B0–0x30029D08` | 2648 | initialized data |
| padding | `0x30029D08–0x30029D20` | 24 | alignment gap |
| `.bss` | `0x30029D20–0x30030848` | 27432 | ordinary static BSS |
| `.heap` COPY | `0x30030848–0x30034848` | 16384 | linker-reserved heap |
| unassigned interval | `0x30034848–0x3003DFE0` | 38808 | linker gap, **not proven allocatable** |
| `.stack` COPY | `0x3003DFE0–0x3003FFE0` | 8192 | linker-reserved stack |
| end guard / tail | `0x3003FFE0–0x30040000` | 32 | linker end tail |

`CM55M_S_APP_DATA` region capacity is 262144 B. Original GNU region report was **198728 B** (75.81%) and the analyzer's sum of ELF `ALLOC` sections is **198704 B**; their 24 B difference reflects that the two metrics use different accounting, and coincides with the `.data`→`.bss` 24 B alignment gap. **Neither of those numbers accounts as usable memory for the separate 16384 B `.heap` plus 8192 B `.stack` reservation.** Once reported `ALLOC` sections, those two COPY reservations and the 24 B accounting difference are counted, `223304 B` (85.18%) of APP_DATA is occupied or reserved and `38840 B` appears in unassigned address spans (38808 B contiguous plus 32 B tail). This is **a static address-map budget only**, not available C heap, a guaranteed safe relocation area, or measured free runtime heap.

The audit's `File-backed=True` column is derived from GNU objdump section **CONTENTS**, **not** from `SHF_ALLOC` / ELF `PT_LOAD`. In particular, COPY `.heap/.stack` are listed with `CONTENTS=True` while excluded from `ALLOC` sums; do not call them flash-image bytes without examining raw `readelf -W -S` and `readelf -W -l` and the signed-image generator's boot mapping. The report shows VMA=LMA for the listed sections, which **does not establish** runtime boot copies or signed-image size.

Other measured symbol examples: `edgelab::DeviceWE2::init()::spi` 4372 B at `0x3002F3E4`, `edgelab::porting::_buf_tx` 4095 B at `0x3002BCB0`, and `uxTimerTaskStack.0` 2048 B at `0x3002A128`. Code symbol `hx_drv_pmu_get_ctrl` is 4020 B at `0x30010EF8` (APP_DATA `.text.ext`); large code symbols are **not** RAM dynamic-allocation evidence. `tflite::OpsResolver::OpsResolver()` appears duplicated at the same address/size in the top symbol list and must not be double counted.

**Decision:** static heap ownership is established; no evidence of runtime OOM, heap high-water, stack peak, boot success, MVE cycles, NPU throughput or framework overhead. Next evidence gate should check original `objdump-sections.txt` + `readelf-program-headers.txt` and map the linker-controlled sections against fixed-address camera/JPEG/DMA buffers. Do not edit the independently verified Native baseline, merge the Draft PR or flash the Watcher.

## 2026-10-15: Follow-up ELF PT_LOAD / objdump inspection (user provided both raw reports)

The previous 7-byte BSS discrepancy is **fully resolved** using the actual section flags: `.persistent` 3 B and `.jcr` 4 B are both `ALLOC` but have no `CONTENTS` flag. They are **not** a 7-byte generic padding gap. Recomputed GNU `arm-none-eabi-size` groups:

| size group | Exact section membership | Bytes |
|---|---|---:|
| text | `.table` 1984 + `.text.ext` 143240 + `.text` 205396 + `.rodata` 25377 + `.ARM.exidx` 8 | 376005 |
| data | `.data` 2648 + `.copy.table` 16 + `.zero.table` 12 | 2676 |
| bss | `.elHeap` 1138688 + `.ucHeap` 344064 + `.bss` 27432 + `.persistent` 3 + `.jcr` 4 | 1510191 |
| total | | 1888872 |

`readelf -W -l` verifies ELF `EXEC`, entry `0x10001BC5`, one `EXIDX` header (not separately double-counted), and **four** `PT_LOAD` segments:

| PT_LOAD | VirtAddr = PhysAddr | FileSiz (B) | MemSiz (B) | Flags | Sections |
|---|---|---:|---:|---|---|
| #1 | `0x10000000` | 207416 | 207416 | RWE | `.table .noinit .text .ARM.exidx .copy.table .zero.table` |
| #2 | `0x30000000` | 171272 | 198728 | RWE | `.text.ext .rodata .persistent .data .bss .jcr` |
| #3 | `0x34000000` | 0 | 344064 | RW | `.ucHeap` |
| #4 | `0x34054000` | 0 | 1138688 | RW | `.elHeap` |

- `PT_LOAD FileSiz` sum is **378688 B**; `PT_LOAD MemSiz` sum is **1888896 B**; the memory-only difference is **1510208 B**. The 24 B difference between total MemSiz and the original GNU `size` total is APP_DATA alignment before `.bss`. The 7 B difference between FileSiz sum and GNU `text+data` is the intervening `.persistent + .jcr` address span, with `ALLOC` but no `CONTENTS`; *neither difference is a memory leak*.
- `.ucHeap` and `.elHeap` each have a `PT_LOAD` with `FileSiz=0`, meaning no preinitialized file payload for those large buffers. These are ELF memory-initialization requirements. Do **not** assert that the actual HX6538 loader performs standard ELF zero-fill without auditing the secure-image packaging and the real startup/loader paths.
- `.heap` and `.stack` have `CONTENTS` but **no** `ALLOC` flag; neither appears in Section-to-Segment mapping. They are linker `COPY` sections outside all `PT_LOAD`, notwithstanding their placement in the raw ELF file. Their nominal ranges remain reserved by `__HeapBase/Limit` and `__StackLimit/Top`.
- `PT_LOAD` flags include RWE for ROM and APP_DATA. These are **ELF program-header metadata**, not a verified MPU/TrustZone permission configuration.
- VMA=PAddr in all `PT_LOAD` headers; this alone does not establish the on-device flash offsets, signed image size, actual boot-copy actions or correctness of zero-init.
- The `watcher.ld` source-defined `.zero.table` only lists `.bss` and `.copy.table` only lists `.data`. The build selects `HX_TFM=ON`; the publicly visible `device/startup_WE2_ARMCM55.cc` Reset_Handler is conditional on `!HX_TFM`, so it cannot be assumed to be this ELF's effective reset/initialization sequence. The correct follow-up is *read-only* symbol/build provenance inspection for Reset_Handler, TF-M/2nd loader, and the secure image generator.

### Next evidence gate — startup/loader provenance, still no flash

Find the actual `Reset_Handler`, `__PROGRAM_START`, and startup object origin in the original ELF/MAP; trace whether the secure boot image generator serializes the VMA-defined buffers or instead packages only file-backed sections and leaves boot RAM initialized by hardware/firmware. Confirm cold/warm boot zero and retention ownership **before** reasoning about PMU/DVFS/retention. Do not use ELF FileSiz sum as the exact flash-image length or link PT_LOAD RWE flags to live security permissions.

The research branch also extends the read-only `analyze-sscma-memory.py` parser so a **future rerun** writes `PT_LOAD` section mapping into both `memory-report.json` and `memory-report.md`. The program-header parser was checked against the original submitted `readelf-program-headers.txt` fixture; re-execution on Windows remains pending.
