# A source/resource tripwire, not a replacement for the native and QML tests.
# Run both at configure time and before every prototype build, including ARM.
if(NOT DEFINED THC_SOURCE_DIR)
    get_filename_component(THC_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()

function(thc_require_text relative_path)
    if(NOT EXISTS "${THC_SOURCE_DIR}/${relative_path}")
        message(FATAL_ERROR "THC live integration missing file: ${relative_path}")
    endif()
    file(READ "${THC_SOURCE_DIR}/${relative_path}" content)
    foreach(required IN LISTS ARGN)
        string(FIND "${content}" "${required}" position)
        if(position EQUAL -1)
            message(FATAL_ERROR
                "THC live integration regression in ${relative_path}: missing '${required}'. Restore the complete integration; do not remove this guard.")
        endif()
    endforeach()
endfunction()

thc_require_text("CMakeLists.txt"
    "qml/ThcLiveTuningPanel.qml"
    "qml/ThcLiveTuningView.qml"
    "qml/ThcTelemetryHistory.qml"
    "qml/ThcTonnageChart.qml"
    "add_dependencies(prototype thc_live_integration_guard)"
    "NAME thc_live_packaged_tests"
    "ThcLiveTuningPanel_foreground_qml_tests"
    "tests/tst_ThcV51OwnerProtocol.cpp")
thc_require_text("qml/ManualModeView.qml"
    "button-thc-live-fine-tune" "manual-thc-live-loader"
    "ThcLiveTuningPanel {" "root.liveTuningOpen = true"
    "root.appState.machineControl" "root.appState.offlineSimulationEnabled")
thc_require_text("qml/ThcLiveTuningPanel.qml"
    "thc-live-tuning-panel" "backend.pressSafetyStopUnconfirmed"
    "contentItem: ThcLiveTuningView {" "ThcTelemetryHistory {"
    "backend.applyThcLiveTuning(settings)" "startBackend.startContinuousThcContactProfile()"
    "preferFine: root.ownsOperation" "fineOwnerId: root.ownsOperation ? root.ownerId"
    "onSurfaceActiveChanged:" "Component.onDestruction: cancelOwned()")
thc_require_text("qml/ThcLiveTuningView.qml"
    "ThcTonnageChart {" "thc-live-confirm-start" "thc-live-stop"
    "root.controller.confirmStart()" "root.controller.cancelOwned()")
thc_require_text("qml/ThcTelemetryHistory.qml"
    "backend.pressTelemetrySequence" "backend.motorRpmAvailable"
    "backend.pressTelemetryFresh" "maximumSamples: 2048" "windowMs: 60000"
    "TH_CTRL_FILTERED_PRE_DEADZONE" "function onThcFineLoadChanged()")
thc_require_text("qml/ThcTonnageChart.qml" "history.seriesSegments" "sample.at")
thc_require_text("qml/main.qml" "--open-thc-live-tuning" "liveTuningCaptureItem")
thc_require_text("src/MachineControlBackend.h"
    "Q_PROPERTY(bool pressSafetyStopUnconfirmed"
    "Q_PROPERTY(QVariantMap thcFineLoad READ thcFineLoad NOTIFY thcFineLoadChanged FINAL)"
    "Q_INVOKABLE bool queryThcLiveTuning()"
    "Q_INVOKABLE bool applyThcLiveTuning(const QVariantMap &settings)"
    "Q_INVOKABLE bool startContinuousThcContactProfile()")
thc_require_text("src/MachineControlBackend.cpp"
    "MachineControlBackend::queryThcLiveTuning()"
    "MachineControlBackend::applyThcLiveTuning("
    "MachineControlBackend::startContinuousThcContactProfile()"
    "MachineControlBackend::observeThcFineLoad(" "MachineControlBackend::thcFineLoad() const"
    "MachineControlBackend::checkThcV53Deadlines()"
    "MachineControlBackend::beginThcV53Cancellation(")
thc_require_text("src/SerialMachineTransport.cpp" "<THC:V53?>" "<THC:CONTACT_PROFILE_V53>")
thc_require_text("src/main.cpp" "ThcLiveIntegrationCheck.h" "startThcLiveIntegrationCheck(")
thc_require_text("src/ThcLiveIntegrationCheck.h" "THC-LIVE-INTEGRATION PASS"
    "meta->indexOfProperty(\"thcFineLoad\")" "packaged fine-source observer/offline isolation failed")
message(STATUS "THC live integration source guard passed")