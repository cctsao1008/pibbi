# pibbi Autonomous Core — fieldable MVP

Status: G0 developer-container Python prototype 11/11 deterministic tests PASS; G1 real Watcher events NOT VERIFIED. Host-only, no firmware flashing, no PR.

## Why this research

Do not reinvent person detection, Helium preprocessing, TFLM, or generic agent frameworks. Seeed Watcher already provides on-device people detection, event-triggered notifications, UART JSON, local/cloud analysis, and documented HTTP push. Focus instead on an auditable, persistent goal-driven controller that chooses when to inquire, when to wait, when to defer, and when to stop, even when physical events are stale or incomplete.

Autonomous behavior is limited to a specific, permission-bounded goal and a closed loop with explicit outcomes; this is not a general autonomous robot, self-directed camera sampler, or tested embodied agent.

## Evidence, not assumptions

- [Official task configuration](https://wiki.seeedstudio.com/getting_started_with_watcher_task/) documents person detection with local AI and actions.
- [Official Watcher to Node-RED](https://wiki.seeedstudio.com/watcher_to_node_red/) documents SenseCraft-configured HTTP push to a LAN PC, using POST /v1/notification/event and HTTP 200 response.
- [Official UART output](https://wiki.seeedstudio.com/uart_output/) documents event JSON with optional large images and version limitations.
- [Official OSHW firmware guide](https://github.com/Seeed-Studio/OSHW-SenseCAP-Watcher/blob/main/Firmware/README.md) warns about erasing ESP32 NVS/factory identity (EUI) and advises against Himax firmware modification.

What is NOT established: actual Watcher-to-PC event delivery in this experiment; exact real HTTP JSON shape; safe bidirectional arbitrary camera sampling or sensor-power APIs; generic human detection proving owner identity; no event proving absence. These must not be silently assumed.

## G0 concrete experimental scenario

An owner delegates one pending task requiring follow-up. The policy should use person-detected as an *opportunity*, never as owner identification. On a suitable opportunity: ask for explicit owner confirmation (on PC, simulated at G0), then ask goal status. On completion, permanently stop; on deferral, wait; on timeout, cool down; on wrong owner, do not reveal private task text.

Normalize synthetic events: person_detected, owner_confirmed, owner_rejected, goal_completed, defer_goal, tick. These are our simulated event types, NOT the raw Watcher protocol.

Machine phases: pending -> verify_owner -> await_result -> done / deferred. A stale positive person event reverts to UNKNOWN, not ABSENT. All action intents have a reason string. Model no physical actuation at G0.

Default **experimental knobs, not empirical best values**:
- Person-evidence TTL 60 s; owner confirmation timeout 30 s; result timeout 60 s.
- Silence/cooldown 600 s after timeout/negative confirmation; explicit defer 1800 s.
- Maximum 3 interaction opportunities per rolling 24 h; configurable.

## G0 acceptance gate — host-only simulation

Python stdlib deterministic policy, JSONL replay, restartable JSON state, append-only JSONL decision audit. Test invariants:

1. Person detection alone must not disclose goal or verify identity.
2. Repeated person detections while awaiting feedback do not duplicate prompts.
3. Stale evidence becomes UNKNOWN, never proof of an empty room.
4. Confirmation timeout enforces cooldown and requires new opportunity.
5. Non-owner rejection never reveals the task.
6. Deferral prevents premature prompts and schedules a later opportunity.
7. Explicit completion stops all future prompts.
8. Rolling daily interruption budget is enforced.
9. Snapshot/restore survives reboot or process restart.
10. Out-of-order timestamps fail closed.
11. Unsolicited completion cannot terminate an unconfirmed goal.

Developer-container tests: 11/11 passed. User's Windows checkout has not yet independently run them.

Engineering baseline: compare to notify-on-every-event on the same recorded event trace; report repeated questions, interrupted opportunities, outcomes, and missed interactions. A correct policy is not a performance benchmark, product readiness, or proof of human-level autonomy.

## G1 — actual Watcher event integration, conditional on physical unit

Run the documented SenseCraft person-detection task + HTTP push into a LAN-only receiver, no flashing. Start with Seeed Node-RED as reference. Capture at least 20 alerts, compare arrival timestamps, deduplication, payload field structure, failures and retry behavior. Avoid persisting images/face data or secrets; redact sensitive fields. Create an explicit adapter only after inspecting sanitized real messages. Do not equate silence with negative evidence, or notification receipt time with image capture time.

GO iff an unchanged factory Watcher can consistently deliver parseable events. If not, stop G1 and retain PC proof of concept.

## G2 — real closed-loop PC pilot

Provide explicit user confirmation and complete/defer input in a local PC UI/CLI. Replay at least 20 episodes with real events where available; track accidental disclosure, duplicate interrupts, mistaken completion and feedback timeouts. No unsolicited message sending or external side-effect tools.

## G3 — optional embedded version (not approved)

Evaluate ESP32-S3 deployment only after separately verified firmware backups, partition recovery and preservation of factory NVS/EUI; Himax firmware unchanged by default. No arbitrary bidirectional sensor control is presumed.

### Research gates

G0 local: tested on synthetic normalized inputs, not on device.
G1: open / hardware event schema unverified.
G2: open / no user interactions yet.
G3: future / no flash authorization.

Continue with direct commits on branch research/hx6538-runtime-baseline-audit-20261015. PR #2 stays closed, no new PR.


## Runnable G0 research files and Windows smoke test

- tools/autonomy/core.py: deterministic bounded decision policy; plain goal snapshot, no device I/O.
- tools/autonomy/replay.py: offline event replay, append-only JSONL decision audit and atomic state update.
- tests/test_autonomy_core.py: 11 behavior and safety invariants.
- tests/data/autonomy-sample.jsonl: synthetic two-opportunity case (deferral and completion).
- Tracking: https://github.com/cctsao1008/pibbi/issues/4

From an already checked-out pibbi **research** branch on Windows:

```powershell
git pull --ff-only
py -m unittest discover -s .\tests -p "test_autonomy*.py" -v

$run = ".\artifacts\pibbi\autonomy-g0"
New-Item -ItemType Directory -Force $run | Out-Null

py .\tools\autonomy\replay.py `
  --trace .\tests\data\autonomy-sample.jsonl `
  --goal "Check one unfinished item" `
  --state "$run\goal-state.json" `
  --audit "$run\decisions.jsonl"
```

**Use fresh state and audit paths for each replay**; prior state holds the last timestamp and rejects older events. The sample's intended action sequence is:
1. 0: request_owner_confirmation
2. 1: none (duplicate suppressed)
3. 4: ask_goal_status
4. 8: record_goal_deferred
5. 60: none
6. 1809: request_owner_confirmation
7. 1810: ask_goal_status
8. 1811: record_goal_completed
9. 1900: none (goal already done)

These are **emitted action intents**, not actual notifications or physical actions. The local JSON state holds goal text **in plaintext**; use a dummy goal for public demonstrations and do not commit personal-state/audit files. The synthetic owner_confirmed event is **not** a verified Watcher detection capability. A real user authentication input remains a G2 gate.

The unit tests were run locally before committing equivalent files. The GitHub copies have not yet been independently rerun in the user's Windows checkout. No claim about hardware-in-the-loop behavior is made.

### Related work / novelty restraint

- Bajcsy et al., [Revisiting active perception](https://link.springer.com/article/10.1007/s10514-017-9615-3), Autonomous Robots (2018). The concepts of acting to improve perception and deciding when to sense have established literature.
- Watcher's native task-triggered alerts are **already** a vendor-provided behavior; our experiment is not to recreate them.

Only a measured difference in interruption load, stale-evidence handling, and goal completion compared to naive event rules on the same trace would justify continued autonomy development; otherwise stop rather than building yet another home-automation rule set.
