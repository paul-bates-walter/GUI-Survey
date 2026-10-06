cmake_minimum_required(VERSION 3.19)

project(png-editor-qt
    VERSION 0.1.0
    DESCRIPTION "Desktop PNG editor (Qt Widgets)"
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Emit build/cmake-host/compile_commands.json for editor IntelliSense (clangd,
# VS Code C/C++). Harmless for the build itself.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# Qt 6.2 LTS is the minimum supported version (ships in Ubuntu 22.04 / Debian 12).
find_package(Qt6 6.2 REQUIRED COMPONENTS Widgets)
if(COMMAND qt_standard_project_setup)
    # Qt 6.3+
    qt_standard_project_setup()
else()
    # Qt 6.2 fallback: enable the auto-generators qt_standard_project_setup would.
    set(CMAKE_AUTOMOC ON)
    set(CMAKE_AUTOUIC ON)
    set(CMAKE_AUTORCC ON)
endif()

set(APP_SOURCES
    src/main.cpp
    src/MainWindow.cpp
    src/MainWindow.h
    src/CanvasWidget.cpp
    src/CanvasWidget.h
    src/MetadataPanel.cpp
    src/MetadataPanel.h)

qt_add_executable(png-editor-qt WIN32 MACOSX_BUNDLE ${APP_SOURCES})
target_link_libraries(png-editor-qt PRIVATE Qt6::Widgets)

set_target_properties(png-editor-qt PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER local.desktop-gui-survey.png-editor-qt
    MACOSX_BUNDLE_BUNDLE_NAME "PNG Editor (Qt)"
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION})

# --- Install rules -----------------------------------------------------------
if(APPLE)
    install(TARGETS png-editor-qt BUNDLE DESTINATION .)
elseif(WIN32)
    install(TARGETS png-editor-qt RUNTIME DESTINATION .)
else()
    install(TARGETS png-editor-qt RUNTIME DESTINATION bin)
    # Generate the freedesktop launcher entry at configure time (no extra asset file).
    set(DESKTOP_ENTRY "${CMAKE_BINARY_DIR}/png-editor-qt.desktop")
    file(WRITE "${DESKTOP_ENTRY}"
"[Desktop Entry]
Type=Application
Name=PNG Editor (Qt)
Comment=Draw on and edit PNG images with text metadata
Exec=png-editor-qt %f
Terminal=false
Categories=Graphics;RasterGraphics;
MimeType=image/png;
")
    install(FILES "${DESKTOP_ENTRY}" DESTINATION share/applications)
endif()

# --- Packaging (CPack) -------------------------------------------------------
set(CPACK_PACKAGE_NAME "png-editor-qt")
set(CPACK_PACKAGE_VENDOR "Desktop GUI Survey")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${PROJECT_DESCRIPTION}")
set(CPACK_PACKAGE_CONTACT "desktop-gui-survey@local")

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(CPACK_GENERATOR "DEB")
    set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Desktop GUI Survey")
    set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
    set(CPACK_DEBIAN_PACKAGE_SECTION "graphics")
elseif(APPLE)
    set(CPACK_GENERATOR "DragNDrop")
elseif(WIN32)
    set(CPACK_GENERATOR "NSIS;ZIP")
endif()

include(CPack)
