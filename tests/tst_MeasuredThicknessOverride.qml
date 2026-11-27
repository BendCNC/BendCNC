import QtQuick
import QtTest
import "../qml" as BendCNC

// Session-only measured thickness override: the active program runs with the
// released measured thickness while programs (and storage) keep their own.
Item {
    width: 640
    height: 480

    BendCNC.AppState {
        id: state
    }

    TestCase {
        name: "MeasuredThicknessOverride"
        when: windowShown

        readonly property var punches: [{ id: "p1", name: "PUNCH 1", heightInch: 3.0 }]
        readonly property var dies: [{ id: "d1", name: "DIE 1", heightInch: 2.0, vdieOpeningInch: 0.5 }]
        readonly property var materials: [{ id: "m1", name: "STEEL", materialTensileStrengthPsi: 60000,
                                            insideRadiusRuleOfThumb: 0.15, materialSpringback: 2.0 }]

        function storedBend(extra) {
            return Object.assign({
                id: "b1", name: "B1", punchId: "p1", dieId: "d1", materialId: "m1",
                thickness: 0.06, bendWidth: 10, desiredBendAngle: 90, angleCompensation: 0,
                additionalRetractAfterBend: 0.5
            }, extra || {})
        }

        function loadProgram(bends) {
            state.setProgramsFromStorage([{ id: "prog1", name: "Battery Plate N1", bends: bends }],
                                         [], punches, dies, materials, null)
        }

        function measure(value) {
            state.applyUserSettings({ measuredMaterialThickness: { value: value, unit: "INCH", valid: true } })
        }

        function calcFor(bend, thickness) {
            return state.measuredThicknessBendCalc(bend, thickness, punches[0], dies[0], materials[0])
        }

        function init() {
            state.runActive = false
            state.runSimulatedRun = false
            state.measuredThicknessOverrideEnabled = false
            state.measuredThicknessOverrideResyncPending = false
            state.applyUserSettings({})
            state.clearAlarm()
        }

        function test_override_recalculates_runtime_without_editing_program() {
            loadProgram([storedBend()])
            measure(0.035)
            var stored = JSON.parse(JSON.stringify(state.programs[0].bends[0]))
            compare(state.programBends[0].startPosition, stored.startPosition)

            verify(state.setMeasuredThicknessOverride(true))
            verify(state.measuredThicknessOverrideActive)
            compare(state.measuredThicknessOverrideUnresolvedCount, 0)
            var runtime = state.programBends[0]
            compare(runtime.measuredThicknessOverride, "APPLIED")
            compare(runtime.thickness, "0.0350")
            compare(runtime.materialThickness, 0.035)
            var dt = 0.035 - 0.06
            fuzzyCompare(Number(runtime.startPosition) - Number(stored.startPosition), dt, 0.00011)
            fuzzyCompare(Number(runtime.clampPosition) - Number(stored.clampPosition),
                         dt * (1 - state.materialClampRatePercentage / 100), 0.00011)
            var base = calcFor(stored, 0.06)
            var measured = calcFor(stored, 0.035)
            fuzzyCompare(Number(runtime.finalPosition) - Number(stored.finalPosition),
                         measured.calculatedFinalBendPosition - base.calculatedFinalBendPosition, 0.00011)
            verify(Number(runtime.finalPosition) !== Number(stored.finalPosition))
            fuzzyCompare(Number(runtime.tonnage), Number(stored.tonnage) * Math.pow(0.035 / 0.06, 2), 0.0011)
            compare(state.selectedBend.startPosition, runtime.startPosition)
            verify(state.measuredThicknessOverrideText().indexOf("MEASURED t 0.0350 in") >= 0)
            verify(state.measuredThicknessOverrideText().indexOf("PROGRAM t 0.0600 in") >= 0)
            verify(state.measuredThicknessOverrideText().indexOf("NOT SAVED") >= 0)

            // Program, stored copy (Create Bend source) and storage stay untouched.
            compare(JSON.stringify(state.programs[0].bends[0]), JSON.stringify(stored))
            compare(state.storedProgramBends[0].startPosition, stored.startPosition)
            compare(state.storedProgramBends[0].thickness, "0.0600")
            verify(state.storedProgramBends[0].measuredThicknessOverride === undefined)

            verify(state.setMeasuredThicknessOverride(false))
            verify(!state.measuredThicknessOverrideActive)
            compare(state.programBends[0].startPosition, stored.startPosition)
            compare(state.programBends[0].finalPosition, stored.finalPosition)
            compare(state.programBends[0].thickness, "0.0600")
            verify(state.programBends[0].measuredThicknessOverride === undefined)
        }

        function test_requires_measurement_and_idle_run() {
            loadProgram([storedBend()])
            verify(!state.setMeasuredThicknessOverride(true))
            compare(state.alarmTitle, "NO MEASURED THICKNESS")
            verify(!state.measuredThicknessOverrideEnabled)

            state.clearAlarm()
            measure(0.035)
            state.runActive = true
            verify(!state.setMeasuredThicknessOverride(true))
            compare(state.alarmTitle, "MEASURED THICKNESS OVERRIDE")
            verify(!state.measuredThicknessOverrideEnabled)
            state.runActive = false

            state.clearAlarm()
            state.runSimulatedRun = true
            verify(!state.setMeasuredThicknessOverride(true))
            verify(!state.measuredThicknessOverrideEnabled)
        }

        function test_measurement_change_during_run_is_deferred() {
            loadProgram([storedBend()])
            measure(0.035)
            verify(state.setMeasuredThicknessOverride(true))
            var during = state.programBends[0].startPosition
            state.runActive = true
            measure(0.04)
            compare(state.programBends[0].startPosition, during)
            verify(state.measuredThicknessOverrideResyncPending)
            state.runActive = false
            verify(!state.measuredThicknessOverrideResyncPending)
            compare(state.programBends[0].thickness, "0.0400")
            fuzzyCompare(Number(state.programBends[0].startPosition) - Number(during), 0.005, 0.00011)
        }

        function test_invalidated_measurement_restores_program_values() {
            loadProgram([storedBend()])
            measure(0.035)
            verify(state.setMeasuredThicknessOverride(true))
            state.applyUserSettings({})
            verify(!state.measuredThicknessOverrideActive)
            compare(state.programBends[0].thickness, "0.0600")
            compare(state.programBends[0].startPosition, state.programs[0].bends[0].startPosition)
        }

        function test_operator_final_override_stays_fixed() {
            var nominal = calcFor(storedBend({ materialThickness: 0.06, punchToMaterialClearance: 0.0306 }), 0.06)
            var operatorFinal = nominal.calculatedFinalBendPosition - 0.01
            loadProgram([storedBend({ overrideFinalBendPositionEnabled: true,
                                      overriddenFinalBendPosition: operatorFinal })])
            measure(0.035)
            var stored = state.programs[0].bends[0]
            fuzzyCompare(Number(stored.finalPosition), operatorFinal, 0.00011)
            verify(state.setMeasuredThicknessOverride(true))
            var runtime = state.programBends[0]
            compare(runtime.measuredThicknessOverride, "APPLIED")
            verify(runtime.measuredThicknessFinalFixed)
            compare(runtime.finalPosition, stored.finalPosition)
            fuzzyCompare(Number(runtime.startPosition) - Number(stored.startPosition), -0.025, 0.00011)
        }

        function test_unresolved_tooling_blocks_run_admission() {
            loadProgram([storedBend({ punchId: "missing" })])
            measure(0.035)
            verify(state.setMeasuredThicknessOverride(true))
            compare(state.measuredThicknessOverrideUnresolvedCount, 1)
            compare(state.alarmTitle, "MEASURED THICKNESS OVERRIDE")
            compare(state.programBends[0].measuredThicknessOverride, "UNRESOLVED")
            // Positions are left as programmed, but RUN cannot be admitted.
            compare(state.programBends[0].startPosition, state.programs[0].bends[0].startPosition)
            state.clearAlarm()
            state.openRunConfirmation()
            compare(state.alarmTitle, "MEASURED THICKNESS OVERRIDE")
            verify(state.alarmBody.indexOf("cannot be recalculated") >= 0)
            verify(!state.runActive)
        }
    }
}
