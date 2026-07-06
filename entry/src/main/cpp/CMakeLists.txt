# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(ClashHarmonyNative)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(entry SHARED napi_init.cpp mihomo_adapter.cpp tun_forwarder.cpp socket_protector.cpp health_monitor.cpp)
target_link_libraries(entry PUBLIC libace_napi.z.so libhilog_ndk.z.so)

set(MIHOMO_OHOS_PREBUILT_PATH "${NATIVERENDER_ROOT_PATH}/prebuilt/${OHOS_ARCH}/libmihomo_ohos.so")
file(GLOB MIHOMO_OHOS_PREBUILT_LIBS "${NATIVERENDER_ROOT_PATH}/prebuilt/${OHOS_ARCH}/*.so")
set(FAKE_MIHOMO_SRC "${NATIVERENDER_ROOT_PATH}/fake_mihomo/fake_mihomo.c")

if(EXISTS "${MIHOMO_OHOS_PREBUILT_PATH}")
    # 真实 mihomo 预编译库存在 — 打包但不链接，让 adapter 在运行时 dlopen。
    add_library(mihomo_ohos SHARED IMPORTED)
    set_target_properties(mihomo_ohos PROPERTIES IMPORTED_LOCATION "${MIHOMO_OHOS_PREBUILT_PATH}")
    target_compile_definitions(entry PRIVATE CLASH_HARMONY_HAS_PREBUILT_MIHOMO=1)
    foreach(MIHOMO_OHOS_PREBUILT_LIB ${MIHOMO_OHOS_PREBUILT_LIBS})
        get_filename_component(MIHOMO_OHOS_PREBUILT_LIB_NAME "${MIHOMO_OHOS_PREBUILT_LIB}" NAME)
        set_property(TARGET entry APPEND PROPERTY LINK_DEPENDS "${MIHOMO_OHOS_PREBUILT_LIB}")
        add_custom_command(TARGET entry POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${MIHOMO_OHOS_PREBUILT_LIB}"
                    "$<TARGET_FILE_DIR:entry>/${MIHOMO_OHOS_PREBUILT_LIB_NAME}"
            COMMENT "Copying prebuilt mihomo native bundle library ${MIHOMO_OHOS_PREBUILT_LIB_NAME} into native output")
    endforeach()
    message(STATUS "Using prebuilt mihomo library: ${MIHOMO_OHOS_PREBUILT_PATH}")
elseif(EXISTS "${FAKE_MIHOMO_SRC}")
    # 无真实预编译库 — 从源码构建功能性 fake mihomo adapter，但仍由 adapter 运行时 dlopen。
    add_library(mihomo_ohos SHARED "${FAKE_MIHOMO_SRC}")
    target_compile_options(mihomo_ohos PRIVATE -O2 -Wall -fvisibility=hidden)
    target_link_libraries(mihomo_ohos PRIVATE)
    add_dependencies(entry mihomo_ohos)
    target_compile_definitions(entry PRIVATE CLASH_HARMONY_HAS_FAKE_MIHOMO=1)
    set_property(TARGET entry APPEND PROPERTY LINK_DEPENDS "${FAKE_MIHOMO_SRC}")
    add_custom_command(TARGET entry POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "$<TARGET_FILE:mihomo_ohos>"
                "$<TARGET_FILE_DIR:entry>/libmihomo_ohos.so"
        COMMENT "Copying fake mihomo library into native output")
    message(STATUS "Building functional fake mihomo adapter from ${FAKE_MIHOMO_SRC}")
else()
    # 无任何 mihomo 实现 — stub fallback
    add_custom_command(TARGET entry POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E remove -f
                "$<TARGET_FILE_DIR:entry>/libmihomo_ohos.so"
        COMMENT "Removing stale prebuilt mihomo library from native output")
    message(STATUS "prebuilt mihomo library not found at ${MIHOMO_OHOS_PREBUILT_PATH}; using stub fallback.")
endif()
