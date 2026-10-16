/* Host-only deterministic tests. No ESP-IDF dependencies or device I/O. */
#include <assert.h>
#include <stdio.h>
#include "pibbi_behavior.h"

static void idle_blink(void) {
    pibbi_behavior_t s;
    pibbi_behavior_init(&s, 100);
    assert(s.pose.mode == PIBBI_BEHAVIOR_IDLE && !s.pose.blink);
    assert(!pibbi_behavior_step(&s, 3299, PIBBI_EVENT_NONE));
    assert(pibbi_behavior_step(&s, 3300, PIBBI_EVENT_NONE));
    assert(s.pose.blink);
    assert(!pibbi_behavior_step(&s, 3400, PIBBI_EVENT_NONE));
    assert(pibbi_behavior_step(&s, 3500, PIBBI_EVENT_NONE));
    assert(!s.pose.blink);
}
static void interaction_and_rest(void) {
    pibbi_behavior_t s;
    pibbi_behavior_init(&s, 0);
    assert(pibbi_behavior_step(&s, 1000, PIBBI_EVENT_KNOB_RIGHT));
    assert(s.pose.mode == PIBBI_BEHAVIOR_ENGAGED && s.pose.gaze == 1);
    assert(!pibbi_behavior_step(&s, 2000, PIBBI_EVENT_NONE));
    assert(pibbi_behavior_step(&s, 5000, PIBBI_EVENT_NONE));
    assert(s.pose.mode == PIBBI_BEHAVIOR_IDLE && s.pose.gaze == 0);
    assert(pibbi_behavior_step(&s, 61000, PIBBI_EVENT_NONE));
    assert(s.pose.mode == PIBBI_BEHAVIOR_REST && !s.pose.blink);
    assert(pibbi_behavior_step(&s, 62000, PIBBI_EVENT_TOUCH));
    assert(s.pose.mode == PIBBI_BEHAVIOR_ENGAGED);
}
static void stale_time_and_interrupted_blink(void) {
    pibbi_behavior_t s;
    pibbi_behavior_init(&s, 0);
    assert(pibbi_behavior_step(&s, 3200, PIBBI_EVENT_NONE) && s.pose.blink);
    assert(pibbi_behavior_step(&s, 3250, PIBBI_EVENT_BUTTON));
    assert(s.pose.mode == PIBBI_BEHAVIOR_ENGAGED && !s.pose.blink);
    assert(!pibbi_behavior_step(&s, 3249, PIBBI_EVENT_TOUCH));
    assert(s.last_ms == 3250 && s.pose.mode == PIBBI_BEHAVIOR_ENGAGED);
}
static void knob_gray_code(void) {
    assert(pibbi_quadrature_delta(0,0,0,1) == 1);
    assert(pibbi_quadrature_delta(0,1,1,1) == 1);
    assert(pibbi_quadrature_delta(1,1,1,0) == 1);
    assert(pibbi_quadrature_delta(1,0,0,0) == 1);
    assert(pibbi_quadrature_delta(1,0,1,1) == -1);
    assert(pibbi_quadrature_delta(0,0,1,1) == 0);
    assert(pibbi_quadrature_delta(3,0,0,0) == 0);
}
static void deterministic_replay(void) {
    pibbi_behavior_t a, b;
    pibbi_behavior_init(&a, 100);
    pibbi_behavior_init(&b, 100);
    for (uint64_t t=100; t<200000; t+=50) {
        pibbi_behavior_event_t event =
            t==500 || t==100500 ? PIBBI_EVENT_TOUCH : PIBBI_EVENT_NONE;
        assert(pibbi_behavior_step(&a,t,event) == pibbi_behavior_step(&b,t,event));
        assert(a.pose.mode == b.pose.mode && a.pose.blink == b.pose.blink &&
               a.pose.gaze == b.pose.gaze);
    }
}
int main(void) {
    idle_blink();
    interaction_and_rest();
    stale_time_and_interrupted_blink();
    knob_gray_code();
    deterministic_replay();
    puts("PIBBI_BEHAVIOR_G0_PASS (5 groups)");
    return 0;
}
