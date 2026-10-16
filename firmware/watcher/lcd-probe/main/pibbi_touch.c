/*
 * Watcher SPD2010 capacitive touch: I2C1 SDA GPIO39, SCL GPIO38.
 * Follows Seeed bsp_touch_indev_init() at pinned firmware source revision.
 * No LVGL, no background task: app_main samples every 50 ms.
 */
#include <stdbool.h>
#include <stdint.h>

#include "driver/gpio.h"
#include "driver/i2c.h"
#include "esp_err.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_touch.h"
#include "esp_lcd_touch_spd2010.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "pibbi_touch.h"
#include "pibbi_power_ui.h"

#define WATCHER_TOUCH_BUS  I2C_NUM_1
#define WATCHER_TOUCH_SDA  GPIO_NUM_39
#define WATCHER_TOUCH_SCL  GPIO_NUM_38

static const char *TAG = "pibbi_touch";
static esp_lcd_touch_handle_t s_touch = NULL;
static esp_lcd_panel_io_handle_t s_touch_io = NULL;

esp_err_t pibbi_touch_init(void)
{
    if (s_touch != NULL) {
        return ESP_OK;
    }

    const i2c_config_t cfg = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = WATCHER_TOUCH_SDA,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_io_num = WATCHER_TOUCH_SCL,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = 400000,
    };
    esp_err_t err = i2c_param_config(WATCHER_TOUCH_BUS, &cfg);
    if (err != ESP_OK) {
        return err;
    }
    err = i2c_driver_install(WATCHER_TOUCH_BUS, I2C_MODE_MASTER, 0, 0,
                             ESP_INTR_FLAG_SHARED);
    if (err != ESP_OK) {
        return err;
    }

    const esp_lcd_touch_config_t touch_cfg = {
        .x_max = PIBBI_LCD_W,
        .y_max = PIBBI_LCD_H,
        .rst_gpio_num = GPIO_NUM_NC, /* Shared reset with LCD */
        .int_gpio_num = GPIO_NUM_NC, /* Poll, no interrupt needed */
        .levels = { .reset = 0, .interrupt = 0 },
        .flags = { .swap_xy = 0, .mirror_x = 0, .mirror_y = 0 },
    };
    const esp_lcd_panel_io_i2c_config_t io_cfg =
        ESP_LCD_TOUCH_IO_I2C_SPD2010_CONFIG();
    err = esp_lcd_new_panel_io_i2c(WATCHER_TOUCH_BUS, &io_cfg, &s_touch_io);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Touch panel I2C IO creation failed: %s",
                 esp_err_to_name(err));
        return err;
    }
    err = esp_lcd_touch_new_i2c_spd2010(s_touch_io, &touch_cfg, &s_touch);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "SPD2010 touch driver failed: %s",
                 esp_err_to_name(err));
        return err;
    }

    /* Vendor BSP requires an initial read and settling time. */
    vTaskDelay(pdMS_TO_TICKS(50));
    err = esp_lcd_touch_read_data(s_touch);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "First touch read failed: %s", esp_err_to_name(err));
        return err;
    }
    vTaskDelay(pdMS_TO_TICKS(100));
    ESP_LOGI(TAG, "TOUCH_READY I2C1 GPIO39/38 412x412");
    return ESP_OK;
}

esp_err_t pibbi_touch_poll(bool *down, uint16_t *x, uint16_t *y)
{
    if (s_touch == NULL || down == NULL || x == NULL || y == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    *down = false;
    *x = 0;
    *y = 0;
    esp_err_t err = esp_lcd_touch_read_data(s_touch);
    if (err != ESP_OK) {
        return err;
    }
    uint16_t xs[1] = {0}, ys[1] = {0}, strength[1] = {0};
    uint8_t count = 0;
    const bool pressed = esp_lcd_touch_get_coordinates(
        s_touch, xs, ys, strength, &count, 1);
    if (pressed && count > 0 &&
        xs[0] < PIBBI_LCD_W && ys[0] < PIBBI_LCD_H) {
        *down = true;
        *x = xs[0];
        *y = ys[0];
    }
    return ESP_OK;
}
