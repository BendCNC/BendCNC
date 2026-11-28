cmake_minimum_required(VERSION 3.16)
# Customer-visible app version (dashboard, About). Bump for every published release.
project(BendCNCQMLPrototype VERSION 1.0.41 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Qt6 6.8 REQUIRED COMPONENTS Quick QuickControls2 SerialPort Network Concurrent GuiPrivate)
qt_standard_project_setup()

option(BENDCNC_REQUIRE_CANVAS_PAINTER
    "Fail configuration unless the Qt 6.11 Canvas Painter renderer is available"
    OFF)

set(BENDCNC_CANVAS_PAINTER_SOURCES)
set(BENDCNC_CANVAS_PAINTER_QML)
if(Qt6_VERSION VERSION_GREATER_EQUAL 6.11)
    find_package(Qt6 QUIET COMPONENTS CanvasPainter)
    if(TARGET Qt6::CanvasPainter)
        list(APPEND BENDCNC_CANVAS_PAINTER_SOURCES
            src/CanvasPainterRunRenderer.cpp
            src/CanvasPainterRunRenderer.h
        )
        list(APPEND BENDCNC_CANVAS_PAINTER_QML
            qml/CanvasPainterRunExecutionLayer.qml
        )
    endif()
endif()
if(BENDCNC_REQUIRE_CANVAS_PAINTER AND NOT TARGET Qt6::CanvasPainter)
    message(FATAL_ERROR
        "BENDCNC_REQUIRE_CANVAS_PAINTER=ON requires Qt 6.11+ with Qt6::CanvasPainter")
endif()

