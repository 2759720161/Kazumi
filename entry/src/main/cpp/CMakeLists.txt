cmake_minimum_required(VERSION 3.10)
project(mpv_napi)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(NAPI_ROOT "${OHOS_NAPI}/sysroot/usr")
set(LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/libs/${OHOS_ARCH}")
set(INC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/includes")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -D_GNU_SOURCE -D__MUSL__")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -D_GNU_SOURCE -D__MUSL__")

if(OHOS_ARCH STREQUAL "x86_64")
    add_library(mpv_napi SHARED
        mpv_client_napi_stub.cpp
    )

    target_include_directories(mpv_napi PRIVATE
        ${NAPI_ROOT}/include
    )

    target_link_libraries(mpv_napi PRIVATE
        ace_napi.z
    )
else()
    add_library(mpv_napi SHARED
        mpv_client_wrapper.cpp
        mpv_event_handler.cpp
        ohos_surface_helper.cpp
        mpv_client_napi.cpp
    )

    target_include_directories(mpv_napi PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${NAPI_ROOT}/include
        ${INC_DIR}
        ${INC_DIR}/mpv
    )

    target_link_libraries(mpv_napi PRIVATE
        ${LIB_DIR}/libmpv.so
        ace_napi.z
        libc++_shared.so
    )
endif()

set_target_properties(mpv_napi PROPERTIES
    OUTPUT_NAME "mpv_napi"
    LINK_FLAGS "-Wl,--as-needed -Wl,--gc-sections -Wl,--disable-new-dtags"
    INSTALL_RPATH ""
    BUILD_RPATH_USE_ORIGIN FALSE
    SKIP_BUILD_RPATH TRUE
)
