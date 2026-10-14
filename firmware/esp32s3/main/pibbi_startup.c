#include <stdint.h>
#include "esp_err.h"
#include "esp_log.h"
#include "app_sensor.h"
#include "pibbi_sensors.h"
#include "pibbi_face.h"
#include "esp_lvgl_port.h"
#include "ui/ui.h"

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
    /*
     * view_init() ran before app_init(), so the SquareLine home screen
     * already exists. The face attaches as a child without touching vendor
     * source or taking ownership of the normal Watcher page manager.
     */
    lvgl_port_lock(0);
    bool face_ready = pibbi_face_attach(ui_Page_Home);
    lvgl_port_unlock();
    if (!face_ready) {
        ESP_LOGE(TAG, "Unable to attach pibbi face");
    }
    return result;
}
