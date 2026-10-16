/*
 * B1b: display one recognizable RGB565 first frame on Watcher SPD2010 QSPI,
 * without LVGL, UI assets, Wi-Fi, audio, or HX6538.
 *
 * Source pin: Seeed-Studio/SenseCAP-Watcher-Firmware
 * 8e37f7ccd3d836bb99f483e0f6e74e8252406644
 *
 * Minimal first-frame bring-up; hardware UI behavior not yet verified.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#include "driver/gpio.h"
#include "driver/ledc.h"
#include "driver/spi_master.h"
#include "esp_err.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_spd2010.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#define LCD_WIDTH            412
#define LCD_HEIGHT           412
#define LCD_STRIPE_HEIGHT     16
#define LCD_TRANSFER_BYTES  (LCD_WIDTH * LCD_STRIPE_HEIGHT * sizeof(uint16_t))
#define LCD_SPI_HOST         SPI3_HOST
#define LCD_PIN_CLK          GPIO_NUM_7
#define LCD_PIN_DATA0        GPIO_NUM_9
#define LCD_PIN_DATA1        GPIO_NUM_1
#define LCD_PIN_DATA2        GPIO_NUM_14
#define LCD_PIN_DATA3        GPIO_NUM_13
#define LCD_PIN_CS           GPIO_NUM_45
#define LCD_PIN_BACKLIGHT    GPIO_NUM_8

static const char *TAG = "pibbi_lcd";

/* The panel sends data asynchronously. Do not reuse the same DMA buffer
 * until the previous transfer has reported completion via this callback. */
static bool lcd_color_done(esp_lcd_panel_io_handle_t io,
                           esp_lcd_panel_io_event_data_t *data,
                           void *ctx)
{
    (void)io;
    (void)data;
    BaseType_t woken = pdFALSE;
    xSemaphoreGiveFromISR((SemaphoreHandle_t)ctx, &woken);
    return woken == pdTRUE;
}

static esp_err_t backlight_init(void)
{
    const ledc_timer_config_t timer = {
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .duty_resolution = LEDC_TIMER_10_BIT,
        .timer_num = LEDC_TIMER_1,
        .freq_hz = 5000,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    esp_err_t rc = ledc_timer_config(&timer);
    if (rc != ESP_OK) {
        return rc;
    }
    const ledc_channel_config_t channel = {
        .gpio_num = LCD_PIN_BACKLIGHT,
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel = LEDC_CHANNEL_1,
        .intr_type = LEDC_INTR_DISABLE,
        .timer_sel = LEDC_TIMER_1,
        .duty = 0,
        .hpoint = 0,
    };
    return ledc_channel_config(&channel);
}

static esp_err_t backlight_on(void)
{
    /* 35% is a first-frame engineering setting, not brightness calibration. */
    esp_err_t rc = ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_1, 358);
    if (rc != ESP_OK) {
        return rc;
    }
    return ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_1);
}

static esp_err_t spi3_qspi_init(void)
{
    const spi_bus_config_t bus = {
        .sclk_io_num = LCD_PIN_CLK,
        .data0_io_num = LCD_PIN_DATA0,
        .data1_io_num = LCD_PIN_DATA1,
        .data2_io_num = LCD_PIN_DATA2,
        .data3_io_num = LCD_PIN_DATA3,
        .max_transfer_sz = LCD_TRANSFER_BYTES + 64,
    };
    return spi_bus_initialize(LCD_SPI_HOST, &bus, SPI_DMA_CH_AUTO);
}

static uint16_t pixel_color(int x, int y)
{
    /* Minimal visual test pattern: dark background + three concentric rings.
     * RGB565 encoded. Avoid image assets/fonts/PSRAM in the critical path. */
    const int dx = x - LCD_WIDTH / 2;
    const int dy = y - LCD_HEIGHT / 2;
    const int radius2 = dx * dx + dy * dy;
    if (radius2 < 38 * 38) {
        return UINT16_C(0xFFFF);
    }
    if (radius2 < 86 * 86) {
        return UINT16_C(0x07E0);
    }
    if (radius2 < 126 * 126) {
        return UINT16_C(0x0410);
    }
    return UINT16_C(0x0000);
}

