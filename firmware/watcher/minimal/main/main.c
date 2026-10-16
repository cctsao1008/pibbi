/*
 * pibbi Watcher B1a: isolated ESP32-S3 boot / power-hold / input telemetry.
 *
 * Vendor reference (pins, masks, I/O-expander order):
 * Seeed-Studio/SenseCAP-Watcher-Firmware @
 * 8e37f7ccd3d836bb99f483e0f6e74e8252406644
 *
 * Hardware behavior still requires first-live UART/LCD verification.
 * Physical layout/backup already checked; B1b OTA1-only bring-up approved.
 */
#include <inttypes.h>
#include <stddef.h>
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

#ifdef PIBBI_LCD_PROBE
#include "pibbi_rgb.h"
#include "pibbi_power_ui.h"
#include "pibbi_behavior.h"
#include "pibbi_touch.h"
#endif

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

static esp_err_t pca9535_read16(uint8_t reg, uint16_t *out)
{
    if (out == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    uint8_t bytes[2] = {0};
    esp_err_t rc = i2c_master_write_read_device(
        WATCHER_I2C_PORT, WATCHER_PCA9535_ADDR, &reg, 1,
        bytes, sizeof(bytes), pdMS_TO_TICKS(50));
    if (rc == ESP_OK) {
        *out = (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
    }
    return rc;
}

static esp_err_t pca9535_read_input(uint16_t *out)
{
    return pca9535_read16(PCA9535_INPUT_REG, out);
}

static esp_err_t watcher_park_external_io(void)
{
    /*
     * The original bsp_i2c_bus_init() parks LCD/QSPI and touch pins LOW
     * before enabling power rails. Preserve this board-specific electrical
     * sequencing in B1a even though there is no LCD/touch driver yet.
     */
    const gpio_config_t config = {
        .pin_bit_mask = (1ULL << GPIO_NUM_39) | (1ULL << GPIO_NUM_38) |
                        (1ULL << GPIO_NUM_7) | (1ULL << GPIO_NUM_9) |
                        (1ULL << GPIO_NUM_1) | (1ULL << GPIO_NUM_14) |
                        (1ULL << GPIO_NUM_13) | (1ULL << GPIO_NUM_45) |
                        (1ULL << GPIO_NUM_8),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t rc = gpio_config(&config);
    if (rc != ESP_OK) {
        return rc;
    }
    const gpio_num_t pins[] = {
        GPIO_NUM_39, GPIO_NUM_38, GPIO_NUM_45, GPIO_NUM_8,
        GPIO_NUM_7, GPIO_NUM_9, GPIO_NUM_1, GPIO_NUM_14, GPIO_NUM_13
    };
    for (size_t i = 0; i < sizeof(pins) / sizeof(pins[0]); ++i) {
        rc = gpio_set_level(pins[i], 0);
        if (rc != ESP_OK) {
            return rc;
        }
    }
    return ESP_OK;
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

#ifdef PIBBI_LCD_PROBE
/* Both edge interrupts capture transitions while the main loop is blocked
 * on LCD DMA. The ISR never draws or calls the behavior engine. */
static portMUX_TYPE s_knob_mux = portMUX_INITIALIZER_UNLOCKED;
static volatile uint8_t s_knob_last_ab = 0;
static volatile int32_t s_knob_pending_edges = 0;
static bool s_knob_irq_ready = false;

static void watcher_knob_edge_isr(void *ctx)
{
    (void)ctx;
    const unsigned a = (unsigned)gpio_get_level(WATCHER_KNOB_A);
    const unsigned b = (unsigned)gpio_get_level(WATCHER_KNOB_B);
    const uint8_t current = (uint8_t)((a << 1) | b);
    portENTER_CRITICAL_ISR(&s_knob_mux);
    const uint8_t previous = s_knob_last_ab;
    s_knob_last_ab = current;
    const int delta = pibbi_quadrature_delta(
        (previous >> 1) & 1U, previous & 1U, a, b);
    if (delta > 0 && s_knob_pending_edges < INT32_MAX) {
        ++s_knob_pending_edges;
    } else if (delta < 0 && s_knob_pending_edges > INT32_MIN) {
        --s_knob_pending_edges;
    }
    portEXIT_CRITICAL_ISR(&s_knob_mux);
}

static int32_t watcher_knob_take_edges(void)
{
    portENTER_CRITICAL(&s_knob_mux);
    const int32_t edges = s_knob_pending_edges;
    s_knob_pending_edges = 0;
    portEXIT_CRITICAL(&s_knob_mux);
    return edges;
}
#endif

static esp_err_t watcher_knob_init(void)
{
    const gpio_config_t config = {
        .pin_bit_mask = (1ULL << WATCHER_KNOB_A) | (1ULL << WATCHER_KNOB_B),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
#ifdef PIBBI_LCD_PROBE
        .intr_type = GPIO_INTR_ANYEDGE,
#else
        .intr_type = GPIO_INTR_DISABLE,
#endif
    };
    esp_err_t err = gpio_config(&config);
    if (err != ESP_OK) {
        return err;
    }
#ifdef PIBBI_LCD_PROBE
    s_knob_last_ab = (uint8_t)(
        (gpio_get_level(WATCHER_KNOB_A) << 1) |
         gpio_get_level(WATCHER_KNOB_B));
    s_knob_pending_edges = 0;

    err = gpio_install_isr_service(0);
    if (err == ESP_OK || err == ESP_ERR_INVALID_STATE) {
        err = gpio_isr_handler_add(WATCHER_KNOB_A, watcher_knob_edge_isr, NULL);
        if (err == ESP_OK) {
            err = gpio_isr_handler_add(
                WATCHER_KNOB_B, watcher_knob_edge_isr, NULL);
            if (err != ESP_OK) {
                gpio_isr_handler_remove(WATCHER_KNOB_A);
            }
        }
        if (err == ESP_OK) {
            s_knob_irq_ready = true;
            ESP_LOGI(TAG, "KNOB_IRQ_READY GPIO41/42 any-edge");
            return ESP_OK;
        }
    }
    /* A driver allocation failure must not break Watcher power/display.
     * Retain legacy sampled inputs as a diagnosed fallback. */
    ESP_LOGW(TAG, "KNOB_IRQ_FAIL, using sampled fallback: %s",
             esp_err_to_name(err));
    (void)gpio_set_intr_type(WATCHER_KNOB_A, GPIO_INTR_DISABLE);
    (void)gpio_set_intr_type(WATCHER_KNOB_B, GPIO_INTR_DISABLE);
#endif
    return ESP_OK;
}


#ifdef PIBBI_LCD_PROBE
/* Touch-confirmed shutdown. Seeed BSP's bsp_system_shutdown() deasserts
 * expander P1.2 (BSP_PWR_SYSTEM); never modify the other power rails.
 * USB power can keep the ESP32-S3 alive even after system latch release. */
static esp_err_t watcher_touch_shutdown(void)
{
    ESP_LOGW(TAG, "SHUTDOWN_REQUESTED_BY_TOUCH");
    ESP_ERROR_CHECK_WITHOUT_ABORT(pibbi_rgb_set_mode(PIBBI_RGB_OFF));
    vTaskDelay(pdMS_TO_TICKS(80)); /* RGB task has time to turn LED dark. */
    ESP_ERROR_CHECK_WITHOUT_ABORT(pibbi_lcd_backlight_off());

    uint16_t current_outputs = 0;
    esp_err_t rc = pca9535_read16(PCA9535_OUTPUT_REG, &current_outputs);
    if (rc == ESP_OK) {
        ESP_LOGW(TAG, "SHUTDOWN_RELEASE_SYSTEM_POWER_HOLD P1.2");
        rc = pca9535_write16(PCA9535_OUTPUT_REG,
                             current_outputs & ~WATCHER_POWER_SYSTEM);
    }
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "Shutdown failed to release power latch: %s",
                 esp_err_to_name(rc));
        ESP_ERROR_CHECK_WITHOUT_ABORT(pibbi_rgb_set_mode(PIBBI_RGB_ERROR));
        ESP_ERROR_CHECK_WITHOUT_ABORT(pibbi_lcd_backlight_on());
        return rc;
    }

    /* Typically power disappears before reaching this point. With USB
     * attached, keep the visible UI dark and never reassert the latch. */
    ESP_LOGI(TAG, "SHUTDOWN_LATCH_RELEASED (USB may still supply power)");
    while (true) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
#endif

void app_main(void)
{
    app_entry_us = esp_timer_get_time();
    boot_mark("APP_ENTER");
#ifdef PIBBI_LCD_PROBE
    bool touch_ready = false;
    bool touch_was_down = false;
    bool touch_can_arm = false; /* First release arms the touch interface. */
    bool confirm_shutdown = false;
    unsigned touch_errors = 0;
    unsigned touch_recoveries = 0;
    bool behavior_ready = false;
    pibbi_behavior_t behavior = {0};
#endif

    /* Critical boot path: no LVGL, audio, Wi-Fi, BLE, cloud, OTA, or NPU. */
    ESP_ERROR_CHECK(watcher_park_external_io());
    boot_mark("EXTERNAL_IO_PARKED");
    ESP_ERROR_CHECK(watcher_i2c_init());
    boot_mark("I2C_READY");

    ESP_ERROR_CHECK(watcher_power_init());
#ifdef PIBBI_LCD_PROBE
    /* Independent RGB task runs while the LCD is initialized. */
    esp_err_t rgb_rc = pibbi_rgb_init();
    if (rgb_rc == ESP_OK) {
        boot_mark("RGB_READY");
    } else {
        ESP_LOGW(TAG, "RGB indicator unavailable: %s", esp_err_to_name(rgb_rc));
        boot_mark("RGB_FAIL");
    }
#endif
    ESP_ERROR_CHECK(watcher_knob_init());
    boot_mark("LOCAL_READY");
#ifdef PIBBI_LCD_PROBE
    boot_mark("LCD_INIT_START");
    esp_err_t lcd_rc = pibbi_lcd_first_frame();
    if (lcd_rc == ESP_OK) {
        boot_mark("UI_READY");
        pibbi_behavior_init(&behavior, (uint64_t)(esp_timer_get_time() / 1000));
        behavior_ready = true;
        boot_mark("BEHAVIOR_READY");
        if (rgb_rc == ESP_OK) {
            ESP_ERROR_CHECK_WITHOUT_ABORT(pibbi_rgb_set_mode(PIBBI_RGB_READY));
        }
        esp_err_t touch_rc = pibbi_touch_init();
        if (touch_rc == ESP_OK) {
            touch_ready = true;
            boot_mark("TOUCH_READY");
        } else {
            ESP_LOGW(TAG, "Touch unavailable: %s", esp_err_to_name(touch_rc));
            boot_mark("TOUCH_FAIL");
        }
    } else {
        ESP_LOGE(TAG, "B1b LCD first frame failed: %s", esp_err_to_name(lcd_rc));
        boot_mark("UI_FAIL");
        if (rgb_rc == ESP_OK) {
            ESP_ERROR_CHECK_WITHOUT_ABORT(pibbi_rgb_set_mode(PIBBI_RGB_ERROR));
        }
    }
#else
    ESP_LOGW(TAG, "B1a is UART + power/input only, NOT a display-ready firmware");
#endif

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
#ifdef PIBBI_LCD_PROBE
        pibbi_behavior_event_t behavior_event = PIBBI_EVENT_NONE;
#endif
        const int a = gpio_get_level(WATCHER_KNOB_A);
        const int b = gpio_get_level(WATCHER_KNOB_B);
        if (a != old_a || b != old_b) {
            ESP_LOGI(TAG, "INPUT raw_knob_a=%d raw_knob_b=%d", a, b);
#ifdef PIBBI_LCD_PROBE
            if (!s_knob_irq_ready) {
                const int qdelta = pibbi_quadrature_delta(
                    (unsigned)old_a, (unsigned)old_b, (unsigned)a, (unsigned)b);
                behavior_event = qdelta > 0 ? PIBBI_EVENT_KNOB_RIGHT :
                                 qdelta < 0 ? PIBBI_EVENT_KNOB_LEFT :
                                              PIBBI_EVENT_KNOB_ACTIVITY;
            }
#endif
            old_a = a;
            old_b = b;
        }
#ifdef PIBBI_LCD_PROBE
        if (s_knob_irq_ready) {
            const int32_t edges = watcher_knob_take_edges();
            if (edges != 0) {
                ESP_LOGI(TAG, "INPUT encoder_edges=%" PRId32, edges);
                behavior_event = edges > 0 ? PIBBI_EVENT_KNOB_RIGHT :
                                             PIBBI_EVENT_KNOB_LEFT;
            }
        }
#endif

        if (pca9535_read_input(&raw) == ESP_OK) {
            const int button = (raw & WATCHER_KNOB_BUTTON_BIT) != 0;
            if (button != old_button) {
                ESP_LOGI(TAG, "INPUT raw_knob_button=%d", button);
#ifdef PIBBI_LCD_PROBE
                if (!button) { /* PCA9535 P0.3 is active low. */
                    behavior_event = PIBBI_EVENT_BUTTON;
                }
#endif
                old_button = button;
            }
        }

#ifdef PIBBI_LCD_PROBE
        if (touch_ready) {
            bool down = false;
            uint16_t x = 0, y = 0;
            const esp_err_t touch_rc = pibbi_touch_poll(&down, &x, &y);
            if (touch_rc != ESP_OK) {
                if ((touch_errors++ % 50U) == 0U) {
                    ESP_LOGW(TAG, "Touch sample error: %s",
                             esp_err_to_name(touch_rc));
                }
                /* A failed read must never count as a release or tap. */
                touch_can_arm = false;
            } else {
                if (touch_errors != 0U) {
                    ++touch_recoveries;
                    if (touch_recoveries <= 3U ||
                        (touch_recoveries % 50U) == 0U) {
                        ESP_LOGI(TAG,
                                 "TOUCH_RECOVERED after %u failed polls",
                                 touch_errors);
                    }
                }
                touch_errors = 0;
                if (!down) {
                    touch_can_arm = true;
                } else if (touch_can_arm && !touch_was_down) {
                    if (!confirm_shutdown &&
                        pibbi_hit_home_off(x, y)) {
                        ESP_LOGI(TAG, "TOUCH_OFF_BUTTON x=%u y=%u", x, y);
                        if (pibbi_lcd_set_view(PIBBI_LCD_CONFIRM_POWER_OFF)
                            == ESP_OK) {
                            confirm_shutdown = true;
                            ESP_LOGI(TAG, "SHUTDOWN_CONFIRM_SHOWN");
                        }
                    } else if (confirm_shutdown &&
                               pibbi_hit_confirm_no(x, y)) {
                        if (pibbi_lcd_set_view(PIBBI_LCD_HOME) == ESP_OK) {
                            confirm_shutdown = false;
                            /* Cancel is still a human interaction; do not
                             * immediately enter Rest after a long prompt. */
                            behavior_event = PIBBI_EVENT_TOUCH;
                            ESP_LOGI(TAG, "SHUTDOWN_CANCELLED");
                        }
                    } else if (confirm_shutdown &&
                               pibbi_hit_confirm_yes(x, y)) {
                        ESP_LOGI(TAG, "TOUCH_CONFIRM_YES x=%u y=%u", x, y);
                        esp_err_t rc = watcher_touch_shutdown();
                        ESP_LOGE(TAG, "SHUTDOWN_FAILED %s",
                                 esp_err_to_name(rc));
                    } else if (!confirm_shutdown) {
                        ESP_LOGI(TAG, "INPUT face_touch x=%u y=%u",
                                 (unsigned)x, (unsigned)y);
                        behavior_event = PIBBI_EVENT_TOUCH; /* face tap */
                    }
                }
                touch_was_down = down;
            }
        }
#endif

#ifdef PIBBI_LCD_PROBE
        if (behavior_ready && !confirm_shutdown &&
            pibbi_behavior_step(&behavior,
                                (uint64_t)(esp_timer_get_time() / 1000),
                                behavior_event)) {
            esp_err_t draw_rc = pibbi_lcd_set_face(behavior.pose);
            if (draw_rc != ESP_OK) {
                ESP_LOGE(TAG, "FACE_RENDER_FAIL: %s", esp_err_to_name(draw_rc));
                /* Disable repeated attempts on an unhealthy display DMA. */
                behavior_ready = false;
            }
        }
#endif

        const int64_t now_us = esp_timer_get_time();
        if (now_us >= next_heartbeat_us) {
            boot_mark("HEARTBEAT");
            next_heartbeat_us = now_us + 5000000;
        }
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}
