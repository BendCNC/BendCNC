import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    width: 640
    height: 480

    QtObject {
        id: backend
        property bool pressConnected: true
        property bool moduleConnected: false
        property string pressConnectionState: "READY"
        property string moduleConnectionState: "DISCONNECTED"
        property string pressMachineState: "IDLE"
        property string moduleState: "UNKNOWN"
        property bool pressTelemetryFresh: true
        property double pressTelemetrySequence: 0
        property string thcCommissioningState: "IDLE"
        property int releaseThcCalls: 0
        property bool moduleTelemetryFresh: false
        property bool pressOperationActive: false
        property bool moduleOperationActive: false
        property bool pressReady: true
        property bool pressHomed: true
        property bool moduleHomed: false
        property bool manualModeEnabled: false
        property real manualModeMaxTonnagePerRam: 12.5
        property bool independentRamTelemetryAvailable: true
        property real ramPositionY1: -1.0
        property real ramPositionY2: -1.0
        property real ramLoadY1: 0
        property real ramLoadY2: 0
        property real ramCommandedJogPosition: -1.0
        property real ramJogSpeed: 0
        property real ramDistanceToGo: 0
        property bool safetyJogLeft: false
        property bool safetyJogRight: false
        property bool bendPedal: false
        property bool antiBind: false
        property string pressFirmwareVersion: "1.2"
        property string moduleFirmwareVersion: ""
        property real moduleWorkX: 0
        property real moduleWorkR: 0
        property real moduleMachineX: 0
        property real moduleMachineR: 0
        property bool moduleLimitX1: false
        property bool moduleLimitX2: false
        property bool moduleLimitR1: false
        property bool moduleLimitR2: false
        property int manualEnableCalls: 0
        property int maxTonnageCalls: 0
        property int jogCalls: 0
        property int strokeCalls: 0
        property int startHoldCalls: 0
        property real lastHoldTarget: 0
        property int stopHoldCalls: 0
        property bool acceptCommands: true
        property bool acceptManualModeCommands: true
        property bool acceptMaxTonnage: true
        property int operationId: 0
        property real lastMaxTonnage: 0
        property real ramToTableOpening: 0
        property bool commandOperationActive: false
        property int ramToTableCalls: 0
        property real lastRamToTableOpening: 0
        property bool lastManualModeRequest: false
        property string lastJogType: ""
        signal commandOperationFinished(int id, string device, string operation,
                                        string state, string error)
        signal connectionFailed(string device, string reason)
        signal operationRejected(string device, string operation, string reason)
        signal telemetryLogLine(string device, string line)
        signal pressSerialLogLine(string source, string content)

        function setManualModeEnabled(enabled) {
            manualEnableCalls += 1
            operationId += 1
            lastManualModeRequest = enabled
            return acceptCommands && acceptManualModeCommands
        }
        function setManualModeMaxTonnage(value) {
            maxTonnageCalls += 1
            operationId += 1
            lastMaxTonnage = value
            return acceptCommands && acceptMaxTonnage
        }
        function jogPress(target, speed, type) {
            jogCalls += 1
            operationId += 1
            lastJogType = type
            return acceptCommands
        }
        function startManualStroke(retract, bend, jogSpeed, bendSpeed) {
            strokeCalls += 1
            operationId += 1
            return acceptCommands
        }
        function startTonnageHold(target, speed) {
            startHoldCalls += 1
            lastHoldTarget = target
            operationId += 1
            return acceptCommands
        }
        function stopTonnageHold() {
            stopHoldCalls += 1
            operationId += 1
            return acceptCommands
        }
        function releaseThcCommissioning() {
            releaseThcCalls += 1
            return acceptCommands
        }
        property int automaticProfileCalls: 0
        property real lastAutomaticTarget: 0
        function startAutomaticThcContactProfile(target) {
            automaticProfileCalls += 1
            lastAutomaticTarget = target
            operationId += 1
            return acceptCommands
        }
        function setRamToTableOpening(value) {
            ramToTableCalls += 1
            operationId += 1
            lastRamToTableOpening = value
            return acceptCommands
        }
    }

    BendCNC.AppState {
        id: state
        machineControl: backend
    }

    TestCase {
        name: "AppStateManualRoutingTests"
        when: windowShown

        function init() {
            backend.manualModeEnabled = false
            backend.pressOperationActive = false
            backend.acceptCommands = true
            backend.acceptManualModeCommands = true
            backend.acceptMaxTonnage = true
            backend.operationId = 0
            backend.manualEnableCalls = 0
            backend.maxTonnageCalls = 0
            backend.jogCalls = 0
            backend.strokeCalls = 0
            backend.startHoldCalls = 0
            backend.stopHoldCalls = 0
            state.manualPendingOperation = ""
            state.manualPendingAction = ""
            state.manualPendingPreviousSetting = undefined
            state.manualActivationPending = false
            state.manualLeavePending = false
            state.manualModeArmed = false
            state.manualRepeatStroke = false
            state.manualRepeatJog = false
            state.tonnageHoldActive = false
            state.tonnageHoldActiveTarget = NaN
            state.tonnageHoldTarget = 1.0
            state.manualMeasurementTonnage = 1.0
            state.contactProfileActive = false
            state.contactProfileTarget = 1.0
            backend.lastHoldTarget = 0
            backend.ramToTableOpening = 0
            backend.ramToTableCalls = 0
            backend.pressMachineState = "IDLE"
            state.ramToTableSaveOperationId = undefined
            state.manualCalibrationOpeningOperationId = undefined
            state.clearManualCalibrationOpening()
            state.setManualCalibrationTooling("PUNCH", null)
            state.setManualCalibrationTooling("DIE", null)
            state.manualMeasurementOnReferencePiece = false
            state.manualMeasurementConvergenceEnabled = false
            state.clearAlarm()
            wait(0)
        }

        function complete(operation, result, error) {
            backend.commandOperationFinished(backend.operationId, "press", operation,
                                             result || "COMPLETED", error || "")
            wait(0)
        }

        function test_activationEnablesThenAppliesTemporaryLimit() {
            verify(state.activateManualMode())
            compare(backend.manualEnableCalls, 1)
            compare(state.manualPendingOperation, "manual-enable")
            backend.manualModeEnabled = true
            complete("manual-enable")
            compare(backend.maxTonnageCalls, 1)
            compare(backend.lastMaxTonnage, state.manualModeMaxTonnagePerRam)
            compare(state.manualPendingOperation, "manual-max-tonnage")
            verify(!state.manualModeArmed)
            complete("manual-max-tonnage")
            compare(state.manualPendingOperation, "")
            verify(state.manualModeArmed)
            compare(state.manualModeState, "ENABLED")
        }

        function test_activationLimitFailureDisablesManualMode() {
            verify(state.activateManualMode())
            backend.manualModeEnabled = true
            complete("manual-enable")
            compare(state.manualPendingOperation, "manual-max-tonnage")

            complete("manual-max-tonnage", "FAILED", "ACK_TIMEOUT")
            compare(backend.manualEnableCalls, 2)
            verify(!backend.lastManualModeRequest)
            verify(!state.manualModeArmed)
            verify(state.manualLeavePending)
            compare(state.manualPendingOperation, "manual-disable")
            compare(state.alarmTitle, "MANUAL ACTIVATION FAILED")

            backend.manualModeEnabled = false
            complete("manual-disable")
            verify(!state.manualLeavePending)
            compare(state.manualPendingOperation, "")
            compare(state.manualModeState, "DISABLED")
        }

        function test_synchronousLimitRejectionDisablesManualMode() {
            verify(state.activateManualMode())
            backend.manualModeEnabled = true
            backend.acceptMaxTonnage = false
            complete("manual-enable")
            compare(backend.maxTonnageCalls, 1)
            compare(backend.manualEnableCalls, 2)
            verify(!backend.lastManualModeRequest)
            verify(!state.manualModeArmed)
            verify(state.manualLeavePending)
            compare(state.manualPendingOperation, "manual-disable")
        }

        function test_enableFailureDispatchesCompensatingDisable() {
            verify(state.activateManualMode())
            complete("manual-enable", "FAILED", "ACK_TIMEOUT")
            compare(backend.manualEnableCalls, 2)
            verify(!backend.lastManualModeRequest)
            verify(!state.manualModeArmed)
            verify(state.manualLeavePending)
            compare(state.manualPendingOperation, "manual-disable")
            compare(state.alarmTitle, "MANUAL ACTIVATION FAILED")
        }

        function test_disableFailureLocksManualControls() {
            backend.manualModeEnabled = true
            state.manualModeArmed = true
            verify(state.deactivateManualMode())
            compare(state.manualPendingOperation, "manual-disable")
            complete("manual-disable", "FAILED", "ACK_TIMEOUT")
            verify(!state.manualModeArmed)
            verify(!state.manualLeavePending)
            compare(state.manualPendingOperation, "")
            compare(state.manualModeState, "DISABLE REQUIRED")
            verify(!state.pressCanOperate)
            verify(!state.manualAction("toggle-repeat-jog"))
            verify(!state.manualRepeatJog)
            verify(!state.setManualSetting("jogStep", 0.01))
            verify(!state.manualAction("jog-down"))
            compare(backend.jogCalls, 0)
            compare(state.alarmTitle, "MANUAL MODE NOT ENABLED")
        }

        function test_sharedJogCompletionIgnoredWithoutManualOwnership() {
            compare(state.manualPendingOperation, "")
            complete("jog-safety")
            compare(state.manualPendingOperation, "")
            verify(!state.alarmVisible)
        }

        function test_staleSameNameCompletionDoesNotOwnCurrentOperation() {
            backend.manualModeEnabled = true
            state.manualModeArmed = true
            verify(state.manualAction("jog-down"))
            var currentId = state.manualPendingOperationId
            backend.commandOperationFinished(currentId - 1, "press", "jog-safety",
                                             "COMPLETED", "")
            wait(0)
            compare(state.manualPendingOperation, "jog-safety")
            compare(state.manualPendingOperationId, currentId)
            backend.commandOperationFinished(currentId, "press", "jog-safety",
                                             "COMPLETED", "")
            wait(0)
            compare(state.manualPendingOperation, "")
        }

        function test_matchingManualJogCompletionCanRepeat() {
            backend.manualModeEnabled = true
            state.manualModeArmed = true
            state.manualRepeatJog = true
            verify(state.manualAction("jog-down"))
            compare(state.manualPendingOperation, "jog-safety")
            compare(backend.jogCalls, 1)
            complete("jog-safety")
            tryCompare(backend, "jogCalls", 2)
            compare(state.manualPendingOperation, "jog-safety")
            state.manualRepeatJog = false
        }

        function test_deactivationFailsClosedWhileOperationActive() {
            backend.manualModeEnabled = true
            state.manualPendingOperation = "jog-safety"
            state.manualPendingAction = "jog-down"
            verify(!state.deactivateManualMode())
            compare(backend.manualEnableCalls, 0)
            verify(state.alarmVisible)
            compare(state.alarmTitle, "MANUAL MODE BUSY")
        }

        function test_holdStopUsesSameNativeLifecycleName() {
            backend.manualModeEnabled = true
            state.manualModeArmed = true
            state.tonnageHoldActive = true
            verify(state.manualAction("tonnage-hold"))
            compare(backend.stopHoldCalls, 1)
            compare(state.manualPendingOperation, "tonnage-hold")
            complete("tonnage-hold")
            verify(!state.tonnageHoldActive)
            compare(state.manualPendingOperation, "")
        }

        function test_automaticForceTimeoutRequiresConfirmedHomeBeforeRetry() {
            state.contactProfileActive = true
            backend.commandOperationFinished(backend.operationId, "press",
                                             "automatic-thc-contact-profile",
                                             "FAILED", "THC_ERROR_FORCE_TIMEOUT")
            wait(0)
            verify(!state.contactProfileActive)
            compare(state.alarmTitle, "AUTOMATIC HOLD FAILED")
            verify(state.alarmBody.indexOf("confirmed Home action") >= 0)
            verify(state.alarmBody.indexOf("No Home or AUTO retry is queued") >= 0)
        }

        function beginLiveCalibration() {
            backend.ramLoadY1 = 0
            backend.ramLoadY2 = 0
            backend.thcCommissioningState = "IDLE"
            backend.releaseThcCalls = 0
            state.hidePopup()
            verify(state.openManualMeasurement("CALIBRATION"))
            verify(state.setManualKnownPieceThickness(0.125, "INCH"))
            state.tonnageHoldTarget = 1.0
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("")
        }

        // Measure against a die top at -1.7803 in; the 100-frame fixed rule
        // and the optional convergence rule apply here.
        function beginLiveMeasurement() {
            backend.ramLoadY1 = 0
            backend.ramLoadY2 = 0
            backend.thcCommissioningState = "IDLE"
            backend.releaseThcCalls = 0
            state.applyUserSettings({
                manualDieTopCalibration: { value: -1.7803, unit: "INCH", valid: true,
                                           referenceThickness: 0.125 }
            })
            state.hidePopup()
            verify(state.openManualMeasurement("MEASUREMENT"))
            state.tonnageHoldTarget = 1.0
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("")
        }

        function endLiveCalibration() {
            state.tonnageHoldActive = false
            state.contactProfileActive = false
            state.closeManualMeasurement()
            backend.ramLoadY1 = 0
            backend.ramLoadY2 = 0
            backend.ramPositionY1 = -1.0
            backend.ramPositionY2 = -1.0
            backend.thcCommissioningState = "IDLE"
            state.hidePopup()
            wait(0)
        }

        function liveFrame(total, position) {
            backend.ramLoadY1 = total / 2
            backend.ramLoadY2 = total / 2
            backend.ramPositionY1 = position
            backend.ramPositionY2 = position
            backend.pressTelemetrySequence += 1
            return state.sampleManualMeasurement()
        }

        function test_liveMeasurementAveragesSlowLoadFluctuationInsideBand() {
            beginLiveCalibration()
            let sum = 0
            for (let index = 0; index < 100; ++index) {
                const position = index % 2 === 0 ? -1.6551 : -1.6555
                sum += position
                liveFrame(1.0 + 0.08 * Math.sin(2 * Math.PI * index / 40), position)
                if (index < 99)
                    compare(state.manualMeasurementQualifiedSamples, index + 1)
            }
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
            compare(state.manualMeasurementAcceptedSamples, 100)
            verify(Math.abs(state.manualMeasurementResult - (sum / 100 - 0.125)) < 1e-9)
            endLiveCalibration()
        }

        function test_liveMeasurementSkipsOutOfBandWithoutRestarting() {
            beginLiveCalibration()
            liveFrame(0.5, -1.6553)
            compare(state.manualMeasurementStatus, "WAITING FOR TARGET")
            compare(state.manualMeasurementQualifiedSamples, 0)
            for (let index = 0; index < 60; ++index)
                liveFrame(1.02, -1.6553)
            liveFrame(1.25, -1.6553)
            compare(state.manualMeasurementQualifiedSamples, 60)
            compare(state.manualMeasurementStatus, "AVERAGING 60 / 100 · OUTSIDE BAND")
            for (let rest = 0; rest < 40; ++rest)
                liveFrame(0.95, -1.6553)
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
            compare(state.manualMeasurementAcceptedSamples, 100)
            verify(Math.abs(state.manualMeasurementAcceptedLoadMean - 0.992) < 1e-9)
            endLiveCalibration()
        }

        function test_liveMeasurementAcceptsQuantizedStatusLoadsSymmetrically() {
            beginLiveCalibration()
            const pairs = [[0.5, 0.5], [0.6, 0.5], [0.5, 0.4], [0.4, 0.6], [0.6, 0.6]]
            for (let index = 0; index < pairs.length; ++index) {
                backend.ramLoadY1 = pairs[index][0]
                backend.ramLoadY2 = pairs[index][1]
                backend.ramPositionY1 = -1.6553
                backend.ramPositionY2 = -1.6553
                backend.pressTelemetrySequence += 1
                state.sampleManualMeasurement()
            }
            // 1.0, 1.1, 0.9 and 1.0 T are averaged; 1.2 T is skipped.
            compare(state.manualMeasurementQualifiedSamples, 4)
            endLiveCalibration()
        }

        function test_liveMeasurementIgnoresRepeatedTelemetryFrame() {
            beginLiveCalibration()
            liveFrame(1.0, -1.6553)
            state.sampleManualMeasurement()
            state.sampleManualMeasurement()
            compare(state.manualMeasurementQualifiedSamples, 1)
            endLiveCalibration()
        }

        function test_liveAutoMeasurementAveragesOnlyRegulatedHold() {
            beginLiveCalibration()
            state.tonnageHoldActive = false
            state.contactProfileActive = true
            backend.thcCommissioningState = "CONTACT"
            liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementStatus, "WAITING FOR HOLD")
            compare(state.manualMeasurementQualifiedSamples, 0)
            backend.thcCommissioningState = "HOLDING"
            for (let index = 0; index < 100; ++index)
                liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
            tryCompare(backend, "releaseThcCalls", 1)
            endLiveCalibration()
        }

        function test_liveMeasurementAcceptsPartialAverageAtTimeLimit() {
            beginLiveCalibration()
            for (let index = 0; index < 35; ++index)
                liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementQualifiedSamples, 35)
            state.manualMeasurementWindowStartedMs = Date.now()
                - state.manualMeasurementMaximumDurationMs - 1
            liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
            compare(state.manualMeasurementAcceptedSamples, 35)
            compare(state.manualMeasurementAcceptedCriterion, "TIME LIMIT")
            endLiveCalibration()
        }

        function test_liveMeasurementTimesOutWithoutMinimumAverage() {
            backend.manualModeEnabled = true
            state.manualModeArmed = true
            beginLiveCalibration()
            for (let index = 0; index < 10; ++index)
                liveFrame(1.0, -1.6553)
            state.manualMeasurementWindowStartedMs = Date.now()
                - state.manualMeasurementMaximumDurationMs - 1
            liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementStatus, "ACQUISITION TIMEOUT")
            verify(!isFinite(state.manualMeasurementResult))
            tryCompare(backend, "stopHoldCalls", 1)
            liveFrame(1.0, -1.6553)
            wait(350)
            compare(backend.stopHoldCalls, 1)
            endLiveCalibration()
        }

        function calibrateWithTooling(punchHeight, dieHeight, position) {
            verify(state.setManualCalibrationTooling("PUNCH", { id: "p", name: "P", heightInch: punchHeight }))
            verify(state.setManualCalibrationTooling("DIE", { id: "d", name: "D", heightInch: dieHeight }))
            beginLiveCalibration()
            for (let index = 0; index < 100; ++index)
                liveFrame(1.0, position)
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
        }

        function test_calibrationOpeningSmallChangeStillRequiresApply() {
            // dieTop = -1.6553 - 0.125 = -1.7803; opening = 4.059 + 2.362 + 1.7803
            // = 8.2013, within 0.050 of the controller value: still never
            // written until the operator presses APPLY OPENING.
            backend.ramToTableOpening = 8.22
            calibrateWithTooling(4.059, 2.362, -1.6553)
            const derived = 4.059 + 2.362 + 1.7803
            // Full 4-decimal resolution; never rounded to the echo.
            const expected = derived
            verify(Math.abs(state.manualCalibrationOpeningCandidate - expected) < 1e-9)
            compare(state.manualCalibrationOpeningState, "REVIEW")
            verify(state.manualCalibrationOpeningCanApply)
            state.tonnageHoldActive = false
            wait(400)
            compare(backend.ramToTableCalls, 0)
            compare(state.manualCalibrationOpeningState, "REVIEW")
            state.tonnageHoldActive = true
            verify(state.applyManualCalibrationOpening())
            compare(state.manualCalibrationOpeningState, "WAITING")
            compare(backend.ramToTableCalls, 0)
            const record = state.userSettingsModel.manualDieTopCalibration
            compare(record.referenceThickness, 0.125)
            compare(record.punchHeight, 4.059)
            verify(Math.abs(record.ramToTableOpening - derived) < 1e-6)
            state.tonnageHoldActive = false
            tryCompare(state, "manualCalibrationOpeningState", "SENT")
            compare(backend.ramToTableCalls, 1)
            verify(Math.abs(backend.lastRamToTableOpening - expected) < 1e-9)
            backend.commandOperationFinished(backend.operationId, "press",
                                             "set-ram-to-table-opening", "COMPLETED", "")
            wait(0)
            compare(state.manualCalibrationOpeningState, "APPLIED")
            compare(state.ramToTableSaveOperationId, undefined)
            verify(!state.popupVisible)
            endLiveCalibration()
        }

        function test_calibrationOpeningLargeChangeRequiresReview() {
            backend.ramToTableOpening = 8.3
            // 4.059 + 2.362 + 1.7803 = 8.2013 -> delta -0.0987 > 0.050
            calibrateWithTooling(4.059, 2.362, -1.6553)
            compare(state.manualCalibrationOpeningState, "REVIEW")
            verify(state.manualCalibrationOpeningCanApply)
            state.tonnageHoldActive = false
            wait(400)
            compare(backend.ramToTableCalls, 0)
            verify(state.applyManualCalibrationOpening())
            tryCompare(state, "manualCalibrationOpeningState", "SENT")
            compare(backend.ramToTableCalls, 1)
            backend.commandOperationFinished(backend.operationId, "press",
                                             "set-ram-to-table-opening", "FAILED", "ACK_TIMEOUT")
            wait(0)
            compare(state.manualCalibrationOpeningState, "FAILED")
            compare(state.alarmTitle, "CALIBRATED OPENING SAVE FAILED")
            compare(state.alarmBody, "ACK TIMEOUT")
            endLiveCalibration()
        }

        function test_calibrationOpeningMatchingEchoIsUnchanged() {
            // 4-decimal echo equal to the derived 8.2013.
            backend.ramToTableOpening = 8.2013
            calibrateWithTooling(4.059, 2.362, -1.6553)
            compare(state.manualCalibrationOpeningState, "UNCHANGED")
            endLiveCalibration()
        }

        function test_calibrationOpeningKeepsFourthDecimalOverCoarseEcho() {
            // An older 3-decimal echo (8.201) keeps the 4th decimal reviewable.
            backend.ramToTableOpening = 8.201
            calibrateWithTooling(4.059, 2.362, -1.6553)
            compare(state.manualCalibrationOpeningState, "REVIEW")
            verify(Math.abs(state.manualCalibrationOpeningCandidate - 8.2013) < 1e-6)
            endLiveCalibration()
        }

        function test_calibrationOpeningEepromBusyExplainsRetry() {
            backend.ramToTableOpening = 8.3
            calibrateWithTooling(4.059, 2.362, -1.6553)
            state.tonnageHoldActive = false
            wait(0)
            verify(state.applyManualCalibrationOpening())
            tryCompare(state, "manualCalibrationOpeningState", "SENT")
            backend.commandOperationFinished(backend.operationId, "press",
                                             "set-ram-to-table-opening", "FAILED",
                                             "RAM_TO_TABLE_EEPROM_BUSY")
            wait(0)
            compare(state.manualCalibrationOpeningState, "FAILED")
            compare(state.alarmTitle, "CALIBRATED OPENING SAVE FAILED")
            verify(state.alarmBody.indexOf("not at rest") >= 0)
            verify(state.alarmBody.indexOf("retry APPLY OPENING") >= 0)
            endLiveCalibration()
        }

        function test_liveOpeningFollowsRunningDieTopWhileAveraging() {
            backend.ramToTableOpening = 8.22
            verify(state.setManualCalibrationTooling("PUNCH", { id: "p", name: "P", heightInch: 4.059 }))
            verify(state.setManualCalibrationTooling("DIE", { id: "d", name: "D", heightInch: 2.362 }))
            beginLiveCalibration()
            verify(!isFinite(state.manualCalibrationLiveOpening))
            for (let index = 0; index < 10; ++index)
                liveFrame(1.0, -1.6553)
            verify(Math.abs(state.manualCalibrationCurrentOpening - 8.22) < 1e-9)
            verify(Math.abs(state.manualCalibrationLiveOpening - 8.2013) < 1e-6)
            compare(state.manualCalibrationOpeningState, "")
            endLiveCalibration()
        }

        function test_convergenceAcceptsStableAverageBeforeFixedCount() {
            state.manualMeasurementConvergenceEnabled = true
            beginLiveMeasurement()
            verify(state.manualMeasurementConvergenceActive)
            let index = 0
            while (state.manualMeasurementStatus !== "MEASUREMENT COMPLETE" && index < 100) {
                liveFrame(1.0, index % 2 === 0 ? -1.6551 : -1.6555)
                ++index
            }
            compare(state.manualMeasurementStatus, "MEASUREMENT COMPLETE")
            compare(state.manualMeasurementAcceptedSamples, state.manualMeasurementMinimumSamples)
            compare(state.manualMeasurementAcceptedCriterion, "CONVERGED")
            verify(state.manualMeasurementConvergenceSpread <= state.manualMeasurementConvergenceTolerance)
            verify(Math.abs(state.manualMeasurementResult - 0.125) < 1e-9)
            endLiveCalibration()
        }

        function test_calibrationIgnoresConvergenceSetting() {
            state.manualMeasurementConvergenceEnabled = true
            beginLiveCalibration()
            verify(!state.manualMeasurementConvergenceActive)
            for (let index = 0; index < 60; ++index)
                liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementStatus, "AVERAGING 60 / 100")
            verify(!isFinite(state.manualMeasurementResult))
            for (let rest = 0; rest < 40; ++rest)
                liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
            compare(state.manualMeasurementAcceptedSamples, 100)
            compare(state.manualMeasurementAcceptedCriterion, "FIXED")
            endLiveCalibration()
        }

        function test_measuringTonnageIsValidatedAndPersistedForBothModes() {
            verify(state.setManualMeasurementTonnage(0.7))
            compare(state.manualMeasurementTonnage, 0.7)
            compare(state.localSettingsModel.manualMeasurementTonnage, 0.7)
            verify(!state.setManualMeasurementTonnage(0.4))
            compare(state.alarmTitle, "MEASURING TONNAGE OUT OF RANGE")
            verify(!state.setManualMeasurementTonnage(1.2))
            compare(state.manualMeasurementTonnage, 0.7)
            // Calibrate shares the measuring tonnage, not the Manual panel target.
            state.tonnageHoldTarget = 2.0
            verify(state.openManualMeasurement("CALIBRATION"))
            compare(state.manualMeasurementTargetTonnage, 0.7)
            state.switchManualMeasurementMode("MEASUREMENT")
            compare(state.manualMeasurementMode, "MEASUREMENT")
            compare(state.manualMeasurementTargetTonnage, 0.7)
            state.closeManualMeasurement()
            state.clearAlarm()
        }

        function test_measurePedalHoldsMeasuringTonnage() {
            state.applyUserSettings({
                manualDieTopCalibration: { value: -1.7803, unit: "INCH", valid: true,
                                           referenceThickness: 0.125 }
            })
            backend.manualModeEnabled = true
            state.manualModeArmed = true
            state.tonnageHoldTarget = 2.0
            verify(state.setManualMeasurementTonnage(0.6))
            state.hidePopup()
            verify(state.openManualMeasurement("MEASUREMENT"))
            verify(state.startManualMeasurementProcess("PEDAL"))
            compare(backend.startHoldCalls, 1)
            compare(backend.lastHoldTarget, 0.6)
            verify(state.tonnageHoldActive)
            compare(state.manualMeasurementTargetTonnage, 0.6)
            // 0.6 T is inside its own band; 1.0 T would be outside it.
            liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementQualifiedSamples, 0)
            liveFrame(0.6, -1.6553)
            compare(state.manualMeasurementQualifiedSamples, 1)
            endLiveCalibration()

            // Calibrate PEDAL holds the same measuring tonnage (0.5 T allowed).
            state.tonnageHoldActive = false
            verify(state.setManualMeasurementTonnage(0.5))
            verify(state.openManualMeasurement("CALIBRATION"))
            verify(state.startManualMeasurementProcess("PEDAL"))
            compare(backend.lastHoldTarget, 0.5)
            compare(state.manualMeasurementTargetTonnage, 0.5)
            endLiveCalibration()
        }

        function test_autoUsesSelectedTarget() {
            backend.automaticProfileCalls = 0
            backend.lastAutomaticTarget = 0
            state.applyUserSettings({
                manualDieTopCalibration: { value: -1.7803, unit: "INCH", valid: true,
                                           referenceThickness: 0.125 }
            })
            // Measure AUTO regulates the measuring tonnage.
            verify(state.setManualMeasurementTonnage(0.8))
            state.hidePopup()
            verify(state.openManualMeasurement("MEASUREMENT"))
            verify(state.startManualMeasurementProcess("AUTO"))
            compare(state.popupTitle, "START AUTOMATIC 0.80 T HOLD")
            // HOLDING acceptance band +/-0.05 T (firmware v53_hold_band_005).
            compare(state.automaticHoldAcceptanceBand, 0.05)
            verify(state.popupBody.indexOf("0.75 to 0.85 T") >= 0)
            state.popupPrimaryHandler()
            compare(backend.automaticProfileCalls, 1)
            compare(backend.lastAutomaticTarget, 0.8)
            verify(state.contactProfileActive)
            compare(state.contactProfileTarget, 0.8)
            compare(state.manualMeasurementTargetTonnage, 0.8)
            // 0.8 T is inside its own band; 1.0 T is not.
            backend.thcCommissioningState = "HOLDING"
            liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementQualifiedSamples, 0)
            liveFrame(0.8, -1.6553)
            compare(state.manualMeasurementQualifiedSamples, 1)
            endLiveCalibration()

            // The Manual panel AUTO regulates the panel target.
            state.tonnageHoldTarget = 2.5
            state.hidePopup()
            verify(state.manualAction("automatic-tonnage-hold"))
            compare(state.popupTitle, "START AUTOMATIC 2.50 T HOLD")
            state.popupPrimaryHandler()
            compare(backend.automaticProfileCalls, 2)
            compare(backend.lastAutomaticTarget, 2.5)
            state.contactProfileActive = false
            state.hidePopup()

            // An old controller refuses the suffix with FORMAT.
            state.contactProfileActive = true
            backend.commandOperationFinished(backend.operationId, "press",
                                             "automatic-thc-contact-profile",
                                             "FAILED", "THC_ERROR_FORMAT")
            wait(0)
            compare(state.alarmTitle, "AUTOMATIC HOLD FAILED")
            verify(state.alarmBody.indexOf("2.50 T automatic target") >= 0)
            state.clearAlarm()

            // Above the controller range nothing is sent.
            state.tonnageHoldTarget = 20.5
            verify(!state.manualAction("automatic-tonnage-hold"))
            compare(state.alarmTitle, "AUTOMATIC HOLD TARGET OUT OF RANGE")
            compare(backend.automaticProfileCalls, 2)
            state.clearAlarm()
            state.tonnageHoldTarget = 1.0
        }

        function test_convergenceShowsProgressBeforeMinimum() {
            state.manualMeasurementConvergenceEnabled = true
            beginLiveMeasurement()
            for (let index = 0; index < 10; ++index)
                liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementStatus, "CONVERGING 10 / 100")
            for (let more = 0; more < 10; ++more)
                liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementStatus, "CONVERGING 20 / 100 · Δ 0.00000")
            verify(!isFinite(state.manualMeasurementResult))
            endLiveCalibration()
        }

        function test_convergenceKeepsAveragingWhileMeanDrifts() {
            // 0.00005 in per frame of creep moves the running mean 0.0005 in
            // over 20 frames, above the tolerance: the fixed count decides.
            state.manualMeasurementConvergenceEnabled = true
            beginLiveMeasurement()
            for (let index = 0; index < 100; ++index)
                liveFrame(1.0, -1.6553 - 0.00005 * index)
            compare(state.manualMeasurementStatus, "MEASUREMENT COMPLETE")
            compare(state.manualMeasurementAcceptedSamples, 100)
            compare(state.manualMeasurementAcceptedCriterion, "FIXED")
            endLiveCalibration()
        }

        function test_fixedModeIgnoresEarlyStabilityWhenConvergenceOff() {
            beginLiveCalibration()
            for (let index = 0; index < 60; ++index)
                liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementStatus, "AVERAGING 60 / 100")
            verify(!isFinite(state.manualMeasurementResult))
            for (let rest = 0; rest < 40; ++rest)
                liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementAcceptedSamples, 100)
            compare(state.manualMeasurementAcceptedCriterion, "FIXED")
            endLiveCalibration()
        }

        function test_calibrationOpeningOutOfRangeIsNotApplied() {
            backend.ramToTableOpening = 8.3
            calibrateWithTooling(4.61, 3.004, -1.6553)
            compare(state.manualCalibrationOpeningState, "OUT OF RANGE")
            compare(state.alarmTitle, "CALIBRATED OPENING OUT OF RANGE")
            verify(!state.manualCalibrationOpeningCanApply)
            state.tonnageHoldActive = false
            wait(400)
            compare(backend.ramToTableCalls, 0)
            endLiveCalibration()
        }

        function test_calibrationWithoutToolingKeepsOpening() {
            backend.ramToTableOpening = 8.3
            beginLiveCalibration()
            for (let index = 0; index < 100; ++index)
                liveFrame(1.0, -1.6553)
            compare(state.manualMeasurementStatus, "CALIBRATION COMPLETE")
            compare(state.manualCalibrationOpeningState, "NO TOOLING")
            verify(!state.alarmVisible)
            compare(state.userSettingsModel.manualDieTopCalibration.referenceThickness, 0.125)
            state.tonnageHoldActive = false
            wait(400)
            compare(backend.ramToTableCalls, 0)
            endLiveCalibration()
        }

        function test_thinMaterialOnReferencePieceSubtractsReference() {
            state.applyUserSettings({
                manualDieTopCalibration: { value: -1.7803, unit: "INCH", valid: true,
                                           referenceThickness: 0.125 }
            })
            compare(state.manualCalibrationReferenceThickness, 0.125)
            state.hidePopup()
            verify(state.openManualMeasurement("MEASUREMENT"))
            verify(state.setManualMeasurementOnReferencePiece(true))
            state.tonnageHoldTarget = 1.0
            state.tonnageHoldActive = true
            state.resetManualMeasurementAcquisition("")
            // 0.125 reference + 0.030 sheet
            for (let index = 0; index < 100; ++index)
                liveFrame(1.0, -1.7803 + 0.155)
            compare(state.manualMeasurementStatus, "MEASUREMENT COMPLETE")
            verify(Math.abs(state.manualMeasurementStackResult - 0.155) < 1e-6)
            verify(Math.abs(state.manualMeasurementResult - 0.030) < 1e-6)
            state.tonnageHoldActive = false
            wait(0)
            verify(state.useManualMeasurementForProgram())
            verify(state.measuredMaterialThicknessValid)
            verify(Math.abs(state.measuredMaterialThickness - 0.030) < 1e-6)
            verify(state.userSettingsModel.measuredMaterialThickness.onReferencePiece)
            compare(state.manualMeasurementStatus, "READY FOR BEND PROGRAM")
            endLiveCalibration()
        }

        function test_thinMeasurementRequiresRecordedReference() {
            state.applyUserSettings({
                manualDieTopCalibration: { value: -1.7803, unit: "INCH", valid: true }
            })
            verify(!isFinite(state.manualCalibrationReferenceThickness))
            verify(state.openManualMeasurement("MEASUREMENT"))
            verify(!state.setManualMeasurementOnReferencePiece(true))
            compare(state.alarmTitle, "REFERENCE PIECE UNKNOWN")
            verify(!state.manualMeasurementOnReferencePiece)
            state.closeManualMeasurement()
            wait(0)
        }

        function test_autoCompletionPopupYieldsToOpenMeasurement() {
            state.hidePopup()
            verify(state.openManualMeasurement("CALIBRATION"))
            var finished = []
            var record = function(owner, completed, reason) {
                finished.push(owner + ":" + completed)
            }
            state.tonnageHoldProfileFinished.connect(record)
            state.contactProfileOwner = "CALIBRATION"
            state.contactProfileActive = true
            backend.commandOperationFinished(backend.operationId, "press",
                                             "automatic-thc-contact-profile",
                                             "COMPLETED", "")
            wait(0)
            verify(!state.contactProfileActive)
            compare(state.contactProfileOwner, "")
            verify(!state.popupVisible)
            state.closeManualMeasurement()
            state.contactProfileOwner = "MANUAL"
            state.contactProfileActive = true
            backend.commandOperationFinished(backend.operationId, "press",
                                             "automatic-thc-contact-profile",
                                             "COMPLETED", "")
            wait(0)
            verify(state.popupVisible)
            compare(state.popupTitle, "AUTOMATIC HOLD COMPLETE")
            state.hidePopup()
            state.tonnageHoldProfileFinished.disconnect(record)
            compare(finished, ["CALIBRATION:true", "MANUAL:true"])
        }

        function test_holdProfileOwnedByFeatureSurvivesWithoutManualMode() {
            backend.manualModeEnabled = false
            state.manualModeState = "DISABLED"
            state.contactProfileOwner = "MEASUREMENT"
            state.contactProfileActive = true
            backend.commandOperationFinished(backend.operationId, "press",
                                             "automatic-thc-contact-profile",
                                             "FAILED", "FORCE_TIMEOUT")
            wait(0)
            verify(!state.contactProfileActive)
            // A non-Manual owner never rewrites the Manual panel state.
            compare(state.manualModeState, "DISABLED")
            compare(state.alarmTitle, "AUTOMATIC HOLD FAILED")
            state.contactProfileOwner = "MEASUREMENT"
            state.contactProfileActive = true
            backend.connectionFailed("press", "TRANSPORT_CLOSED")
            wait(0)
            verify(!state.contactProfileActive)
            compare(state.contactProfileOwner, "")
        }

        function test_pressConnectionFailureClearsManualAuthority() {
            backend.manualModeEnabled = true
            state.manualModeArmed = true
            state.tonnageHoldActive = true
            state.manualRepeatJog = true
            state.manualPendingOperation = "tonnage-hold"
            state.manualPendingAction = "tonnage-hold"
            backend.connectionFailed("press", "TRANSPORT_CLOSED")
            wait(0)
            compare(state.manualPendingOperation, "")
            verify(!state.manualModeArmed)
            verify(!state.tonnageHoldActive)
            verify(!state.manualRepeatJog)
            compare(state.manualModeState, "DISABLED")
            compare(state.alarmTitle, "MACHINE CONNECTION FAILED")
        }
    }
}
