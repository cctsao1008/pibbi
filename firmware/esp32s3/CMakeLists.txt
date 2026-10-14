cmake_minimum_required(VERSION 3.5)

# Match the Seeed factory project compiler options.
add_compile_options(-fdiagnostics-color=always -Wno-error=format= -Wno-format)

# esp-sr v1.7.1 runs COMMAND python when packing speech-recognition models.
# CMake resolves an IMPORTED executable target with that name to its absolute
# location, avoiding Windows cmd.exe PATH/alias resolution differences.
# Register it before project(), while downstream components are configured.
if(CMAKE_HOST_WIN32)
    if(NOT DEFINED ENV{IDF_PYTHON_ENV_PATH})
        message(FATAL_ERROR "IDF_PYTHON_ENV_PATH is required for the ESP-SR Python tool")
    endif()
    file(TO_CMAKE_PATH "$ENV{IDF_PYTHON_ENV_PATH}/Scripts/python.exe" PIBBI_IDF_PYTHON)
    if(NOT EXISTS "${PIBBI_IDF_PYTHON}")
        message(FATAL_ERROR "ESP-IDF Python not found: ${PIBBI_IDF_PYTHON}")
    endif()
    add_executable(python IMPORTED GLOBAL)
    set_target_properties(python PROPERTIES IMPORTED_LOCATION "${PIBBI_IDF_PYTHON}")
endif()

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(pibbi_watcher)

# Compile selected external sources from pibbi-owned corrected copies.
include("${CMAKE_CURRENT_LIST_DIR}/pibbi_component_overlays.cmake")
