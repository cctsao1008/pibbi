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
- The `watcher.ld` source-defined `.zero.table` only lists `.bss` and `.copy.table` only lists `.data`. The makefile setting `HX_TFM=ON` should not be conflated with the C preprocessor symbol: the subsequently inspected final MAP resolves `Reset_Handler` to `device/startup_WE2_ARMCM55.o`, matching this source-level startup implementation. Disassembly remains necessary to confirm the compiled instructions. The correct follow-up is *read-only* symbol/build provenance inspection for Reset_Handler, TF-M/2nd loader, and the secure image generator.

### Next evidence gate — startup/loader provenance, still no flash

Find the actual `Reset_Handler`, `__PROGRAM_START`, and startup object origin in the original ELF/MAP; trace whether the secure boot image generator serializes the VMA-defined buffers or instead packages only file-backed sections and leaves boot RAM initialized by hardware/firmware. Confirm cold/warm boot zero and retention ownership **before** reasoning about PMU/DVFS/retention. Do not use ELF FileSiz sum as the exact flash-image length or link PT_LOAD RWE flags to live security permissions.

The research branch also extends the read-only `analyze-sscma-memory.py` parser so a **future rerun** writes `PT_LOAD` section mapping into both `memory-report.json` and `memory-report.md`. The program-header parser was checked against the original submitted `readelf-program-headers.txt` fixture; re-execution on Windows remains pending.

## 2026-10-15: Real ELF startup symbols and copy/zero table decoding

Evidence from the user's **read-only** `arm-none-eabi-nm -an`, MAP `Select-String` and `arm-none-eabi-objdump -s -j .copy.table -j .zero.table` output from preserved run `20261014T212931104Z-ad823da6`.

### Actual linked startup objects

| Symbol | Address | Provenance |
|---|---|---|
| ELF `e_entry` | `0x10001BC5` | Thumb entry, maps to `Reset_Handler` bit-0 tagged address |
| `Reset_Handler` | `0x10001BC4` | `device/startup_WE2_ARMCM55.o`, `.text.Reset_Handler`, size `0x1A0` |
| `_start` / `_mainCRTStartup` | `0x100013C0` | Arm GNU `thumb/v8-m.main+dp/hard/crt0.o` |
| `__copy_table_start__` | `0x10032A20` | after four alignment bytes in `.copy.table` |
| `__copy_table_end__` | `0x10032A2C` | start of next linker output section |
| `__zero_table_start__` | `0x10032A30` | after four alignment bytes in `.zero.table` |
| `__zero_table_end__` | `0x10032A38` | end of linker zero table |

The MAP includes the startup object with `Reset_Handler` in the actual linked image (also `.vectors` at `0x10000000`). The earlier concern that the upstream source was guarded by `#if !defined(HX_TFM)` must be qualified: **`HX_TFM=ON` is a make variable, not direct proof that the `HX_TFM` preprocessor macro is defined for this object**. Since the Reset_Handler symbol and its source object are present, that guarded source path was linked. Confirm the *actual compiled branches* with disassembly, not the make setting alone.

### Literal table bytes (little-endian, words)

```text
.copy.table @ 0x10032A1C:
  00000000  0x300292B0  0x300292B0  0x00000296

.zero.table @ 0x10032A2C:
  00000000  0x30029D20  0x00001ACA
```

The initial 4-byte zero word in each section is **alignment padding outside the actual table symbol range**, not a table record. `0x296 * 4 = 2648 B` and `0x1ACA * 4 = 27432 B`:

| Table | Effective record | Size | Section covered |
|---|---|---:|---|
| copy | source `0x300292B0` → destination `0x300292B0`, 662 32-bit words | 2648 B | `.data` |
| zero | destination `0x30029D20`, 6858 32-bit words | 27432 B | ordinary `.bss` |

Source and destination in the copy record are identical, consistent with ELF LMA=VMA; **this does not determine the packaging or RAM load mechanism of the signed boot image**. Neither `.ucHeap` nor `.elHeap` is in the zero table. Their `PT_LOAD` headers have `p_filesz=0`, `p_memsz > 0`, but this alone does not prove the actual ROM/secondary loader zeroes both memory pools.

