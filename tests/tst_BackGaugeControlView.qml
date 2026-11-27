import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    id: root
    width: 864
    height: 638.4

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
    }

    BendCNC.BackGaugeControlView {
        id: view
        anchors.fill: parent
        appState: state
    }

    BendCNC.OnScreenKeyboard {
        id: keyboard
        anchors.fill: parent
        appState: state
    }

    TestCase {
        name: "BackGaugeControlViewTests"
        when: windowShown

        function init() {
            state.moduleConnected = true
            state.backGaugeBusy = false
            state.backGaugeHomed = true
            state.backGaugeStatus = "IDLE"
            state.backGaugeMachineX = 0
            state.backGaugeMachineR = 0
            state.backGaugeCoordinateSystem = "G54"
            state.backGaugeCoordinateOffsets = ({ G54: { x: 0, r: 0 }, G55: { x: 0, r: 0 }, G56: { x: 0, r: 0 }, G57: { x: 0, r: 0 }, G58: { x: 0, r: 0 }, G59: { x: 0, r: 0 } })
            state.backGaugeActiveDirection = ""
            state.backGaugeContinuousJog = false
            state.jogStep = 0.1
            state.jogSpeed = 100
            state.backGaugeLimitX1 = false
            state.backGaugeLimitX2 = false
            state.backGaugeLimitR1 = false
            state.backGaugeLimitR2 = false
            state.popupVisible = false
            state.alarmVisible = false
            state.onScreenKeyboardVisible = false
            state.closeOnScreenKeyboardState()
            state.virtualInputMode = "ALWAYS"
            const nameEditor = findChild(view, "coordinate-name-editor")
            if (nameEditor)
                nameEditor.visible = false
            wait(0)
        }

        function test_controlsAndGeometry() {
            const negativeX = findChild(view, "buttonNegativeX")
            const positiveX = findChild(view, "buttonPositiveX")
            const positiveR = findChild(view, "buttonPositiveR")
            const negativeR = findChild(view, "buttonNegativeR")
            const moveX = findChild(view, "move-x-field")
            const moveR = findChild(view, "move-r-field")
            const runButton = findChild(view, "move-run-button")
            const selector = findChild(view, "coordinate-systems-box")
            verify(negativeX && positiveX && positiveR && negativeR)
            verify(moveX && moveR && runButton && selector)
            verify(moveX.width > 100)
            verify(moveR.width > 100)
            compare(selector.model.length, 6)
            compare(selector.displayText, state.backGaugeCoordinateDisplayName("G54"))
            verify(runButton.x + runButton.width <= runButton.parent.width + 0.01)
        }

        function test_profileDropdownRendersEveryName() {
            state.backGaugeCoordinateNames = ({
                G54: "LOWER FINGER",
                G55: "UPPER FINGER",
                G56: "FRONT STOP",
                G57: "REAR STOP",
                G58: "PROFILE FIVE",
                G59: "PROFILE SIX"
            })
            wait(0)
            const selector = findChild(view, "coordinate-systems-box")
            verify(selector)
            compare(selector.model.length, 6)
            for (let index = 0; index < selector.model.length; index++) {
                const id = selector.model[index]
                verify(String(state.backGaugeCoordinateDisplayName(id)).length > 0)
            }
            compare(selector.displayText, "LOWER FINGER")
            selector.currentIndex = 5
            state.selectBackGaugeCoordinateSystem("G59")
            compare(selector.displayText, "PROFILE SIX")
        }

        function test_touchKeyboardsOpenAndCommit() {
            const nameButton = findChild(view, "coordinate-name-edit-button")
            const nameEditor = findChild(view, "coordinate-name-editor")
            const moveX = findChild(view, "move-x-field")
            verify(nameButton && nameEditor && moveX)

            mouseClick(nameButton)
            verify(state.onScreenKeyboardVisible)
            compare(state.onScreenKeyboardKind, "text")
            compare(state.onScreenKeyboardTarget, nameEditor)
            state.clearOnScreenKeyboard()
            state.insertOnScreenKeyboardText("LOWER TOUCH FINGER")
            verify(state.commitOnScreenKeyboard())
            compare(state.backGaugeCoordinateDisplayName("G54"), "LOWER TOUCH FINGER")
            verify(!state.onScreenKeyboardVisible)

            mouseClick(moveX)
            verify(state.onScreenKeyboardVisible)
            compare(state.onScreenKeyboardKind, "numeric")
            compare(state.onScreenKeyboardTarget, moveX)
            state.clearOnScreenKeyboard()
            state.insertOnScreenKeyboardText("1.2500")
            verify(state.commitOnScreenKeyboard())
            compare(moveX.text, "1.2500")
        }

        function test_touchKeyboardRespectsNeverMode() {
            state.virtualInputMode = "NEVER"
            const moveX = findChild(view, "move-x-field")
            verify(moveX)
            mouseClick(moveX)
            verify(!state.onScreenKeyboardVisible)
        }

        function test_touchKeyboardRejectsInvalidNumericValue() {
            const moveX = findChild(view, "move-x-field")
            verify(moveX)
            const originalValue = moveX.text
            mouseClick(moveX)
            verify(state.onScreenKeyboardVisible)
            state.clearOnScreenKeyboard()
            state.insertOnScreenKeyboardText("1..2")
            verify(!state.commitOnScreenKeyboard())
            compare(moveX.text, originalValue)
            verify(state.onScreenKeyboardVisible)
            verify(state.cancelOnScreenKeyboard())
        }

        function test_numericKeyboardUsesCompactJavaLayout() {
            const moveX = findChild(view, "move-x-field")
            verify(moveX)
            mouseClick(moveX)
            tryCompare(state, "onScreenKeyboardKind", "numeric")

            const panel = findChild(keyboard, "numeric-osk-panel")
            verify(panel)
            compare(panel.width, 397)
            compare(panel.height, 537)
            verify(panel.width < keyboard.width / 2)
            const display = findChild(keyboard, "numeric-value-display")
            const displayText = findChild(keyboard, "numeric-value-text")
            verify(display)
            verify(displayText)
            compare(display.height, 85)
            compare(displayText.text, "")
            verify(findChild(keyboard, "numeric-delete-key"))
            verify(findChild(keyboard, "numeric-clear-key"))
            verify(findChild(keyboard, "numeric-ok-key"))
            verify(!findChild(keyboard, "qwerty-value-display"))
            const one = findChild(keyboard, "numeric-key-1")
            const clear = findChild(keyboard, "numeric-clear-key")
            const ok = findChild(keyboard, "numeric-ok-key")
            verify(one && clear && ok)
            fuzzyCompare(one.width, clear.width, 0.01)
            fuzzyCompare(one.width, ok.width, 0.01)
            fuzzyCompare(one.width, one.height, 0.01)
            fuzzyCompare(clear.width, clear.height, 0.01)
            fuzzyCompare(ok.height, one.height * 2 + 7, 0.01)
            state.insertOnScreenKeyboardText("7")
            compare(displayText.text, "7")
            const header = findChild(keyboard, "osk-header")
            const headerContent = findChild(keyboard, "osk-header-content")
            const title = findChild(keyboard, "osk-header-title")
            const close = findChild(keyboard, "osk-close-button")
            const closeContent = findChild(close, "osk-key-content")
            const oneContent = findChild(one, "osk-key-content")
            const oneLabel = findChild(one, "osk-key-label")
            verify(header && headerContent && title && close && closeContent && oneContent && oneLabel)
            compare(title.horizontalAlignment, Text.AlignLeft)
            compare(title.verticalAlignment, Text.AlignVCenter)
            fuzzyCompare(headerContent.height, header.height - 4, 0.01)
            fuzzyCompare(title.y + title.height / 2, headerContent.height / 2, 0.01)
            fuzzyCompare(close.y + closeContent.y + closeContent.height / 2,
                         headerContent.height / 2, 0.01)
            fuzzyCompare(title.y + title.height / 2, header.height / 2 - 2, 0.01)
            fuzzyCompare(close.y + closeContent.y + closeContent.height / 2,
                         header.height / 2 - 2, 0.01)
            fuzzyCompare(oneContent.x + oneContent.width / 2, one.width / 2, 0.01)
            fuzzyCompare(oneContent.y + oneContent.height / 2, one.height / 2, 0.01)
            fuzzyCompare(oneLabel.width, oneContent.width, 0.01)
            fuzzyCompare(oneLabel.height, oneContent.height, 0.01)
            compare(oneLabel.horizontalAlignment, Text.AlignHCenter)
            compare(oneLabel.verticalAlignment, Text.AlignVCenter)
        }

        function test_numericFirstKeyReplacesOriginalValue() {
            const moveX = findChild(view, "move-x-field")
            verify(moveX)
            moveX.text = "12.5000"
            mouseClick(moveX)
            verify(state.onScreenKeyboardOriginalValue)
            state.insertOnScreenKeyboardText("7")
            compare(state.onScreenKeyboardValue, "7")
            compare(state.onScreenKeyboardCursor, 1)
            verify(!state.onScreenKeyboardOriginalValue)
        }

        function test_qwertyKeyboardUsesFullJavaLayout() {
            const nameButton = findChild(view, "coordinate-name-edit-button")
            verify(nameButton)
            mouseClick(nameButton)
            tryCompare(state, "onScreenKeyboardKind", "text")

            const panel = findChild(keyboard, "qwerty-osk-panel")
            verify(panel)
            compare(panel.width, 844)
            compare(panel.height, 618.4)
            verify(panel.width > keyboard.width * 0.9)
            verify(findChild(keyboard, "qwerty-value-display"))
            verify(findChild(keyboard, "qwerty-clear-key"))
            verify(findChild(keyboard, "qwerty-delete-key"))
            verify(findChild(keyboard, "qwerty-shift-key"))
            verify(findChild(keyboard, "qwerty-symbol-key"))
            verify(findChild(keyboard, "qwerty-left-key"))
            verify(findChild(keyboard, "qwerty-right-key"))
            verify(findChild(keyboard, "qwerty-space-key"))
            verify(findChild(keyboard, "qwerty-ok-key"))
            const numberKey = findChild(keyboard, "qwerty-number-key-0")
            const letterKey = findChild(keyboard, "qwerty-row1-key-0")
            const deleteKey = findChild(keyboard, "qwerty-delete-key")
            const shiftKey = findChild(keyboard, "qwerty-shift-key")
            const symbolKey = findChild(keyboard, "qwerty-symbol-key")
            verify(numberKey && letterKey && deleteKey && shiftKey && symbolKey)
            fuzzyCompare(numberKey.height, letterKey.height, 0.01)
            fuzzyCompare(numberKey.height, deleteKey.height, 0.01)
            fuzzyCompare(numberKey.height, shiftKey.height, 0.01)
            fuzzyCompare(numberKey.height, symbolKey.height, 0.01)
        }

        function test_qwertyShiftCapsSymbolsAndCancel() {
            const nameButton = findChild(view, "coordinate-name-edit-button")
            const nameEditor = findChild(view, "coordinate-name-editor")
            verify(nameButton && nameEditor)
            const originalValue = nameEditor.text
            mouseClick(nameButton)
            verify(state.onScreenKeyboardVisible)

            compare(state.onScreenKeyboardShiftState, "NONE")
            state.cycleOnScreenKeyboardShift()
            compare(state.onScreenKeyboardShiftState, "SHIFT")
            state.cycleOnScreenKeyboardShift()
            compare(state.onScreenKeyboardShiftState, "CAPS")
            state.cycleOnScreenKeyboardShift()
            compare(state.onScreenKeyboardShiftState, "NONE")

            state.onScreenKeyboardSymbols = true
            verify(state.onScreenKeyboardSymbols)
            state.clearOnScreenKeyboard()
            state.insertOnScreenKeyboardText("#")
            compare(state.onScreenKeyboardValue, "#")
            verify(state.cancelOnScreenKeyboard())
            compare(nameEditor.text, originalValue)
        }

        function test_stepContinuousAndRapidContracts() {
            verify(state.setBackGaugeJogStep(0.25, false))
            compare(state.jogStep, 0.25)
            verify(!state.backGaugeContinuousJog)
            verify(state.setBackGaugeJogStep(state.jogStep, true))
            verify(state.backGaugeContinuousJog)
            verify(state.setBackGaugeJogSpeed(state.backGaugeSpeedPresets[5]))
            compare(state.jogSpeed, 100)
            verify(state.setBackGaugeJogStep(-5, false))
            compare(state.jogStep, state.backGaugeMinJogStep)
            verify(state.setBackGaugeJogSpeed(9999))
            compare(state.jogSpeed, state.backGaugeMaxJogSpeed)
        }

        function test_jogPressReleaseAndCommand() {
            state.backGaugeContinuousJog = false
            state.jogStep = 0.1
            verify(state.beginBackGaugeJog("X", 1))
            compare(state.backGaugeActiveDirection, "X+")
            compare(state.backGaugeMachineX, 0.1)
            compare(state.backGaugeStatus, "JOG")
            verify(state.backGaugeLastCommands.length === 1)
            verify(String(state.backGaugeLastCommands[0]).indexOf("G91 G54 X 0.1000 F 100.00") >= 0)
            verify(!state.beginBackGaugeJog("R", 1))
            verify(state.releaseBackGaugeJog("X", 1))
            compare(state.backGaugeActiveDirection, "")
            compare(state.backGaugeStatus, "IDLE")
        }

        function test_continuousJogRepeatsAndCancels() {
            state.backGaugeContinuousJog = true
            verify(state.beginBackGaugeJog("R", -1))
            compare(String(state.backGaugeLastCommands[0]).substring(0, 3), "$J=")
            verify(state.continueBackGaugeJog())
            compare(state.backGaugeLastCommands.length, 2)
            compare(String(state.backGaugeLastCommands[1]).substring(0, 3), "$J=")
            verify(state.releaseBackGaugeJog("R", -1))
            compare(state.backGaugeActiveDirection, "")
            compare(state.backGaugeLastCommands.length, 3)
            compare(state.backGaugeLastCommands[2].charCodeAt(0), 0x85)
            verify(!state.continueBackGaugeJog())
            compare(state.backGaugeLastCommands.length, 3)
        }

        function test_workAndMachineTabsSwitchBothDirections() {
            const machineTab = findChild(view, "machine-coordinate-tab")
            const workTab = findChild(view, "work-coordinate-tab")
            const xField = findChild(view, "work-x-field")
            verify(machineTab && workTab && xField)
            state.backGaugeMachineX = 3
            state.backGaugeCoordinateOffsets = ({ G54: { x: 1, r: 0 }, G55: { x: 0, r: 0 }, G56: { x: 0, r: 0 }, G57: { x: 0, r: 0 }, G58: { x: 0, r: 0 }, G59: { x: 0, r: 0 } })
            state.updateBackGaugeWorkPosition()
            compare(xField.text, "2.0000")
            mouseClick(machineTab)
            compare(xField.text, "3.0000")
            verify(xField.readOnly)
            mouseClick(workTab)
            compare(xField.text, "2.0000")
            verify(!xField.readOnly)
        }

        function test_stopCommandsAndAutomaticRecovery() {
            verify(state.backGaugeStop())
            compare(state.backGaugeStatus, "RESETTING")
            verify(state.backGaugeBusy)
            verify(!state.backGaugeHomed)
            compare(state.backGaugeLastCommands.length, 2)
            compare(state.backGaugeLastCommands[0], "!")
            compare(state.backGaugeLastCommands[1].charCodeAt(0), 0x18)
            verify(state.completeBackGaugeReset())
            compare(state.backGaugeStatus, "IDLE")
            verify(!state.backGaugeBusy)
            verify(state.backGaugeHomed)
        }

        function test_coordinateSetAndMoveTo() {
            state.backGaugeMachineX = 2
            state.backGaugeMachineR = 1
            state.updateBackGaugeWorkPosition()
            verify(state.selectBackGaugeCoordinateSystem("G57"))
            verify(state.setBackGaugeWorkPosition("X", 0.5))
            compare(state.backGaugeX, 0.5)
            compare(state.backGaugeMachineX, 2)
            verify(state.backGaugeMoveTo(-1.25, 0.75))
            compare(state.backGaugeX, -1.25)
            compare(state.backGaugeR, 0.75)
            compare(state.backGaugeLastCommands.length, 2)
            verify(String(state.backGaugeLastCommands[0]).indexOf("G57") >= 0)
            verify(!state.backGaugeMoveTo("not-a-number", 0))
            verify(state.alarmVisible)
        }

        function test_homeLimitAndLifecycle() {
            state.backGaugeLimitR1 = true
            verify(!state.requestBackGaugeHome())
            verify(state.alarmVisible)
            state.clearAlarm()
            state.backGaugeLimitR1 = false
            verify(state.requestBackGaugeHome())
            compare(state.popupAction, "back-gauge-home-confirm")
            state.performPopupPrimaryAction()
            compare(state.backGaugeStatus, "HOMING")
            verify(state.backGaugeBusy)
            verify(!state.backGaugeHomed)
            compare(state.backGaugeLastCommands[0], "$H")
            state.cancelBackGaugeHome()
            compare(state.backGaugeLastCommands[0].charCodeAt(0), 0x18)
            compare(state.backGaugeStatus, "IDLE")
            verify(state.requestBackGaugeHome())
            compare(state.popupKind, "caution")
            compare(state.popupAction, "back-gauge-home-confirm")
            compare(state.popupButtonText, "HOME")
            compare(state.popupCancelButtonText, "CLOSE")
            state.performPopupPrimaryAction()
            compare(state.popupKind, "blur")
            state.completeBackGaugeHome()
            compare(state.popupKind, "message")
            compare(state.backGaugeStatus, "IDLE")
            verify(state.backGaugeHomed)
            verify(!state.backGaugeBusy)
        }

        function test_disconnectAndStatusDecode() {
            verify(state.ingestBackGaugeStatus("<Idle|MPos:3.0000,2.0000,0.0000|WCO:1.0000,0.5000,0.0000|Pn:XY>"))
            compare(state.backGaugeMachineX, 3)
            compare(state.backGaugeMachineR, 2)
            compare(state.backGaugeX, 2)
            compare(state.backGaugeR, 1.5)
            verify(state.backGaugeLimitX1)
            verify(state.backGaugeLimitR1)
            state.setConnection("module", false)
            compare(state.backGaugeStatus, "UNKNOWN")
            verify(!state.backGaugeHomed)
            verify(!state.backGaugeReady)
        }
    }
}
