import QtQuick
import QtTest
import "../qml" as Production

Item {
    id: testSurface
    width: 950
    height: 600
    Component {
        id: backendComponent
        QtObject {
            property bool pressConnected: true
            property bool pressTelemetryFresh: true
            property bool independentRamTelemetryAvailable: true
            property double pressTelemetrySequence: 10
            property var ramLoadY1: 0.4
            property var ramLoadY2: 0.6
            property bool motorRpmAvailable: true
            property var motorRpmY1: 1200
            property var motorRpmY2: 1198
            property var thcLiveDiagnostics: ({})
            property var thcFineLoad: ({})
            property double operationId: 7
            property string operationDevice: "press"
            property string operationName: "thc-contact-profile-v53"
            property bool commandOperationActive: true
            property bool thcContinuousActive: true
            signal telemetryChanged()
            signal commandLifecycleChanged()
        }
    }
    Component { id: historyComponent; Production.ThcTelemetryHistory {} }
    SignalSpy { id: sampleSpy; signalName: "samplesChanged" }
    Component {
        id: legacyBackendComponent
        QtObject {
            property bool pressConnected: true
            property bool pressTelemetryFresh: true
            signal telemetryChanged()
        }
    }

    TestCase {
        name: "ThcTelemetryHistoryTests"
        when: windowShown
        property var mock: null
        property var history: null

        function init() {
            mock = createTemporaryObject(backendComponent, testSurface)
            verify(!!mock, "Object exists")
            history = createTemporaryObject(historyComponent, testSurface, { backend: mock, monitoring: true })
            verify(!!history, "Component exists")
            // Deterministic clock for observer tests only, never production data.
            history.agingClock.stop()
            sampleSpy.target = history
            sampleSpy.clear()
        }

        function arrive(y1, y2) {
            mock.ramLoadY1 = y1
            mock.ramLoadY2 = y2
            ++mock.pressTelemetrySequence
        }

        function test_noInitialInventedSamplesOrTimerSamples() {
            compare(history.samples.length, 0)
            history.advance(history.nowMs + 1000)
            compare(history.samples.length, 0)
            compare(history.totalLoad, 1)
            compare(history.rpmDelta, 2)
        }

        function test_arrivalTimestampAndSequenceDedup() {
            const before = Date.now()
            arrive(0.3, 0.8)
            compare(history.samples.length, 1)
            compare(history.samples[0].sequence, "11")
            fuzzyCompare(history.samples[0].total, 1.1, 0.000001)
            verify(history.samples[0].at >= before)
            verify(history.samples[0].at <= Date.now())
            const at = history.samples[0].at
            mock.telemetryChanged() // module/TH_CTRL/duplicate notify is not a new press frame
            compare(history.samples.length, 1)
            compare(history.samples[0].at, at)
            compare(history.seriesSegments.length, 1)
        }

        function test_sourceFractionsArePreservedWithoutDiagnosticSubstitution() {
            // Fractional fixture proves the observer does not quantize; it is
            // not evidence that the current firmware's status has this precision.
            arrive(0.45123, 0.55123)
            fuzzyCompare(history.samples[0].total, 1.00246, 0.0000001)
            compare(history.samples[0].y1, 0.45123)
            compare(history.samples[0].y2, 0.55123)
            const at = history.samples[0].at
            arrive(0.45, 0.56)
            fuzzyCompare(history.samples[1].total, 1.01, 0.0000001)
            compare(history.samples[0].at, at)
            compare(history.samples[0].sequence, "11")
            compare(history.samples[1].sequence, "12")
            mock.thcLiveDiagnostics = { f1: 0.49999, f2: 0.49999, force: 0.99998, ms: 100, age: 0 }
            mock.thcLiveDiagnosticsChanged()
            mock.telemetryChanged()
            compare(history.samples.length, 2)
            compare(history.samples[1].total, history.totalLoad)
            fuzzyCompare(history.totalLoad, 1.01, 0.0000001)
            mock.independentRamTelemetryAvailable = false
            compare(history.totalLoad, null) // precise diagnostics cannot fill missing status
            compare(history.samples[history.samples.length - 1].gap, true)
        }

        function test_staleDisconnectAndResumeGaps_data() {
            return [{ tag: "stale", key: "pressTelemetryFresh" },
                { tag: "disconnected", key: "pressConnected" },
                { tag: "load-absent", key: "independentRamTelemetryAvailable" }]
        }

        function fineArrival(sequence, y1, y2, generation) {
            mock.thcFineLoad = { source: "TH_CTRL_FILTERED_PRE_DEADZONE", ownerId: "7",
                generation: generation || "1", sequence: sequence, f1: y1, f2: y2,
                mcuMs: 1000 + sequence * 100, mcuSequence: sequence * 4, breakBefore: false }
        }

        function test_fineOptInFractionsTransitionsAndNoPollingDuplicates() {
            history.preferFine = true
            history.fineOwnerId = "7"
            arrive(0.4, 0.6)
            fineArrival(1, 0.45123, 0.54877)
            compare(history.fineAvailable, true)
            compare(history.samples.length, 3) // status, gap, fine
            compare(history.samples[0].source, "STATUS")
            compare(history.samples[2].source, "TH_CTRL_FILTERED_PRE_DEADZONE")
            compare(history.samples[2].ownerId, "7")
            compare(history.samples[2].generation, "1")
            fineArrival(2, 0.46123, 0.54877)
            fuzzyCompare(history.samples[3].total, 1.01, 0.0000001)
            compare(mock.ramLoadY1, 0.4)
            compare(mock.ramLoadY2, 0.6)
            const at = history.samples[3].at
            mock.telemetryChanged()
            mock.thcFineLoadChanged()
            arrive(0.5, 0.6) // consume fallback sequence while fine is selected
            compare(history.samples.length, 4)
            compare(history.samples[3].at, at)
            mock.thcFineLoad = ({}) // timeout; don't restamp old status
            compare(history.fineAvailable, false)
            compare(history.samples.length, 5)
            compare(history.samples[4].gap, true)
            fuzzyCompare(history.totalLoad, 1.1, 0.0000001)
            arrive(0.5, 0.7)
            compare(history.samples[5].source, "STATUS")
            compare(history.samples[5].breakBefore, true)
            fineArrival(3, 0.47123, 0.54877, "2")
            compare(history.seriesSegments.length, 2) // same source/owner; separate generations
            compare(history.samples[7].generation, "2")
            compare(history.samples[7].breakBefore, true)
            fuzzyCompare(history.range.minimum, 1.00, 0.0000001)
            fuzzyCompare(history.range.maximum, 1.02, 0.0000001)
        }

        function test_fineOwnerHiddenInvalidAndLegacyStayIsolated() {
            fineArrival(1, 0.49, 0.52)
            compare(history.fineAvailable, false) // default opt-out remains status
            compare(history.samples.length, 0)
            history.preferFine = true
            history.fineOwnerId = "7"
            fineArrival(2, 0.49, 0.52)
            compare(history.samples.length, 1)
            mock.operationId = 8
            mock.commandLifecycleChanged()
            compare(history.fineAvailable, false)
            compare(history.samples[1].gap, true)
            fineArrival(3, 0.48, 0.52)
            compare(history.samples.length, 2) // wrong owner cannot fill the gap
            mock.operationId = 7
            history.monitoring = false
            fineArrival(4, 0.48, 0.52)
            history.monitoring = true
            history.agingClock.stop()
            mock.thcFineLoadChanged()
            compare(history.samples.length, 2) // hidden frame consumed, not resurrected
            fineArrival(5, 0.47, 0.52)
            compare(history.samples.length, 3)
            mock.thcFineLoad = { source: "TH_CTRL_FILTERED_PRE_DEADZONE", ownerId: "7",
                generation: "1", sequence: 6, f1: NaN, f2: 0.5 }
            compare(history.fineAvailable, false)
            compare(history.samples[3].gap, true)
        }

        function test_longFineGenerationsRetainMeasuredWindowWithoutJoining() {
            history.preferFine = true
            history.fineOwnerId = "7"
            const start = Date.now()
            // Drive the existing arrival observer with a deterministic clock,
            // not wall-time property-change callbacks or a production mock.
            history.telemetryConnections.target = null
            history.nowMs = start
            for (let i = 1; i <= 900; ++i) {
                fineArrival(i, 0.45 + (i % 7) * 0.00001, 0.55002,
                    String(1 + Math.floor((i - 1) / 160)))
                verify(history.observe(start + i * 100))
                if (i === 160 || i === 161 || i === 200 || i === 600 || i === 900) {
                    const measured = history.selectedSamples.filter(sample => !sample.gap)
                    compare(measured.length, Math.min(i, 601))
                    compare(measured[0].sequence, String(Math.max(1, i - 600)))
                    compare(measured[measured.length - 1].sequence, String(i))
                }
            }
            compare(history.samples.filter(sample => !sample.gap).length, 601)
            verify(history.samples.every(sample => sample.at >= history.nowMs - 60000))
            compare(history.seriesSegments.length, 5)
            for (const segment of history.seriesSegments) {
                verify(segment.every(sample => sample.ownerId === "7"
                    && sample.generation === segment[0].generation
                    && sample.source === "TH_CTRL_FILTERED_PRE_DEADZONE"))
            }
            fuzzyCompare(history.range.minimum, 1.00002, 0.0000001)
            fuzzyCompare(history.range.maximum, 1.00008, 0.0000001)
        }

        function test_longFineBurstBoundAndSingleNotification() {
            history.preferFine = true
            history.fineOwnerId = "7"
            history.telemetryConnections.target = null
            const start = Date.now()
            history.nowMs = start
            for (let i = 1; i <= 7500; ++i) {
                fineArrival(i, (i % 5) * 0.00001 - 0.2, 0.55002,
                    String(1 + Math.floor((i - 1) / 1600)))
                sampleSpy.clear()
                verify(history.observe(start + i * 10))
                compare(sampleSpy.count, 1) // trim + gap + append is one transaction
                verify(history.samples.length <= 2048)
            }
            compare(history.samples.length, 2048)
            verify(history.samples[0].at >= history.nowMs - 60000)
            const values = history.selectedSamples.filter(sample => !sample.gap)
            compare(values[values.length - 1].sequence, "7500")
            verify(values[0].sequence !== "1")
            fuzzyCompare(history.range.minimum, 0.35002, 0.0000001)
            fuzzyCompare(history.range.maximum, 0.35006, 0.0000001)
            sampleSpy.clear()
            compare(history.observe(history.nowMs), false)
            compare(sampleSpy.count, 0) // repeated notification never copies or appends
        }

        function test_fineTimeoutStatusWarmupAndOwnerStaySeparated() {
            history.preferFine = true
            history.fineOwnerId = "7"
            fineArrival(1, 0.45123, 0.55002)
            const at = history.samples[0].at
            mock.thcFineLoad = ({})
            compare(history.fineAvailable, false)
            compare(history.fineHistorySelected, true)
            arrive(2, 3)
            compare(history.totalLoad, 5)
            compare(history.selectedSamples.filter(sample => !sample.gap).length, 1)
            fineArrival(2, 0.46123, 0.55002, "2")
            compare(history.samples[0].at, at)
            compare(history.seriesSegments.length, 2)
            fuzzyCompare(history.range.minimum, 1.00125, 0.0000001)
            fuzzyCompare(history.range.maximum, 1.01125, 0.0000001)
            mock.pressTelemetryFresh = false
            compare(history.totalLoad, null)
            compare(history.selectedSamples.filter(sample => !sample.gap).length, 2)
            mock.operationId = 8
            history.fineOwnerId = "8"
            mock.pressTelemetryFresh = true
            mock.thcFineLoad = { source: "TH_CTRL_FILTERED_PRE_DEADZONE", ownerId: "8",
                generation: "3", sequence: 3, f1: 0.1, f2: 0.2 }
            compare(history.selectedSamples.filter(sample => !sample.gap).length, 1)
            compare(history.seriesSegments.length, 1)
            compare(history.seriesSegments[0][0].ownerId, "8")
            fuzzyCompare(history.range.minimum, 0.3, 0.0000001)
        }

        function test_staleDisconnectAndResumeGaps(data) {
            arrive(0.4, 0.6)
            mock[data.key] = false
            compare(history.totalLoad, null)
            compare(history.samples.length, 2)
            compare(history.samples[1].gap, true)
            mock.telemetryChanged()
            compare(history.samples.length, 2)
            ++mock.pressTelemetrySequence // An unavailable frame must stay unavailable.
            mock[data.key] = true
            mock.telemetryChanged()
            compare(history.samples.length, 2) // do not resurrect the last old frame
            arrive(0.5, 0.7)
            compare(history.seriesSegments.length, 2)
            compare(history.samples[2].breakBefore, true)
            compare(history.samples[2].total, 1.2)
        }

        function test_missingMetricsAreNullButRealZeroAndNegativeAreRetained() {
            mock.motorRpmAvailable = false
            compare(history.rpmY1, null)
            compare(history.rpmY2, null)
            mock.motorRpmAvailable = true
            mock.motorRpmY1 = NaN
            compare(history.rpmAvailable, false)
            mock.motorRpmY1 = 0
            mock.motorRpmY2 = 0
            compare(history.rpmY1, 0)
            arrive(-0.2, 0)
            compare(history.totalLoad, -0.2)
            compare(history.samples[0].total, -0.2)
            mock.ramLoadY1 = "0.2"
            compare(history.loadY1Available, false)
            compare(history.totalLoad, null)
            mock.ramLoadY1 = NaN
            mock.ramLoadY2 = Infinity
            compare(history.loadY2Available, false)
            compare(history.range.minimum, -0.2)
        }

        function test_invalidArrivalCannotAppend() {
            compare(history.observe(NaN), false)
            compare(history.observe(Infinity), false)
            compare(history.samples.length, 0)
        }

        function test_absentLegacyFieldsAndNullBackendHaveNoSubstitutes() {
            const legacy = createTemporaryObject(legacyBackendComponent, testSurface)
            verify(!!legacy, "Object exists")
            history.backend = legacy
            compare(history.sequence(), "")
            compare(history.totalLoad, null)
            compare(history.rpmY1, null)
            legacy.telemetryChanged()
            compare(history.samples.length, 0)
            history.backend = null
            compare(history.telemetryReady, false)
            compare(history.loadY2, null)
            compare(history.rpmY2, null)
        }

        function test_sequenceSkipsResetAndUnsafeValuesNeverBridge() {
            arrive(0.4, 0.6)
            mock.pressTelemetrySequence += 3
            compare(history.seriesSegments.length, 2)
            mock.pressTelemetrySequence = 1
            compare(history.seriesSegments.length, 3)
            const length = history.samples.length
            mock.pressTelemetrySequence = 9007199254740992
            compare(history.samples.length, length + 1)
            compare(history.samples[length].gap, true)
            mock.pressTelemetrySequence = 0
            compare(history.samples.length, length + 1)
        }

        function test_timeBoundsAndRangeExpireWithoutNewFrames() {
            arrive(0.2, 0.3)
            const firstAt = history.samples[0].at
            history.nowMs = firstAt
            history.advance(firstAt + 60000)
            verify(history.samples.length > 0)
            history.advance(firstAt + 60001)
            compare(history.samples.length, 0)
            compare(history.range.minimum, null)
            compare(history.range.maximum, null)
        }

        function test_countBoundUnderBurstAndNoZeroMarkers() {
            for (let i = 0; i < history.maximumSamples + 10; ++i)
                ++mock.pressTelemetrySequence
            compare(history.samples.length, history.maximumSamples)
            verify(history.samples[0].sequence !== "11")
            mock.pressConnected = false
            compare(history.samples.length, history.maximumSamples)
            const gap = history.samples[history.samples.length - 1]
            compare(gap.gap, true)
            compare(gap.total, undefined)
        }

        function test_hiddenOfflineBackendReplacementAndClockRollback() {
            arrive(0.4, 0.6)
            history.monitoring = false
            arrive(0.5, 0.5)
            compare(history.seriesSegments.length, 1)
            history.monitoring = true
            history.agingClock.stop()
            arrive(0.6, 0.6)
            compare(history.seriesSegments.length, 2)
            history.offline = true
            compare(history.totalLoad, null)
            compare(history.rpmY1, null)
            history.backend = null
            compare(history.samples.length, 0)
            history.backend = mock
            history.offline = false
            arrive(0.4, 0.6)
            compare(history.samples.length, 1)
            history.advance(history.nowMs - 1)
            compare(history.samples.length, 0)
            compare(history.gapOpen, true)
        }
    }
}