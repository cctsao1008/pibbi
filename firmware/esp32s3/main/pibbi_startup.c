#include <stdint.h>
#include "esp_err.h"
#include "esp_log.h"
#include "app_sensor.h"
#include "pibbi_sensors.h"

static const char *TAG = "pibbi_startup";

/* Used by upstream main.c through its source-local compile definition.
 * The original Seeed app_sensor_init remains linked without modification. */
int16_t pibbi_app_sensor_init(void)
{
    int16_t result = app_sensor_init();
    if (result != ESP_OK) {
        return result;
    }

    esp_err_t err = pibbi_sensors_start();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Unable to start pibbi sensor service: %s",
                 esp_err_to_name(err));
    }
    return result;
}
