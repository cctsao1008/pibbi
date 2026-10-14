# Reuse upstream Seeed sources without editing the vendor checkout.
get_filename_component(PIBBI_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(WATCHER_FACTORY "${PIBBI_ROOT}/third_party/SenseCAP-Watcher-Firmware/examples/factory_firmware")
# The build wrapper creates an ignored corrected copy of upstream sources.
# Original third_party/ checkouts are never modified.
set(WATCHER_MAIN "${PIBBI_ROOT}/firmware/esp32s3/vendor_overlay/main")
if(NOT EXISTS "${WATCHER_MAIN}/main.c")
    message(FATAL_ERROR "pibbi vendor overlay missing: run tools/esp32s3/build.ps1")
endif()

set(APP_DIR "${WATCHER_MAIN}/app")
file(GLOB_RECURSE APP_SRCS "${APP_DIR}/*.c")
set(SENSOR_DIR "${WATCHER_MAIN}/sensor")
file(GLOB_RECURSE SENSOR_SRCS "${SENSOR_DIR}/*.c")
set(VIEW_DIR "${WATCHER_MAIN}/view")
file(GLOB_RECURSE VIEW_SRCS "${VIEW_DIR}/*.c")
set(UTIL_DIR "${WATCHER_MAIN}/util")
file(GLOB_RECURSE UTIL_SRCS "${UTIL_DIR}/*.c")
set(TASK_FLOW_ENGINE_DIR "${WATCHER_MAIN}/task_flow_engine")
file(GLOB_RECURSE TASK_FLOW_ENGINE_SRCS "${TASK_FLOW_ENGINE_DIR}/src/*.c")
set(TASK_FLOW_MODULE_DIR "${WATCHER_MAIN}/task_flow_module")
file(GLOB_RECURSE TASK_FLOW_MODULE_SRCS "${TASK_FLOW_MODULE_DIR}/*.c")

idf_component_register(
    SRCS
        "${WATCHER_MAIN}/main.c"
        ${APP_SRCS}
        ${SENSOR_SRCS}
        ${VIEW_SRCS}
        ${UTIL_SRCS}
        ${TASK_FLOW_ENGINE_SRCS}
        ${TASK_FLOW_MODULE_SRCS}
        "pibbi_startup.c"
    REQUIRES pibbi_face
    INCLUDE_DIRS
        "."
        "${WATCHER_MAIN}"
        "${APP_DIR}"
        "${SENSOR_DIR}"
        "${VIEW_DIR}"
        "${UTIL_DIR}"
        "${TASK_FLOW_ENGINE_DIR}/include"
        "${TASK_FLOW_MODULE_DIR}"
        "${TASK_FLOW_MODULE_DIR}/common"
)

# Redirect just the app_sensor_init call in upstream main.c to our
# wrapper. The original app_sensor.c stays untouched and still links.
set_source_files_properties("${WATCHER_MAIN}/main.c" PROPERTIES
    COMPILE_DEFINITIONS "app_sensor_init=pibbi_app_sensor_init"
)

if (CONFIG_ENABLE_FACTORY_FW_DEBUG_LOG)
    target_compile_definitions(${COMPONENT_LIB} PUBLIC "-DLOG_LOCAL_LEVEL=ESP_LOG_DEBUG")
endif()

spiffs_create_partition_image(storage "${WATCHER_FACTORY}/spiffs" FLASH_IN_PROJECT)