### CMSIS code path identified; final disassembly still required

At the historical SDK SHA, `EPII_CM55M_APP_S/CMSIS/cmsis_gcc.h` defines `__PROGRAM_START` as `__cmsis_start`. That inline function iterates `__copy_table_start__ .. __copy_table_end__` using 32-bit source/destination/word-count triplets, then iterates `__zero_table_start__ .. __zero_table_end__` using 32-bit destination/word-count pairs, finally calling `_start()`. `device/startup_WE2_ARMCM55.cc` calls `SystemInit()`, manages caches, then `__PROGRAM_START()`. `app/main.c` selects `board_init(); app_main();` for `SSCMA`.

**Evidence-level conclusion:** source implementation, linked symbol provenance, table contents and lengths all agree; no proof yet that the final instruction stream actually follows this exact loop path, that a signed image boots, or that early ROM/2nd loader zeroes the separate big heap pools. Existing `heap_4.c` initializes heap free-list metadata on first malloc; SSCMA's `set_model()` explicitly clears its tensor arena before use. Neither fact by itself establishes an all-zero state of the entire 1112 KiB pool at cold/warm boot.

### Next read-only step: disassemble only the relevant linked entry paths

```powershell
$run = ".\\artifacts\\hx6538\\build-sscma-legacy\\20261014T212931104Z-ad823da6"
$elf = "$run\\sscma-watcher.elf"
arm-none-eabi-objdump -d -C --disassemble=Reset_Handler $elf
arm-none-eabi-objdump -d -C --disassemble=_start $elf
```

Confirm table loops, branch to `_start`, what C Runtime initializes, and whether either entry path touches the two fixed SRAM pools. No source changes or target access. Keep Native and original Watcher firmware untouched.

## 2026-10-15: Instruction-level startup verification (user-provided ELF disassemblies)

Artifacts: `reset-handler-disasm.txt` (actual instructions) and `crt-start-disasm.txt` (header-only, no instruction listing), produced read-only from the verified historical SSCMA ELF `20261014T212931104Z-ad823da6`.

### Final linked `Reset_Handler` instruction path — VERIFIED in ELF

| Address or range | Observed instructions | Proven meaning |
|---|---|---|
| `0x10001BC4–0x10001BD2` | `msr MSP`, `msr MSPLIM`, `bl 0x1000181C <SystemInit>` | stack registers and system-init call |
| `0x10001BD6–0x10001CCC` | register accesses based at `0xE000ED00`, `dsb/isb`, `dls/le` loops | Cortex-M55 cache maintenance; DLS/LE are low-overhead-loop instructions **not proof of SIMD MVE acceleration** |
| `0x10001CD0–0x10001D02` | table bounds + `ldr.w`/`str.w` copy loop | CMSIS copy-table processing **is compiled into the executable** |
| `0x10001D04–0x10001D42` | `movs r4, #0`, table loop, `str.w r4` | CMSIS zero-table processing **is compiled into the executable** |
| `0x10001D44` | `bl 0x100013C0 <_mainCRTStartup>` | direct call into GCC crt0 entry |

Embedded literal values at `0x10001D54/58/5C/60` are exactly `0x10032A20`, `0x10032A2C`, `0x10032A30`, `0x10032A38`, corresponding to the actual linked copy/zero start/end symbols. With the previously decoded table contents, this executable's CMSIS code operates on the same `.data` 2648 B (source = destination, hence copies bytes onto themselves) and ordinary `.bss` 27432 B ranges.

**Strict evidence statement:** final instructions and control-flow **path exist**; no boot of a custom image has been performed, so this does not prove startup executed on actual Watcher hardware. Neither table references the separate `.ucHeap` 344064 B or `.elHeap` 1138688 B pools. Their reset-time zeroing/reliance on earlier loader initialization remains **OPEN**. FreeRTOS heap metadata initialization and the SSCMA model callback's arena clear are separate mechanisms.

### Why `crt-start-disasm.txt` was empty

`arm-none-eabi-objdump -d -C --disassemble=_start` emitted just section headers, so **it did not inspect crt0 instructions**. The MAP resolves `_start` and `_mainCRTStartup` at the same entry address `0x100013C0`; GNU objdump displays `_mainCRTStartup` at the Reset_Handler callsite. A symbol-name filter can miss an address shared by multiple aliases; an empty disassembly is **not** proof of absent code, corrupted CRT, or no BSS initialization.

