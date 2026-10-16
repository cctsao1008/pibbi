# Share the existing proven B1a power/knob/bootstrap source without copying.
# Only B1b compiles the optional LCD hook.
set(PIBBI_B1A_SOURCE "${CMAKE_CURRENT_LIST_DIR}/../../minimal/main/main.c")
idf_component_register(
    SRCS "${PIBBI_B1A_SOURCE}" "lcd_first_frame.c" "pibbi_rgb.c"
    INCLUDE_DIRS "."
    REQUIRES driver esp_timer esp_lcd
)
target_compile_definitions(${COMPONENT_LIB} PRIVATE PIBBI_LCD_PROBE=1)
