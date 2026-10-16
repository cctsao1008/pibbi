# pibbi v0.1 — First Behavior (Watcher)

Status (2026-10-16): **v0.1 and the subsequent eye-ROI / encoder-IRQ / blink-scheduling refinement have both booted and run on the physical Watcher OTA1**. UART confirms LCD, RGB, behavior, rotary ISR, improved frame timing, touch recovery, OFF/NO cancellation and OFF/YES power-latch release. Rest (60 s no input) and independent power-current measurements remain open. Host-only pure-C tests had previously passed 5 groups; a sixth regression test is present but no separate new host test execution log is available.
No automatic OTA1 write, branch merge or PR has been performed.

## Purpose

Replace the diagnostic rings on the verified Watcher B1b hardware baseline with
the smallest possible embodied interaction loop: **Idle / Engaged / Rest**.
This is **not** a claim of human presence detection, user identification, goal autonomy,
vision inference, or conversational intelligence. Real inputs are limited to the
known-good capacitive touch, GPIO41/42 rotary raw levels and button P0.3.

This is intentionally separate from `tools/autonomy/core.py` and its experimental,
permission-bounded goal-followup policy. The Python policy is not ported to
the MCU as part of v0.1.

## Concrete local behavior

| Trigger | Behavior | Visual result |
|---|---|---|
| First screen | Idle | White eyes, centered gaze, static PIBBI title |
| Quiet idle | Blink at deterministic varying intervals | Short 160 ms eye closure |
| Face-area touch | Engaged for 4 s | Wider cyan-tinted eyes, centered gaze |
| Rotary Gray-code edge | Engaged for 4 s | Gaze moves left/right (direction provisional) |
| Rotary button press | Engaged for 4 s | Attentive eyes |
| No new interaction for 4 s | Back to Idle | Neutral gaze |
| 60 s since last interaction | Rest | Relaxed half-closed eyes |
| Touch OFF | Existing confirmation UI | POWER OFF? YES / NO unchanged |
| YES | Existing shutdown sequence | RGB dark, LCD backlight off, P1.2 power hold released |

Rotary direction decoding currently samples GPIO41/42 every ~50 ms.
This may miss quick quadrature edges; precise detent counting is **not** claimed.
No camera/person-detection evidence is used to infer presence.

## Architecture

`pibbi_behavior.c/.h` is a deterministic pure-C state machine without
RTOS, heap, ESP-IDF, network or sensor dependencies. Its step function produces
a changed `pibbi_face_pose_t` only when mood/blink/gaze visibly changes.

`lcd_first_frame.c` draws eyes and mouth using integer RGB565 geometry,
small built-in bitmap glyphs and the **existing** QSPI stripe DMA. It does not
allocate a full framebuffer. Original v0.1 face changes redrew **x=[80,332), y=[136,300)**
(252 x 164 pixels, 41,328 pixels), as compared with the original full
412 x 412 (169,744 pixels) frame. The first live v0.1 firmware used 252 x 164 (41,328 pixels). After measuring its ~107 ms refresh, the **new source-only revision** refreshes eyes in x=[96,316), y=[136,232) (21,120 pixels), and mouth in x=[168,244), y=[252,284) only on mode change (+2,432 pixels). **No new hardware speedup measurement exists yet**.
Both face horizontal endpoints are 4-pixel aligned for SPD2010; each DMA
stripe is awaited before its buffer can be reused.

The STATIC `PIBBI` header and the OFF hitbox are outside the partial-refresh
region. The confirmation screen always takes precedence: no behavior frames
are drawn when `POWER OFF?` is visible. Touch shutdown, RGB breathing,
power sequencing and existing OTA1 partition layout are unchanged.

`FACE_FRAME mode=... blink=... gaze=... us=... region=252x164` records
actual panel-driver/transfer timing for each changed pose.
`BOOT_MARK stage=BEHAVIOR_READY` records state-engine initialization.
No additional tasks are required; the behavior step runs in the existing
50 ms input loop. The RGB breathing task continues independently.

## Verification already completed

A developer-container GCC 11-compatible C11 build with
`-Wall -Wextra -Werror -O2 -fsanitize=address,undefined` executed five
deterministic groups: initial Idle/blink, user engagement and return to Rest,
interrupted blink/out-of-order timestamps, legal/illegal encoder transitions,
and deterministic replay. Result: **PIBBI_BEHAVIOR_G0_PASS (5 groups)**.
These are **host-only** results, not firmware build or on-device pass.

## Next hardware gate (manual)

Close COM31 Miniterm. In ESP-IDF v5.2.1 PowerShell:

```powershell
cd D:\my-github\pibbi
git switch research/hx6538-runtime-baseline-audit-20261015
git pull --ff-only
.\tools\watcher\build-lcd-probe.ps1
```

**Stop if Build fails.** Because current Watcher boots OTA1, use the
existing guarded `tools/watcher/update-minimal-ota1.ps1` only when ready to
flash the newly built, validated image; never use `idf.py flash` or
the first-install tool. It writes only `ota_1` app at 0xD10000 and keeps
`ota_0` and OTA-selection metadata intact.