Next host-only targeted disassembly (address range, not symbol filter):

```powershell
$run = '.\\artifacts\\hx6538\\build-sscma-legacy\\20261014T212931104Z-ad823da6'
$elf = "$run\\sscma-watcher.elf"
arm-none-eabi-objdump -d -C --start-address=0x100013b8 --stop-address=0x10001434 $elf |
  Out-File "$run\\crt0-address-disasm.txt"
```

Then inspect `_mainCRTStartup` and the transition to `main` / `__libc_init_array`. Keep the linker/ELF evidence gate **COMPLETE** but physical boot/secure-loader zeroing, cold/warm reset behavior, runtime heap high-water, M55/MVE performance and NPU performance **NOT VERIFIED**.

No new firmware build, signed image, device I/O or flash is required for this step.

## 2026-10-15: GCC crt0 disassembly closes the application startup instruction gate

Evidence: user-provided `crt0-address-disasm.txt` from the **same manifest-verified** legacy SSCMA ELF. Address-ranged disassembly recovered the alias-shared `_mainCRTStartup` entry that a prior `--disassemble=_start` symbol filter missed. No new build/image/flash/device I/O.

| Instruction(s) | Effective behavior | Evidence level |
|---|---|---|
| `0x100013C0–0x100013CA` | set `sp` from literal `0x3003FFE0`, call `_stack_init` | linked machine code |
| `0x100013CE–0x100013DA` | `r1=0`, `r0=0x30029D20`, `r2=0x30030848-0x30029D20=27432`; call `memset` at `0x100317E4` | linked machine code |
| `0x100013DE–0x100013EC` | check and conditionally invoke two hook function pointers | linked machine code; hooks need no further analysis for memory audit |
| `0x10001402` | call `__libc_init_array` at `0x100303C4` | linked machine code |
| `0x1000140A` | call `main` at `0x1001F328` | linked machine code |
| `0x1000140E` | call `exit` at `0x1002FB48` if `main` returns | linked machine code |

### Repeated clearing of ordinary .bss: VERIFIED STATICALLY

The compiled `Reset_Handler` first iterates `.zero.table`, targeting `0x30029D20–0x30030848` (27432 B). `_mainCRTStartup` **then calls `memset` over that same 27432 B range again**. Thus the normal linked control path performs two BSS zero passes. This establishes **redundant initialization work of one extra 27432-byte clear** at the instruction level; it does **not** establish runtime cycles, measurable startup latency, flash/boot correctness, or a defect requiring immediate patching. We are not changing vendor startup or modifying any baseline firmware.

The CRT disassembly also confirms no direct memset of `.ucHeap` at `0x34000000` (344064 B) or `.elHeap` at `0x34054000` (1138688 B) in its displayed entry path. Their hardware/earlier-loader initialization is still unresolved. `heap_4.c` sets allocator bookkeeping at first allocation; `sscma::callback::set_model` zeroes the requested 1110 KiB tensor arena before model use. Neither proves that the whole pool is zero immediately after reset.

### Gate closure and research direction

- **DONE (ELF static):** linker section layout; ELF PT_LOAD VMA/PAddr; `copy.table` and `zero.table` record values; startup object provenance; disassembled CMSIS loops; disassembled GNU crt0 path; repeated BSS zero accounting.
- **OPEN (requires loader source or validated HW):** how signed-image boot stages establish APP_DATA VMA contents; initial state of excluded SRAM pools; reset/retention behavior; actual execution/performance of the custom ELF. Do not claim device behavior from static disassembly.
- **NEXT: Native M55/Helium ISA *static feasibility* audit**, using the independently verified Native ELF without rebuilding or flashing. Record ELF/SDK/toolchain SHA, `readelf -A` attributes, link flags and representative disassembly. Distinguish compiler target configuration and low-overhead-loop `DLS/LE` from genuine MVE SIMD usage (e.g. vector predicate and lane operations). Prepare matched workload and measurement gates afterwards. Do not compare this unmatched historical SSCMA runtime against Native as a framework performance delta.

