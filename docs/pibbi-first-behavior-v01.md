# pibbi v0.1 — First Behavior (Watcher)

Status (2026-10-16): **the original v0.1 behavior firmware has now booted and run on physical Watcher OTA1**. Blink, Engaged, gaze and knob/button inputs are evidenced by UART. A subsequent performance/input-reliability source refinement is **NOT YET rebuilt or device-tested**. Pure-C host tests previously passed (5 groups).
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
- These changes do **not** touch bootloader, OTA selection metadata, OTA0, NVS, HX6538, or existing user-confirmed shutdown mechanism. **Source commits are not physical flash operations.**

Next validation: rebuild with ESP-IDF v5.2.1; inspect new `KNOB_IRQ_READY` vs `KNOB_IRQ_FAIL`, `TOUCH_RECOVERED`, `FACE_FRAME ... eye=220x96`, compare latency distribution to 106.852ms baseline, run two-stage OFF/NO and OFF/YES, and hold idle over 60s to verify Rest.
