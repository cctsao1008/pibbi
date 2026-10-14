/*
 * pibbi Watcher B1a: isolated ESP32-S3 boot / power-hold / input telemetry.
 *
 * Vendor reference (pins, masks, I/O-expander order):
 * Seeed-Studio/SenseCAP-Watcher-Firmware @
 * 8e37f7ccd3d836bb99f483e0f6e74e8252406644
 *
 * DESIGN / BUILD ONLY: not tested on physical Watcher; do not flash
 * until actual partitions, factory backup, and recovery have been verified.
 */
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>

#include "driver/gpio.h"
#include "driver/i2c.h"
#include "esp_err.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define WATCHER_I2C_PORT          I2C_NUM_0
#define WATCHER_I2C_SDA           GPIO_NUM_47
#define WATCHER_I2C_SCL           GPIO_NUM_48
#define WATCHER_I2C_HZ            400000
#define WATCHER_PCA9535_ADDR      0x21

#define PCA9535_INPUT_REG         0x00
#define PCA9535_OUTPUT_REG        0x02
#define PCA9535_DIRECTION_REG     0x06

/* Original Watcher BSP: input P0.0..7 and P1.5; other P1 pins output. */
#define WATCHER_INPUT_MASK        UINT16_C(0x20FF)
#define WATCHER_OUTPUT_MASK       UINT16_C(0xDF00)
#define WATCHER_POWER_SYSTEM      UINT16_C(0x0400)  /* P1.2 */
#define WATCHER_POWER_STARTUP     UINT16_C(0xDF00)  /* original BSP */
#define WATCHER_KNOB_BUTTON_BIT   UINT16_C(0x0008)  /* P0.3 */

/* Quadrature channels wired directly to ESP32-S3, not the expander. */
#define WATCHER_KNOB_A            GPIO_NUM_41
#define WATCHER_KNOB_B            GPIO_NUM_42

static const char *TAG = "pibbi";
static int64_t app_entry_us = 0;

static void boot_mark(const char *stage)
{
    const int64_t now_us = esp_timer_get_time();
    ESP_LOGI(TAG, "BOOT_MARK stage=%s boot_us=%" PRId64 " app_elapsed_us=%" PRId64,
             stage, now_us, now_us - app_entry_us);
}

static esp_err_t pca9535_write16(uint8_t reg, uint16_t data)
{
    const uint8_t wire[3] = {reg, (uint8_t)data, (uint8_t)(data >> 8)};
    esp_err_t rc = ESP_FAIL;
    for (int attempt = 0; attempt != 3; ++attempt) {
        rc = i2c_master_write_to_device(
            WATCHER_I2C_PORT, WATCHER_PCA9535_ADDR, wire, sizeof(wire),
            pdMS_TO_TICKS(50));
        if (rc == ESP_OK) {
            return ESP_OK;
        }
        vTaskDelay(pdMS_TO_TICKS(5));
    }
    ESP_LOGE(TAG, "PCA9535 reg=0x%02x write failed: %s",
             reg, esp_err_to_name(rc));
    return rc;
}

static esp_err_t pca9535_read_input(uint16_t *out)
{
    if (out == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    const uint8_t reg = PCA9535_INPUT_REG;
    uint8_t bytes[2] = {0};
    esp_err_t rc = i2c_master_write_read_device(
        WATCHER_I2C_PORT, WATCHER_PCA9535_ADDR, &reg, 1,
        bytes, sizeof(bytes), pdMS_TO_TICKS(50));
    if (rc == ESP_OK) {
        *out = (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
    }
    return rc;
}

static esp_err_t watcher_i2c_init(void)
{
    const i2c_config_t config = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = WATCHER_I2C_SDA,
        .scl_io_num = WATCHER_I2C_SCL,
        .sda_pullup_en = GPIO_PULLUP_DISABLE,
        .scl_pullup_en = GPIO_PULLUP_DISABLE,
        .master.clk_speed = WATCHER_I2C_HZ,
    };
    esp_err_t rc = i2c_param_config(WATCHER_I2C_PORT, &config);
    if (rc != ESP_OK) {
        return rc;
    }
    return i2c_driver_install(WATCHER_I2C_PORT, I2C_MODE_MASTER, 0, 0, 0);
}

static esp_err_t watcher_power_init(void)
{
    /*
     * Deliberately mirrors the original BSP's direction/output sequence.
     * Do not "optimize" a board-wide power latch before bench verification.
     */
    esp_err_t rc = pca9535_write16(PCA9535_DIRECTION_REG, WATCHER_INPUT_MASK);
    if (rc != ESP_OK) {
        return rc;
    }
    rc = pca9535_write16(PCA9535_OUTPUT_REG, 0);
    if (rc != ESP_OK) {
        return rc;
    }
    rc = pca9535_write16(PCA9535_OUTPUT_REG, WATCHER_POWER_SYSTEM);
    if (rc != ESP_OK) {
        return rc;
    }
    boot_mark("POWER_HOLD");
    vTaskDelay(pdMS_TO_TICKS(100));

    rc = pca9535_write16(PCA9535_OUTPUT_REG, WATCHER_POWER_STARTUP);
    if (rc != ESP_OK) {
        return rc;
    }
    vTaskDelay(pdMS_TO_TICKS(50));
    boot_mark("POWER_PERIPHERALS");
    return ESP_OK;
}

static esp_err_t watcher_knob_init(void)
{
    const gpio_config_t config = {
        .pin_bit_mask = (1ULL << WATCHER_KNOB_A) | (1ULL << WATCHER_KNOB_B),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    return gpio_config(&config);
}

void app_main(void)
{
    app_entry_us = esp_timer_get_time();
    boot_mark("APP_ENTER");

    /* Critical boot path: no LVGL, audio, Wi-Fi, BLE, cloud, OTA, or NPU. */
    ESP_ERROR_CHECK(watcher_i2c_init());
    boot_mark("I2C_READY");

    ESP_ERROR_CHECK(watcher_power_init());
    ESP_ERROR_CHECK(watcher_knob_init());
    boot_mark("LOCAL_READY");
    ESP_LOGW(TAG, "B1a is UART + power/input only, NOT a display-ready firmware");

    uint16_t raw = 0;
    esp_err_t read_rc = pca9535_read_input(&raw);
    if (read_rc != ESP_OK) {
        ESP_LOGW(TAG, "initial PCA9535 input read failed: %s",
                 esp_err_to_name(read_rc));
    }

    int old_a = gpio_get_level(WATCHER_KNOB_A);
    int old_b = gpio_get_level(WATCHER_KNOB_B);
    int old_button = (read_rc == ESP_OK)
        ? ((raw & WATCHER_KNOB_BUTTON_BIT) != 0) : -1;
    int64_t next_heartbeat_us = esp_timer_get_time() + 5000000;

    while (true) {
        const int a = gpio_get_level(WATCHER_KNOB_A);
        const int b = gpio_get_level(WATCHER_KNOB_B);
        if (a != old_a || b != old_b) {
            ESP_LOGI(TAG, "INPUT raw_knob_a=%d raw_knob_b=%d", a, b);
            old_a = a;
            old_b = b;
        }

        if (pca9535_read_input(&raw) == ESP_OK) {
            const int button = (raw & WATCHER_KNOB_BUTTON_BIT) != 0;
            if (button != old_button) {
                ESP_LOGI(TAG, "INPUT raw_knob_button=%d", button);
                old_button = button;
            }
        }

        const int64_t now_us = esp_timer_get_time();
        if (now_us >= next_heartbeat_us) {
            boot_mark("HEARTBEAT");
            next_heartbeat_us = now_us + 5000000;
        }
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}
