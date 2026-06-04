cmake_minimum_required(VERSION 3.16)
project(BuildBrowser VERSION 1.0 LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

execute_process(
    COMMAND git rev-list --count HEAD
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    OUTPUT_VARIABLE BUILD_GIT_COUNT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if(NOT BUILD_GIT_COUNT MATCHES "^[0-9]+$")
    set(BUILD_GIT_COUNT "1")
endif()

add_executable(BuildBrowser MACOSX_BUNDLE
    src/main.mm
    src/AppDelegate.mm
    src/BrowserWindowController.mm
    src/TabManager.mm
    src/BookmarkManager.mm
    src/HistoryManager.mm
    src/SettingsManager.mm
    src/DownloadManager.mm
    src/Profile.mm
    src/ProfileManager.mm
    src/ProfilePanel.mm
    src/SettingsPanel.mm
    src/SidePanel.mm
    src/DownloadsPanel.mm
    src/ContentBlocker.mm
    src/UpdateManager.mm
    resources/BuildBrowser.icns
)

target_include_directories(BuildBrowser PRIVATE include)

target_link_libraries(BuildBrowser PRIVATE
    "-framework Cocoa"
    "-framework WebKit"
    "-framework Foundation"
    "-framework Security"
    "-framework UniformTypeIdentifiers"
)

set_target_properties(BuildBrowser PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER  "io.kiro.browser"
    MACOSX_BUNDLE_BUNDLE_NAME     "BuildBrowser"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
    MACOSX_BUNDLE_BUNDLE_VERSION "${BUILD_GIT_COUNT}"
    MACOSX_BUNDLE_COPYRIGHT "Copyright 2026 BuildBrowser"
    MACOSX_BUNDLE_ICON_FILE "BuildBrowser.icns"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/resources/Info.plist.in"
)

set_source_files_properties(resources/BuildBrowser.icns PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources"
)

# ARC + set deployment target so __weak works
target_compile_options(BuildBrowser PRIVATE -fobjc-arc)
target_link_options(BuildBrowser PRIVATE -mmacosx-version-min=12.0)
set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0" CACHE STRING "" FORCE)
