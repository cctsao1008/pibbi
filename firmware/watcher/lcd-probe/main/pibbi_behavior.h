#pragma once
#include <stdbool.h>
#include <stdint.h>

/* Deterministic presence loop, no sensor inference, external IO or heap. */
typedef enum { PIBBI_BEHAVIOR_IDLE, PIBBI_BEHAVIOR_ENGAGED, PIBBI_BEHAVIOR_REST } pibbi_behavior_mode_t;
typedef enum {
    PIBBI_EVENT_NONE, PIBBI_EVENT_TOUCH, PIBBI_EVENT_KNOB_LEFT,
    PIBBI_EVENT_KNOB_RIGHT, PIBBI_EVENT_KNOB_ACTIVITY, PIBBI_EVENT_BUTTON
} pibbi_behavior_event_t;
typedef struct {
    pibbi_behavior_mode_t mode;
    bool blink;
    int8_t gaze; /* -1 left, 0 center, +1 right */
} pibbi_face_pose_t;
typedef struct {
    uint64_t last_ms, last_interaction_ms, engaged_until_ms;
    uint64_t next_blink_ms, blink_end_ms;
    uint32_t blink_count;
    pibbi_face_pose_t pose;
} pibbi_behavior_t;

void pibbi_behavior_init(pibbi_behavior_t *state, uint64_t now_ms);
bool pibbi_behavior_step(pibbi_behavior_t *state, uint64_t now_ms,
                         pibbi_behavior_event_t event);
int pibbi_quadrature_delta(unsigned old_a, unsigned old_b,
                           unsigned new_a, unsigned new_b);
