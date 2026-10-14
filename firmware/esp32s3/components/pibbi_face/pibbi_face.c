#include "pibbi_face.h"

#include <stdbool.h>
#include <stdint.h>

#define PIBBI_FACE_TICK_MS        60U
#define PIBBI_FACE_BLINK_EVERY_MS 3200U
#define PIBBI_FACE_BLINK_TIME_MS  150U
#define PIBBI_FACE_GAZE_EVERY_MS  3900U
#define PIBBI_FACE_TAP_HAPPY_MS   1800U

/* Warm, flat colors from the approved minimal 2D white-bear direction. */
#define PIBBI_COLOR_BG        0xF7EEE4
#define PIBBI_COLOR_WHITE     0xFFFDF9
#define PIBBI_COLOR_EAR       0xF6D0CB
#define PIBBI_COLOR_MUZZLE    0xFFF8F1
#define PIBBI_COLOR_EYE       0x302929
#define PIBBI_COLOR_HIGHLIGHT 0xFFFFFF
#define PIBBI_COLOR_CHEEK     0xF7D7D1
#define PIBBI_COLOR_CHEEK_ON  0xF5B8B4
#define PIBBI_COLOR_TONGUE    0xF48F96

typedef struct {
    lv_obj_t *home;
    lv_obj_t *panel;
    lv_obj_t *return_button;
    lv_obj_t *left_eye;
    lv_obj_t *right_eye;
    lv_obj_t *left_cheek;
    lv_obj_t *right_cheek;
    lv_obj_t *mouth_neutral;
    lv_obj_t *mouth_open;
    lv_obj_t *tongue;
    lv_timer_t *timer;
    pibbi_face_expression_t expression;
    uint32_t blink_at_ms;
    uint32_t gaze_at_ms;
    uint32_t happy_at_ms;
    int gaze_x;
    int target_gaze_x;
    uint8_t gaze_step;
    bool blinking;
    bool temporary_happy;
    bool long_pressed;
} pibbi_face_t;

static pibbi_face_t s_face;

/* Static LVGL line points: lv_line_set_points retains this pointer. */
static const lv_point_t s_mouth_points[] = {
    { 0, 0 }, { 8, 5 }, { 16, 0 }
};

