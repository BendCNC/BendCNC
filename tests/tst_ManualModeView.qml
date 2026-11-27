import QtQuick
import QtTest
import QtQuick.Controls.Basic
import "../qml" as BendCNC

Control {
    width: 864
    height: 638
    font.family: testTheme.appFontFamily

    BendCNC.Theme { id: testTheme }

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
    }

    BendCNC.AppState {
        id: dispatchProbe
        offlineSimulationEnabled: true
        safetyPopupsEnabled: false
        property string receivedAction: ""
        property var receivedValue: undefined
        function manualAction(action, value) {
            receivedAction = action
            receivedValue = value
            return true
        }
        function activateManualMode() { receivedAction = "enable"; return true }
        function deactivateManualMode() { receivedAction = "disable"; return true }
    }

    BendCNC.ManualModeView {
        id: view
        anchors.fill: parent
        appState: state
    }

    BendCNC.OnScreenKeyboard {
        anchors.fill: parent
        appState: state
    }

    TestCase {
        name: "ManualModeViewTests"
        when: windowShown

        function init() {
            view.appState = state
            state.offlineSimulationEnabled = true
            state.manualModeArmed = true
            state.manualModeState = "ENABLED"
            state.manualRepeatStroke = false
            state.manualRepeatJog = false
            state.tonnageHoldActive = false
            state.contactProfileActive = false
            state.closeManualMeasurement()
            state.tonnageHoldTarget = 1.0
            state.virtualInputMode = "ALWAYS"
            state.onScreenKeyboardVisible = false
            state.closeOnScreenKeyboardState()
            state.applyUserSettings({
                manualModeSafetyPlaneClearance: { value: 0.05, unit: "INCH" },
                manualModeStartRamPosition: { value: -1.0, unit: "INCH" },
                manualModeEndRamPosition: { value: -1.0001, unit: "INCH" },
                manualModeMaxTonnagePerRam: 12.5,
                jogStep: { value: 0.1, unit: "INCH" },
                manualModeMoveToPosition: { value: -2.0, unit: "INCH" },
                manualDieTopCalibration: { value: 0.0, unit: "INCH", valid: false }
            })
            wait(0)
        }

        function cleanup() { view.appState = state }

        function test_actionButtonsKeepTheirDispatch_data() {
            return [
                { tag: "stroke", name: "button-run-manual-stroke", action: "stroke" },
                { tag: "up", name: "manual-jog-up", action: "jog-up" },
                { tag: "down", name: "manual-jog-down", action: "jog-down" },
                { tag: "move", name: "button-run", action: "move-to" },
                { tag: "continuous", name: "button-manual-continuous-jog", action: "continuous-down" },
                { tag: "pedal", name: "button-tonnage-hold button-tonnage-hold-active", action: "tonnage-hold" },
                { tag: "cancel-auto", name: "button-automatic-tonnage-hold", action: "automatic-tonnage-hold" }
            ]
        }

        function test_actionButtonsKeepTheirDispatch(data) {
            dispatchProbe.receivedAction = ""
            dispatchProbe.contactProfileActive = data.tag === "cancel-auto"
            view.appState = dispatchProbe
            waitForRendering(view)
            const button = findChild(view, data.name)
            verify(button && button.enabled)
            mouseClick(button)
            compare(dispatchProbe.receivedAction, data.action)
            if (data.tag === "move")
                compare(dispatchProbe.receivedValue, dispatchProbe.manualMoveToPosition)
            dispatchProbe.contactProfileActive = false
        }

        function test_explicitManualEnableDisableRemainsClickable() {
            view.appState = dispatchProbe
            dispatchProbe.manualModeArmed = false
            dispatchProbe.receivedAction = ""
            const button = findChild(view, "button-enable-manual-machine")
            mouseClick(button)
            compare(dispatchProbe.receivedAction, "enable")
            dispatchProbe.manualModeArmed = true
            mouseClick(button)
            compare(dispatchProbe.receivedAction, "disable")
        }

        function test_disconnectedMotionStaysDisabledButCardsOpen() {
            state.offlineSimulationEnabled = false
            waitForRendering(view)
            const buttons = ["button-run-manual-stroke", "manual-jog-up", "manual-jog-down",
                             "button-run", "button-manual-continuous-jog",
                             "button-tonnage-hold button-tonnage-hold-active", "button-automatic-tonnage-hold"]
            for (const name of buttons)
                compare(findChild(view, name).enabled, false, name)
            mouseClick(findChild(view, "button-die-top-calibration"))
            verify(state.manualMeasurementVisible)
            verify(state.closeManualMeasurement())
        }

        function test_serviceMenuKeepsBothMeasurementRoutes() {
            const calibration = findChild(view, "button-die-top-calibration")
            const measurement = findChild(view, "button-piece-measurement")
            verify(calibration && measurement)
            mouseClick(calibration)
            compare(state.manualMeasurementMode, "CALIBRATION")
            verify(state.closeManualMeasurement())
            mouseClick(measurement)
            compare(state.manualMeasurementMode, "MEASUREMENT")
            verify(state.closeManualMeasurement())
        }

        function test_serviceMenuBleedUsesExistingGuardedFlow() {
            const bleed = findChild(view, "button-open-bleed-hydraulics")
            verify(bleed && bleed.enabled)
            mouseClick(bleed)
            compare(state.bleedState, "PRIMING")
            state.bleedState = "IDLE"
        }

        function test_javaParityPanelsAndActionsExist() {
            verify(findChild(view, "panel-set-temp-tonnage-limit"))
            verify(findChild(view, "panel-manual-stroke-operation"))
            verify(findChild(view, "panel-tonnage-hold panel-tonnage-hold-compact"))
            verify(findChild(view, "manual-jog-step-view ManualModeJogStepView"))
            verify(findChild(view, "manual-mode-move-to-view ManualModeMoveToView"))
            verify(findChild(view, "button-run-manual-stroke"))
            verify(findChild(view, "button-tonnage-hold button-tonnage-hold-active"))
            verify(findChild(view, "button-manual-continuous-jog"))
            verify(findChild(view, "manual-measurement-menu manual-service-menu"))
            verify(findChild(view, "button-die-top-calibration"))
            verify(findChild(view, "button-piece-measurement"))
            verify(findChild(view, "button-open-bleed-hydraulics"))
            verify(findChild(view, "button-enable-manual-machine"))
        }

        function test_subcardBodiesJoinHeadersWithoutRoundedGaps() {
            const panels = [
                "panel-set-temp-tonnage-limit", "panel-manual-stroke-operation",
                "manual-calibration-card", "manual-bleed-card",
                "panel-tonnage-hold panel-tonnage-hold-compact",
                "manual-jog-step-view ManualModeJogStepView",
                "manual-mode-move-to-view ManualModeMoveToView"
            ]
            waitForRendering(view)
            // Capture the viewport and map item coordinates explicitly: the
            // offscreen software backend crops nested grabs from the origin.
            const image = grabImage(view)
            const scaleX = image.width / view.width
            const scaleY = image.height / view.height
            for (const name of panels) {
                const panel = findChild(view, name)
                const header = findChild(panel, "header label-title")
                const body = findChild(panel, "manual-subcard-body")
                verify(header && body, name)
                fuzzyCompare(header.y + header.height, body.y, 0.01, name + " gap")
                compare(body.width, header.width, name + " shared width")
                const pos = body.mapToItem(view, 0, 0)
                const left = Math.floor((pos.x + 0.5) * scaleX)
                const right = Math.floor((pos.x + body.width - 0.5) * scaleX)
                const top = Math.floor((pos.y + 0.5) * scaleY)
                const bottom = Math.floor((pos.y + body.height - 0.5) * scaleY)
                compare(image.pixel(left, top), body.color, name + " top left")
                compare(image.pixel(right, top), body.color, name + " top right")
                verify(!Qt.colorEqual(image.pixel(left, bottom), body.color),
                       name + " bottom left stays rounded")
                verify(!Qt.colorEqual(image.pixel(right, bottom), body.color),
                       name + " bottom right stays rounded")
            }
        }

        function test_defaultsAndStrokeDistanceMatchJava() {
            compare(state.manualSafetyPlaneClearance, 0.05)
            compare(state.manualStartRamPosition, -1.0)
            compare(state.manualEndRamPosition, -1.0001)
            fuzzyCompare(state.manualStrokeDistance, 0.0001, 0.0000001)
            compare(state.manualModeMaxTonnagePerRam, 12.5)
            compare(state.manualJogStep, 0.1)
            compare(state.manualMoveToPosition, -2.0)
            compare(state.tonnageHoldTarget, 1.0)
        }

        function test_compactLayoutFitsWithoutOverlaps_data() {
            return [
                { tag: "enabled", mode: "ENABLED" },
                { tag: "disconnected", mode: "DISABLED" },
                { tag: "long-state", mode: "AUTOMATIC HOLD CANCELLING" }
            ]
        }

        function test_compactLayoutFitsWithoutOverlaps(data) {
            state.manualModeState = data.mode
            state.offlineSimulationEnabled = data.mode !== "DISABLED"
            waitForRendering(view)
            const panels = [
                "manual-mode-state-view ManualModeStateView",
                "panel-set-temp-tonnage-limit", "panel-manual-stroke-operation",
                "manual-calibration-card", "manual-bleed-card",
                "panel-tonnage-hold panel-tonnage-hold-compact",
                "manual-jog-step-view ManualModeJogStepView",
                "manual-mode-move-to-view ManualModeMoveToView",
                "button-manual-continuous-jog"
            ].map(function(name) {
                const item = findChild(view, name)
                verify(item, name)
                const pos = item.mapToItem(view, 0, 0)
                verify(pos.x >= 0 && pos.y >= 0, name + " begins outside viewport")
                verify(pos.x + item.width <= view.width + 1, name + " overflows width")
                verify(pos.y + item.height <= view.height + 1, name + " overflows height")
                return { name: name, x: pos.x, y: pos.y, w: item.width, h: item.height }
            })
            for (let i = 0; i < panels.length; ++i) {
                for (let j = i + 1; j < panels.length; ++j) {
                    const a = panels[i], b = panels[j]
                    verify(a.x + a.w <= b.x + 1 || b.x + b.w <= a.x + 1
                           || a.y + a.h <= b.y + 1 || b.y + b.h <= a.y + 1,
                           a.name + " overlaps " + b.name)
                }
            }
            verifyChildrenFit(view)
        }

        function verifyChildrenFit(item) {
            for (let i = 0; i < item.children.length; ++i) {
                const child = item.children[i]
                if (!child.visible || child.width <= 0 || child.height <= 0)
                    continue
                // Controls own internal decorations; validate the control itself,
                // its content size and text rather than Basic style internals.
                const name = (child.objectName || String(child))
                    + (child.text !== undefined ? " [" + child.text + "]" : "")
                verify(child.x >= -1 && child.y >= -1, name + " starts outside parent")
                verify(child.x + child.width <= item.width + 1, name + " exceeds parent width")
                verify(child.y + child.height <= item.height + 1, name + " exceeds parent height")
                if (child.contentItem !== undefined) {
                    if (child.label !== undefined) {
                        verify(child.contentItem.implicitHeight <= child.availableHeight + 1,
                               name + " button text exceeds height")
                        // Designer v9 compact buttons are 38 px (OPEN, RUN, CALIBRATE).
                        verify(child.width >= 38 && child.height >= 38,
                               name + " action target below 38px")
                    }
                } else {
                    if (child.paintedWidth !== undefined) {
                           verify(child.paintedWidth <= child.width + 1,
                               name + " text width " + child.paintedWidth + " > " + child.width)
                        verify(child.paintedHeight <= child.height + 1, name + " text overflows height")
                    }
                    verifyChildrenFit(child)
                }
            }
        }

        function test_presetsAndMeasurementCardsRemainClickable() {
            const preset = findChild(view, "manual-jog-preset-0.0010")
            verify(preset)
            mouseClick(preset)
            compare(state.manualJogStep, 0.001)
            const calibration = findChild(view, "button-die-top-calibration")
            mouseClick(calibration)
            verify(state.manualMeasurementVisible)
            compare(state.manualMeasurementMode, "CALIBRATION")
            verify(state.closeManualMeasurement())
            const measurement = findChild(view, "button-piece-measurement")
            measurement.forceActiveFocus()
            keyClick(Qt.Key_Space)
            verify(state.manualMeasurementVisible)
            compare(state.manualMeasurementMode, "MEASUREMENT")
            verify(state.closeManualMeasurement())
        }

        function test_repeatSwitchesRemainClickable() {
            const strokeToggle = findChild(view, "manual-repeat-stroke")
            const jogToggle = findChild(view, "manual-repeat-jog")
            // Switch indicators occupy the right side of each repeat panel.
            mouseClick(strokeToggle, strokeToggle.width - 30, strokeToggle.height / 2)
            verify(state.manualRepeatStroke)
            mouseClick(jogToggle, jogToggle.width - 30, jogToggle.height / 2)
            verify(state.manualRepeatJog)
        }

        function test_settingOskCommitsAndDisplayBindingRecovers() {
            const field = findChild(view, "manual-setting-jog-step")
            verify(field)
            mouseClick(field)
            tryCompare(state, "onScreenKeyboardVisible", true)
            state.clearOnScreenKeyboard()
            state.insertOnScreenKeyboardText("0.0100")
            verify(state.commitOnScreenKeyboard())
            compare(state.manualJogStep, 0.01)
            wait(0)
            compare(field.text, "0.0100")
        }

        function test_manualSettingRangesAndEndConstraint() {
            verify(state.setManualSetting("manualModeSafetyPlaneClearance", 2.0))
            compare(state.manualSafetyPlaneClearance, 1.0)
            verify(state.setManualSetting("manualModeStartRamPosition", -0.2))
            compare(state.manualStartRamPosition, -1.05)
            verify(state.setManualSetting("manualModeEndRamPosition", -0.5))
            verify(state.manualEndRamPosition <= state.manualStartRamPosition - 0.0001)
            verify(state.setManualSetting("manualModeMaxTonnagePerRam", 30))
            compare(state.manualModeMaxTonnagePerRam, 12.5)
            verify(state.setManualSetting("jogStep", 0))
            compare(state.manualJogStep, 0.0005)
            verify(state.setManualSetting("manualModeMoveToPosition", -10))
            compare(state.manualMoveToPosition, -4.0)
        }

        function test_holdTargetOskClampsAndBindingRecovers() {
            const target = findChild(view, "tonnage-hold-target")
            verify(target)
            mouseClick(target)
            tryCompare(state, "onScreenKeyboardVisible", true)
            state.clearOnScreenKeyboard()
            state.insertOnScreenKeyboardText("99")
            verify(state.commitOnScreenKeyboard())
            compare(state.tonnageHoldTarget, 24.0)
            wait(0)
            compare(target.text, "24.0")
        }

        function test_repeatAndHoldButtonsRemainActive() {
            verify(state.manualAction("toggle-repeat-stroke"))
            verify(state.manualRepeatStroke)
            verify(state.manualAction("toggle-repeat-jog"))
            verify(state.manualRepeatJog)
            state.manualAction("tonnage-hold")
            verify(state.tonnageHoldActive)
            state.manualAction("tonnage-hold")
            verify(!state.tonnageHoldActive)
        }

        function test_calibrationUsesPhysicalMeanMinusKnownPiece() {
            verify(state.openManualMeasurement("CALIBRATION"))
            verify(state.setManualKnownPieceThickness(0.125))
            state.tonnageHoldActive = true
            for (let sample = 0; sample < 100; ++sample) {
                state.ramPosition = 1.375
                state.sampleManualMeasurement()
            }
            fuzzyCompare(state.manualMeasurementResult, 1.25, 0.0000001)
            verify(state.manualDieTopCalibrationValid)
            fuzzyCompare(state.manualDieTopCalibration, 1.25, 0.0000001)
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
            compare(state.manualMeasurementAcceptedSamples, 100)
            compare(state.manualMeasurementAcceptedDurationMs, 9900)
            fuzzyCompare(state.manualMeasurementAcceptedLoadMean, 1.0, 0.0000001)
            fuzzyCompare(state.manualMeasurementAcceptedLoadPeak, 1.0, 0.0000001)
        }

        function test_measurementUsesPersistedDieTopReference() {
            state.applyUserSettings({
                manualDieTopCalibration: { value: 1.25, unit: "INCH", valid: true }
            })
            verify(state.openManualMeasurement("MEASUREMENT"))
            state.tonnageHoldActive = true
            for (let sample = 0; sample < 100; ++sample) {
                state.ramPosition = 1.4375
                state.sampleManualMeasurement()
            }
            fuzzyCompare(state.manualMeasurementResult, 0.1875, 0.0000001)
            compare(state.manualMeasurementStatus, "MEASUREMENT COMPLETE")
        }

        function test_knownPieceUnitConvertsWithoutReinterpretingThickness() {
            verify(state.openManualMeasurement("CALIBRATION"))
            verify(state.setManualKnownPieceThickness(0.125, "INCH"))
            verify(state.setManualKnownPieceUnit("MILLIMETER"))
            fuzzyCompare(state.manualKnownPieceDisplayValue, 3.175, 0.0000001)
            verify(state.setManualKnownPieceThickness(25.4, "MILLIMETER"))
            fuzzyCompare(state.manualKnownPieceThickness, 1.0, 0.0000001)
            verify(state.setManualKnownPieceUnit("INCH"))
            fuzzyCompare(state.manualKnownPieceDisplayValue, 1.0, 0.0000001)
        }

        function test_measurementDiscardsSamplesOutsidePositionGuard() {
            verify(state.openManualMeasurement("CALIBRATION"))
            state.tonnageHoldActive = true
            state.ramPosition = 1.0
            verify(!state.sampleManualMeasurement())
            state.ramPosition = 1.002
            verify(!state.sampleManualMeasurement())
            compare(state.manualMeasurementQualifiedSamples, 2)
            state.ramPosition = 1.006
            verify(!state.sampleManualMeasurement())
            compare(state.manualMeasurementQualifiedSamples, 2)
            compare(state.manualMeasurementStatus, "AVERAGING 2 / 100")
            verify(!isFinite(state.manualMeasurementResult))
        }

        function test_measurementCannotCompleteBeforeQualifiedWindow() {
            verify(state.openManualMeasurement("CALIBRATION"))
            state.tonnageHoldActive = true
            state.ramPosition = 1.375
            for (let sample = 0; sample < 99; ++sample)
                verify(!state.sampleManualMeasurement())
            compare(state.manualMeasurementQualifiedSamples, 99)
            verify(!isFinite(state.manualMeasurementResult))
            verify(state.sampleManualMeasurement())
            compare(state.manualMeasurementAcceptedDurationMs, 9900)
        }

        function test_knownPieceRejectsInvalidUnitAndRange() {
            verify(state.openManualMeasurement("CALIBRATION"))
            verify(!state.setManualKnownPieceThickness(0, "INCH"))
            verify(!state.setManualKnownPieceThickness(10.001, "INCH"))
            verify(!state.setManualKnownPieceThickness(254.1, "MILLIMETER"))
            verify(!state.setManualKnownPieceThickness(1, "CENTIMETER"))
            verify(!state.setManualKnownPieceUnit("CENTIMETER"))
            verify(state.setManualKnownPieceThickness(254, "MILLIMETER"))
            fuzzyCompare(state.manualKnownPieceThickness, 10, 0.0000001)
        }

        function test_measurementRequiresCalibration() {
            verify(state.openManualMeasurement("MEASUREMENT"))
            verify(!state.startManualMeasurementProcess("AUTO"))
            compare(state.alarmTitle, "MEASUREMENT CALIBRATION REQUIRED")
        }
    }
}