add_library(machine_control_backend STATIC
    src/MachineControlBackend.cpp
    src/MachineControlBackend.h
    src/PressTelemetryRecorder.cpp
    src/PressTelemetryRecorder.h
    src/MachineProtocolParsers.cpp
    src/MachineProtocolParsers.h
    src/MachineTransport.h
    src/NullMachineTransport.cpp
    src/NullMachineTransport.h
)
target_link_libraries(machine_control_backend PUBLIC Qt6::Core)
target_include_directories(machine_control_backend PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

add_library(machine_serial_transport STATIC
    src/SerialDeviceDiscovery.cpp
    src/SerialDeviceDiscovery.h
    src/SerialMachineTransport.cpp
    src/SerialMachineTransport.h
)
target_link_libraries(machine_serial_transport PUBLIC
    machine_control_backend
    Qt6::Core
    Qt6::SerialPort
)
target_include_directories(machine_serial_transport PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

qt_add_executable(prototype
    src/main.cpp
    src/ThcLiveIntegrationCheck.h
    src/ThcV51OwnerProtocol.h
    src/ThcV53RemoteTuning.h
    src/DisplaySleepController.cpp
    src/DisplaySleepController.h
    src/FileIo.h
    src/HostSystemBackend.cpp
    src/HostSystemBackend.h
    src/MachineFirmwareBackend.cpp
    src/MachineFirmwareBackend.h
    src/RunFrameTiming.cpp
    src/RunFrameTiming.h
    src/NativeRunRenderer.cpp
    src/NativeRunRenderer.h
    src/ModalPreviewController.cpp
    src/ModalPreviewController.h
    src/LicenseManager.cpp
    src/LicenseManager.h
    src/UnfoldSequencePlanner.cpp
    src/UnfoldSequencePlanner.h
    ${BENDCNC_CANVAS_PAINTER_SOURCES}
)

# Paid-distribution builds: -DBENDCNC_LICENSING=ON
#   -DBENDCNC_LICENSE_SERVER=https://... -DBENDCNC_LICENSE_PUBKEY=<base64>
option(BENDCNC_LICENSING "Enforce cloud license / 30-day trial" OFF)
set(BENDCNC_LICENSE_SERVER "" CACHE STRING "License server base URL")
set(BENDCNC_LICENSE_PUBKEY "" CACHE STRING "Ed25519 public key (base64, 32 bytes raw)")
if(BENDCNC_LICENSING)
    if(NOT BENDCNC_LICENSE_PUBKEY OR NOT BENDCNC_LICENSE_SERVER)
        message(FATAL_ERROR "BENDCNC_LICENSING requires BENDCNC_LICENSE_SERVER and BENDCNC_LICENSE_PUBKEY")
    endif()
    find_package(OpenSSL 1.1.1 REQUIRED COMPONENTS Crypto)
    target_link_libraries(prototype PRIVATE OpenSSL::Crypto)
    target_compile_definitions(prototype PRIVATE
        BENDCNC_LICENSING
        BENDCNC_LICENSE_SERVER="${BENDCNC_LICENSE_SERVER}"
        BENDCNC_LICENSE_PUBKEY="${BENDCNC_LICENSE_PUBKEY}")
endif()
# Commit is reported to the license server only (admin dashboard), never shown to customers.
if(NOT BENDCNC_GIT_COMMIT)
    execute_process(COMMAND git rev-parse --short HEAD WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
                    OUTPUT_VARIABLE BENDCNC_GIT_COMMIT OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
endif()
if(NOT BENDCNC_GIT_COMMIT)
    set(BENDCNC_GIT_COMMIT "unknown")
endif()
target_compile_definitions(prototype PRIVATE BENDCNC_APP_VERSION="${PROJECT_VERSION}"
                                             BENDCNC_GIT_COMMIT="${BENDCNC_GIT_COMMIT}"
                                             BENDCNC_PLANNER_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/sequence-planner")

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/ThcLiveIntegrationGuard.cmake")
add_custom_target(thc_live_integration_guard
    COMMAND "${CMAKE_COMMAND}" "-DTHC_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ThcLiveIntegrationGuard.cmake"
    VERBATIM
    COMMENT "Checking required THC live tuning integration"
)
add_dependencies(prototype thc_live_integration_guard)

# Keep the resource path stable with the explicit Qt 6.8 minimum. Production
# Canvas Painter builds require Qt 6.11 as enforced by the option above.
if(Qt6_VERSION VERSION_GREATER_EQUAL 6.5)
    qt_policy(SET QTP0001 NEW)
endif()
if(Qt6_VERSION VERSION_GREATER_EQUAL 6.8)
    qt_policy(SET QTP0004 NEW)
endif()

# Runtime data + icon assets. DataStore.qml loads data/current/*.json via a SYNC
# XHR GET (qrc:/qml/data/...), which HANGS on a missing qrc file, so every JSON the
# app reads must be bundled. Icons are loaded as qrc:/qml/icons/*.svg.
file(GLOB BENDCNC_DATA_FILES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/qml/data/current/*.json")
file(GLOB BENDCNC_ICON_FILES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/qml/icons/*.svg")
file(GLOB BENDCNC_FONT_FILES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/qml/fonts/*.ttf")
set(BENDCNC_VERTICAL_DIAGRAM_IMAGE
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/vertical_diagram.png")
set_source_files_properties(${BENDCNC_VERTICAL_DIAGRAM_IMAGE} PROPERTIES
    QT_RESOURCE_ALIAS "qml/images/info/create_bend/vertical_diagram.png")
set(BENDCNC_RUNTIME_ASSETS)
foreach(_f ${BENDCNC_DATA_FILES})
    file(RELATIVE_PATH _rel "${CMAKE_CURRENT_SOURCE_DIR}" "${_f}")
    list(APPEND BENDCNC_RUNTIME_ASSETS "${_rel}")
endforeach()
foreach(_f ${BENDCNC_ICON_FILES})
    file(RELATIVE_PATH _rel "${CMAKE_CURRENT_SOURCE_DIR}" "${_f}")
    list(APPEND BENDCNC_RUNTIME_ASSETS "${_rel}")
endforeach()
foreach(_f ${BENDCNC_FONT_FILES})
    file(RELATIVE_PATH _rel "${CMAKE_CURRENT_SOURCE_DIR}" "${_f}")
    list(APPEND BENDCNC_RUNTIME_ASSETS "${_rel}")
endforeach()
list(APPEND BENDCNC_RUNTIME_ASSETS ${BENDCNC_VERTICAL_DIAGRAM_IMAGE})

# Optional LIVE 3D view (Qt Quick 3D). Without Quick3D the RUN view keeps the
# 2D LIVE canvas; the Loader for qml/LiveScene3D.qml fails and falls back.
find_package(Qt6 QUIET COMPONENTS Quick3D)
set(BENDCNC_LIVE3D_QML)
if(Qt6Quick3D_FOUND)
    target_sources(prototype PRIVATE live3d/LiveScene3D.h live3d/LiveScene3D.cpp)
    target_include_directories(prototype PRIVATE live3d)
    target_link_libraries(prototype PRIVATE Qt6::Quick3D)
    target_compile_definitions(prototype PRIVATE BENDCNC_LIVE3D=1)
    set(BENDCNC_LIVE3D_QML qml/LiveScene3D.qml)
endif()

qt_add_qml_module(prototype
    URI BendCNCPrototype
    VERSION 1.0
    # QTP0001 NEW supplies the default /qt/qml prefix, registering below
    # qrc:/qt/qml/BendCNCPrototype/qml/...; keep this aligned with main.cpp.
    QML_FILES
        qml/main.qml
        qml/AppState.qml
        qml/DataStore.qml
        qml/Theme.qml
        qml/LayoutMetrics.qml
        qml/ModalMetrics.qml
        qml/ActionBarView.qml
        qml/ToolBarView.qml
        qml/ColumnRightView.qml
        qml/RunView.qml
        qml/LiveIsometricViewCube.qml
        qml/RunExecutionCanvas.qml
        qml/NativeRunExecutionLayer.qml
        ${BENDCNC_CANVAS_PAINTER_QML}
        qml/CreateBendView.qml
        qml/ToolsView.qml
        qml/BackGaugeControlView.qml
        qml/BackGaugeClassicView.qml
        qml/CreateBendV7View.qml
        qml/ToolsV7View.qml
        qml/ProgramsView.qml
        qml/ManualModeView.qml
        qml/ThcLiveTuningPanel.qml
        qml/LicensePanel.qml
        qml/ThcLiveTuningView.qml
        qml/ThcTelemetryHistory.qml
        qml/ThcTonnageChart.qml
        qml/MeasurementModal.qml
        qml/ManualMeasurementPopup.qml
        qml/CadImportView.qml
        qml/CadGeometryModal.qml
        qml/GeneratedCadSnapshotView.qml
        qml/SettingsView.qml
        qml/RamDroView.qml
        qml/UserControlView.qml
        qml/MachinePopupLayer.qml
        qml/BleedModal.qml
        qml/CadResultModal.qml
        qml/MachineAlarmPopupLayer.qml
        qml/OnScreenKeyboard.qml
        qml/ModalPreviewer.qml
        qml/ModalDesignerSurface.qml
        qml/ModalDesignerCanvasSource.qml
        qml/ActivatorProposalsView.qml
        qml/BendModeProposalsView.qml
        qml/modal-previews/v5/ColumnRightView.qml
        qml/modal-previews/v5/RamDroView.qml
        qml/modal-previews/v5/RunLeftView.qml
        qml/modal-previews/v5/ManualLeftView.qml
        qml/modal-previews/v5/ThcLiveTuningPreview.qml
        qml/modal-previews/v6/ColumnRightView.qml
        qml/modal-previews/v6/RamDroView.qml
        qml/modal-previews/v6/RunLeftView.qml
        qml/modal-previews/v6/ManualLeftView.qml
        qml/modal-previews/v6/V6BackGaugeLeftView.qml
        qml/modal-previews/v6/V6ToolsLeftView.qml
        qml/modal-previews/v6/CreateBendLeftView.qml
        qml/modal-previews/v6/V6CreateBendLeftView.qml
        qml/modal-previews/v6/ThcLiveTuningPreview.qml
        qml/modal-previews/v7/ColumnRightView.qml
        qml/modal-previews/v7/RamDroView.qml
        qml/modal-previews/v7/RunLeftView.qml
        qml/modal-previews/v7/ManualLeftView.qml
        qml/modal-previews/v7/V6BackGaugeLeftView.qml
        qml/modal-previews/v7/V6ToolsLeftView.qml
        qml/modal-previews/v7/CreateBendLeftView.qml
        qml/modal-previews/v7/V7CreateBendLeftView.qml
        qml/modal-previews/v7/V7ProgramsLeftView.qml
        qml/modal-previews/v7/V8SettingsLeftView.qml
        qml/modal-previews/v7/PreviewScene.qml
        qml/modal-previews/v7/ThcLiveTuningPreview.qml
        qml/modal-previews/current/PreviewScene.qml
        qml/modal-previews/v1/PreviewScene.qml
        qml/modal-previews/v1/OperationalPreview.qml
        qml/modal-previews/v1/CriticalPreview.qml
        qml/modal-previews/v1/NotificationPreview.qml
    RESOURCES
        # JS engine modules are imported via relative paths (import "core/.../X.js")
        # and must live in the same resource tree as the QML that imports them.
        qml/core/BendCalculator.js
        qml/core/CadLoadWorker.js
        qml/core/ToolingPlanningEngine.js
        qml/core/UnfoldPlanMapping.js
        qml/core/execution/DwellAndBailOut.js
        qml/core/execution/ExecutionStateModel.js
        qml/core/machine/BackGauge.js
        qml/core/Units.js
        qml/core/OriginalFingerMesh.js
        qml/core/machine/MachineController.js
        qml/core/machine/MockPressDevice.js
        qml/core/machine/protocol.js
        qml/core/settings/SettingsModel.js
        qml/core/services/ServicesModel.js
        qml/core/sheetmetal/CanonicalRuntimeGeometry.js
        qml/core/sheetmetal/LiveBranchContactMapBuilder.js
        qml/core/sheetmetal/LivePlacementJointMap.js
        qml/core/sheetmetal/RigidTransform3D.js
        qml/core/sheetmetal/SheetMetalGeometry.js
        qml/core/sheetmetal/SheetMetalRenderGeometry.js
        qml/core/sheetmetal/SheetMetalLiveProjection.js
        qml/core/sheetmetal/SheetMetalPoseGraph.js
        qml/core/sheetmetal/SheetMetalPoseEvaluator.js
        qml/core/sheetmetal/SheetMetalFoldSolver.js
        qml/core/sheetmetal/BendAllowanceCalculator.js
        qml/core/storage/EntityEditingManager.js
        qml/core/storage/EntityStorage.js
        qml/core/MathUtil.js
        ${BENDCNC_LIVE3D_QML}
        ${BENDCNC_RUNTIME_ASSETS}
)

target_link_libraries(prototype PRIVATE
    machine_control_backend
    machine_serial_transport
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Network
    Qt6::Concurrent
    Qt6::GuiPrivate
)
target_compile_definitions(prototype PRIVATE
    BENDCNC_QML_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
)
if(TARGET Qt6::CanvasPainter)
    target_link_libraries(prototype PRIVATE Qt6::CanvasPainter)
endif()
# Tooling DXFs and sample parts are read from <appDir>/assets at runtime.
set(BENDCNC_TOOLING_ASSET_DIR "${CMAKE_CURRENT_SOURCE_DIR}/assets")
if(NOT EXISTS "${BENDCNC_TOOLING_ASSET_DIR}/Punches")
    set(BENDCNC_TOOLING_ASSET_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../assets")
endif()
if(NOT ANDROID AND EXISTS "${BENDCNC_TOOLING_ASSET_DIR}/Punches")
    set(_bendcnc_asset_dirs Punches Dies Fingers)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/assets/bcbends")
        list(APPEND _bendcnc_asset_dirs bcbends)
    endif()
    foreach(_dir ${_bendcnc_asset_dirs})
        if(EXISTS "${BENDCNC_TOOLING_ASSET_DIR}/${_dir}")
            add_custom_command(TARGET prototype POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_directory
                    "${BENDCNC_TOOLING_ASSET_DIR}/${_dir}"
                    "$<TARGET_FILE_DIR:prototype>/assets/${_dir}")
        endif()
    endforeach()
    file(GLOB _bendcnc_finger_dxfs "${BENDCNC_TOOLING_ASSET_DIR}/Finger *.dxf*")
    if(_bendcnc_finger_dxfs)
        add_custom_command(TARGET prototype POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${_bendcnc_finger_dxfs}
                "$<TARGET_FILE_DIR:prototype>/assets/")
    endif()
endif()
# Android: android/build-deploy-android.ps1 stages tooling DXFs/bcbends here so
# they are packaged as APK assets (assets:/assets/...).
if(ANDROID)
    target_sources(prototype PRIVATE src/AndroidUsbSerialPort.cpp src/AndroidUsbSerialPort.h)
endif()
if(ANDROID AND BENDCNC_ANDROID_PACKAGE_DIR)
    set_property(TARGET prototype PROPERTY
        QT_ANDROID_PACKAGE_SOURCE_DIR "${BENDCNC_ANDROID_PACKAGE_DIR}")
    set_target_properties(prototype PROPERTIES
        QT_ANDROID_APP_NAME "Bend OS"
        QT_ANDROID_APP_ICON "@mipmap/ic_launcher")
endif()

include(CTest)
if(WIN32)
    add_custom_target(package_arm64
        COMMAND powershell.exe -NoProfile -NonInteractive -File
            "${CMAKE_CURRENT_SOURCE_DIR}/deploy-arm64/build-arm64.ps1"
            -OutputDirectory "${CMAKE_CURRENT_BINARY_DIR}/arm64-package"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        USES_TERMINAL
        COMMENT "Package the Qt ARM64 application using the reviewed Docker workflow"
    )
endif()

# Standalone Qt Quick 3D comparison viewer for unfold plans (optional, PC only).
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/viewer3d/main.cpp" AND Qt6Quick3D_FOUND)
    qt_add_executable(unfold3d_viewer
        viewer3d/main.cpp
        viewer3d/SceneFrames.h viewer3d/SceneFrames.cpp
    )
    qt_add_qml_module(unfold3d_viewer
        URI Unfold3DViewer
        VERSION 1.0
        QML_FILES viewer3d/Main.qml
    )
    target_include_directories(unfold3d_viewer PRIVATE viewer3d)
    target_link_libraries(unfold3d_viewer PRIVATE Qt6::Quick Qt6::Quick3D)
    target_compile_definitions(unfold3d_viewer PRIVATE
        BENDCNC_EXPORTER="${CMAKE_CURRENT_SOURCE_DIR}/tools/export_unfold_scene.mjs")
endif()

if(BUILD_TESTING)
    find_package(Qt6 6.8 REQUIRED COMPONENTS QuickTest Test)

    add_test(
        NAME thc_live_packaged_tests
        COMMAND "${CMAKE_COMMAND}" "-DTHC_EXE=$<TARGET_FILE:prototype>"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/RunThcLivePackaged.cmake"
    )
    set_tests_properties(thc_live_packaged_tests PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QML_XHR_ALLOW_FILE_READ=1;QT_FORCE_STDERR_LOGGING=1"
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        TIMEOUT 20
    )
    find_program(BENDCNC_NODE_EXECUTABLE NAMES node node.exe)
    if(BENDCNC_NODE_EXECUTABLE)
        add_test(
            NAME thc_live_integration_guard_tests
            COMMAND "${BENDCNC_NODE_EXECUTABLE}" --test
                "${CMAKE_CURRENT_SOURCE_DIR}/tests/thc-live-integration-guard.test.cjs"
        )
        set_tests_properties(thc_live_integration_guard_tests PROPERTIES
            ENVIRONMENT "THC_GUARD_CMAKE=${CMAKE_COMMAND}"
            TIMEOUT 30
        )
        add_test(
            NAME thc_live_designer_isolation_tests
            COMMAND "${BENDCNC_NODE_EXECUTABLE}" --test
                "${CMAKE_CURRENT_SOURCE_DIR}/tests/thc-live-designer.test.cjs"
        )
        set_tests_properties(thc_live_designer_isolation_tests PROPERTIES TIMEOUT 15)
    endif()

    qt_add_executable(thc_v51_owner_protocol_tests
        tests/tst_ThcV51OwnerProtocol.cpp
    )
    target_link_libraries(thc_v51_owner_protocol_tests PRIVATE
        machine_control_backend
        machine_serial_transport
        Qt6::Test
    )
    add_test(
        NAME thc_v51_owner_protocol_tests
        COMMAND "$<TARGET_FILE:thc_v51_owner_protocol_tests>"
            -o "${CMAKE_CURRENT_BINARY_DIR}/thc-v51-owner-protocol-tests.txt,txt"
    )
    set_tests_properties(thc_v51_owner_protocol_tests PROPERTIES TIMEOUT 90)

    qt_add_executable(machine_control_backend_tests
        tests/tst_MachineControlBackend.cpp
    )
    target_link_libraries(machine_control_backend_tests PRIVATE
        machine_control_backend
        machine_serial_transport
        Qt6::Test
    )
    add_test(
        NAME machine_control_backend_tests
        COMMAND "$<TARGET_FILE:machine_control_backend_tests>"
            -o "${CMAKE_CURRENT_BINARY_DIR}/machine-control-backend-tests.txt,txt"
    )
    add_test(
        NAME machine_control_serial_diagnostics_tests
        COMMAND "$<TARGET_FILE:machine_control_backend_tests>"
            serialDiagnosticLoggingCanBeChangedAtRuntime
            -o "${CMAKE_CURRENT_BINARY_DIR}/machine-control-serial-diagnostics-tests.txt,txt"
    )

    qt_add_executable(run_frame_timing_tests
        tests/tst_RunFrameTiming.cpp
        src/RunFrameTiming.cpp
        src/RunFrameTiming.h
    )
    target_link_libraries(run_frame_timing_tests PRIVATE
        Qt6::Quick
        Qt6::Test
    )
    target_include_directories(run_frame_timing_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    add_test(
        NAME run_frame_timing_tests
        COMMAND "$<TARGET_FILE:run_frame_timing_tests>"
    )

    qt_add_executable(display_sleep_controller_tests
        tests/tst_DisplaySleepController.cpp
        src/DisplaySleepController.cpp
        src/DisplaySleepController.h
    )
    target_link_libraries(display_sleep_controller_tests PRIVATE
        Qt6::Gui
        Qt6::GuiPrivate
        Qt6::Test
    )
    target_include_directories(display_sleep_controller_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    add_test(
        NAME display_sleep_controller_tests
        COMMAND "$<TARGET_FILE:display_sleep_controller_tests>"
    )
    set_tests_properties(display_sleep_controller_tests PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
        LABELS "fast;display-sleep"
        TIMEOUT 15
    )

    qt_add_executable(press_telemetry_recorder_tests
        tests/tst_PressTelemetryRecorder.cpp
    )
    target_link_libraries(press_telemetry_recorder_tests PRIVATE
        machine_control_backend
        Qt6::Test
    )
    add_test(
        NAME press_telemetry_recorder_tests
        COMMAND "$<TARGET_FILE:press_telemetry_recorder_tests>"
    )

    qt_add_executable(sheetmetal_qml_tests
        tests/qmltest_main.cpp
        src/NativeRunRenderer.cpp
        src/NativeRunRenderer.h
        ${BENDCNC_CANVAS_PAINTER_SOURCES}
    )
    target_link_libraries(sheetmetal_qml_tests PRIVATE Qt6::Quick Qt6::QuickTest)
    if(TARGET Qt6::CanvasPainter)
        target_link_libraries(sheetmetal_qml_tests PRIVATE Qt6::CanvasPainter)
        target_compile_definitions(sheetmetal_qml_tests PRIVATE
            BENDCNC_HAS_CANVAS_PAINTER=1
        )
    endif()
    target_include_directories(sheetmetal_qml_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_compile_definitions(sheetmetal_qml_tests PRIVATE
        QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests"
    )

    add_test(
        NAME sheetmetal_qml_tests
        COMMAND "$<TARGET_FILE:sheetmetal_qml_tests>"
            -input "${CMAKE_CURRENT_SOURCE_DIR}/tests"
            -o "${CMAKE_CURRENT_BINARY_DIR}/sheetmetal-qml-tests.txt,txt"
    )
    add_test(
        NAME SettingsView_qml_tests
        COMMAND "$<TARGET_FILE:sheetmetal_qml_tests>"
            -input "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_SettingsView.qml"
            -o "${CMAKE_CURRENT_BINARY_DIR}/settings-view-qml-tests.txt,txt"
    )
    add_test(
        NAME native_run_renderer_transport_tests
        COMMAND "$<TARGET_FILE:sheetmetal_qml_tests>"
            -input "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_NativeRunRendererTransport.qml"
            -o "${CMAKE_CURRENT_BINARY_DIR}/native-run-renderer-transport-tests.txt,txt"
    )
    set_tests_properties(sheetmetal_qml_tests PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QML_XHR_ALLOW_FILE_READ=1"
    )
    set_tests_properties(native_run_renderer_transport_tests PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QML_XHR_ALLOW_FILE_READ=1"
    )
        foreach(_manual_test IN ITEMS
            ManualModeView
            ThcLiveTuningPanel
            ThcTelemetryHistory
            ThcTonnageChart
            ThcLiveTuningPreview
            ManualMeasurementPopup
            MachineAlarmPopupLayer
            MachinePopupLayer)
        add_test(
            NAME ${_manual_test}_qml_tests
            COMMAND "$<TARGET_FILE:sheetmetal_qml_tests>"
                -input "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_${_manual_test}.qml"
                -o "${CMAKE_CURRENT_BINARY_DIR}/${_manual_test}-qml-tests.txt,txt"
        )
        set_tests_properties(${_manual_test}_qml_tests PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QML_XHR_ALLOW_FILE_READ=1"
            TIMEOUT 60
        )
    endforeach()
    if(WIN32)
        add_test(
            NAME ThcLiveTuningPanel_foreground_qml_tests
            COMMAND "$<TARGET_FILE:sheetmetal_qml_tests>"
                -input "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_ThcLiveTuningPanel.qml"
                -o "${CMAKE_CURRENT_BINARY_DIR}/ThcLiveTuningPanel-foreground-qml-tests.txt,txt"
        )
        set_tests_properties(ThcLiveTuningPanel_foreground_qml_tests PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=windows;QML_XHR_ALLOW_FILE_READ=1"
            TIMEOUT 60
        )
    endif()
    if(WIN32 AND TARGET Qt6::CanvasPainter)
        add_test(
            NAME canvas_painter_renderer_tests
            COMMAND "$<TARGET_FILE:sheetmetal_qml_tests>"
                -input "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_CanvasPainterRunRenderer.qml"
                -o "${CMAKE_CURRENT_BINARY_DIR}/canvas-painter-renderer-tests.txt,txt"
        )
        set_tests_properties(canvas_painter_renderer_tests PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=windows;QSG_RHI_BACKEND=d3d11;QML_XHR_ALLOW_FILE_READ=1"
        )
    endif()
    if(WIN32)
        get_target_property(_qt_qmake_executable Qt6::qmake IMPORTED_LOCATION)
        get_filename_component(_qt_runtime_dir "${_qt_qmake_executable}" DIRECTORY)
        get_filename_component(_compiler_runtime_dir "${CMAKE_CXX_COMPILER}" DIRECTORY)
        set_tests_properties(
            thc_live_packaged_tests
            ManualModeView_qml_tests
            ThcLiveTuningPanel_qml_tests
            ThcLiveTuningPanel_foreground_qml_tests
            ThcTelemetryHistory_qml_tests
            ThcTonnageChart_qml_tests
            ThcLiveTuningPreview_qml_tests
            ManualMeasurementPopup_qml_tests
            MachineAlarmPopupLayer_qml_tests
            MachinePopupLayer_qml_tests
            PROPERTIES
            ENVIRONMENT_MODIFICATION
                "PATH=path_list_prepend:${_compiler_runtime_dir};PATH=path_list_prepend:${_qt_runtime_dir}"
        )
        set_tests_properties(sheetmetal_qml_tests PROPERTIES
            ENVIRONMENT_MODIFICATION
                "PATH=path_list_prepend:${_compiler_runtime_dir};PATH=path_list_prepend:${_qt_runtime_dir}"
        )
        set_tests_properties(native_run_renderer_transport_tests PROPERTIES
            ENVIRONMENT_MODIFICATION
                "PATH=path_list_prepend:${_compiler_runtime_dir};PATH=path_list_prepend:${_qt_runtime_dir}"
        )
        set_tests_properties(machine_control_backend_tests machine_control_serial_diagnostics_tests thc_v51_owner_protocol_tests PROPERTIES
            ENVIRONMENT_MODIFICATION
                "PATH=path_list_prepend:${_compiler_runtime_dir};PATH=path_list_prepend:${_qt_runtime_dir}"
        )
        set_tests_properties(run_frame_timing_tests PROPERTIES
            ENVIRONMENT_MODIFICATION
                "PATH=path_list_prepend:${_compiler_runtime_dir};PATH=path_list_prepend:${_qt_runtime_dir}"
        )
        set_tests_properties(display_sleep_controller_tests PROPERTIES
            ENVIRONMENT_MODIFICATION
                "PATH=path_list_prepend:${_compiler_runtime_dir};PATH=path_list_prepend:${_qt_runtime_dir}"
        )
        set_tests_properties(press_telemetry_recorder_tests PROPERTIES
            ENVIRONMENT_MODIFICATION
                "PATH=path_list_prepend:${_compiler_runtime_dir};PATH=path_list_prepend:${_qt_runtime_dir}"
        )
        if(TARGET Qt6::CanvasPainter)
            set_tests_properties(canvas_painter_renderer_tests PROPERTIES
                ENVIRONMENT_MODIFICATION
                    "PATH=path_list_prepend:${_compiler_runtime_dir};PATH=path_list_prepend:${_qt_runtime_dir}"
            )
        endif()
    endif()
    set_tests_properties(machine_control_serial_diagnostics_tests PROPERTIES
        LABELS "fast;serial-diagnostics"
        TIMEOUT 15
    )
    set_tests_properties(SettingsView_qml_tests PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QML_XHR_ALLOW_FILE_READ=1"
        LABELS "fast;settings"
        TIMEOUT 15
    )
    if(WIN32)
        set_tests_properties(SettingsView_qml_tests PROPERTIES
            ENVIRONMENT_MODIFICATION
                "PATH=path_list_prepend:${_compiler_runtime_dir};PATH=path_list_prepend:${_qt_runtime_dir}"
        )
    endif()
endif()

# Feature regression guard (tools/feature-guard.txt): runs on every build of prototype.
add_custom_target(feature_guard ALL
    COMMAND ${CMAKE_COMMAND} -DROOT=${CMAKE_CURRENT_SOURCE_DIR} -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/FeatureGuard.cmake
    COMMENT "Checking feature regression markers"
    VERBATIM)
add_dependencies(prototype feature_guard)
add_test(NAME feature_guard COMMAND ${CMAKE_COMMAND} -DROOT=${CMAKE_CURRENT_SOURCE_DIR} -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/FeatureGuard.cmake)

