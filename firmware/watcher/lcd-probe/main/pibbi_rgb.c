/*
 * SenseCAP Watcher: single WS2813-Mini compatible GRB addressable RGB LED.
 *
 * Seeed BSP's known-working configuration: ESP32-S3 GPIO40, GRB, WS2812
 * protocol, RMT 10 MHz, non-DMA. One low-priority FreeRTOS task owns all
 * LED writes; other code only queues a status change. No LVGL or assets.
 */
#include <stdint.h>

#include "driver/gpio.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "led_strip.h"
#include "pibbi_rgb.h"

#define PIBBI_RGB_GPIO             GPIO_NUM_40
#define PIBBI_RGB_STEP_MS          40
#define PIBBI_RGB_PHASE_STEPS      64
#define PIBBI_RGB_PEAK             32 /* Low brightness: max 32 of 255 */
#define PIBBI_RGB_TASK_STACK       3072

static const char *TAG = "pibbi_rgb";
static led_strip_handle_t s_strip = NULL;
static QueueHandle_t s_mode_queue = NULL;

/* Only called by rgb_task(): single writer to RMT/led_strip handle. */
static esp_err_t rgb_write(uint8_t red, uint8_t green, uint8_t blue)
{
    esp_err_t err = led_strip_set_pixel(s_strip, 0, red, green, blue);
    if (err != ESP_OK) {
        return err;
    }
    return led_strip_refresh(s_strip);
}

static uint8_t breathe_level(unsigned phase)
{
    /* 2.56-second triangle wave, level 2..32, no floating point. */
    unsigned triangular = (phase < 32U) ? phase : (64U - phase);
    return (uint8_t)(2U + (triangular * (PIBBI_RGB_PEAK - 2U)) / 32U);
}

static void rgb_task(void *arg)
{
    (void)arg;
    pibbi_rgb_mode_t mode = PIBBI_RGB_BOOT;
    unsigned phase = 0;
    while (true) {
        pibbi_rgb_mode_t next = PIBBI_RGB_BOOT;
        if (xQueueReceive(s_mode_queue, &next,
                          pdMS_TO_TICKS(PIBBI_RGB_STEP_MS)) == pdTRUE) {
            if (next != mode) {
                mode = next;
                phase = 0;
                ESP_LOGI(TAG, "RGB_MODE=%s",
                         mode == PIBBI_RGB_BOOT ? "BOOT" :
                         mode == PIBBI_RGB_READY ? "READY" : "ERROR");
            }
        }

        const uint8_t brightness = breathe_level(phase);
        esp_err_t err;
        switch (mode) {
        case PIBBI_RGB_BOOT:
            err = rgb_write(0, 0, brightness); /* breathing blue */
            break;
        case PIBBI_RGB_READY:
            err = rgb_write(0, brightness, 0); /* breathing green */
            break;
        case PIBBI_RGB_ERROR:
            err = rgb_write((phase < 16U || (phase >= 32U && phase < 48U)) ?
                                PIBBI_RGB_PEAK : 0U, 0, 0); /* red blink */
            break;
        default:
            err = ESP_ERR_INVALID_ARG;
            break;
        }
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "RMT RGB update failed: %s", esp_err_to_name(err));
            break; /* Avoid infinitely retrying a broken peripheral. */
        }
        phase = (phase + 1U) % PIBBI_RGB_PHASE_STEPS;
    }
    vTaskDelete(NULL);
}

esp_err_t pibbi_rgb_set_mode(pibbi_rgb_mode_t mode)
{
    if (s_mode_queue == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    if (mode != PIBBI_RGB_BOOT && mode != PIBBI_RGB_READY &&
        mode != PIBBI_RGB_ERROR) {
        return ESP_ERR_INVALID_ARG;
    }
    return xQueueOverwrite(s_mode_queue, &mode) == pdTRUE ?
           ESP_OK : ESP_FAIL;
}

esp_err_t pibbi_rgb_init(void)
{
    if (s_mode_queue != NULL) {
        return ESP_OK;
    }

    const led_strip_config_t strip = {
        .strip_gpio_num = PIBBI_RGB_GPIO,
        .max_leds = 1,
        .led_pixel_format = LED_PIXEL_FORMAT_GRB,
        /* Per Seeed's Watcher BSP, WS2812 timing works for WS2813-Mini. */
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
        ESP_LOGE(TAG, "GPIO40 LED driver failed: %s", esp_err_to_name(err));
        return err;
    }

    err = led_strip_clear(s_strip);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "GPIO40 clear failed: %s", esp_err_to_name(err));
        led_strip_del(s_strip);
        s_strip = NULL;
        return err;
    }

    s_mode_queue = xQueueCreate(1, sizeof(pibbi_rgb_mode_t));
    if (s_mode_queue == NULL) {
        led_strip_del(s_strip);
        s_strip = NULL;
        return ESP_ERR_NO_MEM;
    }

    if (xTaskCreate(rgb_task, "pibbi_rgb", PIBBI_RGB_TASK_STACK, NULL,
                    tskIDLE_PRIORITY + 1, NULL) != pdPASS) {
        vQueueDelete(s_mode_queue);
        s_mode_queue = NULL;
        led_strip_del(s_strip);
        s_strip = NULL;
        return ESP_ERR_NO_MEM;
    }

    ESP_LOGI(TAG, "RGB_READY GPIO40 low-brightness breathing task");
    return ESP_OK;
}
