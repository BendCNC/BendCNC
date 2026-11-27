pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts

Rectangle {
    id: root
    objectName: "thc-live-tonnage-chart"
    property var history: null
    readonly property var minimum: history ? history.range.minimum : null
    readonly property var maximum: history ? history.range.maximum : null
    readonly property bool hasData: typeof minimum === "number" && isFinite(minimum)
        && typeof maximum === "number" && isFinite(maximum) && maximum >= minimum
    readonly property real span: hasData ? Math.max(0.01, maximum - minimum) : 1
    readonly property real axisStep: hasData ? tickStep(span / 4) : 0.01
    readonly property real axisPadding: hasData ? Math.max(0.005, span * 0.06) : 0
    readonly property real axisMinimum: hasData
        ? Math.floor((minimum - axisPadding) / axisStep) * axisStep : 0
    readonly property real axisMaximum: hasData
        ? Math.ceil((maximum + axisPadding) / axisStep) * axisStep : 1
    readonly property var axisTicks: ticks()
    property var plotSegments: []
    property bool projectionDirty: true
    // Sampled firmware threshold shown for orientation only; NOT a force ceiling.
    readonly property real sampledThreshold: 5.0
    readonly property bool thresholdVisible: hasData && sampledThreshold >= axisMinimum
        && sampledThreshold <= axisMaximum
    radius: 9
    color: "#141A24"
    border.color: "#273244"
    implicitHeight: 190

    function metric(value, digits) {
        if (typeof value !== "number" || !isFinite(value)) return qsTr("—")
        // Avoid a misleading negative-zero label without changing any sample.
        return (Math.abs(value) < 0.5 * Math.pow(10, -digits) ? 0 : value).toFixed(digits)
    }

    function tickStep(wanted) {
        if (wanted <= 0.01) return 0.01
        const power = Math.pow(10, Math.floor(Math.log(wanted) / Math.LN10))
        const scaled = wanted / power
        return (scaled <= 1 ? 1 : scaled <= 2 ? 2 : scaled <= 5 ? 5 : 10) * power
    }

    function ticks() {
        if (!hasData) return []
        const count = Math.round((axisMaximum - axisMinimum) / axisStep)
        const values = []
        for (let index = 0; index <= count; ++index)
            values.push(axisMinimum + index * axisStep)
        return values
    }

    function projectSegments() {
        if (!history || !hasData) return []
        return history.seriesSegments.map(segment => segment.map(sample => Qt.point(
            (sample.at - (history.nowMs - history.windowMs)) / history.windowMs * plot.width,
            plot.height - (sample.total - axisMinimum) / (axisMaximum - axisMinimum) * plot.height)))
    }

    function refreshProjection() {
        plotSegments = projectSegments()
        projectionDirty = false
    }

    onHistoryChanged: refreshProjection()
    onHasDataChanged: {
        if (!hasData) plotSegments = []
        projectionDirty = true
    }
    onAxisMinimumChanged: projectionDirty = true
    onAxisMaximumChanged: projectionDirty = true
    Component.onCompleted: refreshProjection()
    Connections {
        target: root.history
        ignoreUnknownSignals: true
        function onSamplesChanged() { root.projectionDirty = true }
        function onNowMsChanged() { root.projectionDirty = true }
        // Never leave a previous source/owner under the new source label.
        function onSelectionKeyChanged() {
            root.plotSegments = []
            root.projectionDirty = true
            // The selector/extrema bindings settle after the identity signal.
            Qt.callLater(root.refreshProjection)
        }
    }
    Timer {
        interval: 100
        repeat: true
        running: root.visible && root.projectionDirty
        onTriggered: root.refreshProjection()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 5
        // Designer v9 header: accent bar, title and RANGE / LIVE / PEAK chips.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
                        Text {
                Layout.fillWidth: true
                text: qsTr("TONNAGE DYNAMICS · LAST 60 s")
                color: "#E2E8F0"
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 0.5
                elide: Text.ElideRight
            }
            Rectangle {
                objectName: "thc-live-load-range-chip"
                visible: root.width >= 500
                Layout.preferredHeight: 20
                Layout.preferredWidth: rangeText.implicitWidth + 12
                radius: 4
                color: "#18202F"
                border.color: "#334155"
                Text {
                    id: rangeText
                    anchors.centerIn: parent
                    text: qsTr("RANGE %1–%2 T").arg(root.metric(root.minimum, 2)).arg(root.metric(root.maximum, 2))
                    color: "#94A3B8"
                    font.bold: true
                    font.pixelSize: 11
                }
            }
            Rectangle {
                Layout.preferredHeight: 20
                Layout.preferredWidth: liveText.implicitWidth + 12
                radius: 4
                color: "#0C4A6E"
                border.color: "#0284C7"
                Text {
                    id: liveText
                    objectName: "thc-live-load-total"
                    anchors.centerIn: parent
                    text: qsTr("LIVE %1 T").arg(root.metric(root.history ? root.history.totalLoad : null, 3))
                    color: "#38BDF8"
                    font.bold: true
                    font.pixelSize: 11
                }
            }
            Rectangle {
                Layout.preferredHeight: 20
                Layout.preferredWidth: peakText.implicitWidth + 12
                radius: 4
                color: "#451A03"
                border.color: "#D97706"
                Text {
                    id: peakText
                    objectName: "thc-live-load-peak"
                    anchors.centerIn: parent
                    text: qsTr("PEAK %1 T").arg(root.metric(root.maximum, 3))
                    color: "#FBBF24"
                    font.bold: true
                    font.pixelSize: 11
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            Item {
                id: axisLabels
                Layout.preferredWidth: 50
                Layout.fillHeight: true
                Repeater {
                    model: root.axisTicks
                    Text {
                        required property real modelData
                        objectName: "thc-live-axis-tick"
                        width: axisLabels.width
                        y: Math.max(0, Math.min(axisLabels.height - height,
                            (root.axisMaximum - modelData) / (root.axisMaximum - root.axisMinimum)
                            * (axisLabels.height - 1) - height / 2))
                        text: qsTr("%1 T").arg(root.metric(modelData, 2))
                        horizontalAlignment: Text.AlignRight
                        color: "#94A3B8"
                        font.pixelSize: 11
                    }
                }
            }
            Item {
                id: plot
                objectName: "thc-live-chart-plot"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                onWidthChanged: root.projectionDirty = true
                onHeightChanged: root.projectionDirty = true
                Repeater {
                    model: root.axisTicks
                    Rectangle {
                        required property real modelData
                        width: plot.width
                        height: 1
                        y: (root.axisMaximum - modelData) / (root.axisMaximum - root.axisMinimum)
                            * (plot.height - 1)
                        color: "#1F2937"
                    }
                }
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        x: (index + 1) / 4 * (plot.width - 1)
                        width: 1
                        height: plot.height
                        color: "#1F2937"
                    }
                }
                Shape {
                    objectName: "thc-live-chart-threshold"
                    visible: root.thresholdVisible
                    width: plot.width
                    height: 2
                    y: root.thresholdVisible ? (root.axisMaximum - root.sampledThreshold)
                        / (root.axisMaximum - root.axisMinimum) * (plot.height - 1) : 0
                    ShapePath {
                        strokeColor: "#EF4444"
                        strokeWidth: 1.2
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [4, 4]
                        fillColor: "transparent"
                        startX: 0
                        startY: 0
                        PathLine { x: plot.width; y: 0 }
                    }
                    Text {
                        x: 8
                        y: -height - 1
                        text: qsTr("Sampled 5 T threshold · not a ceiling")
                        color: "#EF4444"
                        font.pixelSize: 11
                    }
                }
                Shape {
                    objectName: "thc-live-chart-path"
                    anchors.fill: parent
                    ShapePath {
                        strokeColor: "#38BDF8"
                        strokeWidth: 2
                        fillColor: "transparent"
                        // One retained shape; each path begins with a move,
                        // so no geometry or filled polygon bridges a gap.
                        PathMultiline { paths: root.plotSegments }
                    }
                }
                Repeater {
                    model: root.plotSegments.length
                    Rectangle {
                        required property int index
                        readonly property var points: root.plotSegments[index] || []
                        readonly property var endpoint: points.length > 0 ? points[points.length - 1] : Qt.point(0, 0)
                        // A single real sample remains visible without interpolation.
                        x: endpoint.x - 2
                        y: endpoint.y - 2
                        width: 4
                        height: 4
                        radius: 2
                        color: "#38BDF8"
                    }
                }
                Text {
                    objectName: "thc-live-chart-empty"
                    anchors.centerIn: parent
                    visible: !root.hasData
                    text: qsTr("No fresh load samples")
                    color: "#94A3B8"
                    font.pixelSize: 12
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.preferredWidth: 50 }
            Text { text: qsTr("−60 s"); color: "#64748B"; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            Text { text: qsTr("−45 s"); color: "#64748B"; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            Text { text: qsTr("−30 s"); color: "#64748B"; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            Text { text: qsTr("−15 s"); color: "#64748B"; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            Text { text: qsTr("NOW · arrival time"); color: "#64748B"; font.pixelSize: 11 }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Text {
                objectName: "thc-live-load-channels"
                textFormat: Text.StyledText
                text: qsTr("<font color=\"#10B981\">Y1 LOAD %1 T</font> · <font color=\"#38BDF8\">Y2 LOAD %2 T</font>")
                    .arg(root.metric(root.history ? root.history.loadY1 : null, 3))
                    .arg(root.metric(root.history ? root.history.loadY2 : null, 3))
                color: "#94A3B8"
                font.pixelSize: 11
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: qsTr("SPAN Δ %1 T · AUTO-SCALE").arg(root.metric(root.hasData ? root.maximum - root.minimum : null, 3))
                color: "#94A3B8"
                font.pixelSize: 11
                font.bold: true
            }
        }
        Text {
            objectName: "thc-live-chart-resolution"
            Layout.fillWidth: true
            text: (root.history && root.history.fineHistorySelected
                ? qsTr("TH_CTRL filtered / pre-deadzone · 0.01 T display · not physical accuracy")
                : qsTr("STATUS fallback · 0.1 T/channel · no fine data"))
                + (root.history && root.history.fineHistorySelected && !root.history.fineAvailable
                    ? " · " + qsTr("Fine history retained; LIVE is STATUS fallback or unavailable") : "")
                + " · " + qsTr("grid %1 T · one history source; gaps on changes")
                    .arg(root.metric(root.hasData ? root.axisStep : null, 2))
                + " · " + qsTr("Gaps are not zero load")
            color: "#64748B"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }
    Accessible.role: Accessible.Graphic
    Accessible.name: qsTr("Measured tonnage over the last 60 seconds; gaps indicate unavailable telemetry")
}