The startup audit is **CLOSED AT STATIC ELF LEVEL**; hardware/boot/retention validation remains explicitly open.

## 2026-10-15: Native Cortex-M55 / Helium (MVE) and Ethos-U55 ELF static audit

**Artifacts inspected (user-supplied, host-only):**
- Native `readelf -A` output `elf-attributes.txt`
- Native `arm-none-eabi-objdump -d -C` output `native-disassembly.txt` (57,512 lines, full text inspected)
- Native `arm-none-eabi-nm -C --defined-only` output `native-symbols.txt`
- Native build manifest was checked for ELF SHA-256 equality by the user's PowerShell script before those reports were produced. The reports themselves were not independently SHA-bound to the ELF, so **do not claim a separately verified hash of the disassembly text**.

**ISA attributes from `readelf -A`:** `Tag_CPU_name="cortex-m55"`, `Tag_CPU_arch=v8.1-M.mainline`, `Tag_FP_arch=FPv5/FP-D16 for ARMv8`, `Tag_ABI_VFP_args=VFP registers`, `Tag_DSP_extension=Allowed`, `Tag_MVE_arch=MVE Integer and FP`. ELF ISA attributes establish configured ISA support, **not** an executed SIMD workload or real hardware support validation.

### Compiled Q-register MVE instructions: POSITIVE

A line-by-line strict scan of the complete provided `objdump -d -C` output parsed 51,545 instruction lines and found **122 instructions with explicit `q0`–`q7` operands**, across **15 symbol-labelled functions**. This is a **lower bound for visible Q-register instructions, not a full MVE ISA count**. 94 of these appear inside `FastImageResize_BGR8U3C_to_RGB24_helium` (`0x1001A4C8`). Confirmed examples:

| Address | Disassembled instruction | Meaning |
|---|---|---|
| `0x1001A518` | `vdup.32 q2, r5` | broadcast scalar into vector |
| `0x1001A51C` | `vadd.i32 q2, q2, q6` | integer SIMD addition |
| `0x1001A524` | `vcvt.f32.u32 q2, q2` | vector integer-to-float conversion |
| `0x1001A642` | `vmul.f32 q3, q3, q4` | vector floating-point multiplication |
| `0x1001A64A` | `vadd.f32 q3, q3, q1` | vector floating-point addition |

Other Q-register functions include `scrfd_get_best_face` (3 Q-register operations) and several peripheral/driver functions. `dls`/`le` are Low Overhead Loop ISA and must **not** be confused with a vectorized SIMD loop or throughput.

**Disassembly caveat:** some instruction words inside the Helium resize routine are printed by this GNU objdump as coprocessor instructions (`ldc`, `stc`, `cdp`). Their exact opcode identities and any vector memory/predicate operations should **not** be inferred from the text without a separately verified MVE-aware decode of the original ELF. Absence of textual `vldrw/vstrw/vctp/vpst` is not proof those encodings are absent.

**Application call chain shown by actual BL instructions:**

```text
cv_face_embedding_run @ 0x100010B8
  BL @ 0x10001190 -> hx_lib_image_resize_BGR8U3C_to_RGB24_helium @ 0x1001AA60
  BL @ 0x1000122A -> tflite::MicroInterpreter::Invoke @ 0x10020428
  BL @ 0x1000169E -> tflite::MicroInterpreter::Invoke @ 0x10020428

hx_lib_image_resize_BGR8U3C_to_RGB24_helium
  BL @ 0x1001AA88 -> calloc @ 0x1002357C
  BL @ 0x1001AAA6 -> FastImageResize_BGR8U3C_to_RGB24_helium @ 0x1001A4C8
  B.W @ 0x1001AAB6 -> free @ 0x100235C0
```

Thus the built Native face-embedding path can reach the vectorized resize kernel; its wrapper includes **per-invocation calloc/free operations**. This is a concrete performance/memory-fragmentation candidate, **not** evidence of a slowdown, memory leak or allocation failure on hardware. The helper appears to allocate a temporary buffer based on an argument; do not claim measured capacity, lifetime in cycles or whether the kernel fully vectorizes pixel loads/stores from current evidence.

