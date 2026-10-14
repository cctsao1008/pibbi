# Source-level component corrections, without changing original components.
# Replacing (not appending) prevents linking duplicate implementations.
function(pibbi_override_component_source component source_name replacement)
    if(NOT EXISTS "${replacement}")
        message(FATAL_ERROR "Missing generated source overlay: ${replacement}")
    endif()
    idf_component_get_property(lib "${component}" COMPONENT_LIB)
    if(NOT TARGET "${lib}")
        message(FATAL_ERROR "Missing ESP-IDF component: ${component}")
    endif()
    get_target_property(original "${lib}" SOURCES)
    get_target_property(comp_dir "${lib}" SOURCE_DIR)
    set(kept "")
    set(matches 0)
    foreach(item IN LISTS original)
        get_filename_component(basename "${item}" NAME)
        if(basename STREQUAL "${source_name}")
            math(EXPR matches "${matches}+1")
            if(IS_ABSOLUTE "${item}")
                set(old_path "${item}")
            else()
                set(old_path "${comp_dir}/${item}")
            endif()
            get_filename_component(old_parent "${old_path}" DIRECTORY)
        else()
            list(APPEND kept "${item}")
        endif()
    endforeach()
    if(NOT matches EQUAL 1)
        message(FATAL_ERROR "Expected exactly one ${component}/${source_name}; found ${matches}")
    endif()
    list(APPEND kept "${replacement}")
    set_property(TARGET "${lib}" PROPERTY SOURCES "${kept}")
    # Preserve relative include searches for private headers in the old source
    # directory, in addition to all existing component include directories.
    target_include_directories("${lib}" PRIVATE "${old_parent}")
    message(STATUS "pibbi patched component source: ${component}/${source_name}")
endfunction()

set(pibbi_comp_overlay "${CMAKE_CURRENT_LIST_DIR}/vendor_overlay/components")
pibbi_override_component_source(
    esp_lvgl_port esp_lvgl_port.c
    "${pibbi_comp_overlay}/esp_lvgl_port/esp_lvgl_port.c")
pibbi_override_component_source(
    sscma_client sscma_client_ops.c
    "${pibbi_comp_overlay}/sscma_client/sscma_client_ops.c")
pibbi_override_component_source(
    chmorgan__esp-audio-player audio_player.cpp
    "${pibbi_comp_overlay}/chmorgan__esp-audio-player/audio_player.cpp")
