import QtQuick
import QtTest
import "../qml" as Production

Item {
    id: testSurface
    width: 950
    height: 600
    Component { id: chartComponent; Production.ThcTonnageChart { width: 530; height: 220 } }
    Component { id: historyComponent; Production.ThcTelemetryHistory {} }
    Component {
        id: fineBackendComponent
        QtObject {
            property bool pressConnected: true
            property bool pressTelemetryFresh: true
            property bool independentRamTelemetryAvailable: true
            property double pressTelemetrySequence: 1
            property double ramLoadY1: 0.4
            property double ramLoadY2: 0.6
            property double operationId: 7
            property string operationDevice: "press"
            property string operationName: "thc-contact-profile-v53"
            property bool commandOperationActive: true
            property bool thcContinuousActive: true
            property var thcFineLoad: ({})
        }
    }

    TestCase {
        name: "ThcTonnageChartTests"
        when: windowShown
        property var chart: null
        property var history: null

        function init() {
            history = createTemporaryObject(historyComponent, testSurface)
            verify(!!history, "Object exists")
            chart = createTemporaryObject(chartComponent, testSurface, { history: history })
            verify(!!chart, "Component exists")
            verify(waitForItemPolished(chart))
        }

        function test_absenceDoesNotDrawFakeCurve() {
            compare(chart.hasData, false)
            compare(chart.plotSegments.length, 0)
            const empty = findChild(chart, "thc-live-chart-empty")
            verify(!!empty, "Object exists")
            compare(empty.visible, true)
            const live = findChild(chart, "thc-live-load-total")
            verify(!!live, "Object exists")
            verify(live.text.indexOf("LIVE — T") >= 0)
        }

        function test_shapeIdentityAndBoundedProjectionUnderBurst() {
            const shape = findChild(chart, "thc-live-chart-path")
            verify(!!shape)
            const start = history.nowMs
            for (let n = 1; n <= 30; ++n) {
                history.samples = Array.from({ length: 2048 }, (_, index) => ({
                    at: start - (2047 - index) * 10, total: 1 + (index % 7) * 0.00001,
                    breakBefore: index === 0 || index === 1024 }))
                compare(chart.plotSegments.length, 0) // synchronous burst is coalesced
                verify(findChild(chart, "thc-live-chart-path") === shape)
            }
            tryCompare(chart, "projectionDirty", false)
            compare(chart.plotSegments.length, 2)
            compare(chart.plotSegments[0].length, 1024)
            compare(chart.plotSegments[1].length, 1024)
            verify(findChild(chart, "thc-live-chart-path") === shape)
            verify(waitForItemPolished(chart))
            history.advance(start + 60001)
            compare(chart.plotSegments.length, 0) // immediate empty-window clearing
        }

        function test_timeCoordinatesGapsAndNegativeAutoScale() {
            history.nowMs = 100000
            history.samples = [{ at: 50000, total: -0.2, breakBefore: true },
                { at: 70000, total: 0.7 }, { at: 71000, gap: true },
                { at: 99000, total: 1.2, breakBefore: true }]
            chart.refreshProjection()
            compare(chart.hasData, true)
            compare(chart.minimum, -0.2)
            compare(chart.maximum, 1.2)
            verify(chart.axisMinimum < -0.2)
            verify(chart.axisMaximum > 1.2)
            compare(chart.plotSegments.length, 2)
            compare(chart.plotSegments[0].length, 2)
            compare(chart.plotSegments[1].length, 1)
            const first = chart.plotSegments[0][0].x
            const second = chart.plotSegments[0][1].x
            const last = chart.plotSegments[1][0].x
            fuzzyCompare((second - first) / (last - first), 20000 / 49000, 0.00001)
            verify(waitForRendering(chart))
            history.advance(160001)
            chart.refreshProjection()
            compare(chart.plotSegments.length, 0)
            compare(chart.hasData, false)
        }

        function test_uniformAndSingleMeasuredSampleDoNotCollapse() {
            history.samples = [{ at: history.nowMs, total: 0, breakBefore: true }]
            chart.refreshProjection()
            compare(chart.plotSegments.length, 1)
            compare(chart.plotSegments[0].length, 1)
            verify(isFinite(chart.plotSegments[0][0].y))
            verify(chart.axisMaximum > chart.axisMinimum)
            compare(chart.metric(null, 3), "—")
            compare(chart.metric(NaN, 3), "—")
            compare(chart.metric(0, 3), "0.000")
        }

        function test_realFineFluctuationsLabelAndFallbackNeverJoinSources() {
            const mock = createTemporaryObject(fineBackendComponent, testSurface)
            verify(!!mock)
            history.backend = mock
            history.preferFine = true
            history.fineOwnerId = "7"
            history.monitoring = true
            history.agingClock.stop()
            for (let i = 1; i <= 3; ++i)
                mock.thcFineLoad = { source: "TH_CTRL_FILTERED_PRE_DEADZONE", ownerId: "7",
                    generation: "1", sequence: i, f1: 0.44 + i * 0.01, f2: 0.54 }
            chart.refreshProjection()
            compare(history.samples.length, 3)
            fuzzyCompare(chart.maximum - chart.minimum, 0.02, 0.0000001)
            compare(chart.plotSegments.length, 1)
            verify(chart.plotSegments[0][0].y !== chart.plotSegments[0][2].y)
            const notice = findChild(chart, "thc-live-chart-resolution")
            verify(!!notice)
            verify(notice.text.indexOf("filtered / pre-deadzone") >= 0)
            verify(notice.text.indexOf("not physical accuracy") >= 0)
            mock.thcFineLoad = ({})
            chart.refreshProjection()
            compare(chart.plotSegments.length, 1) // admitted history does not expire with LIVE
            verify(notice.text.indexOf("Fine history retained") >= 0)
            verify(notice.text.indexOf("LIVE is STATUS fallback") >= 0)
            ++mock.pressTelemetrySequence
            chart.refreshProjection()
            compare(chart.plotSegments.length, 1)
            compare(chart.plotSegments[0].length, 3) // never mix fallback under fine history label
            compare(history.samples[4].source, "STATUS")
            mock.commandOperationActive = false
            tryCompare(chart, "projectionDirty", false)
            compare(chart.plotSegments.length, 1)
            compare(chart.plotSegments[0].length, 1)
            verify(notice.text.indexOf("STATUS fallback") >= 0)
        }

        function test_narrowFluctuationsUseHundredthGrid_data() {
            return [{ tag: "positive", values: [0.99, 1.00, 1.01] },
                { tag: "negative", values: [-1.01, -1.00, -0.99] },
                { tag: "cross-zero", values: [-0.01, 0, 0.01] },
                { tag: "below-hundredth", values: [0.998, 1.001, 1.003] }]
        }

        function test_narrowFluctuationsUseHundredthGrid(data) {
            history.samples = data.values.map((value, index) => ({
                at: history.nowMs - (data.values.length - 1 - index) * 100,
                total: value, breakBefore: index === 0 }))
            chart.refreshProjection()
            fuzzyCompare(chart.axisStep, 0.01, 0.000001)
            verify(chart.axisMaximum - chart.axisMinimum < 0.1)
            verify(chart.axisMinimum < data.values[0])
            verify(chart.axisMaximum > data.values[data.values.length - 1])
            const plot = findChild(chart, "thc-live-chart-plot")
            verify(!!plot, "Object exists")
            verify(plot.height > 0)
            const points = chart.plotSegments[0]
            // Supplied real fractions remain distinct; formatting does not round the geometry.
            verify(Math.abs(points[2].y - points[0].y) > plot.height * 0.1)
            const tick = findChild(chart, "thc-live-axis-tick")
            verify(!!tick, "Object exists")
            verify(/^-?\d+\.\d{2} T$/.test(tick.text))
            const notice = findChild(chart, "thc-live-chart-resolution")
            verify(!!notice, "Object exists")
            verify(notice.text.indexOf("grid 0.01 T") >= 0)
            verify(notice.text.indexOf("0.1 T/channel") >= 0)
        }

        function test_flatAxisIsCenteredWithoutTargetOrZero_data() {
            return [0, 1, 5, -1, 1.003].map(value => ({ tag: String(value), value: value }))
        }

        function test_flatAxisIsCenteredWithoutTargetOrZero(data) {
            history.samples = [{ at: history.nowMs, total: data.value, breakBefore: true }]
            chart.refreshProjection()
            fuzzyCompare(chart.axisStep, 0.01, 0.000001)
            verify(chart.axisMinimum < data.value)
            verify(chart.axisMaximum > data.value)
            verify(chart.axisMaximum - chart.axisMinimum <= 0.03 + 0.000001)
            verify(isFinite(chart.plotSegments[0][0].y))
            compare(chart.metric(-0.0001, 2), "0.00")
        }

        function test_broadRangeRetainsAllBounds_data() {
            return [{ tag: "positive", low: 0.2, high: 10 },
                { tag: "negative", low: -20, high: -0.1 },
                { tag: "mixed", low: -5, high: 5 }]
        }

        function test_broadRangeRetainsAllBounds(data) {
            history.samples = [{ at: history.nowMs - 100, total: data.low, breakBefore: true },
                { at: history.nowMs, total: data.high }]
            chart.refreshProjection()
            verify(chart.axisMinimum < data.low)
            verify(chart.axisMaximum > data.high)
            verify(chart.axisTicks.length >= 3 && chart.axisTicks.length <= 8)
            for (let index = 1; index < chart.axisTicks.length; ++index)
                fuzzyCompare(chart.axisTicks[index] - chart.axisTicks[index - 1], chart.axisStep, 0.000001)
            const plot = findChild(chart, "thc-live-chart-plot")
            verify(!!plot, "Object exists")
            for (const point of chart.plotSegments[0])
                verify(point.y >= 0 && point.y <= plot.height)
        }

        function test_missingAndNonfiniteTotalsDoNotBecomeZero() {
            history.samples = [{ at: history.nowMs - 100, gap: true },
                { at: history.nowMs, total: NaN }]
            chart.refreshProjection()
            compare(chart.hasData, false)
            compare(chart.axisTicks.length, 0)
            compare(chart.plotSegments.length, 0)
            history.samples = [{ at: history.nowMs, total: Infinity }]
            chart.refreshProjection()
            compare(chart.hasData, false)
            compare(chart.plotSegments.length, 0)
            history.samples = []
            chart.refreshProjection()
            compare(chart.axisTicks.length, 0)
        }
    }
}