### Linked Ethos-U55 / TFLM route: POSITIVE at program-code level

The native symbol table and disassembly identify:

| Address | Function | Observed link/branch |
|---|---|---|
| `0x10005362` | `cv_face_embedding_init` | `BL 0x1001E2AC <ethosu_init>` |
| `0x100057DC` | `cv_face_embedding_init` | `BL 0x100211F0 <tflite::Register_ETHOSU()>` |
| `0x10005832` | `cv_face_embedding_init` | `BL 0x10020D48 <tflite::Register_L2_NORMALIZATION()>` |
| `0x1000122A,0x1000169E` | `cv_face_embedding_run` | two `BL` sites to `MicroInterpreter::Invoke` |
| `0x100211B8` | `tflite::(anonymous namespace)::Eval` | `BL 0x1001E830 <ethosu_invoke_v3>` |
| `0x1001E842` | `ethosu_invoke_v3` | `BL 0x1001E588 <ethosu_invoke_async>` |
| `0x1001E714` | `ethosu_invoke_async` | `BL 0x1001E93C <ethosu_dev_run_command_stream>` |
| `0x1001E96C ... 0x1001E9A4` | `ethosu_dev_run_command_stream` | MMIO command stream register writes (source-level driver path present) |

The `Register_ETHOSU()` literal at `0x10021228` contains `0x10021045`, the Thumb-tagged pointer to `tflite::(anonymous namespace)::Eval` at `0x10021044`, matching the registration function-pointers passed to `tflite::micro::RegisterOp`. The intermediate `MicroInterpreterGraph::InvokeSubgraph` invokes registered operators through **indirect calls**, so this is a linked and registered potential NPU invocation path, **not** proof of actual model dispatch, command stream execution or NPU throughput on a device.

This confirms that TFLM, its Ethos-U custom-op registration and the Ethos-U driver are present in the Native ELF. It does **not** establish that a model is successfully loaded, an NPU inference completes, or that the separate SSCMA revision is slower/faster.

### Engineering observations / next gate

1. **Compiler/ISA capability:** ELF attribute confirms MVE Integer+FP allowed.
2. **Compiled implementation:** explicit Q-register vector arithmetic present; Native resize BL chain reaches that function in the linked code.
3. **NPU path:** `ethosu_init` call, Ethos-U TFLM registration, operator eval, and command-stream writer exist; actual operator invocation and hardware success remain unmeasured.
4. **Potential costs to investigate when safe:** `calloc/free` each resize invocation; DMA/cache behavior; unknown number/effectiveness of vectorized load/store instructions; pixel preprocess scalar loops; RTOS scheduling not applicable to this Native bare-metal comparison without matched workloads.
5. **No performance claim**: zero measured cycles, latency, speedup, energy, occupancy, cache misses or RTOS overhead. SDK versions and workloads differ; do not compare Native and SSCMA binaries numerically.

**Next static evidence:** use a MVE-aware disassembler on the manifest-pinned original Native ELF and manually audit `FastImageResize` over `0x1001A4C8–0x1001AA60` (especially `ldc/stc/cdp` renderings). Separately review the Native image-processing call flow, allocation strategy and framebuffer memory placement. Only after recovery/flash safety is established should optional matched runtime benchmarks be designed. Keep Native vendor source and Watcher factory firmware untouched.

## 2026-10-15: Native MVE memory-access audit — GNU/LLVM cross-decoding

