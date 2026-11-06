# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(InboxPlus LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "InboxPlus")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

find_program(INBOXPLUS_BASH_EXECUTABLE NAMES bash
  HINTS "$ENV{ProgramFiles}/Git/bin" "$ENV{ProgramFiles}/Git/usr/bin")
if(DEFINED ENV{GO_BINARY})
  set(INBOXPLUS_GO_BINARY "$ENV{GO_BINARY}" CACHE FILEPATH "Pinned Go 1.27.3 executable")
else()
  find_program(INBOXPLUS_GO_BINARY NAMES go)
endif()
if(NOT INBOXPLUS_BASH_EXECUTABLE OR NOT INBOXPLUS_GO_BINARY)
  message(FATAL_ERROR "Building Inbox+ connectors requires Git Bash, a MinGW C compiler, and Go 1.27.3. Set GO_BINARY to the verified pinned Go SDK and CC to the matching MinGW compiler.")
endif()
if(FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64")
  message(FATAL_ERROR "Windows ARM64 is unavailable: the pinned media libraries support Windows x64. Build --target-platform windows-x64.")
elseif(FLUTTER_TARGET_PLATFORM STREQUAL "windows-x64")
  set(INBOXPLUS_GOARCH amd64)
else()
  message(FATAL_ERROR "Unsupported Flutter Windows target: ${FLUTTER_TARGET_PLATFORM}")
endif()
get_filename_component(INBOXPLUS_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
set(INBOXPLUS_CONNECTOR_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/inboxplus-connectors")
set(INBOXPLUS_CONNECTOR_LIBRARY "${INBOXPLUS_CONNECTOR_BUILD_DIR}/inboxplus_connectors.dll")
add_custom_target(inboxplus_connectors ALL
  COMMAND "${CMAKE_COMMAND}" -E env
    "GO_BINARY=${INBOXPLUS_GO_BINARY}" "GOARCH=${INBOXPLUS_GOARCH}"
    "${INBOXPLUS_BASH_EXECUTABLE}" "${INBOXPLUS_REPO_ROOT}/native/connectors/build.sh"
    windows "${INBOXPLUS_CONNECTOR_BUILD_DIR}"
  BYPRODUCTS "${INBOXPLUS_CONNECTOR_LIBRARY}"
  VERBATIM
)
add_dependencies(${BINARY_NAME} inboxplus_connectors)
add_custom_target(inboxplus_connector_bundle ALL
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${INBOXPLUS_CONNECTOR_LIBRARY}" "$<TARGET_FILE_DIR:${BINARY_NAME}>"
  DEPENDS inboxplus_connectors ${BINARY_NAME}
  VERBATIM
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
find_package(Python3 REQUIRED COMPONENTS Interpreter)
execute_process(
  COMMAND "${Python3_EXECUTABLE}" "${INBOXPLUS_REPO_ROOT}/Scripts/verify-media-artifacts.py"
    --platform windows --cache-dir "${CMAKE_BINARY_DIR}"
  RESULT_VARIABLE INBOXPLUS_MEDIA_VERIFY_RESULT
)
if(NOT INBOXPLUS_MEDIA_VERIFY_RESULT EQUAL 0)
  message(FATAL_ERROR "Native media artifact verification failed.")
endif()
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
install(FILES "${INBOXPLUS_CONNECTOR_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
