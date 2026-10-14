idf_component_register(
    SRCS "pibbi_sensors.c"
    INCLUDE_DIRS "include"
    REQUIRES sensecap-watcher esp_event esp_timer driver
)
