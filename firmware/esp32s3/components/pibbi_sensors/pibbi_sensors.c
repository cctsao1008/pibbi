#include <stddef.h>

#include "pibbi_sensors.h"

#include "driver/i2c.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define PIBBI_SENSOR_POLL_MS   30000
#define PIBBI_SENSOR_TASK_STACK 3072

/* Watcher BSP: the general-purpose I2C bus is I2C_NUM_0 on GPIO47/48.
 * Avoid including sensecap-watcher.h: its umbrella header brings unrelated
 * component headers into pibbi_sensors' compilation requirements. */
#define PIBBI_WATCHER_I2C_NUM I2C_NUM_0

/* Both functions are implemented by the upstream sensecap-watcher BSP.
 * bsp_i2c_check is not declared in the vendor's public header. */
extern esp_err_t bsp_i2c_bus_init(void);
extern esp_err_t bsp_i2c_check(i2c_port_t i2c_num, uint8_t address);

ESP_EVENT_DEFINE_BASE(PIBBI_SENSOR_EVENTS);

static const char *TAG = "pibbi_sensors";

static const struct {
    const char *name;
    uint8_t address;
    pibbi_sensor_id_t id;
} s_sensors[] = {
    { "ICM-20948", 0x68, PIBBI_SENSOR_ICM20948 },
    { "BME280",    0x76, PIBBI_SENSOR_BME280 },
    { "TSL25911",  0x29, PIBBI_SENSOR_TSL25911 },
    { "LTR390",    0x53, PIBBI_SENSOR_LTR390 },
    { "SGP40",     0x59, PIBBI_SENSOR_SGP40 },
};

static portMUX_TYPE s_state_lock = portMUX_INITIALIZER_UNLOCKED;
static pibbi_sensor_presence_t s_latest;
static bool s_started;

bool pibbi_sensors_get_presence(pibbi_sensor_presence_t *out)
{
    if (out == NULL) {
        return false;
    }
    portENTER_CRITICAL(&s_state_lock);
    *out = s_latest;
    portEXIT_CRITICAL(&s_state_lock);
    return out->generation != 0;
}

static void pibbi_sensor_task(void *arg)
{
    (void)arg;

    if (bsp_i2c_bus_init() != ESP_OK) {
        ESP_LOGE(TAG, "Watcher I2C bus initialization failed");
        vTaskDelete(NULL);
        return;
    }

    for (;;) {
        uint32_t mask = 0;
        for (size_t i = 0; i < sizeof(s_sensors) / sizeof(s_sensors[0]); ++i) {
            if (bsp_i2c_check(PIBBI_WATCHER_I2C_NUM, s_sensors[i].address) == ESP_OK) {
                mask |= PIBBI_SENSOR_PRESENT(s_sensors[i].id);
            }
        }

        const int64_t now_us = esp_timer_get_time();
        pibbi_sensor_presence_t snapshot;
        bool changed;

        portENTER_CRITICAL(&s_state_lock);
        changed = (s_latest.generation == 0 || s_latest.present_mask != mask);
        s_latest.present_mask = mask;
        s_latest.timestamp_us = now_us;
        ++s_latest.generation;
        snapshot = s_latest;
        portEXIT_CRITICAL(&s_state_lock);

        if (changed) {
            for (size_t i = 0; i < sizeof(s_sensors) / sizeof(s_sensors[0]); ++i) {
                ESP_LOGI(TAG, "%s (0x%02x): %s",
                         s_sensors[i].name, s_sensors[i].address,
                         (mask & PIBBI_SENSOR_PRESENT(s_sensors[i].id))
                             ? "present" : "absent");
            }

            esp_err_t err = esp_event_post(
                PIBBI_SENSOR_EVENTS, PIBBI_SENSOR_PRESENCE_CHANGED,
                &snapshot, sizeof(snapshot), pdMS_TO_TICKS(100));
            if (err != ESP_OK) {
                ESP_LOGW(TAG, "Could not publish sensor inventory: %s",
                         esp_err_to_name(err));
            }
        }

        vTaskDelay(pdMS_TO_TICKS(PIBBI_SENSOR_POLL_MS));
    }
}

esp_err_t pibbi_sensors_start(void)
{
    if (s_started) {
        return ESP_OK;
    }
    BaseType_t result = xTaskCreate(
        pibbi_sensor_task, "pibbi_sensors",
        PIBBI_SENSOR_TASK_STACK, NULL, tskIDLE_PRIORITY + 1, NULL);
    if (result != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    s_started = true;
    return ESP_OK;
}
