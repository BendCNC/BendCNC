import QtQuick
import QtTest

TestCase {
    id: root
    name: "ActionBarViewTests"
    width: 1366
    height: 768
    when: windowShown

    QtObject {
        id: state
        property string cpuLoadText: "12.3%"
        property string cpuLoadLevel: "low"
        property string cpuTemperatureText: "48.9°C"
        property string cpuTemperatureLevel: "low"
        property string memoryText: "15.4%"
        property string memoryLevel: "low"
        property string applicationVersion: "24.1.1"
        property bool applicationUpdateAvailable: false
        property bool moduleUpdateAvailable: false
        property bool machineUpdateAvailable: false
        property bool motorRpmAvailable: true
        property real motorRpmY1: -200
        property real motorRpmY2: 400
        function toolbarAction(action) {}
    }

    function findByObjectName(parent, name) {
        if (!parent)
            return null
        if (String(parent.objectName || "").split(" ").indexOf(name) >= 0)
            return parent
        let children = parent.children || []
        for (let index = 0; index < children.length; index++) {
            let match = findByObjectName(children[index], name)
            if (match)
                return match
        }
        return null
    }

    function findDescendantByObjectName(parent, name) {
        let children = parent ? parent.children || [] : []
        for (let index = 0; index < children.length; index++) {
            let match = findByObjectName(children[index], name)
            if (match)
                return match
        }
        return null
    }

    function createActionBar() {
        let component = Qt.createComponent("../qml/ActionBarView.qml")
        verify(component.status === Component.Ready, component.errorString())
        let bar = component.createObject(root, {
            width: root.width,
            height: 40,
            appState: state
        })
        verify(!!bar)
        wait(0)
        return bar
    }

    function test_metricsTextAndSeverityBindings() {
        let bar = createActionBar()
        let cpu = findByObjectName(bar, "cpu-load-value")
        let temperature = findByObjectName(bar, "cpu-temperature-value")
        let memory = findByObjectName(bar, "memory-used-value")
        verify(!!cpu)
        verify(!!temperature)
        verify(!!memory)
        compare(cpu.text, "12.3%")
        compare(temperature.text, "48.9°C")
        compare(memory.text, "15.4%")
        compare(cpu.color, "#59a60c")
        compare(temperature.color, "#59a60c")
        compare(memory.color, "#59a60c")

        state.cpuLoadText = "76.0%"
        state.cpuLoadLevel = "high"
        state.cpuTemperatureText = "60.0°C"
        state.cpuTemperatureLevel = "medium"
        state.memoryText = "91.2%"
        state.memoryLevel = "high"
        wait(0)
        compare(cpu.text, "76.0%")
        compare(temperature.text, "60.0°C")
        compare(memory.text, "91.2%")
        compare(cpu.color, "#a82011")
        compare(temperature.color, "#ffa500")
        compare(memory.color, "#a82011")

        state.cpuLoadText = "--"
        state.cpuLoadLevel = "unknown"
        state.cpuTemperatureText = "--"
        state.cpuTemperatureLevel = "unknown"
        state.memoryText = "--"
        state.memoryLevel = "unknown"
        wait(0)
        compare(cpu.text, "--")
        compare(temperature.text, "--")
        compare(memory.text, "--")
        compare(cpu.color, "#a8a8a8")
        compare(temperature.color, "#a8a8a8")
        compare(memory.color, "#a8a8a8")
        bar.destroy()
    }

    function test_operatorUtilityButtonsAreWiderWithinFixedBarWithVectorIcons() {
        let bar = createActionBar()
        let logButton = findDescendantByObjectName(bar, "machine-log-view")
        let backupButton = findDescendantByObjectName(bar, "backup-view")
        let wifiButton = findDescendantByObjectName(bar, "wifi-connection-button")
        verify(!!logButton)
        verify(!!backupButton)
        verify(!!wifiButton)

        let buttons = [logButton, backupButton, wifiButton]
        for (let index = 0; index < buttons.length; index++) {
            compare(buttons[index].width, 36)
            compare(buttons[index].height, 32)
            verify(buttons[index].width > buttons[index].height)
            let icon = findByObjectName(buttons[index], "icon-image")
            verify(!!icon)
            verify(icon.source.toString().length > 0)
            tryCompare(icon, "status", Image.Ready)
        }

        verify(wifiButton.iconSource.toString().indexOf("fa-wifi.svg") >= 0)
        compare(wifiButton.iconSize, 26)
        bar.destroy()
    }

    function test_motorRpmRemovedFromActionBar() {
        let bar = createActionBar()
        let y1 = findByObjectName(bar, "y1-motor-rpm-value")
        let y2 = findByObjectName(bar, "y2-motor-rpm-value")
        verify(!y1, "Y1 motor RPM indicator should be removed from upper action bar")
        verify(!y2, "Y2 motor RPM indicator should be removed from upper action bar")
        bar.destroy()
    }

    function test_bleedHydraulicsRemovedFromActionBar() {
        let bar = createActionBar()
        let button = findDescendantByObjectName(bar, "bleed-hydarulics-view")
        verify(!button, "Bleed Hydraulics button should be removed from upper action bar")
        bar.destroy()
    }

}
