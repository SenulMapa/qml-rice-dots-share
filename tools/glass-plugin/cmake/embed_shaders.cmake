# Generates a header holding the GLSL sources as raw string literals.
# usage: cmake -DOUT=<header> -DGLASS=<glass.frag> -DBLUR=<glass_blur.frag> -DALPHA=<glass_alpha.frag> -DALPHA_EXT=<glass_alpha_ext.frag> -P embed_shaders.cmake
file(READ "${GLASS}" GLASS_SRC)
file(READ "${BLUR}" BLUR_SRC)
file(READ "${ALPHA}" ALPHA_SRC)
file(READ "${ALPHA_EXT}" ALPHA_EXT_SRC)
file(WRITE "${OUT}"
"#pragma once\n// generated from shaders/*.frag, do not edit\n"
"inline constexpr const char* GLASS_FRAG = R\"QMLGLSL(${GLASS_SRC})QMLGLSL\";\n"
"inline constexpr const char* BLUR_FRAG  = R\"QMLGLSL(${BLUR_SRC})QMLGLSL\";\n"
"inline constexpr const char* ALPHA_FRAG = R\"QMLGLSL(${ALPHA_SRC})QMLGLSL\";\n"
"inline constexpr const char* ALPHA_EXT_FRAG = R\"QMLGLSL(${ALPHA_EXT_SRC})QMLGLSL\";\n")
