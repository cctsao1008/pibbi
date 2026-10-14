#pragma once

#include <stdbool.h>
#include "lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    PIBBI_FACE_IDLE = 0,
    PIBBI_FACE_HAPPY,
    PIBBI_FACE_CURIOUS,
    PIBBI_FACE_THINKING,
    PIBBI_FACE_SLEEPY,
} pibbi_face_expression_t;

/* Call with the LVGL lock held, after the factory ui_init() has run.
 * The factory Home screen remains available via a long press. */
bool pibbi_face_attach(lv_obj_t *home_screen);

/* Call from an LVGL callback or with the LVGL port lock held.
 * Expression choice does not imply a real emotion or semantic judgment. */
void pibbi_face_set_expression(pibbi_face_expression_t expression);

#ifdef __cplusplus
}
#endif
