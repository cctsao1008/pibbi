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
#include <string.h>

#include "driver/gpio.h"
#include "driver/ledc.h"
#include "driver/spi_master.h"
#include "esp_err.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_spd2010.h"
#include "pibbi_power_ui.h"
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


/* Single caller: app_main. The panel and its DMA resources remain alive so
 * confirmation and return-to-home are safe without reinitializing SPI/QSPI. */
static esp_lcd_panel_handle_t s_panel = NULL;
static SemaphoreHandle_t s_color_done = NULL;
static uint16_t *s_stripe = NULL;
static pibbi_lcd_view_t s_view = PIBBI_LCD_HOME;

static const uint8_t *font_rows(char c)
{
    /* Fixed 5x7 glyphs for OFF, POWER OFF?, YES, NO. */
    static const uint8_t blank[7] = {0};
    static const uint8_t p[7] = {30,17,17,30,16,16,16};
    static const uint8_t o[7] = {14,17,17,17,17,17,14};
    static const uint8_t w[7] = {17,17,17,21,21,21,10};
    static const uint8_t e[7] = {31,16,16,30,16,16,31};
    static const uint8_t r[7] = {30,17,17,30,20,18,17};
    static const uint8_t f[7] = {31,16,16,30,16,16,16};
    static const uint8_t y[7] = {17,17,10,4,4,4,4};
    static const uint8_t s[7] = {15,16,16,14,1,1,30};
    static const uint8_t n[7] = {17,25,21,19,17,17,17};
    static const uint8_t q[7] = {14,17,1,6,4,0,4};
    switch (c) {
    case 'P': return p;
    case 'O': return o;
    case 'W': return w;
    case 'E': return e;
    case 'R': return r;
    case 'F': return f;
    case 'Y': return y;
    case 'S': return s;
    case 'N': return n;
    case '?': return q;
    default: return blank;
    }
}

static bool text_pixel(int x, int y, int left, int top,
                       const char *text, int scale)
{
    const int dx = x - left;
    const int dy = y - top;
    if (dx < 0 || dy < 0 || dy >= 7 * scale) {
        return false;
    }
    const size_t n = strlen(text);
    const int char_index = dx / (6 * scale);
    if (char_index < 0 || (size_t)char_index >= n) {
        return false;
    }
    const int column = (dx % (6 * scale)) / scale;
    if (column >= 5) {
        return false;
    }
    const uint8_t *glyph = font_rows(text[char_index]);
    return (glyph[dy / scale] & (1U << (4 - column))) != 0;
}

static bool inside(int x, int y, int x0, int y0, int x1, int y1)
{
    return x >= x0 && x < x1 && y >= y0 && y < y1;
}