For validation, confirm: full screen initial eyes and OFF button; alternating
blink while idle; touch/knob interaction; Rest after ~60 s; OFF->NO returns
to eyes; OFF->YES still cuts power; no `FACE_RENDER_FAIL`; changed-face
frame times from UART. Also verify three cold boots, the first
`UI_READY` and touch operation.

No additional OTA write has been executed by this authoring step.

## 2026-10-16 23:29 — actual Watcher UART evidence

Source: user-supplied COM31 115200 boot and 28s event log (sanitized, no provisioning secrets reproduced). Bootloader loaded `ota_1` from `0xd10000`. App name `pibbi_watcher_lcd_probe`, version `9f85c2b`, compiled 2026-10-16 22:43:21, ESP-IDF v5.2.1, ESP32-S3 160MHz.

| Marker | Boot time | App elapsed |
|---|---:|---:|
| `APP_ENTER` | 352.982 ms | 0.004 ms |
| `RGB_READY` | 621.169 ms | 268.191 ms |
| `LOCAL_READY` | 647.602 ms | 294.624 ms |
| `UI_READY` | **1,077.885 ms** | **724.907 ms** |
| `BEHAVIOR_READY` | 1,081.387 ms | 728.409 ms |
| `TOUCH_READY` | 1,247.799 ms | 894.821 ms |

The log includes **25** `FACE_FRAME` events; frame-transfer measurement mean **106.852ms** (min **98.160ms**, max **108.686ms**) for the original 252×164 partial-render region. Five blink-close events are visible. Several Engaged `mode=1` events and gaze -1/0/+1 follow recorded GPIO41/42 knob and expander button transitions. There are no crashes or watchdog resets within the observed excerpt. Rest cannot yet be claimed: only 28s were captured and the Rest threshold is 60s after the latest interaction.

One **Touch I2C transaction failure** is recorded immediately after `TOUCH_READY` (`panel_io_i2c_tx_buffer`, `write_tp_cpu_start_cmd`). The rest of the log contains no touch events or a positive recovery marker. Hence touch recovery and touch shutdown in this specific v0.1 run remain unproven, despite the previous B1b shutdown user acceptance. Do not claim the single error permanently disabled touch.

### Source-only follow-up after measuring the real bottleneck

- `lcd_first_frame.c`: narrow frequent gaze/blink redraw to eye ROI **220×96 = 21,120 pixels** (48.9% fewer pixels than previous 41,328), with small separate mouth ROI **76×32** only when behavior mode changes. Preserves 4-pixel X alignment, DMA completion waiting and OFF/YES/NO priority. Real speed is unknown until rebuilt and measured.
- `minimal/main/main.c`: capture GPIO41/42 quadrature edges in a **GPIO any-edge ISR**, accumulate legal Gray transitions under FreeRTOS spinlock while QSPI drawing blocks `app_main()`, and consume net direction in the existing loop. No new Task. Retain raw GPIO telemetry and a logged polling fallback if ISR installation fails. Runtime validation pending.
- `minimal/main/main.c`: add rate-limited `TOUCH_RECOVERED after N failed polls` diagnostics to distinguish a one-time initial I2C failure from persistent errors; does not alter the SPD2010 driver protocol.
- Observed a behavior detail: after the last knob event (~23.7s) the first post-Engaged `mode=0` frame (~27.9s) was already blinking. Root cause: the old blink timer was scheduled 3.2s after input while Engaged lasted 4s. Fixed the pure C deadline to **4s engagement + 3.2s idle**; added a new regression group `blink_waits_for_engagement_to_end` (now 6 host test groups defined, latest 6-group run not yet reported).
- These changes do **not** touch bootloader, OTA selection metadata, OTA0, NVS, HX6538, or existing user-confirmed shutdown mechanism. **Source commits are not physical flash operations.**

Next validation: rebuild with ESP-IDF v5.2.1; inspect new `KNOB_IRQ_READY` vs `KNOB_IRQ_FAIL`, `TOUCH_RECOVERED`, `FACE_FRAME ... eye=220x96`, compare latency distribution to 106.852ms baseline, run two-stage OFF/NO and OFF/YES, and hold idle over 60s to verify Rest.

## 2026-10-16 — refined v0.1 firmware real Watcher acceptance (app `71bda59`)

User-provided second COM31/115200 capture (Oct 16, compiled 23:39:14) establishes an actual **OTA1 (`0xD10000`) run** with the previously source-only refinements. No assistant performed a flash. The following are **measured UART timings, not estimated display response to finger movement**:

