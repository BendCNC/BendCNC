cmake_minimum_required(VERSION 3.21)
project(bendcnc_setup LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Gui Qml Quick QuickControls2 Network)

qt_add_executable(bendcnc-setup
    main.cpp SetupBackend.cpp SetupBackend.h
    ../src/LicenseManager.cpp ../src/LicenseManager.h
    setup.qrc)
target_compile_definitions(bendcnc-setup PRIVATE
    BENDCNC_LICENSE_SERVER="https://license.bendcnc.com"
    BENDCNC_GIT_COMMIT="setup")
target_link_libraries(bendcnc-setup PRIVATE Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Network)