static uint16_t pixel_color(int x, int y, pibbi_lcd_view_t view)
{
    if (view == PIBBI_LCD_CONFIRM_POWER_OFF) {
        if (text_pixel(x, y, 116, 101, "POWER OFF?", 3)) {
            return UINT16_C(0xFFFF);
        }
        if (inside(x, y, 25, 232, 194, 331)) {
            if (text_pixel(x, y, 73, 265, "YES", 4)) {
                return UINT16_C(0xFFFF);
            }
            return (x < 29 || x >= 190 || y < 236 || y >= 327)
                ? UINT16_C(0xF800) : UINT16_C(0x5000);
        }
        if (inside(x, y, 218, 232, 387, 331)) {
            if (text_pixel(x, y, 271, 265, "NO", 4)) {
                return UINT16_C(0xFFFF);
            }
            return (x < 222 || x >= 383 || y < 236 || y >= 327)
                ? UINT16_C(0xC618) : UINT16_C(0x18E3);
        }
        return UINT16_C(0x0000);
    }

    /* Existing diagnostic rings; OFF button overlays their lower edge. */
    if (pibbi_hit_home_off((unsigned)x, (unsigned)y)) {
        if (text_pixel(x, y, 170, 356, "OFF", 4)) {
            return UINT16_C(0xFFFF);
        }
        return (x < 126 || x >= 286 || y < 342 || y >= 398)
            ? UINT16_C(0xFFFF) : UINT16_C(0x2104);
    }
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

static esp_err_t draw_view(pibbi_lcd_view_t view)
{
    if (s_panel == NULL || s_stripe == NULL || s_color_done == NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    for (int y0 = 0; y0 < LCD_HEIGHT; y0 += LCD_STRIPE_HEIGHT) {
        const int y1 = (y0 + LCD_STRIPE_HEIGHT <= LCD_HEIGHT)
            ? y0 + LCD_STRIPE_HEIGHT : LCD_HEIGHT;
        for (int y = y0; y < y1; ++y) {
            for (int x = 0; x < LCD_WIDTH; ++x) {
                s_stripe[(y - y0) * LCD_WIDTH + x] = pixel_color(x, y, view);
            }
        }
        esp_err_t err = esp_lcd_panel_draw_bitmap(
            s_panel, 0, y0, LCD_WIDTH, y1, s_stripe);
        if (err != ESP_OK) {
            return err;
        }
        if (xSemaphoreTake(s_color_done, pdMS_TO_TICKS(2000)) != pdTRUE) {
            /* Never free/reuse the DMA buffer after an uncertain transfer. */
            return ESP_ERR_TIMEOUT;
        }
    }
    s_view = view;
    return ESP_OK;
}

esp_err_t pibbi_lcd_set_view(pibbi_lcd_view_t view)
{
    if (view != PIBBI_LCD_HOME && view != PIBBI_LCD_CONFIRM_POWER_OFF) {
        return ESP_ERR_INVALID_ARG;
    }
    if (s_panel == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    if (view == s_view) {
        return ESP_OK;
    }
    return draw_view(view);
}

esp_err_t pibbi_lcd_backlight_off(void)
{
    esp_err_t err = ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_1, 0);
    return err == ESP_OK ?
        ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_1) : err;
}

esp_err_t pibbi_lcd_backlight_on(void)
{
    return backlight_on();
}

esp_err_t pibbi_lcd_first_frame(void)
{
    if (s_panel != NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    esp_lcd_panel_io_handle_t panel_io = NULL;
    esp_lcd_panel_handle_t panel = NULL;
    esp_err_t err = backlight_init();
    if (err != ESP_OK) {
        return err;
    }
    err = spi3_qspi_init();
    if (err != ESP_OK) {
        return err;
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
    err = esp_lcd_new_panel_io_spi(
        (esp_lcd_spi_bus_handle_t)LCD_SPI_HOST, &io_cfg, &panel_io);
    if (err != ESP_OK) {
        return err;
    }

    spd2010_vendor_config_t vendor_cfg = {
        .flags = {.use_qspi_interface = 1},
    };
    const esp_lcd_panel_dev_config_t panel_cfg = {
        .reset_gpio_num = GPIO_NUM_NC,
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
        .bits_per_pixel = 16,
        .vendor_config = &vendor_cfg,
    };
    err = esp_lcd_new_panel_spd2010(panel_io, &panel_cfg, &panel);
    if (err != ESP_OK) {
        return err;
    }
    err = esp_lcd_panel_reset(panel);
    if (err != ESP_OK) {
        return err;
    }
    err = esp_lcd_panel_init(panel);
    if (err != ESP_OK) {
        return err;
    }
    err = esp_lcd_panel_mirror(panel, false, false);
    if (err != ESP_OK) {
        return err;
    }
    err = esp_lcd_panel_disp_on_off(panel, true);
    if (err != ESP_OK) {
        return err;
    }

    s_color_done = xSemaphoreCreateBinary();
    s_stripe = heap_caps_malloc(LCD_TRANSFER_BYTES,
                                MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA);
    if (s_color_done == NULL || s_stripe == NULL) {
        return ESP_ERR_NO_MEM;
    }
    const esp_lcd_panel_io_callbacks_t callbacks = {
        .on_color_trans_done = lcd_color_done,
    };
    err = esp_lcd_panel_io_register_event_callbacks(
        panel_io, &callbacks, s_color_done);
    if (err != ESP_OK) {
        return err;
    }

    s_panel = panel;
    err = draw_view(PIBBI_LCD_HOME);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "LCD first frame failed: %s", esp_err_to_name(err));
        return err;
    }
    err = backlight_on();
    if (err != ESP_OK) {
        return err;
    }
    ESP_LOGI(TAG, "UI first frame and OFF touch button displayed");
    return ESP_OK;
}