esp_err_t pibbi_lcd_first_frame(void)
{
    esp_lcd_panel_io_handle_t panel_io = NULL;
    esp_lcd_panel_handle_t panel = NULL;
    esp_err_t rc = backlight_init();
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "Backlight PWM init failed: %s", esp_err_to_name(rc));
        return rc;
    }
    rc = spi3_qspi_init();
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "SPI3 init failed: %s", esp_err_to_name(rc));
        return rc;
    }

    const esp_lcd_panel_io_spi_config_t io_cfg = {
        .cs_gpio_num = LCD_PIN_CS,
        .dc_gpio_num = -1,
        .spi_mode = 3,
        .pclk_hz = 40000000,
        .trans_queue_depth = 1,
        .lcd_cmd_bits = 32,
        .lcd_param_bits = 8,
        .flags = {.quad_mode = true},
    };
    rc = esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)LCD_SPI_HOST,
                                  &io_cfg, &panel_io);
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "Panel IO init failed: %s", esp_err_to_name(rc));
        return rc;
    }

    spd2010_vendor_config_t vendor_cfg = {
        .flags = {.use_qspi_interface = 1},
    };
    const esp_lcd_panel_dev_config_t panel_cfg = {
        .reset_gpio_num = GPIO_NUM_NC, /* shared touch reset, not wired */
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
        .bits_per_pixel = 16,
        .vendor_config = &vendor_cfg,
    };
    rc = esp_lcd_new_panel_spd2010(panel_io, &panel_cfg, &panel);
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "SPD2010 panel init failed: %s", esp_err_to_name(rc));
        return rc;
    }
    rc = esp_lcd_panel_reset(panel);
    if (rc != ESP_OK) {
        return rc;
    }
    rc = esp_lcd_panel_init(panel);
    if (rc != ESP_OK) {
        return rc;
    }
    rc = esp_lcd_panel_mirror(panel, false, false);
    if (rc != ESP_OK) {
        return rc;
    }
    rc = esp_lcd_panel_disp_on_off(panel, true);
    if (rc != ESP_OK) {
        return rc;
    }

    SemaphoreHandle_t color_done = xSemaphoreCreateBinary();
    if (color_done == NULL) {
        return ESP_ERR_NO_MEM;
    }
    const esp_lcd_panel_io_callbacks_t callbacks = {
        .on_color_trans_done = lcd_color_done,
    };
    rc = esp_lcd_panel_io_register_event_callbacks(panel_io, &callbacks, color_done);
    if (rc != ESP_OK) {
        vSemaphoreDelete(color_done);
        return rc;
    }

    uint16_t *stripe = heap_caps_malloc(LCD_TRANSFER_BYTES,
                                         MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA);
    if (stripe == NULL) {
        return ESP_ERR_NO_MEM;
    }

    /* SPD2010 requires 4-pixel horizontal alignment. x0=0, x1=412 both
     * meet the vendor driver contract. Last stripe has 12 rows. */
    for (int y0 = 0; y0 < LCD_HEIGHT; y0 += LCD_STRIPE_HEIGHT) {
        const int y1 = (y0 + LCD_STRIPE_HEIGHT <= LCD_HEIGHT)
            ? y0 + LCD_STRIPE_HEIGHT : LCD_HEIGHT;
        for (int y = y0; y < y1; ++y) {
            for (int x = 0; x < LCD_WIDTH; ++x) {
                stripe[(y - y0) * LCD_WIDTH + x] = pixel_color(x, y);
            }
        }
        rc = esp_lcd_panel_draw_bitmap(panel, 0, y0, LCD_WIDTH, y1, stripe);
        if (rc != ESP_OK) {
            break;
        }
        if (xSemaphoreTake(color_done, pdMS_TO_TICKS(2000)) != pdTRUE) {
            rc = ESP_ERR_TIMEOUT;
            break;
        }
    }

    /* On failure the DMA state might still be active: intentionally
     * retain the DMA allocation until reboot to avoid a use-after-free. */
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "LCD draw/transfer failed: %s", esp_err_to_name(rc));
        return rc;
    }

    heap_caps_free(stripe);
    vSemaphoreDelete(color_done);

    rc = backlight_on();
    if (rc != ESP_OK) {
        return rc;
    }
    ESP_LOGI(TAG, "UI first complete frame submitted and backlight enabled");
    return ESP_OK;
}
