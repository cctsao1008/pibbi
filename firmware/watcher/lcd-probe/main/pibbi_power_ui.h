#pragma once
/* Minimal fixed 412x412 framebuffer UI and touch target mapping, no LVGL. */
#include <stdbool.h>
#include "esp_err.h"
#include "pibbi_behavior.h"

typedef enum {
    PIBBI_LCD_HOME = 0,
    PIBBI_LCD_CONFIRM_POWER_OFF
} pibbi_lcd_view_t;

enum { PIBBI_LCD_W = 412, PIBBI_LCD_H = 412 };

static inline bool pibbi_hit_home_off(unsigned x, unsigned y) {
    return x >= 122 && x < 290 && y >= 338 && y < 402;
}
static inline bool pibbi_hit_confirm_yes(unsigned x, unsigned y) {
    return x >= 25 && x < 194 && y >= 232 && y < 331;
}
static inline bool pibbi_hit_confirm_no(unsigned x, unsigned y) {
    return x >= 218 && x < 387 && y >= 232 && y < 331;
}

esp_err_t pibbi_lcd_first_frame(void);
esp_err_t pibbi_lcd_set_view(pibbi_lcd_view_t view);
/* Only the face region is refreshed when the behavior pose changes. */
esp_err_t pibbi_lcd_set_face(pibbi_face_pose_t pose);
esp_err_t pibbi_lcd_backlight_off(void);
esp_err_t pibbi_lcd_backlight_on(void);
