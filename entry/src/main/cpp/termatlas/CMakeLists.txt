cmake_minimum_required(VERSION 3.5.0)
project(termatlas)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH})

add_library(termatlas SHARED
    napi_init.cpp
    atlas_gl.cpp
)

target_link_libraries(termatlas PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libace_ndk.z.so
    libnative_drawing.so
    libnative_window.so
    libEGL.so
    libGLESv3.so
)
