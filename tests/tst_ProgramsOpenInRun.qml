import QtQuick
import QtTest
import "../qml" as BendCNC

// PROGRAMS -> RUN hand-off as main.qml performs it: the program switch is
// requested while RUN is not mounted, then the left tab is replaced by RunView,
// which must pick up the pending selection and show the switch overlay.
Item {
    id: root
    width: 1024
    height: 768

    BendCNC.DataStore { id: store }

    BendCNC.AppState {
        id: appState
        offlineSimulationEnabled: true
        virtualInputMode: "NEVER"
    }

    Loader {
        id: tabLoader
        anchors.fill: parent
        onLoaded: {
            if (item.hasOwnProperty("appState"))
                item.appState = appState
            if (item.hasOwnProperty("dataStore"))
                item.dataStore = store
            if (typeof item.openInRunRequested === "function")
                item.openInRunRequested.connect(function() { tabLoader.source = "../qml/RunView.qml" })
        }
    }

    TestCase {
        name: "ProgramsOpenInRunTests"
        when: windowShown

        function test_openFromLibraryFinishesSwitchInRun() {
            let bendA = { id: "bend-a", name: "Bend A", finalPosition: -1.5 }
            let bendB = { id: "bend-b", name: "Bend B", finalPosition: -1.2 }
            appState.setProgramsFromStorage([
                { id: "p-a", name: "Program A", bends: [bendA] },
                { id: "p-b", name: "Program B", bends: [bendB, bendA] }
            ], [], [], [], {})
            compare(appState.activeProgram, "Program A")

            tabLoader.source = "../qml/ProgramsView.qml"
            tryCompare(tabLoader, "status", Loader.Ready)
            let panel = findChild(tabLoader.item, "programs-left-panel-v7")
            verify(!!panel)
            compare(panel.rows.length, 2)
            panel.pickedIndex = 1
            mouseClick(findChild(panel, "programs-open-run"))

            tryVerify(function() { return String(tabLoader.source).indexOf("RunView.qml") >= 0 })
            tryCompare(tabLoader, "status", Loader.Ready)
            tryCompare(appState, "selectedProgramIndex", 1, 3000)
            compare(appState.activeProgram, "Program B")
            compare(appState.programBends.length, 2)
            compare(appState.runProgramSwitchPendingIndex, -1)

            // RunView mounted mid-switch owns the feedback overlay. These
            // synthetic programs carry no CAD preview, so the canvas never
            // reports a ready frame here; completion with a real frame is
            // covered at canvas level by tst_RunExecutionCanvasV5.
            let overlay = findChild(tabLoader.item, "run-program-switch-overlay")
            verify(!!overlay)
            verify(appState.runProgramSwitching)
            verify(overlay.visible)
            appState.finishRunProgramSwitch("ready")
            verify(!overlay.visible)
        }
    }
}
