cmake_minimum_required(VERSION 3.14)
project(media_kit_video LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(PLUGIN_NAME "media_kit_video_plugin")
add_library(${PLUGIN_NAME} SHARED
  "angle_surface_manager.cc"
  "media_kit_video_plugin_c_api.cc" "media_kit_video_plugin.cc"
  "video_output_manager.cc" "video_output.cc" "utils.cc"
  "../common/mpv/media_kit_mpv.c")
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE
  FLUTTER_PLUGIN_IMPL _DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)
target_compile_options(${PLUGIN_NAME} PRIVATE "/utf-8")
target_include_directories(${PLUGIN_NAME}
  INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include"
  PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../common/mpv/include" "${CMAKE_CURRENT_SOURCE_DIR}/ANGLE/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin
  "${CMAKE_CURRENT_SOURCE_DIR}/ANGLE/lib/libEGL.dll.lib"
  "${CMAKE_CURRENT_SOURCE_DIR}/ANGLE/lib/libGLESv2.dll.lib")
# Native libraries are emitted by media_kit's Dart build hook.
set(media_kit_video_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/ANGLE/libEGL.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/ANGLE/libGLESv2.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/ANGLE/libc++.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/ANGLE/zlib.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/ANGLE/d3dcompiler_47.dll"
  PARENT_SCOPE)