static lv_obj_t *shape(lv_obj_t *parent, lv_coord_t w, lv_coord_t h,
                       lv_coord_t x, lv_coord_t y, uint32_t rgb,
                       lv_coord_t radius)
{
    lv_obj_t *obj = lv_obj_create(parent);
    lv_obj_remove_style_all(obj);
    lv_obj_set_size(obj, w, h);
    lv_obj_align(obj, LV_ALIGN_CENTER, x, y);
    lv_obj_set_style_bg_color(obj, lv_color_hex(rgb), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(obj, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_radius(obj, radius, LV_PART_MAIN);
    lv_obj_clear_flag(obj, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    return obj;
}

static void show_expression(void)
{
    const bool open_mouth =
        s_face.expression == PIBBI_FACE_HAPPY ||
        s_face.expression == PIBBI_FACE_CURIOUS;
    const bool happy = s_face.expression == PIBBI_FACE_HAPPY;

    if (open_mouth) {
        lv_obj_add_flag(s_face.mouth_neutral, LV_OBJ_FLAG_HIDDEN);
        lv_obj_clear_flag(s_face.mouth_open, LV_OBJ_FLAG_HIDDEN);
        lv_obj_set_size(s_face.mouth_open, happy ? 28 : 12, happy ? 22 : 13);
        lv_obj_align(s_face.mouth_open, LV_ALIGN_CENTER, 0, 65);
    } else {
        lv_obj_clear_flag(s_face.mouth_neutral, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_face.mouth_open, LV_OBJ_FLAG_HIDDEN);
    }

    if (happy) {
        lv_obj_clear_flag(s_face.tongue, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(s_face.tongue, LV_OBJ_FLAG_HIDDEN);
    }

    lv_color_t cheek_color = lv_color_hex(
        happy ? PIBBI_COLOR_CHEEK_ON : PIBBI_COLOR_CHEEK);
    lv_obj_set_style_bg_color(s_face.left_cheek, cheek_color, LV_PART_MAIN);
    lv_obj_set_style_bg_color(s_face.right_cheek, cheek_color, LV_PART_MAIN);

    lv_coord_t height = (s_face.blinking ||
                         s_face.expression == PIBBI_FACE_SLEEPY) ? 4 : 30;
    lv_obj_set_height(s_face.left_eye, height);
    lv_obj_set_height(s_face.right_eye, height);
}

void pibbi_face_set_expression(pibbi_face_expression_t expression)
{
    if (s_face.panel == NULL || expression > PIBBI_FACE_SLEEPY) {
        return;
    }

    s_face.expression = expression;
    s_face.temporary_happy = false;
    show_expression();
}

static void face_tick(lv_timer_t *timer)
{
    (void)timer;
    if (s_face.home == NULL || lv_scr_act() != s_face.home ||
        lv_obj_has_flag(s_face.panel, LV_OBJ_FLAG_HIDDEN)) {
        return;
    }

    const uint32_t now = lv_tick_get();
    if (s_face.temporary_happy &&
        (uint32_t)(now - s_face.happy_at_ms) >= PIBBI_FACE_TAP_HAPPY_MS) {
        pibbi_face_set_expression(PIBBI_FACE_IDLE);
    }

    if ((uint32_t)(now - s_face.blink_at_ms) >=
        (s_face.blinking ? PIBBI_FACE_BLINK_TIME_MS
                         : PIBBI_FACE_BLINK_EVERY_MS)) {
        s_face.blinking = !s_face.blinking;
        s_face.blink_at_ms = now;
        show_expression();
    }

    if ((uint32_t)(now - s_face.gaze_at_ms) >= PIBBI_FACE_GAZE_EVERY_MS) {
        static const int8_t gaze_targets[] = { -8, 5, 0, 9, -4, 0 };
        s_face.target_gaze_x = gaze_targets[
            s_face.gaze_step % (sizeof(gaze_targets) / sizeof(gaze_targets[0]))];
        ++s_face.gaze_step;
        s_face.gaze_at_ms = now;
    }

    if (s_face.gaze_x < s_face.target_gaze_x) {
        ++s_face.gaze_x;
    } else if (s_face.gaze_x > s_face.target_gaze_x) {
        --s_face.gaze_x;
    }

    lv_obj_align(s_face.left_eye, LV_ALIGN_CENTER, -66 + s_face.gaze_x, -14);
    lv_obj_align(s_face.right_eye, LV_ALIGN_CENTER, 66 + s_face.gaze_x, -14);
}

static void return_to_face(lv_event_t *event)
{
    if (lv_event_get_code(event) != LV_EVENT_CLICKED) {
        return;
    }

    lv_obj_add_flag(s_face.return_button, LV_OBJ_FLAG_HIDDEN);
    lv_obj_clear_flag(s_face.panel, LV_OBJ_FLAG_HIDDEN);
    s_face.long_pressed = false;
    pibbi_face_set_expression(PIBBI_FACE_IDLE);
}

static void face_interaction(lv_event_t *event)
{
    const lv_event_code_t code = lv_event_get_code(event);
    if (code == LV_EVENT_LONG_PRESSED) {
        s_face.long_pressed = true;
        lv_obj_add_flag(s_face.panel, LV_OBJ_FLAG_HIDDEN);
        lv_obj_clear_flag(s_face.return_button, LV_OBJ_FLAG_HIDDEN);
    } else if (code == LV_EVENT_CLICKED && !s_face.long_pressed) {
        pibbi_face_set_expression(PIBBI_FACE_HAPPY);
        s_face.temporary_happy = true;
        s_face.happy_at_ms = lv_tick_get();
    }
}

bool pibbi_face_attach(lv_obj_t *home_screen)
{
    if (home_screen == NULL) {
        return false;
    }
    if (s_face.panel != NULL) {
        return s_face.home == home_screen;
    }

    s_face.home = home_screen;
    s_face.expression = PIBBI_FACE_IDLE;

    /* The factory home page is retained underneath this opaque face. */
    s_face.panel = lv_obj_create(home_screen);
    lv_obj_remove_style_all(s_face.panel);
    lv_obj_set_size(s_face.panel, LV_PCT(100), LV_PCT(100));
    lv_obj_align(s_face.panel, LV_ALIGN_CENTER, 0, 0);
    lv_obj_set_style_bg_color(s_face.panel, lv_color_hex(PIBBI_COLOR_BG), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(s_face.panel, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_radius(s_face.panel, 0, LV_PART_MAIN);
    lv_obj_clear_flag(s_face.panel, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(s_face.panel, LV_OBJ_FLAG_CLICKABLE);

    /* Rounded ears behind the head, with small pink inner ears. */
    shape(s_face.panel, 91, 91, -115, -124, PIBBI_COLOR_WHITE, LV_RADIUS_CIRCLE);
    shape(s_face.panel, 91, 91, 115, -124, PIBBI_COLOR_WHITE, LV_RADIUS_CIRCLE);
    shape(s_face.panel, 47, 47, -115, -125, PIBBI_COLOR_EAR, LV_RADIUS_CIRCLE);
    shape(s_face.panel, 47, 47, 115, -125, PIBBI_COLOR_EAR, LV_RADIUS_CIRCLE);

    /* The head fills the round LCD, keeping the portrait easy to recognize. */
    shape(s_face.panel, 326, 308, 0, 17, PIBBI_COLOR_WHITE, 143);
    shape(s_face.panel, 100, 76, 0, 52, PIBBI_COLOR_MUZZLE, LV_RADIUS_CIRCLE);

    s_face.left_cheek = shape(s_face.panel, 44, 26, -110, 35,
                              PIBBI_COLOR_CHEEK, LV_RADIUS_CIRCLE);
    s_face.right_cheek = shape(s_face.panel, 44, 26, 110, 35,
                               PIBBI_COLOR_CHEEK, LV_RADIUS_CIRCLE);

    s_face.left_eye = shape(s_face.panel, 23, 30, -66, -14,
                            PIBBI_COLOR_EYE, LV_RADIUS_CIRCLE);
    s_face.right_eye = shape(s_face.panel, 23, 30, 66, -14,
                             PIBBI_COLOR_EYE, LV_RADIUS_CIRCLE);
    shape(s_face.left_eye, 6, 6, 4, -7, PIBBI_COLOR_HIGHLIGHT, LV_RADIUS_CIRCLE);
    shape(s_face.right_eye, 6, 6, 4, -7, PIBBI_COLOR_HIGHLIGHT, LV_RADIUS_CIRCLE);

    shape(s_face.panel, 29, 19, 0, 37, PIBBI_COLOR_EYE, LV_RADIUS_CIRCLE);

    s_face.mouth_neutral = lv_line_create(s_face.panel);
    lv_line_set_points(s_face.mouth_neutral, s_mouth_points,
                       sizeof(s_mouth_points) / sizeof(s_mouth_points[0]));
    lv_obj_align(s_face.mouth_neutral, LV_ALIGN_CENTER, -8, 64);
    lv_obj_set_style_line_color(s_face.mouth_neutral,
                                lv_color_hex(PIBBI_COLOR_EYE), LV_PART_MAIN);
    lv_obj_set_style_line_width(s_face.mouth_neutral, 4, LV_PART_MAIN);
    lv_obj_set_style_line_rounded(s_face.mouth_neutral, true, LV_PART_MAIN);
    lv_obj_clear_flag(s_face.mouth_neutral, LV_OBJ_FLAG_CLICKABLE);

    s_face.mouth_open = shape(s_face.panel, 28, 22, 0, 65,
                              PIBBI_COLOR_EYE, LV_RADIUS_CIRCLE);
    s_face.tongue = shape(s_face.panel, 15, 8, 0, 72,
                          PIBBI_COLOR_TONGUE, LV_RADIUS_CIRCLE);
    lv_obj_add_flag(s_face.mouth_open, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(s_face.tongue, LV_OBJ_FLAG_HIDDEN);

    lv_obj_add_event_cb(s_face.panel, face_interaction, LV_EVENT_ALL, NULL);

    /* Explicit escape hatch to the original Watcher settings and tools. */
    s_face.return_button = lv_btn_create(home_screen);
    lv_obj_set_size(s_face.return_button, 96, 36);
    lv_obj_align(s_face.return_button, LV_ALIGN_TOP_MID, 0, 19);
    lv_obj_set_style_bg_color(s_face.return_button,
                              lv_color_hex(PIBBI_COLOR_BG), LV_PART_MAIN);
    lv_obj_set_style_radius(s_face.return_button, LV_RADIUS_CIRCLE, LV_PART_MAIN);
    lv_obj_set_style_shadow_width(s_face.return_button, 0, LV_PART_MAIN);
    lv_obj_t *label = lv_label_create(s_face.return_button);
    lv_label_set_text(label, "pibbi");
    lv_obj_center(label);
    lv_obj_add_flag(s_face.return_button, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_event_cb(s_face.return_button, return_to_face, LV_EVENT_CLICKED, NULL);

    s_face.blink_at_ms = lv_tick_get();
    s_face.gaze_at_ms = s_face.blink_at_ms;
    s_face.timer = lv_timer_create(face_tick, PIBBI_FACE_TICK_MS, NULL);
    return s_face.timer != NULL;
}
