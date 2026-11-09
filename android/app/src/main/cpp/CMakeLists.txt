cmake_minimum_required(VERSION 3.18)
project(aurasync_dsp CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(AURA_NATIVE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native)

add_library(aurasync_dsp SHARED
    ${AURA_NATIVE_DIR}/dsp_engine.cpp
    ${AURA_NATIVE_DIR}/audio_output_android.cpp
    ${AURA_NATIVE_DIR}/audio_output_keep.cpp)

target_include_directories(aurasync_dsp PRIVATE ${AURA_NATIVE_DIR})
target_compile_options(aurasync_dsp PRIVATE -O2 -fvisibility=hidden)
find_library(opensles-lib OpenSLES)
find_library(log-lib log)
target_link_libraries(aurasync_dsp ${opensles-lib} ${log-lib})
# 16 KB page-size alignment required for Android 15+ devices.
target_link_options(aurasync_dsp PRIVATE -Wl,-z,max-page-size=16384)
