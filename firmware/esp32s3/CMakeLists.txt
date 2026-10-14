cmake_minimum_required(VERSION 3.5)

# Match the Seeed factory project compiler options.
add_compile_options(-fdiagnostics-color=always -Wno-error=format= -Wno-format)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(pibbi_watcher)
