# The still.fail core's engine for the mbui app on Android (scripts/native.ts, part `engine` android-arm64): engine.cpp,
# its C API engine.h (src/host/android_core.c calls it), on React Native 0.81.4's Hermes (hermes-android's libhermes.so
# and its headers, HERMES_SO and HERMES_INCLUDE: the AAR's), the JSI built beside it (../jsi, MIT: libhermes.so needs a
# libjsi.so beside it), and the Rust shell (client/shell, SHELL_SO), with the NDK's C++ runtime shared.
cmake_minimum_required(VERSION 3.22.1)
project(stillfail_hermes CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(jsi SHARED ../jsi/jsi/jsi.cpp)
target_include_directories(jsi PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../jsi)
target_compile_options(jsi PRIVATE -fexceptions -frtti -O2)

add_library(hermes SHARED IMPORTED)
set_target_properties(hermes PROPERTIES IMPORTED_LOCATION ${HERMES_SO} INTERFACE_INCLUDE_DIRECTORIES ${HERMES_INCLUDE})

add_library(stillfail_shell SHARED IMPORTED)
set_target_properties(stillfail_shell PROPERTIES IMPORTED_LOCATION ${SHELL_SO})

add_library(stillfail_hermes SHARED ../engine.cpp)
target_compile_options(stillfail_hermes PRIVATE -fexceptions -frtti -O2 -Wall)
target_link_libraries(stillfail_hermes hermes jsi stillfail_shell log)
# Android 15+ devices may use 16 KiB pages
target_link_options(stillfail_hermes PRIVATE -Wl,-z,max-page-size=16384)
