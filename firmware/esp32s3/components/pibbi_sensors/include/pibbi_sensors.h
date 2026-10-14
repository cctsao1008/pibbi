#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
#include "esp_event.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    PIBBI_SENSOR_ICM20948 = 0,  /* 9-axis IMU */
    PIBBI_SENSOR_BME280   = 1,  /* temperature, humidity, pressure */
    PIBBI_SENSOR_TSL25911 = 2,  /* visible / infrared light */
    PIBBI_SENSOR_LTR390   = 3,  /* UV / ambient light */
    PIBBI_SENSOR_SGP40    = 4,  /* VOC raw readings */
} pibbi_sensor_id_t;

#define PIBBI_SENSOR_PRESENT(id) (1U << (id))

typedef struct {
    uint32_t generation;       /* increments on every discovery scan */
    int64_t timestamp_us;      /* monotonic ESP32 clock */
    uint32_t present_mask;     /* bit i corresponds to pibbi_sensor_id_t */
} pibbi_sensor_presence_t;

ESP_EVENT_DECLARE_BASE(PIBBI_SENSOR_EVENTS);

typedef enum {
    PIBBI_SENSOR_PRESENCE_CHANGED = 1,
} pibbi_sensor_event_id_t;

/* Starts an asynchronous inventory of Waveshare Environment Sensor HAT
 * endpoints on the existing Watcher I2C bus. Measurements are not yet read. */
esp_err_t pibbi_sensors_start(void);

/* Returns false until the first inventory scan has completed. */
bool pibbi_sensors_get_presence(pibbi_sensor_presence_t *out);

#ifdef __cplusplus
}
#endif
