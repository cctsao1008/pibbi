#include "pibbi_behavior.h"
#include <stddef.h>

#define ENGAGED_MS UINT64_C(4000)
#define REST_AFTER_MS UINT64_C(60000)
#define FIRST_BLINK_MS UINT64_C(3200)
#define BLINK_DURATION_MS UINT64_C(160)

static const uint16_t blink_intervals_ms[] = {4200, 5300, 3800, 6100};

void pibbi_behavior_init(pibbi_behavior_t *state, uint64_t now_ms)
{
    if (state == NULL) return;
    *state = (pibbi_behavior_t){
        .last_ms = now_ms, .last_interaction_ms = now_ms,
        .engaged_until_ms = now_ms, .next_blink_ms = now_ms + FIRST_BLINK_MS,
        .pose = {.mode = PIBBI_BEHAVIOR_IDLE, .blink = false, .gaze = 0}
    };
}

bool pibbi_behavior_step(pibbi_behavior_t *state, uint64_t now_ms,
                         pibbi_behavior_event_t event)
{
    if (state == NULL || now_ms < state->last_ms) return false;
    state->last_ms = now_ms;
    const pibbi_face_pose_t prev = state->pose;
    if (event > PIBBI_EVENT_NONE && event <= PIBBI_EVENT_BUTTON) {
        state->last_interaction_ms = now_ms;
        state->engaged_until_ms = now_ms + ENGAGED_MS;
        state->blink_end_ms = 0;
        /* Blink only after engagement has ended and the face has settled.
         * Previously this deadline fell inside the 4s Engaged window,
         * causing an immediate blink on return to Idle. */
        state->next_blink_ms = state->engaged_until_ms + FIRST_BLINK_MS;
        state->pose.gaze = event == PIBBI_EVENT_KNOB_LEFT ? -1 :
                           event == PIBBI_EVENT_KNOB_RIGHT ? 1 : 0;
    }
    if (now_ms < state->engaged_until_ms) {
        state->pose.mode = PIBBI_BEHAVIOR_ENGAGED;
    } else if (now_ms - state->last_interaction_ms >= REST_AFTER_MS) {
        state->pose.mode = PIBBI_BEHAVIOR_REST;
    } else {
        state->pose.mode = PIBBI_BEHAVIOR_IDLE;
    }
    if (state->pose.mode != PIBBI_BEHAVIOR_ENGAGED) state->pose.gaze = 0;
    if (state->pose.mode == PIBBI_BEHAVIOR_IDLE) {
        if (now_ms >= state->next_blink_ms) {
            state->blink_end_ms = now_ms + BLINK_DURATION_MS;
            state->next_blink_ms = now_ms +
                blink_intervals_ms[state->blink_count %
                                  (sizeof(blink_intervals_ms) / sizeof(blink_intervals_ms[0]))];
            state->blink_count++;
        }
        state->pose.blink = now_ms < state->blink_end_ms;
    } else {
        state->pose.blink = false;
    }
    return state->pose.mode != prev.mode || state->pose.blink != prev.blink ||
           state->pose.gaze != prev.gaze;
}

int pibbi_quadrature_delta(unsigned old_a, unsigned old_b,
                           unsigned new_a, unsigned new_b)
{
    if ((old_a | old_b | new_a | new_b) > 1U) return 0;
    /* +1: 00->01->11->10->00; illegal/skipped edges produce zero. */
    static const int8_t delta[16] = {
        0, 1,-1, 0,
       -1, 0, 0, 1,
        1, 0, 0,-1,
        0,-1, 1, 0
    };
    unsigned previous = (old_a << 1) | old_b;
    unsigned current = (new_a << 1) | new_b;
    return delta[(previous << 2) | current];
}
