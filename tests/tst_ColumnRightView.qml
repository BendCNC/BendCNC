import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    id: root
    width: 462
    height: 668

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
        machineStatus: "STARTUP HOMING REQUIRED"
        ramPosition: -1.2345
        commandedJogSpeed: 4.5
        liveTonnage: 12.5
    }

    BendCNC.ColumnRightView {
        id: view
        anchors.fill: parent
        appState: state
    }

    TestCase {
        name: "ColumnRightViewTests"
        when: windowShown

        function test_fixedPanelGeometryAndBindings() {
            wait(350)
            compare(view.width, 462)
            compare(view.height, 668)

            var ramDro = findChild(view, "ram-dro-view header body panel-load main-axis panel-home-position axis-y-1 axis-y-2 axis-y-diff panel-total-load panel-live-ram-velocity value-box value-row")
            verify(ramDro !== null)
            verify(Math.abs(ramDro.displayedRamCurrent - state.ramPosition) < 0.001)
            verify(Math.abs(ramDro.displayedRamVelocity - state.measuredRamVelocity) < 0.01)
            verify(Math.abs(ramDro.displayedRamTotalLoad - state.liveTonnage) < 0.01)

            var y1Load = findChild(view, "panel-load y1-load")
            var y2Load = findChild(view, "panel-load y2-load")
            verify(y1Load !== null)
            verify(y2Load !== null)
            compare(y1Load.width, 60)
            compare(y1Load.height, 197)
            verify(Math.abs(y1Load.normalizedIntensity - 0.5) < 0.01)
            verify(Math.abs(y2Load.normalizedIntensity - 0.5) < 0.01)

            var loadTrack = findChild(y1Load, "load-intensity-track")
            var loadFill = findChild(y1Load, "load-intensity-fill")
            verify(loadTrack !== null)
            verify(loadFill !== null)
            compare(loadTrack.width, 48)
            compare(loadTrack.height, 118)
            fuzzyCompare(loadFill.height, loadTrack.height * y1Load.animatedIntensity, 0.5)
            fuzzyCompare(loadFill.y + loadFill.height, loadTrack.height, 0.01)

            var ramDroHeader = findChild(ramDro, "header")
            var y1Axis = findChild(ramDro, "axis-y-1")
            var totalLoad = findChild(ramDro, "panel-total-load")
            verify(ramDroHeader !== null)
            verify(y1Axis !== null)
            verify(totalLoad !== null)
            compare(view.topGroupHeight, 456)
            compare(ramDroHeader.height, 33)
            compare(y1Axis.width, 100)
            compare(totalLoad.height, 56)
        }

        function test_currentDroUsesPhysicalEncoderMean() {
            const ramDro = findChild(view, "ram-dro-view header body panel-load main-axis panel-home-position axis-y-1 axis-y-2 axis-y-diff panel-total-load panel-live-ram-velocity value-box value-row")
            verify(ramDro !== null)

            state.offlineSimulationEnabled = false
            state.machineControl = Qt.createQmlObject(`
                import QtQuick
                QtObject {
                    property bool pressConnected: true
                    property bool moduleConnected: false
                    property string pressConnectionState: "READY"
                    property string moduleConnectionState: "DISCONNECTED"
                    property string pressMachineState: "IDLE"
                    property string moduleState: "DISCONNECTED"
                    property string pressFirmwareVersion: "test"
                    property string moduleFirmwareVersion: ""
                    property bool pressReady: true
                    property bool panelJogSupported: true
                    property bool panelJogRequiresPhysicalInputs: true
                    property string lastPanelAction: ""
                    function startAdvanceJog(speed) { lastPanelAction = "advance:" + speed; return true }
                    function startRetractJog(speed) { lastPanelAction = "retract:" + speed; return true }
                    function releasePanelJog() { lastPanelAction = "release"; return true }
                    property bool moduleReady: false
                    property bool pressHomed: true
                    property bool moduleHomed: false
                    property bool pressOperationActive: false
                    property bool moduleOperationActive: false
                    property bool pressTelemetryFresh: true
                    property bool moduleTelemetryFresh: false
                    property bool independentRamTelemetryAvailable: true
                    property real ramPositionY1: -0.04
                    property real ramPositionY2: -0.10
                    property real ramLoadY1: 0
                    property real ramLoadY2: 0
                    property real ramTargetPosition: -0.32
                    property real ramCommandedJogPosition: 0
                    property real ramDistanceToGo: 0
                    property real ramJogSpeed: 0
                    property real ramVelocity: 0
                    property bool measuredRamVelocityAvailable: true
                    property real measuredRamVelocity: -1.7
                    property bool safetyJogLeft: false
                    property bool safetyJogRight: false
                    property bool bendPedal: false
                    property bool antiBind: false
                }
            `, root, "physicalRamTelemetry")
            state.ramPosition = -0.32
            wait(0)

            fuzzyCompare(ramDro.ramCurrent, -0.07, 0.0001)
            fuzzyCompare(ramDro.ramVelocity, -1.7, 0.0001)
            const requirement = findChild(view, "panel-input-requirement")
            compare(requirement.text, "PHYSICAL\nTWO-HAND\nREQUIRED")
            verify(requirement.contentWidth <= requirement.width)
            verify(state.machineAction("advance-jog"))
            compare(state.machineControl.lastPanelAction, "advance:" + state.jogRamSpeed)
            verify(state.machineAction("retract-jog"))
            compare(state.machineControl.lastPanelAction, "retract:" + state.jogRamSpeed)
            verify(state.machineAction("advance-jog-release"))
            compare(state.machineControl.lastPanelAction, "release")
            verify(state.machineAction("retract-jog-release"))
            compare(state.machineControl.lastPanelAction, "release")
            state.machineControl.panelJogSupported = false
            verify(!state.pressCanPanelJog)

            state.machineControl.destroy()
            state.machineControl = null
            state.offlineSimulationEnabled = true
        }

        function test_precisionAuxReadoutsDoNotOverlap() {
            const box = findChild(view, "precision-aux-readouts")
            const current = findChild(view, "current-value")
            const number = findChild(view, "current-value-number")
            verify(box !== null)
            verify(current !== null)
            verify(number !== null)
            verify(!number.truncated)
            const currentEnd = current.mapToItem(view, current.width, 0)
            const boxStart = box.mapToItem(view, 0, 0)
            verify(currentEnd.x + 2 <= boxStart.x)
            const labels = ["commanded-label", "distance-to-go-label"]
            const values = ["commanded-value", "distance-to-go-value"]
            for (let i = 0; i < labels.length; ++i) {
                const label = findChild(box, labels[i])
                const value = findChild(box, values[i])
                verify(label !== null)
                verify(value !== null)
                verify(!label.truncated)
                const labelInBox = label.mapToItem(box, label.width, 0)
                const valueInBox = value.mapToItem(box, 0, 0)
                verify(labelInBox.x + 2 <= valueInBox.x)
                verify(valueInBox.x + value.width <= box.width - 7)
            }
        }

        function test_longMachineStatusRemainsVisible() {
            var statusPanel = findChild(view, "machine-state-view")
            var statusBadge = findChild(view, "machine-state idle")
            var statusLabel = findChild(view, "machine-status-label")
            var statusValue = findChild(view, "machine-status-value")
            var switchHint = findChild(view, "panel-input-requirement")
            verify(statusPanel !== null)
            verify(statusBadge !== null)
            verify(statusLabel !== null)
            verify(statusValue !== null)
            verify(statusBadge.width >= 35)
            verify(statusBadge.width >= statusValue.implicitWidth)
            verify(statusLabel.width > 0)
            verify(statusValue.width > 0)
            verify(statusValue.height > 0)
            verify(!statusValue.truncated)
            verify(statusPanel.x >= switchHint.x + switchHint.width)
            verify(statusPanel.x + statusPanel.width <= view.width - view.pad + 0.01)
        }

        function test_machineStatusIsCenteredAndHumanReadable() {
            const badge = findChild(view, "machine-state idle")
            const value = findChild(view, "machine-status-value")
            verify(badge !== null)
            verify(value !== null)
            state.machineStatus = "tracking-error"
            wait(250)
            compare(value.text, "TRACKING ERROR")
            compare(value.horizontalAlignment, Text.AlignHCenter)
            compare(value.verticalAlignment, Text.AlignVCenter)
            fuzzyCompare(value.mapToItem(badge, value.width / 2, value.height / 2).x,
                         badge.width / 2, 0.1)
            state.machineStatus = "retract_jog"
            wait(250)
            compare(value.text, "RETRACT JOG")
            state.machineStatus = "STARTUP HOMING REQUIRED"
        }

        function test_userControlsUseBalancedRows() {
            var topRow = findChild(view, "grid user-control-grid row-top")
            var bottomRow = findChild(view, "grid user-control-grid row-bottom")
            verify(topRow !== null)
            verify(bottomRow !== null)
            fuzzyCompare(topRow.height, bottomRow.height, 0.01)
            compare(bottomRow.y + bottomRow.height, view.height - 7)
        }

        function test_backGaugePositionsUseLiveStateAndHideStaleTelemetry() {
            const positions = findChild(view, "backgauge-positions-view")
            const xValue = findChild(view, "backgauge-x-value")
            const rValue = findChild(view, "backgauge-r-value")
            verify(positions !== null)
            verify(xValue !== null)
            verify(rValue !== null)

            state.offlineSimulationEnabled = true
            state.backGaugeX = 12.34567
            state.backGaugeR = -0.81234
            state.backGaugeUnit = "MILLIMETER"
            wait(0)
            compare(positions.positionAvailable, true)
            compare(positions.bgUnit, "mm")
            compare(xValue.text, "12.3457")
            compare(rValue.text, "-0.8123")

            state.offlineSimulationEnabled = false
            state.machineControl = null
            wait(0)
            compare(positions.positionAvailable, false)
            compare(xValue.text, "----")
            compare(rValue.text, "----")

            state.offlineSimulationEnabled = true
            state.backGaugeUnit = "INCH"
        }

        function test_measureButtonOpensMeasurementModal() {
            const measure = findChild(view, "open-measurement-button")
            verify(measure !== null)
            state.manualMeasurementVisible = false
            state.manualMeasurementMode = "CALIBRATION"
            mouseClick(measure)
            compare(state.manualMeasurementVisible, true)
            compare(state.manualMeasurementMode, "MEASUREMENT")
        }

        function test_ledLabelsAndIndicatorSizes() {
            var jogPanel = findChild(view, "led-panel-jog")
            var pedalPanel = findChild(view, "led-panel-pedal")
            var antiBindPanel = findChild(view, "led-panel-anti-bind")
            verify(jogPanel !== null)
            verify(pedalPanel !== null)
            verify(antiBindPanel !== null)
            compare(jogPanel.width, view.ledWideWidth)
            compare(pedalPanel.width, view.ledWideWidth)
            compare(antiBindPanel.width, view.ledNarrowWidth)
            verify(findChild(jogPanel, "jog-indicator-left") !== null)
            verify(findChild(jogPanel, "jog-indicator-right") !== null)
            verify(findChild(pedalPanel, "pedal-indicator") !== null)
            verify(findChild(antiBindPanel, "anti-bind-indicator") !== null)
        }

        function test_pedalIndicatorTracksPhysicalInput() {
            const pedalIndicator = findChild(view, "pedal-indicator")
            verify(pedalIndicator !== null)

            state.bendJogPedal = false
            wait(0)
            compare(pedalIndicator.active, false)

            state.bendJogPedal = true
            wait(0)
            compare(pedalIndicator.active, true)

            state.bendJogPedal = false
        }

        function test_loadIntensityClampsToCapacity() {
            state.liveTonnage = 40
            wait(350)
            var y1Load = findChild(view, "panel-load y1-load")
            compare(y1Load.normalizedIntensity, 1)

            state.liveTonnage = 0
            wait(350)
            compare(y1Load.normalizedIntensity, 0)
        }

        function test_pedalForceTimeoutIsQuietButOtherFailuresAlarm() {
            state.alarmVisible = false
            state.manualPendingOperation = "tonnage-hold"
            state.manualPendingAction = "hold"
            verify(state.handleManualOperationFinished(
                       "tonnage-hold", "FAILED", "FORCE_TIMEOUT"))
            verify(!state.alarmVisible)

            state.manualPendingOperation = "tonnage-hold"
            state.manualPendingAction = "hold"
            verify(state.handleManualOperationFinished(
                       "tonnage-hold", "FAILED", "LOAD_CHANNELS"))
            verify(state.alarmVisible)
            compare(state.alarmTitle, "MANUAL OPERATION FAILED")
            state.alarmVisible = false
        }

        function test_continuousRetractUsesPressAndReleaseLifecycle() {
            var retract = findChild(view, "button continuous-retract-jog")
            verify(retract !== null)
            state.machineStatus = "IDLE"
            mousePress(retract)
            compare(state.machineStatus, "RETRACT JOG")
            mouseRelease(retract)
            compare(state.machineStatus, "IDLE")
            compare(state.commandedJogSpeed, 0)
        }

        function test_holdGestureSurvivesAdmissionPropertyChangingFalse() {
            const retract = findChild(view, "button continuous-retract-jog")
            const input = findChild(retract, "control-input")
            verify(retract !== null)
            verify(input !== null)
            state.machineStatus = "IDLE"

            mousePress(retract)
            verify(input.pressed)
            compare(state.machineStatus, "RETRACT JOG")

            // Hardware admission becomes false as soon as the backend marks
            // the operation active. The already-admitted pointer must remain
            // owned until release so STOP is generated by the same gesture.
            retract.controlEnabled = false
            wait(0)
            verify(input.enabled)
            verify(input.pressed)

            mouseRelease(retract)
            compare(state.machineStatus, "IDLE")
            compare(state.commandedJogSpeed, 0)
            retract.controlEnabled = Qt.binding(function() {
                return state.pressCanPanelJog
            })
        }

        function test_continuousAdvanceUsesPressAndReleaseLifecycle() {
            var advance = findChild(view, "button continuous-advance-jog")
            verify(advance !== null)
            state.machineStatus = "IDLE"
            state.ramPosition = -1.0
            mousePress(advance)
            compare(state.machineStatus, "SAFETY JOG")
            verify(state.ramPosition < -1.0)
            mouseRelease(advance)
            compare(state.machineStatus, "IDLE")
            compare(state.commandedJogSpeed, 0)
        }

        function test_homeButtonReflectsHomedAndSupportsCombinedHome() {
            var home = findChild(view, "button home-machine")
            verify(home !== null)
            state.offlineSimulationEnabled = true
            state.machineStatus = "STARTUP_HOMING_REQUIRED"
            wait(0)
            compare(home.controlEnabled, true)
            compare(home.controllerRequiresHoming, true)
            compare(home.needsHoming, true)
            verify(home.glowPulse >= 0)

            verify(state.startCombinedHome())
            compare(state.machineStatus, "HOMING")
            compare(home.isHoming, true)
            compare(home.needsHoming, false)
            compare(state.backGaugeHomed, false)
            wait(500)
            compare(state.machineStatus, "IDLE")
            compare(state.backGaugeHomed, true)
            compare(home.isHomed, true)
            compare(home.needsHoming, false)
        }

        function test_continuousRetractReflectsMachineAvailability() {
            var retract = findChild(view, "button continuous-retract-jog")
            verify(retract !== null)
            compare(retract.controlEnabled, true)
            state.offlineSimulationEnabled = false
            wait(0)
            compare(retract.controlEnabled, false)
            state.offlineSimulationEnabled = true
        }

        function test_speedFieldsOpenNumericKeyboardAndClamp() {
            state.machineStatus = "IDLE"
            state.bendRamSpeed = 5
            state.jogRamSpeed = 5
            const bendSpeed = findChild(view, "bend-speed-field")
            const jogSpeed = findChild(view, "jog-speed-field")
            verify(bendSpeed && jogSpeed)
            mouseClick(bendSpeed)
            verify(state.onScreenKeyboardVisible)
            compare(state.onScreenKeyboardKind, "numeric")
            state.clearOnScreenKeyboard()
            state.insertOnScreenKeyboardText("20")
            verify(state.commitOnScreenKeyboard())
            compare(state.bendRamSpeed, 15)
            mouseClick(jogSpeed)
            state.clearOnScreenKeyboard()
            state.insertOnScreenKeyboardText("0.1")
            verify(state.commitOnScreenKeyboard())
            compare(state.jogRamSpeed, 0.5)
        }
    }
}