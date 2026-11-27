import QtQuick
import QtTest
import "../qml/modal-previews/v5-gemini-precision" as Preview

TestCase {
    name: "ManualLeftPreviewTests"
    width: 864
    height: 668
    when: windowShown

    QtObject {
        id: state
        property bool pressCanOperate: false
        property bool manualActivationPending: false
        property bool manualLeavePending: false
        property bool tonnageHoldActive: false
        property bool manualModeEnabled: false
        property bool safetyPopupsEnabled: true
        property bool independentRamTelemetryAvailable: false
        property bool contactProfileActive: false
        property bool manualRepeatJog: false
        property bool manualRepeatStroke: false
        property bool manualDieTopCalibrationValid: false
        property string manualModeState: "IDLE"
        property real manualSafetyPlaneClearance: 0
        property real manualStartRamPosition: 0
        property real manualEndRamPosition: 0
        property real manualModeMaxTonnagePerRam: 0
        property real manualMoveToPosition: 0
        property real manualJogStep: 0
        property real manualStrokeDistance: 0
        property real manualDieTopCalibration: 0
        property real liveTonnage: 0
        property real tonnageHoldTarget: 1
    }

    Preview.ManualLeftView {
        id: preview
        anchors.fill: parent
        appState: state
    }

    function test_zeroValuesAreNotReplacedByFallbacks() {
        compare(preview.settingText("manualModeSafetyPlaneClearance"), "0.0000")
        compare(preview.settingText("manualModeStartRamPosition"), "0.0000")
        compare(preview.settingText("manualModeEndRamPosition"), "0.0000")
        compare(preview.settingText("manualModeMaxTonnagePerRam"), "0.0")
        compare(preview.settingText("manualModeMoveToPosition"), "0.0000")
        compare(preview.settingText("jogStep"), "0.0000")
    }
}
