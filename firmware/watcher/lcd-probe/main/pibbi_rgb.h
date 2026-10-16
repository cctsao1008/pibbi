#pragma once

#include <stdint.h>
#include "esp_err.h"

/* One physical GRB addressable LED on ESP32-S3 GPIO40. */
esp_err_t pibbi_rgb_init(void);
esp_err_t pibbi_rgb_set(uint8_t red, uint8_t green, uint8_t blue);
