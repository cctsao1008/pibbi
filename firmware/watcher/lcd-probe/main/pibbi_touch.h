#pragma once
/* Minimal polling driver for Watcher SPD2010 I2C touch panel, no LVGL. */
#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"

esp_err_t pibbi_touch_init(void);
esp_err_t pibbi_touch_poll(bool *down, uint16_t *x, uint16_t *y);