| Evidence | Value |
|---|---|
| Boot `APP_ENTER` | 353.261 ms |
| `UI_READY` | **1,078.177 ms** (app elapsed 724.920 ms) |
| `BEHAVIOR_READY` | 1,081.674 ms |
| `TOUCH_READY` | 1,248.102 ms |
| ISR setup | **`KNOB_IRQ_READY GPIO41/42 any-edge`** |
| Eye-only region and frame count | **220×96 pixels, n=14** |
| Eye-only update, min / mean / median / max | **58.169 / 58.449 / 58.395 / 58.737 ms** |
| Eye plus mouth (`23552` pixels) | **n=2; mean 78.966 ms** |
| All 16 face updates | **mean 61.014 ms** |
| Comparison to previous user trace (n=25, mean 106.852 ms for 252×164) | Eye-only updates **45.3% less time**, ~**1.83×** update throughput; fewer pixels were transferred (−48.9%) |

Functional outcomes in the same trace:

- GPIO41/42 interrupt installation succeeded, `INPUT encoder_edges` recorded signed counts such as `+2`, `-3`; both `gaze=+1` and `gaze=-1` were rendered, and the knob button returned face to center. Physical rotary detent accuracy or jitter rate is not yet calibrated.
- Three blink=1/0 pairs with 160 ms log-to-log close/open difference are visible; the current deterministic blink scheduler no longer produces the immediate post-engagement blink observed in the previous trace.
- SPD2010 touch initialization succeeded. One I2C transaction failed on the first post-init poll at ~1.25s, then **`TOUCH_RECOVERED after 1 failed polls` at 1.332s**. Later touch behavior is conclusively functional: OFF button registered **3 times**, `SHUTDOWN_CANCELLED` **2 times**, then a confirmed YES invoked `SHUTDOWN_REQUESTED_BY_TOUCH`, RGB OFF and `SHUTDOWN_RELEASE_SYSTEM_POWER_HOLD P1.2` at **25.162s**. The UART also reports `SHUTDOWN_LATCH_RELEASED`; USB versus battery current and actual rail-off timing were not measured.
- No `FACE_RENDER_FAIL`, crash, reboot loop or watchdog failure appears in the capture. Current boot-to-UI timing is virtually identical to prior 1,077.885 ms first-behavior run.
- **Rest remains unverified:** total trace ends near 25.2s and includes input activity, so it never achieves 60s inactivity. No `INPUT face_touch` is in this capture; only the OFF/confirmation screen touch flow is exercised. A dedicated tap on the face area would verify the non-shutdown touch action.

**Decision:** This firmware revision is a viable first-behavior **bench baseline**. Do not introduce additional code churn solely to remove the one transient I2C error. Next targeted checks: hands-off ≥65s to observe `FACE_FRAME mode=2`, one non-OFF face touch (`INPUT face_touch`), and optional encoder detent repeatability. Keep `ota_0`, NVS, OTA metadata and HX6538 untouched; no flashing required to collect these observations.

## 2026-10-17 — code review: software-only acceptance, no redundant manual touch/idle test

Reviewed the pure-C Behavior Engine, ESP32-S3 app loop, touch-down edge logic, OFF/YES/NO confirmation handler, LCD face ROI updates, and GPIO41/42 any-edge ISR against the two physical UART traces.

- **Behavior boundary PASS (host C tests):** independent GCC C11 `-Wall -Wextra -Werror -O1 -g -fsanitize=address,undefined` run completed `PIBBI_BEHAVIOR_G0_PASS (6 groups)`. Includes exact boundary: at 59,999 ms after last interaction mode remains Idle; at 60,000 ms becomes Rest; touch while resting returns to Engaged; after engagement first blink waits another 3.2s. Deterministic replay and Gray-code cases also pass.
- **Touch routing (code inspection):** when touch I2C is usable, only a new touch-down edge on the home view outside the OFF rectangle emits `PIBBI_EVENT_TOUCH`. OFF opens confirmation; YES alone calls the existing physical power-hold release; NO cancels. Runtime UART independently confirms OFF/NO/YES on Watcher. No need to ask the user to wait for Rest or repeat tapping solely to prove core state transitions.
- **Bug found and fixed:** cancelling an OFF confirmation page did not update Behavior Engine's last interaction timestamp. If the page had been left open >60s, returning home could immediately enter Rest. The successful `NO` cancel branch now emits `PIBBI_EVENT_TOUCH` into the existing loop, producing Engaged and resetting its idle timer. It does not modify the shutdown power-hold logic.
- **Design limitations, not established regressions:** one Behavior event is selected per loop (simultaneous touch/knob inputs can coalesce); GPIO IRQ accumulates net signed encoder edges (opposite edges may cancel before consumption); first touch I2C sample can fail once but previously recovered in the observed run. These do not warrant speculative changes absent a user-observed symptom.
- **Boundary:** the new NO-cancel source line is not yet part of a fresh device build; host tests validate the pure C transitions, not ESP-IDF wiring or physical power current. Existing UART supports the old working physical OFF/YES/NO path. Only further hardware testing justified by a genuine display, touch, electrical or timing symptom is required.

Review conclusion: **Behavior semantics PASS; do not hold the current milestone open waiting for a redundant 65-second idle observation or a face-tap demonstration.**
