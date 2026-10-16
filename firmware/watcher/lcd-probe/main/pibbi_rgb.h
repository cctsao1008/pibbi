#pragma once

#include "esp_err.h"

/* Single RMT-driven WS2813-Mini-compatible LED on ESP32-S3 GPIO40. */
typedef enum {
    PIBBI_RGB_BOOT = 0,  /* blue breathing */
    PIBBI_RGB_READY,     /* green breathing */
    PIBBI_RGB_ERROR,     /* red blinking */
    PIBBI_RGB_OFF        /* dark before shutdown */
} pibbi_rgb_mode_t;

esp_err_t pibbi_rgb_init(void);
esp_err_t pibbi_rgb_set_mode(pibbi_rgb_mode_t mode);
