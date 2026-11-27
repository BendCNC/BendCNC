import QtQuick
import QtTest

TestCase {
    id: root
    name: "SettingsViewTests"

    QtObject {
        id: state
        property string runFlatPatternContourRenderer: "classic"
        property string runToolingAppearance: "SOLID"
        property bool tonnageProtectionEnabled: false
        property bool safetyPopupsEnabled: true
        property bool legacyRunUiEnabled: false
        property bool runPreviewDebugLogsEnabled: false
        property bool serialDiagnosticLogsEnabled: true
        property bool runPreviewDebugOverlaysEnabled: false
        property bool desktopFrameDeflectionCompensationEnabled: false
        property int displaySleepMinutes: 0
        function displaySleepText() {
            return displaySleepMinutes === 0 ? "OFF" : displaySleepMinutes + " MIN"
        }
        function cycleDisplaySleepMinutes() {
            let choices = [0, 5, 10, 30]
            displaySleepMinutes = choices[(choices.indexOf(displaySleepMinutes) + 1) % choices.length]
        }
    }

    function test_numericValuesAreNotConvertedToDisabled() {
        let component = Qt.createComponent("../qml/SettingsView.qml")
        verify(component.status === Component.Ready, component.errorString())
        let view = component.createObject(root, { appState: state })
        verify(!!view)
        compare(view.settingValue("Material Clamp Rate", "10.0 %", "info"), "10.0 %")
        compare(view.settingValue("Air Tonnage Threshold", "0.0", "decimal"), "0.0")
        compare(view.settingValue("Max Tonnage Per Ram", "10.0", "decimal"), "10.0")
        compare(view.settingValue("Tonnage Protection", "DISABLED", "toggle"), "DISABLED")
        view.destroy()
    }

    function test_serialDiagnosticLogsReflectPersistedState() {
        let component = Qt.createComponent("../qml/SettingsView.qml")
        verify(component.status === Component.Ready, component.errorString())
        let view = component.createObject(root, { appState: state })
        verify(!!view)
        verify(view.toggleSelected("Serial Diagnostic Logs", "toggle-info"))
        compare(view.settingValue("Serial Diagnostic Logs", "ENABLED", "toggle-info"), "ENABLED")
        state.serialDiagnosticLogsEnabled = false
        verify(!view.toggleSelected("Serial Diagnostic Logs", "toggle-info"))
        compare(view.settingValue("Serial Diagnostic Logs", "DISABLED", "toggle-info"), "DISABLED")
        view.destroy()
    }

    function test_displaySleepUsesSupportedTimeoutChoices() {
        let component = Qt.createComponent("../qml/SettingsView.qml")
        verify(component.status === Component.Ready, component.errorString())
        let view = component.createObject(root, { appState: state })
        verify(!!view)
        state.displaySleepMinutes = 0
        compare(view.settingValue("Display Sleep", "OFF", "combo"), "OFF")
        state.cycleDisplaySleepMinutes()
        compare(view.settingValue("Display Sleep", "OFF", "combo"), "5 MIN")
        state.cycleDisplaySleepMinutes()
        compare(view.settingValue("Display Sleep", "OFF", "combo"), "10 MIN")
        state.cycleDisplaySleepMinutes()
        compare(view.settingValue("Display Sleep", "OFF", "combo"), "30 MIN")
        state.cycleDisplaySleepMinutes()
        compare(view.settingValue("Display Sleep", "OFF", "combo"), "OFF")
        view.destroy()
    }
}