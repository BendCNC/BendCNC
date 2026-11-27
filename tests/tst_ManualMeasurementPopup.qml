import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    width: 1366
    height: 768

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
    }

    BendCNC.MachinePopupLayer {
        id: machinePopupLayer
        anchors.fill: parent
        appState: state
    }

    BendCNC.MachineAlarmPopupLayer {
        id: machineAlarmPopupLayer
        anchors.fill: parent
        appState: state
    }

    BendCNC.ManualMeasurementPopup {
        id: popup
        anchors.fill: parent
        appState: state
    }

    TestCase {
        name: "ManualMeasurementPopupTests"
        when: windowShown

        function init() {
            state.closeManualMeasurement()
            state.manualModeArmed = true
            state.tonnageHoldActive = false
            state.contactProfileActive = false
            state.manualMeasurementConvergenceEnabled = false
            state.manualMeasurementTonnage = 1.0
            state.tonnageHoldActiveTarget = NaN
            state.ramPosition = 1.375
            state.applyUserSettings({
                manualDieTopCalibration: { value: 0.0, unit: "INCH", valid: false }
            })
            wait(0)
        }

        function test_calibrationModalExposesRealtimeFieldsAndControls() {
            verify(state.openManualMeasurement("CALIBRATION"))
            tryCompare(popup, "visible", true)
            const dialog = findChild(popup, "manual-measurement-dialog")
            verify(dialog)
            compare(dialog.width, 950)
            compare(dialog.height, 600)
            verify(dialog.x >= 0)
            verify(dialog.y >= 0)
            verify(dialog.x + dialog.width <= popup.width)
            verify(dialog.y + dialog.height <= popup.height)
            compare(state.manualMeasurementMode, "CALIBRATION")
            compare(state.manualKnownPieceUnit, "INCH")
            compare(state.manualMeasurementRequiredSamples, 100)
            compare(state.manualMeasurementMinimumSamples, 30)
            compare(state.manualMeasurementMaximumDurationMs, 30000)
            compare(state.manualMeasurementLoadBand, 0.10)
        }

        function test_confirmationAndAlarmStackAboveOpenMeasurement() {
            // Declared after both layers, as in main.qml: only z decides.
            verify(state.openManualMeasurement("CALIBRATION"))
            tryCompare(popup, "visible", true)
            verify(popup.z < machinePopupLayer.z)
            verify(popup.z < machineAlarmPopupLayer.z)
            let confirmed = false
            state.showConfirmation("START AUTOMATIC 1.00 T HOLD", "body",
                                   function() { confirmed = true })
            tryCompare(machinePopupLayer, "visible", true)
            verify(popup.visible)
            state.performPopupPrimaryAction()
            verify(confirmed)
            verify(popup.visible)
        }

        function test_measurementModalDoesNotRequireMachineConnectionToOpen() {
            verify(state.openManualMeasurement("MEASUREMENT"))
            tryCompare(popup, "visible", true)
            compare(state.manualMeasurementStatus, "CALIBRATION REQUIRED")
            compare(state.manualMeasurementMode, "MEASUREMENT")
        }

        function test_knownPieceUnitButtonsConvertDisplayValue() {
            verify(state.openManualMeasurement("CALIBRATION"))
            verify(state.setManualKnownPieceThickness(0.125, "INCH"))
            verify(state.setManualKnownPieceUnit("MILLIMETER"))
            compare(state.manualKnownPieceUnit, "MILLIMETER")
            compare(state.manualKnownPieceDisplayValue.toFixed(3), "3.175")
            verify(state.setManualKnownPieceUnit("INCH"))
            compare(state.manualKnownPieceUnit, "INCH")
            compare(state.manualKnownPieceDisplayValue.toFixed(4), "0.1250")
        }

        function test_closeButtonClosesCalibrationModal() {
            verify(state.openManualMeasurement("CALIBRATION"))
            tryCompare(popup, "visible", true)
            state.closeManualMeasurement()
            tryCompare(popup, "visible", false)
            compare(state.manualMeasurementClosePending, false)
        }

        function test_closeButtonStopsActivePedalBeforeClosing() {
            verify(state.openManualMeasurement("CALIBRATION"))
            state.tonnageHoldActive = true
            tryCompare(popup, "visible", true)
            state.closeManualMeasurement()
            tryCompare(state, "tonnageHoldActive", false)
            tryCompare(popup, "visible", false)
            compare(state.manualMeasurementClosePending, false)
        }

        function test_modeSwitchStopsActiveProcessBeforeChangingAuthorityMode() {
            verify(state.openManualMeasurement("CALIBRATION"))
            state.tonnageHoldActive = true
            state.switchManualMeasurementMode("MEASUREMENT")
            tryCompare(state, "tonnageHoldActive", false)
            compare(state.tonnageHoldActive, false)
            compare(state.manualMeasurementMode, "MEASUREMENT")
            compare(state.manualMeasurementStatus, "CALIBRATION REQUIRED")
        }

        function test_modalModeToggleUsesStopBeforeSwitchContract() {
            verify(state.openManualMeasurement("CALIBRATION"))
            const dialog = findChild(popup, "manual-measurement-dialog")
            verify(dialog)
            state.tonnageHoldActive = true
            dialog.operationalMode = "MEASURE"
            tryCompare(state, "tonnageHoldActive", false)
            compare(state.manualMeasurementMode, "MEASUREMENT")
            compare(state.manualMeasurementStatus, "CALIBRATION REQUIRED")
        }

        function test_calibrationAveragesFixedCountOfFreshReadings() {
            verify(state.openManualMeasurement("CALIBRATION"))
            verify(state.setManualKnownPieceThickness(0.125, "INCH"))
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("WAITING FOR TARGET")

            for (let index = 0; index < 150 && !isFinite(state.manualMeasurementResult); ++index) {
                state.ramPosition = index % 2 === 0 ? -1.6551 : -1.6555
                state.sampleManualMeasurement()
                if (index === 98)
                    verify(!isFinite(state.manualMeasurementResult))
            }

            verify(isFinite(state.manualMeasurementResult))
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
            compare(state.manualMeasurementAcceptedSamples, 100)
            verify(Math.abs(state.manualMeasurementResult - (-1.7803)) < 0.00001)
        }

        function test_slowPositionDriftIsAveragedNotChased() {
            // The former half-means drift gate never completed on this input.
            verify(state.openManualMeasurement("CALIBRATION"))
            verify(state.setManualKnownPieceThickness(0.125, "INCH"))
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("WAITING FOR TARGET")
            let sum = 0
            for (let index = 0; index < 100; ++index) {
                const position = -1.6553 + 0.0004 * Math.sin(2 * Math.PI * index / 70)
                sum += position
                state.ramPosition = position
                state.sampleManualMeasurement()
            }
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
            compare(state.manualMeasurementAcceptedSamples, 100)
            verify(Math.abs(state.manualMeasurementResult - (sum / 100 - 0.125)) < 1e-9)
        }

        function test_offlineCalibrationAppliesDerivedOpening() {
            verify(state.openManualMeasurement("CALIBRATION"))
            tryCompare(popup, "visible", true)
            verify(findChild(popup, "manual-calibration-tooling-picker"))
            verify(state.setManualCalibrationTooling("PUNCH", { id: "p", name: "P", heightInch: 4.059 }))
            verify(state.setManualCalibrationTooling("DIE", { id: "d", name: "D", heightInch: 2.362 }))
            verify(state.setManualKnownPieceThickness(0.125, "INCH"))
            state.desktopRamToTableOpening = 8.22
            state.clearManualCalibrationOpening()
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("WAITING FOR TARGET")
            const info = findChild(popup, "manual-measurement-info-line")
            verify(info)
            for (let index = 0; index < 100; ++index) {
                state.ramPosition = -1.6553
                state.sampleManualMeasurement()
                if (index === 49)
                    compare(info.text, "OPENING 8.2200 → 8.2013 in (Δ -0.0187) · LIVE")
            }
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
            // A small change is never applied automatically.
            compare(state.manualCalibrationOpeningState, "REVIEW")
            verify(Math.abs(state.desktopRamToTableOpening - 8.22) < 1e-9)
            verify(info.text.indexOf("REVIEW") >= 0)
            state.tonnageHoldActive = false
            wait(0)
            const apply = findChild(popup, "manual-calibration-apply-opening")
            verify(apply)
            tryCompare(apply, "visible", true)
            verify(apply.controlEnabled)
            // Earlier tests can leave the offline TONNAGE HOLD message open,
            // which (correctly) stacks above the modal and eats the click.
            state.hidePopup()
            wait(0)
            mouseClick(apply)
            compare(state.manualCalibrationOpeningState, "APPLIED")
            verify(Math.abs(state.desktopRamToTableOpening - 8.2013) < 1e-6)
            verify(info.text.indexOf("APPLIED") >= 0)
        }

        function test_convergenceModeShowsProgressAndCriterion() {
            state.manualMeasurementConvergenceEnabled = true
            state.applyUserSettings({
                manualDieTopCalibration: { value: -1.7803, unit: "INCH", valid: true,
                                           referenceThickness: 0.125 }
            })
            verify(state.openManualMeasurement("MEASUREMENT"))
            tryCompare(popup, "visible", true)
            const prompt = findChild(popup, "manual-measurement-result-prompt")
            const count = findChild(popup, "manual-measurement-sample-count")
            const info = findChild(popup, "manual-measurement-info-line")
            verify(prompt)
            verify(count)
            verify(info)
            verify(info.text.indexOf("Accepts once stable") >= 0)
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("WAITING FOR TARGET")
            for (let index = 0; index < 10; ++index) {
                state.ramPosition = -1.7803 + 0.0625
                state.sampleManualMeasurement()
            }
            compare(prompt.text, "CONVERGING 10 · Δ ---- / 0.0002 in · LIVE, NOT FINAL")
            for (let index = 10; index < 100 && !isFinite(state.manualMeasurementResult); ++index) {
                state.ramPosition = -1.7803 + 0.0625
                state.sampleManualMeasurement()
            }
            compare(state.manualMeasurementStatus, "MEASUREMENT COMPLETE")
            compare(state.manualMeasurementAcceptedSamples, 30)
            compare(count.text, "30 SAMPLES · CONVERGED")
            state.tonnageHoldActive = false
            wait(0)
        }

        function test_calibrationAveragesFixedCountWithConvergenceOn() {
            state.manualMeasurementConvergenceEnabled = true
            verify(state.openManualMeasurement("CALIBRATION"))
            tryCompare(popup, "visible", true)
            verify(state.setManualKnownPieceThickness(0.125, "INCH"))
            const prompt = findChild(popup, "manual-measurement-result-prompt")
            const count = findChild(popup, "manual-measurement-sample-count")
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("WAITING FOR TARGET")
            for (let index = 0; index < 40; ++index) {
                state.ramPosition = -1.6553
                state.sampleManualMeasurement()
            }
            compare(prompt.text, "AVERAGING 40 / 100 · LIVE, NOT FINAL")
            for (let index = 40; index < 100; ++index) {
                state.ramPosition = -1.6553
                state.sampleManualMeasurement()
            }
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
            compare(count.text, "100 SAMPLES · FIXED 100")
            state.tonnageHoldActive = false
            wait(0)
        }

        function test_measuringTonnageTargetIsTappableInBothModes() {
            state.applyUserSettings({
                manualDieTopCalibration: { value: -1.7803, unit: "INCH", valid: true,
                                           referenceThickness: 0.125 }
            })
            verify(state.openManualMeasurement("MEASUREMENT"))
            tryCompare(popup, "visible", true)
            const target = findChild(popup, "manual-measurement-tonnage-target")
            const auto = findChild(popup, "manual-measurement-auto")
            verify(target)
            verify(auto)
            verify(target.tappable)
            compare(target.valueText, "1.000")
            verify(auto.controlEnabled)
            state.hidePopup()
            wait(0)
            mouseClick(target)
            verify(state.onScreenKeyboardVisible)
            compare(state.onScreenKeyboardValue, "1.00")
            state.onScreenKeyboardValue = "0.6"
            verify(state.commitOnScreenKeyboard())
            compare(state.manualMeasurementTonnage, 0.6)
            compare(target.valueText, "0.600")
            verify(auto.controlEnabled)
            compare(auto.text, "AUTO MEASURE")

            // Calibrate shows and edits the same measuring tonnage.
            state.tonnageHoldTarget = 2.0
            state.switchManualMeasurementMode("CALIBRATION")
            verify(target.tappable)
            compare(target.tag, "CALIBRATE TARGET")
            compare(target.valueText, "0.600")
            mouseClick(target)
            verify(state.onScreenKeyboardVisible)
            compare(state.onScreenKeyboardValue, "0.60")
            state.onScreenKeyboardValue = "0.5"
            verify(state.commitOnScreenKeyboard())
            compare(state.manualMeasurementTonnage, 0.5)
            compare(target.valueText, "0.500")
            verify(auto.controlEnabled)
            state.tonnageHoldTarget = 1.0
            verify(state.setManualMeasurementTonnage(1.0))
        }

        function test_runningAverageIsShownWhileAveraging() {
            verify(state.openManualMeasurement("CALIBRATION"))
            tryCompare(popup, "visible", true)
            verify(state.setManualKnownPieceThickness(0.125, "INCH"))
            const big = findChild(popup, "manual-measurement-big-result")
            const prompt = findChild(popup, "manual-measurement-result-prompt")
            verify(big)
            verify(prompt)
            compare(big.text, "----")
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("WAITING FOR TARGET")
            for (let index = 0; index < 40; ++index) {
                state.ramPosition = index % 2 === 0 ? -1.6550 : -1.6556
                state.sampleManualMeasurement()
            }
            verify(state.manualMeasurementAveraging)
            verify(Math.abs(state.manualMeasurementRunningValue - (-1.7803)) < 1e-6)
            compare(big.text, "-1.7803 in")
            verify(prompt.text.indexOf("40 / 100") >= 0)
            for (let index = 40; index < 100; ++index) {
                state.ramPosition = index % 2 === 0 ? -1.6550 : -1.6556
                state.sampleManualMeasurement()
            }
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
            verify(!state.manualMeasurementAveraging)
            compare(big.text, "-1.7803 in")
            compare(prompt.text, "NEW DIE TOP CALIBRATED & LOCKED")
            state.tonnageHoldActive = false
            wait(0)

            verify(state.openManualMeasurement("MEASUREMENT"))
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("WAITING FOR TARGET")
            for (let index = 0; index < 25; ++index) {
                state.ramPosition = -1.7803 + 0.0625
                state.sampleManualMeasurement()
            }
            compare(big.text, "0.0625")
            state.tonnageHoldActive = false
            wait(0)
            verify(!state.manualMeasurementAveraging)
            compare(big.text, "----")

            verify(state.setManualKnownPieceUnit("MILLIMETER"))
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("WAITING FOR TARGET")
            for (let index = 0; index < 25; ++index) {
                state.ramPosition = -1.7803 + 0.0625
                state.sampleManualMeasurement()
            }
            compare(big.text, "1.588")
            state.tonnageHoldActive = false
            wait(0)
            verify(state.setManualKnownPieceUnit("INCH"))
        }

        function test_measuredThicknessCanBeReleasedToPrograms() {
            state.applyUserSettings({
                manualDieTopCalibration: { value: -1.7803, unit: "INCH", valid: true,
                                           referenceThickness: 0.125 }
            })
            verify(state.openManualMeasurement("MEASUREMENT"))
            tryCompare(popup, "visible", true)
            verify(state.setManualMeasurementOnReferencePiece(true))
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("WAITING FOR TARGET")
            for (let index = 0; index < 100; ++index) {
                state.ramPosition = -1.7803 + 0.125 + 0.036
                state.sampleManualMeasurement()
            }
            verify(Math.abs(state.manualMeasurementResult - 0.036) < 1e-6)
            state.tonnageHoldActive = false
            wait(0)
            verify(state.useManualMeasurementForProgram())
            verify(Math.abs(state.measuredMaterialThickness - 0.036) < 1e-6)
            state.setManualMeasurementOnReferencePiece(false)
        }

        function test_measurementConvergesWithoutControllerHoldPhase() {
            state.applyUserSettings({
                manualDieTopCalibration: { value: -1.7803, unit: "INCH", valid: true }
            })
            verify(state.openManualMeasurement("MEASUREMENT"))
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("WAITING FOR TARGET")

            for (let index = 0; index < 150 && !isFinite(state.manualMeasurementResult); ++index) {
                state.ramPosition = index % 2 === 0 ? -1.6551 : -1.6555
                state.sampleManualMeasurement()
            }

            verify(isFinite(state.manualMeasurementResult))
            compare(state.manualMeasurementStatus, "MEASUREMENT COMPLETE")
            verify(Math.abs(state.manualMeasurementResult - 0.125) < 0.00001)
        }
    }
}