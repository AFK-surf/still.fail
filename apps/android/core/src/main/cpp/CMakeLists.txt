# The core's engine for the app (engine.cpp): Hermes (com.facebook.react:hermes-android, through prefab), the JSI it
# is built against (jsi/, React Native 0.81.4's, MIT: libhermes.so needs a libjsi.so beside it), and the Rust shell
# (client/shell, put in build/generated/jniLibs by apps/android/build.py).
cmake_minimum_required(VERSION 3.22.1)
project(stillfail_hermes CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(hermes-engine REQUIRED CONFIG)

add_library(jsi SHARED jsi/jsi/jsi.cpp)
target_include_directories(jsi PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/jsi)
target_compile_options(jsi PRIVATE -fexceptions -frtti -O2)

add_library(stillfail_shell SHARED IMPORTED)
set_target_properties(stillfail_shell PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/../../../build/generated/jniLibs/${ANDROID_ABI}/libstillfail_shell.so)

add_library(stillfail_hermes SHARED engine.cpp)
target_compile_options(stillfail_hermes PRIVATE -fexceptions -frtti -O2 -Wall)
target_link_libraries(stillfail_hermes hermes-engine::libhermes jsi stillfail_shell log)
target_link_options(stillfail_hermes PRIVATE -Wl,-z,max-page-size=16384)
