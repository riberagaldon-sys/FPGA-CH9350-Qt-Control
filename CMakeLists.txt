cmake_minimum_required(VERSION 3.19)
project(CH9350_PC_UI LANGUAGES CXX)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Widgets SerialPort)

qt_standard_project_setup()

qt_add_executable(CH9350_PC_UI
    WIN32 MACOSX_BUNDLE
    main.cpp
    mainwindow.cpp
    mainwindow.h
    mainwindow.ui
)

target_link_libraries(CH9350_PC_UI
    PRIVATE
        Qt::Core
        Qt::Widgets
        Qt::SerialPort
)

install(TARGETS CH9350_PC_UI
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

qt_generate_deploy_app_script(
    TARGET CH9350_PC_UI
    OUTPUT_SCRIPT deploy_script
    NO_UNSUPPORTED_PLATFORM_ERROR
)
install(SCRIPT ${deploy_script})