Tracking: [Issue #3](https://github.com/cctsao1008/pibbi/issues/3). This is **a direct research-branch commit, not a PR**.

### Primary evidence and decoding procedure

- Original Native SDK: Seeed \`sscma-example-we2/1.0.x\` at \`3ac4e9f557f09fbe4e62806c2a19b5e8a23a9a70\`; Native build manifest verified by the user prior to dumping \`native-disassembly.txt\`.
- Scope: \`FastImageResize_BGR8U3C_to_RGB24_helium\`, \`0x1001A4C8–0x1001AA60\` (**1432 B**, end exclusive). Parsed GNU disassembly contains **417** recognizable instruction-form lines.
- GNU objdump for the Arm GNU 13.2 toolchain renders **74** MVE encodings as \`ldc/ldc2/stc/cdp\`. The exact 16-bit opcode halfwords were recovered from the original GNU objdump text and separately assembled for **Clang/LLVM 17.0.0** (\`-target thumbv8.1m.main-none-eabi -march=armv8.1-m.main+mve.fp -mfloat-abi=hard\`, \`llvm-objdump -d --mattr=+mve,+mve.fp\`) decoding; all **74/74** mapped to valid MVE instructions. This is cross-decoding of supplied instruction halfwords, not an independent dump of original ELF bytes; preserve the original artifact provenance.
- GNU output already had **94** instructions with explicit \`q0–q7\` operands. Adding the 74 distinct cross-decoded sites yields **at least 168 MVE instruction sites** in this one kernel. They are static instruction sites, **not instructions executed per invocation**. \`dls/le\` low-overhead loop instructions are not counted as SIMD.
- The missing 74 instructions comprise: \`vldrb.u32\` 11, \`vstrb.32\` 6, \`vldrw.u32\` 14, \`vstrw.32\` 11, \`vadd.f32\` 14, \`vadd.i32\` 8, \`vmul.f32\` 7, \`vmov\` 2, \`vidup.u32\` 1. Exactly **42** of these are vector memory instructions (17 byte pixel-path accesses and 25 word stack spills/reloads).

Representative opcode cross-decoding evidence:

| Address | Original halfwords | GNU objdump | LLVM MVE-aware decode | Interpretation |
|---|---|---|---|---|
| \`0x1001A4EA\` | \`ec10 ef02\` | \`ldc\` | \`vmov q7[2], q7[0], r2, r0\` | vector lane setup |
| \`0x1001A514\` | \`ee23 cf6e\` | \`cdp\` | \`vidup.u32 q6, r2, #0x1\` | vector index generation |
| \`0x1001A532\` | \`ed8d 5f14\` | \`stc\` | \`vstrw.32 q2, [sp, #80]\` | vector spill |
| \`0x1001A632\` | \`fc94 6f02\` | \`ldc2\` | \`vldrb.u32 q3, [r4, q1]\` | indexed, zero-extended byte gather |
| \`0x1001A636\` | \`fc94 2f00\` | \`ldc2\` | \`vldrb.u32 q1, [r4, q0]\` | indexed byte gather |
| \`0x1001A65A\` | \`ec86 6f0e\` | \`stc\` | \`vstrb.32 q3, [r6, q7]\` | indexed byte scatter |
| \`0x1001A6EC\` | \`fc94 6f08\` | \`ldc2\` | \`vldrb.u32 q3, [r4, q4]\` | indexed byte gather |
| \`0x1001A7D8\` | \`ed9d 5f00\` | \`ldc\` | \`vldrw.u32 q2, [sp]\` | vector reload |
| \`0x1001A810\` | \`ed86 4f00\` | \`stc\` | \`vstrb.32 q2, [r6]\` | contiguous byte store |
| \`0x1001A9A0\` | \`ed87 6f00\` | \`stc\` | \`vstrb.32 q3, [r7]\` | contiguous byte store |

**Conclusion:** the Native resize kernel's preprocessing data path is genuinely vectorized for *both* arithmetic **and** pixel memory operations. These are 4-lane, 32-bit vector register accesses for 8-bit RGB/BGR pixel data, including indexed gathers/scatters. It is inaccurate to call the kernel scalar-memory-only. Conversely, gather/scatter and stack spills are possible costs that must be **measured**; no cache/bus/performance bottleneck has been demonstrated.

### Loop tails and API contract

Four \`dls/le\` low-overhead loop pairs occur at:
\`0x1001A60E/0x1001A660\`,
\`0x1001A6DC/0x1001A708\`,
\`0x1001A798/0x1001A816\`,
\`0x1001A916/0x1001A9A6\`.

No \`vctp*\` or \`vpst\` predicate instruction was seen among the audited kernel's existing decoded instructions. Several loop-count sequences use \`(width-1)>>2 + 1\`, i.e. ceil(width/4) lanes; do not claim generic safe unpredicated tails without enforcing the API's preconditions.

Crucially, the Native SDK's **pinned** \`EPII_CM55M_APP_S/library/img_proc/img_proc_helium.h\` explicitly states: **output resize width must be a multiple of four**. The same pinned \`tflm_face_embedding/common_config.h\` sets \`FD_INPUT_TENSOR_WIDTH=160\` and \`FD_INPUT_TENSOR_HEIGHT=160\`; \`cvapp_face_embedding.cpp\` passes \`new_w=160\` and \`new_h=160\` to \`hx_lib_image_resize_BGR8U3C_to_RGB24_helium\`. Therefore **this build's actual documented call site satisfies the width contract**. Missing tail predication does **not** establish an out-of-bounds defect in the currently observed application.

### Per-invocation scratch allocation (source ABI + ELF corroboration)

The wrapper at \`0x1001AA60\` loads stack arguments \`[sp,#56]\` and \`[sp,#60]\` into \`r9\` / \`r4\` after saving 56 B. Under Arm hard-float AAPCS and the pinned function declaration these are \`channels\` and \`output_w\`. It executes \`lsl.w r0, r4, #1\`, \`movs r1, #1\`, then \`bl calloc\` at \`0x1001AA88\`, calls the kernel at \`0x1001AAA6\`, and tail-branches to \`free\` at \`0x1001AAB6\`. This is **calloc(2 * output_w, 1)** plus \`free\` **per resize call**. The present \`160\`-pixel width therefore requests a **320-byte temporary buffer** each invocation; this is **not** a 160×160 image-sized temporary allocation.

Its initialization/allocator latency, success status and system-level fragmentation impact have **not** been measured. The shown wrapper does not test the \`calloc\` return before passing it to the kernel, but do not infer an observed allocation failure. The main Native application separately reserves model arenas and fixed buffers via \`mm_reserve_align\`; this temporary allocation belongs to the ordinary C heap.

### Closure and next experiment

- **Verified static:** MVE Integer+FP capability; 168+ vectorized opcode sites in specific kernel; vectorized gather/scatter and stack vector load/store; documented output-width restriction; current 160-width call satisfies contract; 320 B \`calloc/free\` per resize; linked TFLM/Ethos-U driver path.
- **Still unverified:** boot execution, image-output correctness, pointer memory safety outside documented API contract, cache/bus stall cycles, real vector speedup, allocation latency, total preprocessing vs NPU elapsed time.
- **Next:** choose *instrumentation boundaries* for resize, quantization/copy, face-detection Invoke, postprocessing, face alignment, embedding Invoke. Create a no-flash benchmark design referencing stable Native symbols, buffer lifetimes and cache-maintenance boundaries. Do not compare unrelated SSCMA SDK revision to Native for framework overhead.

**Project policy:** continue with direct commits to the isolated research branch and [Issue #3](https://github.com/cctsao1008/pibbi/issues/3). Keep PR #2 closed; do not open another PR, merge, generate signed flash images, or modify the factory firmware/Native SDK.


### Reproducible read-only MVE instruction audit tool

Committed `tools/hx6538/audit-native-mve.py` on the **research branch** (Python 3.8+). The tool reads the original GNU objdump text, counts explicit Q-register instructions, and optionally reconstructs suspect instruction halfwords inside an ephemeral assembled object for an MVE-aware LLVM disassembler. It does not change SDK files, generate images, or access hardware.

From the repo root after `git pull --ff-only`:

```powershell
$input = '.\artifacts\hx6538\analysis\native-isa\native-disassembly.txt'
$output = '.\artifacts\hx6538\analysis\native-isa\mve-audit.json'

py .\tools\hx6538\audit-native-mve.py --disassembly $input --output $output

# Optional when MVE-capable LLVM clang + llvm-objdump are installed:
py .\tools\hx6538\audit-native-mve.py --disassembly $input --output $output `
  --clang clang --llvm-objdump llvm-objdump
```

Expected uploaded reference: 417 parsed instruction lines, 94 explicit Q-register sites, 74 GNU ambiguous sites; with LLVM, 74/74 decoded and lower bound **168**. Without LLVM, all 74 suspects intentionally remain **UNRESOLVED**. The original disassembly text SHA-256 is `4502ef797f98902d18b0d9b626066d40005082c28fa8e5142b2332d762f764c4`; it is not the ELF manifest SHA-256.
