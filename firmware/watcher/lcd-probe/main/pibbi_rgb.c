/*
 * SenseCAP Watcher single addressable RGB LED on ESP32-S3 GPIO40.
 * Controller-compatible GRB/WS2812 RMT timing follows the pinned Seeed BSP.
 * No animation/task/timer; status transitions only.
 */
#include <stdint.h>

#include "driver/gpio.h"
#include "esp_err.h"
#include "esp_log.h"
#include "led_strip.h"
#include "pibbi_rgb.h"

#define PIBBI_RGB_GPIO  GPIO_NUM_40

static const char *TAG = "pibbi_rgb";
static led_strip_handle_t s_strip = NULL;

esp_err_t pibbi_rgb_set(uint8_t red, uint8_t green, uint8_t blue)
{
    if (s_strip == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = led_strip_set_pixel(s_strip, 0, red, green, blue);
    if (err != ESP_OK) {
        return err;
    }
    return led_strip_refresh(s_strip);
}

esp_err_t pibbi_rgb_init(void)
{
    if (s_strip != NULL) {
        return ESP_OK;
    }

    const led_strip_config_t strip = {
        .strip_gpio_num = PIBBI_RGB_GPIO,
        .max_leds = 1,
        .led_pixel_format = LED_PIXEL_FORMAT_GRB,
        /* Watcher Seeed BSP uses this timing for the WS2813-Mini LED. */
        .led_model = LED_MODEL_WS2812,
        .flags.invert_out = false,
    };

    const led_strip_rmt_config_t rmt = {
        .clk_src = RMT_CLK_SRC_DEFAULT,
        .resolution_hz = 10 * 1000 * 1000,
        .flags.with_dma = false,
    };

    esp_err_t err = led_strip_new_rmt_device(&strip, &rmt, &s_strip);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "GPIO40 RGB init failed: %s", esp_err_to_name(err));
        return err;
    }

    /* Start dark so the LED never retains an arbitrary previous indication. */
    err = led_strip_clear(s_strip);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "GPIO40 RGB clear failed: %s", esp_err_to_name(err));
    }
    return err;
}
