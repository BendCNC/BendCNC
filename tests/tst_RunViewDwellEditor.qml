import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    width: 1024
    height: 768

    BendCNC.DataStore {
        id: store
    }

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
        autoClampEnabled: true
        autoClampDwellEnabled: true
        virtualInputMode: "NEVER"
    }

    BendCNC.RunView {
        id: view
        anchors.fill: parent
        appState: state
        dataStore: store
    }

    TestCase {
        name: "RunViewDwellEditorTests"
        when: windowShown

        function dwellTile() {
            return findChild(view, "dwell-toggle-tile")
        }

        function init() {
            state.cancelOnScreenKeyboard()
            state.autoClampEnabled = true
            state.autoClampDwellEnabled = true
            state.autoClampDwellSec = 3.0
            state.bendModePopupVisible = false
            wait(0)
        }

        function test_bottomControlsKeepStateBinding() {
            const bend = { id: "mode-bend", name: "Mode bend", finalPosition: -1.5 }
            state.setProgramsFromStorage([{ name: "Mode program", bends: [bend] }], [], [], [], {})
            const selector = findChild(view, "bendModeControl")
            const clamp = findChild(view, "auto-clamp-to-bend-control")
            const dwell = findChild(view, "dwell-toggle-tile")
            const deck = findChild(view, "run-operator-deck")
            verify(selector && clamp && dwell && deck)
            // v9 deck: the always-visible 2x2 matrix replaced the upward dock.
            compare(findChild(view, "bend-mode-options-dock"), null)
            compare(deck.height, 74)
            compare(findChild(view, "run-program-actuator").width, 165)
            compare(findChild(view, "run-auto-clamp-bay").width, 245)
            verify(selector.width >= 420)
            verify(selector.enabledState)
            compare(clamp.labelText, "AUTO CLAMP TO BEND")
            verify(dwell.enabledState)
            mouseClick(clamp)
            compare(state.autoClampEnabled, false)
            compare(dwell.enabledState, false)
            verify(!findChild(view, "dwell-increment-button").enabledState)
            mouseClick(clamp)
            compare(state.autoClampEnabled, true)
            verify(dwell.enabledState)
        }

        function test_dwellStepperUsesWholeSecondsWithinProductionLimit() {
            const minus = findChild(view, "dwell-decrement-button")
            const plus = findChild(view, "dwell-increment-button")
            const dwell = dwellTile()
            verify(minus && plus && dwell)
            compare(dwell.displayText, "3 s")
            mouseClick(plus)
            fuzzyCompare(state.autoClampDwellSec, 4.0, 0.001)
            compare(dwell.displayText, "4 s")
            state.autoClampDwellSec = 4.5
            compare(dwell.displayText, "4.5 s")
            mouseClick(minus)
            fuzzyCompare(state.autoClampDwellSec, 4.0, 0.001)
            state.autoClampDwellSec = 9.5
            mouseClick(plus)
            fuzzyCompare(state.autoClampDwellSec, 10.0, 0.001)
            verify(!plus.enabledState)
            mouseClick(plus)
            fuzzyCompare(state.autoClampDwellSec, 10.0, 0.001)
            state.autoClampDwellSec = 1.0
            mouseClick(minus)
            fuzzyCompare(state.autoClampDwellSec, 0.0, 0.001)
            compare(dwell.displayText, "OFF")
            verify(!minus.enabledState)
            verify(plus.enabledState)
            state.autoClampDwellSec = 3.0
            mouseClick(dwell)
            compare(state.autoClampDwellEnabled, false)
            compare(dwell.displayText, "OFF")
            verify(!plus.enabledState)
            mouseClick(dwell)
            compare(state.autoClampDwellEnabled, true)
        }

        function test_stageRibbonFollowsRealExecutionPhases() {
            state.offlineSimulationEnabled = false
            const bays = ["run-stage-start", "run-stage-clamp", "run-stage-final", "run-stage-retract"]
            const phases = [
                ["SAFETY_CLEARANCE_POSITION_MOVE", 0],
                ["CLAMP_MATERIAL_MOVE", 1],
                ["BEND_MOVE", 2],
                ["BACK_GAUGE_AND_RAM_RETRACT_MOVE", 3],
                ["FINISHING_PROGRAM", -1]
            ]
            compare(view.activeRunStage, -1)
            for (let b = 0; b < bays.length; b++)
                verify(!findChild(view, bays[b]).current, "idle must not highlight " + bays[b])
            state.runActive = true
            for (let i = 0; i < phases.length; i++) {
                state.executionPhase = phases[i][0]
                compare(view.activeRunStage, phases[i][1], phases[i][0])
                for (let b = 0; b < bays.length; b++)
                    compare(findChild(view, bays[b]).current, b === phases[i][1], phases[i][0] + " " + bays[b])
            }
            state.runActive = false
            state.executionPhase = "STARTING"
            state.offlineSimulationEnabled = true
            compare(view.activeRunStage, -1)
        }

        function test_headerTextDropsLatin1DegreeArtifacts() {
            compare(view.cleanHeaderText("B1/4 | 90.0\u00C2\u00B0 | GOOSENECK 88\u00C2\u00B0"),
                    "B1/4 | 90.0\u00B0 | GOOSENECK 88\u00B0")
            compare(view.cleanHeaderText("BG X 0.8634\" | DIR UP"), "BG X 0.8634\" | DIR UP")
        }

        function test_bendModeOptionsRemainConnectedAfterSelection() {
            const bends = [
                { id: "mode-a", name: "First", finalPosition: -1.5 },
                { id: "mode-b", name: "Second", finalPosition: -1.4 }
            ]
            state.setProgramsFromStorage([{ name: "Two bends", bends: bends }], [], [], [], {})
            const selector = findChild(view, "bendModeControl")
            verify(selector && selector.enabledState)
            const choices = [
                ["bend-mode-single-once-option", "SINGLE_BEND_MODE"],
                ["bend-mode-single-repeat-option", "SINGLE_BEND_REPEAT"],
                ["bend-mode-program-once-option", "PROGRAM_BEND_MODE"],
                ["bend-mode-program-loop-option", "PROGRAM_BEND_LOOP"]
            ]
            for (let i = 0; i < choices.length; i++) {
                const option = findChild(view, choices[i][0])
                verify(option !== null, choices[i][0])
                verify(option.visible && option.enabledState, choices[i][0] + " should be usable")
                mouseClick(option)
                compare(state.bendMode, choices[i][1])
                compare(selector.mode, choices[i][1])
                verify(option.selected)
                for (let j = 0; j < choices.length; j++)
                    if (j !== i)
                        verify(!findChild(view, choices[j][0]).selected, choices[j][0])
            }

            state.setProgramsFromStorage([{ name: "One bend", bends: [bends[0]] }], [], [], [], {})
            state.setBendMode("PROGRAM_BEND_LOOP")
            compare(state.bendMode, "SINGLE_BEND_MODE")
            const loop = findChild(view, "bend-mode-program-loop-option")
            verify(!loop.enabledState)
            verify(!findChild(view, "bend-mode-program-once-option").enabledState)
            mouseClick(loop)
            compare(state.bendMode, "SINGLE_BEND_MODE")
            verify(findChild(view, "bend-mode-single-once-option").selected)
        }

        function test_longPressOpensNumericKeyboardWithoutTogglingDwell() {
            var tile = dwellTile()
            verify(tile !== null)
            compare(state.autoClampDwellEnabled, true)

            mousePress(tile, tile.width / 2, tile.height / 2)
            wait(900)
            mouseRelease(tile, tile.width / 2, tile.height / 2)
            wait(0)

            compare(state.autoClampDwellEnabled, true)
            compare(state.onScreenKeyboardVisible, true)
            compare(state.onScreenKeyboardKind, "numeric")
            compare(state.onScreenKeyboardTitle, "DWELL TIME (SECONDS)")
            compare(state.onScreenKeyboardValue, "3.0")
        }

        function test_numericCommitUpdatesDwellSeconds() {
            var tile = dwellTile()
            verify(tile !== null)
            mousePress(tile, tile.width / 2, tile.height / 2)
            wait(900)
            mouseRelease(tile, tile.width / 2, tile.height / 2)
            wait(0)

            state.onScreenKeyboardValue = "4.5"
            verify(state.commitOnScreenKeyboard())
            fuzzyCompare(state.autoClampDwellSec, 4.5, 0.001)
        }

        function test_retractTargetTracksSelectedStoredBend() {
            var bends = [
                { id: "retract-a", name: "A", finalPosition: -2.0,
                  punchToMaterialClearance: 0.10, additionalRetractAfterBend: 0.15 },
                { id: "retract-b", name: "B", finalPosition: -1.5,
                  punchToMaterialClearance: 0.10, additionalRetractAfterBend: 0.20 }
            ]
            state.setProgramsFromStorage([
                { id: "retract-test", name: "Retract test", bendIds: ["retract-a", "retract-b"] }
            ], bends, [], [], {})
            compare(state.selectedBend.retractPosition, "-1.7500")
            compare(state.runRamTargetText("retractPosition", " in"), "-1.7500 in")
            state.selectRunBend(1)
            compare(state.selectedBend.retractPosition, "-1.2000")
            compare(state.runRamTargetText("retractPosition", " in"), "-1.2000 in")
        }

        function test_bendListTableShowsProgramDataAndSelectsThroughAppState() {
            const dies = [{ id: "die-v", name: "Acute 30 Die [D-7]", vdieOpeningInch: 0.375 }]
            const punches = [{ id: "punch-g", name: "Gooseneck 88 Punch [P-12]" }]
            const bends = [
                { id: "list-a", name: "A", finalPosition: -1.5, punchId: "punch-g", dieId: "die-v",
                  backGaugeXPosition: 1.25, backGaugeRPosition: 0.5 },
                { id: "list-b", name: "B", finalPosition: -1.4, backGaugeXPosition: 2.5 }
            ]
            state.setProgramsFromStorage([{ id: "list-prog", name: "List program", bendIds: ["list-a", "list-b"] }],
                                         bends, punches, dies, [], {})
            state.runBendListVisible = false
            mouseClick(findChild(view, "run-toggle-list-button"))
            const table = findChild(view, "run-bend-list-table")
            verify(table && table.visible)
            wait(0)
            const row0 = findChild(view, "run-bend-row-0")
            const row1 = findChild(view, "run-bend-row-1")
            verify(row0 && row1)
            compare(row0.punchTitle, "GOOSENECK 88")
            compare(row0.punchCatalog, "P-12")
            compare(row0.dieTitle, "ACUTE 30")
            compare(row0.dieCatalog, "D-7")
            compare(row0.dieVOpening, "V 0.375\"")
            compare(row0.xText, "1.2500\"")
            compare(row0.rText, "0.5000\"")
            compare(row0.statusText, "SELECTED")
            // Unknown tooling is shown as such, never as an invented tool or opening.
            compare(row1.punchTitle, "UNDEFINED")
            compare(row1.dieVOpening, "")
            compare(row1.statusText, "READY")
            verify(state.runSimulationHeader1().indexOf("V 0.375\"") > 0)

            mouseClick(row1)
            compare(state.selectedRunBend, 1)
            compare(state.selectedBend.id, "list-b")
            compare(state.runBendListVisible, false)

            // An admitted execution owns the sequence: the row click is refused.
            state.runBendListVisible = true
            state.runActive = true
            wait(0)
            compare(row1.statusText, "ACTIVE")
            compare(row0.statusText, "DONE")
            mouseClick(row0)
            compare(state.selectedRunBend, 1)
            compare(state.runBendListVisible, true)
            state.runActive = false

            mouseClick(findChild(view, "run-bend-list-close"))
            compare(state.runBendListVisible, false)
            state.runBendListVisible = true
            wait(0)
            mouseClick(findChild(view, "run-bend-list-add"))
            compare(state.runBendListVisible, false)
            compare(state.addBendPopupVisible, true)
            state.closeAddBendPopup()
        }

        function test_retractUsesPhysicalStartWithTableOpening() {
            var bend = { id: "table-retract", name: "Table coordinates", finalPosition: 2.0,
                         punchToMaterialClearance: 0.10, additionalRetractAfterBend: 0.15 }
            state.desktopRamToTableOpening = 4.0
            state.setProgramsFromStorage([
                { name: "Table retract", bends: [bend] }
            ], [], [], [], {})
            compare(state.runRamTargetText("startPosition", " in"), "-1.9000 in")
            compare(state.runRamTargetText("retractPosition", " in"), "-1.7500 in")
        }
    }
}
