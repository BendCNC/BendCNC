import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    id: root
    width: 864
    height: 668

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
    }

    BendCNC.CadImportView {
        id: view
        anchors.fill: parent
        appState: state
    }

    BendCNC.OnScreenKeyboard {
        anchors.fill: parent
        appState: state
    }

    TestCase {
        name: "CadImportViewTests"
        when: windowShown

        function init() {
            state.closeOnScreenKeyboardState()
            state.virtualInputMode = "ALWAYS"
            var rows = [
                {
                    id: "A", seq: 1, fix: "AUTO", locked: false,
                    angle: "90.0", angleValue: 90, width: "9.729", tonnage: "4.575",
                    tonnageValue: 4.575, vdie: "8mm", dir: "UP", ref: "EDGE",
                    setup: "Standard segmented setup", setupLabel: "STD",
                    punch: "GN88", punchName: "Gooseneck 88° Punch",
                    dieName: "Acute 8mm Die", chg: "START", bg: "0.9494",
                    bgr: "-0.2500", bgrValue: -0.25, status: "OK",
                    errors: [], warnings: []
                },
                {
                    id: "B", seq: 2, fix: "AUTO", locked: false,
                    angle: "90.0", angleValue: 90, width: "6.809", tonnage: "3.202",
                    tonnageValue: 3.202, vdie: "8mm", dir: "UP", ref: "EDGE",
                    setup: "Standard segmented setup", setupLabel: "STD",
                    punch: "GN88", punchName: "Gooseneck 88° Punch",
                    dieName: "Acute 8mm Die", chg: "SAME", bg: "0.9494",
                    bgr: "-0.2500", bgrValue: -0.25, status: "OK",
                    errors: [], warnings: []
                }
            ]
            state.cadImported = true
            state.cadHasErrors = false
            state.cadBendCount = rows.length
            state.cadLoadedJson = {
                bends: [
                    { id: "A", sequence: 1, direction: "UP", angle_deg: 90, bgRPosition_in: -0.25 },
                    { id: "B", sequence: 2, direction: "UP", angle_deg: 90, bgRPosition_in: -0.25 }
                ]
            }
            state.cadSuggestedOrderIds = ["A", "B"]
            state.cadBends = rows
            view.selectedBendIndex = 0
            wait(10)
        }

        function test_editableFieldsOpenCorrectKeyboard() {
            const programName = findChild(view, "cad-program-name-input")
            const backGaugeR = findChild(view, "cad-bgr-input")
            verify(programName && backGaugeR)

            mouseClick(programName)
            compare(state.onScreenKeyboardKind, "text")
            state.clearOnScreenKeyboard()
            state.insertOnScreenKeyboardText("CAD TOUCH PROGRAM")
            verify(state.commitOnScreenKeyboard())
            compare(state.cadProgramName, "CAD TOUCH PROGRAM")

            mouseClick(backGaugeR)
            compare(state.onScreenKeyboardKind, "numeric")
            state.insertOnScreenKeyboardText("-0.375")
            verify(state.commitOnScreenKeyboard())
            compare(state.cadBends[0].bgr, "-0.3750")
        }

        function test_rowsRenderModelDataAndSelectionDefaults() {
            wait(50)
            compare(view.selectedBendIndex, 0)
            compare(view.selectedBend().id, "A")
            verify(view.visible)
            compare(state.cadBends[0].angle, "90.0")
            compare(state.cadBends[1].width, "6.809")
        }

        function test_dragReleaseReordersAndKeepsSelection() {
            view.draggedBendIndex = 0
            view.draggedBendTargetIndex = 1
            var row = findChild(view, "cad-bend-row-0")
            verify(row !== null)
            row.finishDragReorder()
            compare(state.cadBends[0].id, "B")
            compare(state.cadBends[1].id, "A")
            compare(view.selectedBendIndex, 1)
            compare(view.draggedBendIndex, -1)
            compare(view.draggedBendTargetIndex, -1)
        }
    }
}