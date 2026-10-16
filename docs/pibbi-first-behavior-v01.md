# pibbi v0.1 — First Behavior (Watcher)

Status (2026-10-16): **implementation committed; pure C host tests PASS (5 groups)**.
The updated ESP-IDF application **has not yet been rebuilt or run on the physical Watcher**.
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
allocate a full framebuffer. Face changes redraw **x=[80,332), y=[136,300)**
(252 x 164 pixels, 41,328 pixels), as compared with the original full
412 x 412 (169,744 pixels) frame. This is about 24% of full-frame pixel count;
**do not mistake pixels for a verified 4x speedup**.
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
