cmake_minimum_required(VERSION 3.27)

project(qmlrice-glass
    DESCRIPTION "Liquid-glass render effect for selected layer-shell surfaces"
    VERSION 0.1
)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Shaders are compiled into the plugin so the .so is self-contained.
set(GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/gen")
add_custom_command(
    OUTPUT "${GEN_DIR}/shaders_embedded.hpp"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${GEN_DIR}"
    COMMAND ${CMAKE_COMMAND}
        -DOUT=${GEN_DIR}/shaders_embedded.hpp
        -DGLASS=${CMAKE_CURRENT_SOURCE_DIR}/shaders/glass.frag
        -DBLUR=${CMAKE_CURRENT_SOURCE_DIR}/shaders/glass_blur.frag
        -DALPHA=${CMAKE_CURRENT_SOURCE_DIR}/shaders/glass_alpha.frag
        -DALPHA_EXT=${CMAKE_CURRENT_SOURCE_DIR}/shaders/glass_alpha_ext.frag
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/embed_shaders.cmake
    DEPENDS shaders/glass.frag shaders/glass_blur.frag shaders/glass_alpha.frag shaders/glass_alpha_ext.frag cmake/embed_shaders.cmake
    VERBATIM
)

add_library(qmlrice-glass SHARED src/main.cpp src/GlassPass.cpp "${GEN_DIR}/shaders_embedded.hpp")
target_include_directories(qmlrice-glass PRIVATE src "${GEN_DIR}")

find_package(PkgConfig REQUIRED)
pkg_check_modules(deps REQUIRED IMPORTED_TARGET
    hyprland
    libdrm
    libinput
    libudev
    pixman-1
    wayland-server
    xkbcommon
    glesv2
)
target_link_libraries(qmlrice-glass PRIVATE rt PkgConfig::deps)
target_compile_options(qmlrice-glass PRIVATE -Wall -Wno-narrowing)
# Output file name (without .so). dlopen keeps a library that is already loaded from the same path,
# so a rebuilt plugin that must be loaded again in a session gets a new name, e.g. qmlrice-glass-dma.
set(QMLRICE_GLASS_OUTPUT_NAME "qmlrice-glass" CACHE STRING "Output file name of the plugin, without .so")
set_target_properties(qmlrice-glass PROPERTIES PREFIX "" OUTPUT_NAME "${QMLRICE_GLASS_OUTPUT_NAME}")

# Offline shader check (needs glslangValidator): cmake --build . --target check-shaders
find_program(GLSLANG glslangValidator)
if(GLSLANG)
    add_custom_target(check-shaders
        COMMAND ${GLSLANG} -S frag ${CMAKE_CURRENT_SOURCE_DIR}/shaders/glass.frag
        COMMAND ${GLSLANG} -S frag ${CMAKE_CURRENT_SOURCE_DIR}/shaders/glass_blur.frag
        COMMAND ${GLSLANG} -S frag ${CMAKE_CURRENT_SOURCE_DIR}/shaders/glass_alpha.frag
        COMMAND ${GLSLANG} -S frag ${CMAKE_CURRENT_SOURCE_DIR}/shaders/glass_alpha_ext.frag
        VERBATIM)
endif()
