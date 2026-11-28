pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Redesigned V46 Live / Fine Tune V53 Modal
// Standard BendCNC Precision Modal: 950 × 600
Rectangle {
    id: root
    objectName: "designer-thc-live-tuning"
    width: 950
    height: 600
    radius: 12
    clip: true
    color: "#0F141C"
    border.color: "#222D3D"
    border.width: 1.5

    signal closeRequested()

    // -------------------------------------------------------------------------
    // Candidate & Preview State Contract
    // -------------------------------------------------------------------------
    property string previewState: "IDLE" // "IDLE" | "HOLD" | "OFFLINE" | "STOP"
    property bool confirmationVisible: false
    property bool draftDirty: false
    property int sampleRevision: 7
    property var sampleValues: ({ kp: 0.1, ki: 0.01, kd: 0.005, rate: 0.005, cq: 0.01, fs: 0.04 })
    property var draft: Object.assign({}, sampleValues)
    readonly property bool previewOnly: true
    readonly property bool tuningEnabled: previewState === "IDLE" || previewState === "HOLD"
    readonly property bool draftValid: validValues(draft)
    readonly property color ink: "#232323"
    readonly property color charcoal: "#2B2C2B"
    readonly property color teal: "#10B981"
    readonly property color red: "#EF4444"
    readonly property color blue: "#0284C7"
    readonly property color amber: "#F59E0B"
    readonly property color purple: "#8B5CF6"
    readonly property var statesForPreview: ["IDLE", "HOLD", "OFFLINE", "STOP"]

    readonly property var fields: [
        { key: "kp", title: qsTr("Kp"), minimum: 0, maximum: 3000, step: 10, digits: 3, unit: "Gain" },
        { key: "ki", title: qsTr("Ki"), minimum: 0, maximum: 400, step: 1, digits: 4, unit: "Int" },
        { key: "kd", title: qsTr("Kd"), minimum: 0, maximum: 600, step: 5, digits: 4, unit: "Deriv" },
        { key: "rate", title: qsTr("Rate"), minimum: 20, maximum: 100, step: 1, digits: 4, unit: "kHz" },
        { key: "cq", title: qsTr("CQ"), minimum: 50, maximum: 200, step: 10, digits: 3, unit: "Thresh" },
        { key: "fs", title: qsTr("FS"), minimum: 200, maximum: 1000, step: 10, digits: 3, unit: "Stroke" }
    ]

    // -------------------------------------------------------------------------
    // 60-Second Tonnage Telemetry & Dual Motor RPM State
    // -------------------------------------------------------------------------
    property var tonnageHistory: {
        var arr = []
        for (var i = 0; i < 60; i++) {
            if (i < 15) {
                arr.push(0.15 + (Math.random() * 0.08))
            } else if (i < 25) {
                var ramp = (i - 15) / 10.0
                arr.push(0.2 + ramp * 4.6 + (Math.random() * 0.12))
            } else {
                arr.push(4.82 + (Math.sin(i * 0.45) * 0.14) + ((Math.random() - 0.5) * 0.08))
            }
        }
        return arr
    }

    readonly property real curveMinTonnage: {
        if (!tonnageHistory || tonnageHistory.length === 0) return 0.0
        var m = tonnageHistory[0]
        for (var i = 1; i < tonnageHistory.length; i++) {
            if (tonnageHistory[i] < m) m = tonnageHistory[i]
        }
        return m
    }
    readonly property real curveMaxTonnage: {
        if (!tonnageHistory || tonnageHistory.length === 0) return 1.0
        var m = tonnageHistory[0]
        for (var i = 1; i < tonnageHistory.length; i++) {
            if (tonnageHistory[i] > m) m = tonnageHistory[i]
        }
        return m
    }

    property real liveTonnage: previewState === "HOLD" ? 4.85 : (previewState === "IDLE" ? 0.15 : 0.00)
    property real peakTonnage: curveMaxTonnage
    property real minTonnage: curveMinTonnage
    property real liveTonnageY1: liveTonnage * 0.498
    property real liveTonnageY2: liveTonnage * 0.502
    property real thresholdTonnage: 5.00

    property int motorRpmY1: previewState === "HOLD" ? 1420 : 0
    property int motorRpmY2: previewState === "HOLD" ? 1418 : 0
    property int motorTargetRpm: previewState === "HOLD" ? 1425 : 0
    property real motorTempY1: 41.5
    property real motorTempY2: 42.1
    property real motorTorqueY1: previewState === "HOLD" ? 68.4 : 0.0
    property real motorTorqueY2: previewState === "HOLD" ? 69.1 : 0.0
    readonly property int motorSyncDelta: Math.abs(motorRpmY1 - motorRpmY2)

    function validValues(values) {
        if (!values) return false
        for (const field of fields) {
            const value = values[field.key]
            if (typeof value !== "number" || !isFinite(value)
                    || value < field.minimum / 10000 || value > field.maximum / 10000)
                return false
        }
        return values.fs > values.cq
    }

    function numericText(values, key, digits) {
        const value = values ? values[key] : undefined
        return typeof value === "number" && isFinite(value) ? value.toFixed(digits) : qsTr("—")
    }

    function editSample(key, value) {
        if (!tuningEnabled || confirmationVisible) return
        const next = Object.assign({}, draft)
        next[key] = value
        draft = next
        draftDirty = true
    }

    function loadSample() {
        draft = Object.assign({}, sampleValues)
        draftDirty = false
    }

    function applySample() {
        if (!tuningEnabled || !draftValid || !draftDirty || confirmationVisible) return false
        sampleValues = Object.assign({}, draft)
        sampleRevision++
        draftDirty = false
        return true
    }

    onPreviewStateChanged: {
        confirmationVisible = false
        stepDynamics()
    }

    function stepDynamics() {
        var nextHistory = tonnageHistory.slice(1)
        var newTonnage = 0.0
        if (previewState === "HOLD") {
            newTonnage = 4.82 + (Math.sin(Date.now() * 0.002) * 0.16) + ((Math.random() - 0.5) * 0.06)
            motorRpmY1 = 1420 + Math.round((Math.random() - 0.5) * 8)
            motorRpmY2 = 1418 + Math.round((Math.random() - 0.5) * 8)
            motorTargetRpm = 1425
            motorTorqueY1 = 68.0 + (Math.random() * 1.5)
            motorTorqueY2 = 68.6 + (Math.random() * 1.5)
        } else if (previewState === "IDLE") {
            newTonnage = 0.15 + (Math.random() * 0.05)
            motorRpmY1 = 0
            motorRpmY2 = 0
            motorTargetRpm = 0
            motorTorqueY1 = 0.0
            motorTorqueY2 = 0.0
        } else {
            newTonnage = 0.0
            motorRpmY1 = 0
            motorRpmY2 = 0
            motorTargetRpm = 0
            motorTorqueY1 = 0.0
            motorTorqueY2 = 0.0
        }

        nextHistory.push(newTonnage)
        tonnageHistory = nextHistory
        liveTonnage = newTonnage
        liveTonnageY1 = newTonnage * 0.498
        liveTonnageY2 = newTonnage * 0.502
        if (newTonnage > peakTonnage) peakTonnage = newTonnage

        if (tonnageCanvas) {
            tonnageCanvas.requestPaint()
        }
    }

    // Dynamic Sliding Window Simulation (Ticks every 1s without prohibited classes)
    SequentialAnimation {
        running: root.visible
        loops: Animation.Infinite
        PauseAnimation { duration: 1000 }
        ScriptAction { script: root.stepDynamics() }
    }

    // -------------------------------------------------------------------------
    // Reusable Custom Button Component
    // -------------------------------------------------------------------------
    component PreviewButton: Button {
        id: button
        property color actionColor: "#1E293B"
        property color textColor: "#FFFFFF"
        property color borderColor: "#334155"
        Layout.minimumHeight: 38
        Layout.preferredHeight: 38
        padding: 6
        font.pixelSize: 11
        font.bold: true

        background: Rectangle {
            radius: 6
            color: !button.enabled ? "#1A202C"
                : button.down ? Qt.darker(button.actionColor, 1.2)
                : (button.hovered ? Qt.lighter(button.actionColor, 1.15) : button.actionColor)
            border.width: button.activeFocus ? 2 : 1
            border.color: button.activeFocus ? "#38BDF8" : button.borderColor
        }

        contentItem: Text {
            text: button.text
            color: button.enabled ? button.textColor : "#64748B"
            font: button.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        Accessible.name: text
    }

    // =========================================================================
    // MAIN LAYOUT
    // =========================================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // =====================================================================
        // HEADER BAR (Height: 56px)
        // =====================================================================
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Icon Badge
            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                radius: 8
                color: "#182333"
                border.color: "#0284C7"
                border.width: 1.5

                Text {
                    anchors.centerIn: parent
                    text: "V46"
                    color: "#38BDF8"
                    font.bold: true
                    font.pixelSize: 13
                }
            }

            // Titles
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                RowLayout {
                    spacing: 8
                    Text {
                        text: qsTr("V46 LIVE / FINE TUNE · V53")
                        color: "white"
                        font.pixelSize: 16
                        font.bold: true
                        font.letterSpacing: 0.5
                    }

                    // Mode Status Badge
                    Rectangle {
                        height: 20
                        Layout.preferredWidth: statusText.implicitWidth + 14
                        radius: 4
                        color: root.previewState === "HOLD" ? "#1A3828" : (root.previewState === "STOP" ? "#38181A" : "#1E293B")
                        border.color: root.previewState === "HOLD" ? root.teal : (root.previewState === "STOP" ? root.red : "#475569")
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: root.previewState === "HOLD" ? root.teal : (root.previewState === "STOP" ? root.red : "#94A3B8")
                            }
                            Text {
                                id: statusText
                                text: root.previewState === "HOLD" ? qsTr("HOLDING 5.0 T") : root.previewState
                                color: "white"
                                font.bold: true
                                font.pixelSize: 10
                            }
                        }
                    }
                }

                Text {
                    objectName: "designer-thc-safety-label"
                    text: qsTr("DESIGN ONLY · Sample values · No machine commands · F5 reloads source")
                    color: "#94A3B8"
                    font.pixelSize: 10
                }
            }

            // Simulation State Selector
            ComboBox {
                id: stateCombo
                objectName: "designer-thc-state"
                Layout.preferredWidth: 155
                Layout.preferredHeight: 34
                model: [qsTr("IDLE · sample"), qsTr("HOLD · sample"), qsTr("OFFLINE · sample"), qsTr("STOP · sample")]
                currentIndex: root.statesForPreview.indexOf(root.previewState)
                onActivated: root.previewState = root.statesForPreview[currentIndex]
                Accessible.name: qsTr("Simulated panel state")
                background: Rectangle {
                    color: "#18202F"
                    border.color: "#334155"
                    border.width: 1
                    radius: 5
                }
                contentItem: Text {
                    leftPadding: 8
                    text: stateCombo.displayText
                    color: "#E2E8F0"
                    font.pixelSize: 10
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // Close Button
            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 6
                color: closeMouse.containsMouse ? "#7F1D1D" : "#1E293B"
                border.color: closeMouse.containsMouse ? "#EF4444" : "#334155"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 13
                }

                MouseArea {
                    id: closeMouse
                    objectName: "designer-thc-close"
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.closeRequested()
                }
            }
        }

        // =====================================================================
        // BODY (Height: 450px): Dual Column Architecture
        // Left Column (530px): 60s Tonnage Curve + Motor RPM Telemetry
        // Right Column (380px): PID Loop Parameters + Actions
        // =====================================================================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // -----------------------------------------------------------------
            // LEFT COLUMN: Tonnage Curve & Motor RPM (530px)
            // -----------------------------------------------------------------
            ColumnLayout {
                Layout.preferredWidth: 530
                Layout.fillHeight: true
                spacing: 10

                // CARD 1: 60-Second Tonnage Curve (Height: 232px)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 232
                    radius: 9
                    color: "#141A24"
                    border.color: "#273244"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        // Curve Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                width: 3
                                height: 13
                                radius: 1.5
                                color: "#38BDF8"
                            }

                            Text {
                                text: qsTr("TONNAGE DYNAMICS (LAST 60 SECONDS)")
                                color: "#E2E8F0"
                                font.bold: true
                                font.pixelSize: 11
                                font.letterSpacing: 0.5
                                Layout.fillWidth: true
                            }

                            // Dynamic Range Badge
                            Rectangle {
                                height: 20
                                Layout.preferredWidth: rangeText.implicitWidth + 12
                                radius: 4
                                color: "#18202F"
                                border.color: "#334155"
                                border.width: 1

                                Text {
                                    id: rangeText
                                    anchors.centerIn: parent
                                    text: qsTr("RANGE: ") + root.curveMinTonnage.toFixed(2) + " – " + root.curveMaxTonnage.toFixed(2) + " T"
                                    color: "#94A3B8"
                                    font.bold: true
                                    font.pixelSize: 10
                                }
                            }

                            // Live Tonnage Badge
                            Rectangle {
                                height: 20
                                Layout.preferredWidth: liveText.implicitWidth + 12
                                radius: 4
                                color: "#0C4A6E"
                                border.color: "#0284C7"
                                border.width: 1

                                Text {
                                    id: liveText
                                    anchors.centerIn: parent
                                    text: qsTr("LIVE: ") + root.liveTonnage.toFixed(2) + " T"
                                    color: "#38BDF8"
                                    font.bold: true
                                    font.pixelSize: 10
                                }
                            }

                            // Peak Badge
                            Rectangle {
                                height: 20
                                Layout.preferredWidth: peakText.implicitWidth + 12
                                radius: 4
                                color: "#451A03"
                                border.color: "#D97706"
                                border.width: 1

                                Text {
                                    id: peakText
                                    anchors.centerIn: parent
                                    text: qsTr("PEAK: ") + root.curveMaxTonnage.toFixed(2) + " T"
                                    color: "#FBBF24"
                                    font.bold: true
                                    font.pixelSize: 10
                                }
                            }
                        }

                        // 60-Second Canvas Graph (Dynamic Range Auto-Scaling)
                        Canvas {
                            id: tonnageCanvas
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            onPaint: {
                                var ctx = getContext("2d")
                                var w = width
                                var h = height
                                ctx.clearRect(0, 0, w, h)

                                var pts = root.tonnageHistory
                                if (pts.length < 2) return

                                var paddingLeft = 42
                                var paddingRight = 10
                                var paddingTop = 12
                                var paddingBottom = 22
                                var plotW = w - paddingLeft - paddingRight
                                var plotH = h - paddingTop - paddingBottom

                                // Dynamic curve range in this 60s period
                                var curMin = root.curveMinTonnage
                                var curMax = root.curveMaxTonnage
                                var span = curMax - curMin
                                if (span < 0.05) span = 0.05 // prevent collapse if values are uniform

                                // 6% padding top and bottom so the curve does not clip to edges
                                var margin = span * 0.06
                                var visibleMin = Math.max(0.0, curMin - margin)
                                var visibleMax = curMax + margin
                                var visibleRange = visibleMax - visibleMin
                                if (visibleRange <= 0.001) visibleRange = 1.0

                                // Background grid
                                ctx.strokeStyle = "#1F2937"
                                ctx.lineWidth = 1
                                ctx.fillStyle = "#64748B"
                                ctx.font = "8px Monospace"

                                // Horizontal grid lines & dynamic labels across the visible range
                                var numGridLines = 4
                                for (var step = 0; step <= numGridLines; step++) {
                                    var val = visibleMin + (step / numGridLines) * visibleRange
                                    var y = paddingTop + plotH - ((val - visibleMin) / visibleRange * plotH)
                                    ctx.beginPath()
                                    ctx.moveTo(paddingLeft, y)
                                    ctx.lineTo(paddingLeft + plotW, y)
                                    ctx.stroke()
                                    ctx.fillText(val.toFixed(2) + "T", 4, y + 3)
                                }

                                // Vertical grid lines (-60s, -45s, -30s, -15s, NOW)
                                var timeLabels = ["-60s", "-45s", "-30s", "-15s", "NOW"]
                                for (var s = 0; s < 5; s++) {
                                    var x = paddingLeft + (s / 4.0 * plotW)
                                    ctx.beginPath()
                                    ctx.moveTo(x, paddingTop)
                                    ctx.lineTo(x, paddingTop + plotH)
                                    ctx.stroke()
                                    ctx.fillText(timeLabels[s], x - 10, h - 6)
                                }

                                // Red dashed threshold line (5.0 T) - drawn if within visible range
                                if (root.thresholdTonnage >= visibleMin && root.thresholdTonnage <= visibleMax) {
                                    var threshY = paddingTop + plotH - ((root.thresholdTonnage - visibleMin) / visibleRange * plotH)
                                    ctx.strokeStyle = "#EF4444"
                                    ctx.lineWidth = 1.2
                                    ctx.setLineDash([4, 4])
                                    ctx.beginPath()
                                    ctx.moveTo(paddingLeft, threshY)
                                    ctx.lineTo(paddingLeft + plotW, threshY)
                                    ctx.stroke()
                                    ctx.setLineDash([]) // Reset dash

                                    ctx.fillStyle = "#EF4444"
                                    ctx.fillText(qsTr("Sampled 5.0 T Threshold"), paddingLeft + 10, threshY - 4)
                                }

                                // Draw Gradient Fill under curve
                                var grad = ctx.createLinearGradient(0, paddingTop, 0, paddingTop + plotH)
                                grad.addColorStop(0, "rgba(56, 189, 248, 0.28)")
                                grad.addColorStop(1, "rgba(56, 189, 248, 0.00)")

                                ctx.beginPath()
                                ctx.moveTo(paddingLeft, paddingTop + plotH)
                                for (var i = 0; i < pts.length; i++) {
                                    var px = paddingLeft + (i / (pts.length - 1) * plotW)
                                    var py = paddingTop + plotH - ((pts[i] - visibleMin) / visibleRange * plotH)
                                    py = Math.max(paddingTop, Math.min(paddingTop + plotH, py))
                                    ctx.lineTo(px, py)
                                }
                                ctx.lineTo(paddingLeft + plotW, paddingTop + plotH)
                                ctx.closePath()
                                ctx.fillStyle = grad
                                ctx.fill()

                                // Draw Main Tonnage Stroke (Cyan)
                                ctx.beginPath()
                                for (var j = 0; j < pts.length; j++) {
                                    var cx = paddingLeft + (j / (pts.length - 1) * plotW)
                                    var cy = paddingTop + plotH - ((pts[j] - visibleMin) / visibleRange * plotH)
                                    cy = Math.max(paddingTop, Math.min(paddingTop + plotH, cy))
                                    if (j === 0) ctx.moveTo(cx, cy)
                                    else ctx.lineTo(cx, cy)
                                }
                                ctx.strokeStyle = "#38BDF8"
                                ctx.lineWidth = 2.0
                                ctx.stroke()

                                // Current Head Dot
                                var lastVal = pts[pts.length - 1]
                                var lastX = paddingLeft + plotW
                                var lastY = paddingTop + plotH - ((lastVal - visibleMin) / visibleRange * plotH)
                                lastY = Math.max(paddingTop, Math.min(paddingTop + plotH, lastY))
                                ctx.fillStyle = "#38BDF8"
                                ctx.beginPath()
                                ctx.arc(lastX, lastY, 3.5, 0, 2 * Math.PI)
                                ctx.fill()
                            }
                        }

                        // Bottom Tonnage Split Breakdown
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Text {
                                text: qsTr("Y1 LOAD: ") + root.liveTonnageY1.toFixed(2) + " T (49.8%)"
                                color: "#10B981"
                                font.bold: true
                                font.pixelSize: 10
                            }
                            Text {
                                text: qsTr("Y2 LOAD: ") + root.liveTonnageY2.toFixed(2) + " T (50.2%)"
                                color: "#0284C7"
                                font.bold: true
                                font.pixelSize: 10
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: qsTr("SPAN Δ: ") + (root.curveMaxTonnage - root.curveMinTonnage).toFixed(2) + qsTr(" T · AUTO-SCALE")
                                color: "#94A3B8"
                                font.bold: true
                                font.pixelSize: 9
                            }
                        }
                    }
                }

                // CARD 2: Motor RPM Telemetry for Each Motor (Height: 200px)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 200
                    radius: 9
                    color: "#141A24"
                    border.color: "#273244"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        // Header with Sync Badge
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                width: 3
                                height: 13
                                radius: 1.5
                                color: "#10B981"
                            }

                            Text {
                                text: qsTr("MOTOR RPM & SERVO VELOCITY TELEMETRY")
                                color: "#E2E8F0"
                                font.bold: true
                                font.pixelSize: 11
                                font.letterSpacing: 0.5
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                height: 20
                                Layout.preferredWidth: syncText.implicitWidth + 12
                                radius: 4
                                color: root.motorSyncDelta <= 15 ? "#064E3B" : "#78350F"
                                border.color: root.motorSyncDelta <= 15 ? "#10B981" : "#F59E0B"
                                border.width: 1

                                Text {
                                    id: syncText
                                    anchors.centerIn: parent
                                    text: qsTr("SYNC Δ ") + String(root.motorSyncDelta) + " RPM · LOCKED"
                                    color: root.motorSyncDelta <= 15 ? "#6EE7B7" : "#FCD34D"
                                    font.bold: true
                                    font.pixelSize: 9
                                }
                            }
                        }

                        // Dual Motor Columns (Y1 Left & Y2 Right)
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 10

                            // Motor Y1 Pod
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 7
                                color: "#0B0F17"
                                border.color: "#1E2838"
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: qsTr("MOTOR Y1 · LEFT CYLINDER")
                                            color: "#10B981"
                                            font.bold: true
                                            font.pixelSize: 10
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: qsTr("CMD: ") + String(root.motorTargetRpm)
                                            color: "#64748B"
                                            font.pixelSize: 9
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: String(root.motorRpmY1)
                                            color: "white"
                                            font.bold: true
                                            font.pixelSize: 22
                                            font.family: "Monospace"
                                        }
                                        Text {
                                            text: qsTr("RPM")
                                            color: "#94A3B8"
                                            font.bold: true
                                            font.pixelSize: 11
                                            Layout.alignment: Qt.AlignBottom
                                        }
                                    }

                                    // Tachometer Progress Bar (0 to 3000 RPM)
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 6
                                        radius: 3
                                        color: "#1E293B"

                                        Rectangle {
                                            width: Math.min(parent.width, Math.max(0, parent.width * (root.motorRpmY1 / 3000.0)))
                                            height: parent.height
                                            radius: 3
                                            color: root.motorRpmY1 > 2400 ? "#EF4444" : "#10B981"
                                        }
                                    }

                                    // Motor Metrics
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: qsTr("Temp: ") + root.motorTempY1.toFixed(1) + "°C"
                                            color: "#94A3B8"
                                            font.pixelSize: 9
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: qsTr("Torque: ") + root.motorTorqueY1.toFixed(1) + "%"
                                            color: "#94A3B8"
                                            font.pixelSize: 9
                                        }
                                    }
                                }
                            }

                            // Motor Y2 Pod
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 7
                                color: "#0B0F17"
                                border.color: "#1E2838"
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: qsTr("MOTOR Y2 · RIGHT CYLINDER")
                                            color: "#0284C7"
                                            font.bold: true
                                            font.pixelSize: 10
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: qsTr("CMD: ") + String(root.motorTargetRpm)
                                            color: "#64748B"
                                            font.pixelSize: 9
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: String(root.motorRpmY2)
                                            color: "white"
                                            font.bold: true
                                            font.pixelSize: 22
                                            font.family: "Monospace"
                                        }
                                        Text {
                                            text: qsTr("RPM")
                                            color: "#94A3B8"
                                            font.bold: true
                                            font.pixelSize: 11
                                            Layout.alignment: Qt.AlignBottom
                                        }
                                    }

                                    // Tachometer Progress Bar (0 to 3000 RPM)
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 6
                                        radius: 3
                                        color: "#1E293B"

                                        Rectangle {
                                            width: Math.min(parent.width, Math.max(0, parent.width * (root.motorRpmY2 / 3000.0)))
                                            height: parent.height
                                            radius: 3
                                            color: root.motorRpmY2 > 2400 ? "#EF4444" : "#0284C7"
                                        }
                                    }

                                    // Motor Metrics
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: qsTr("Temp: ") + root.motorTempY2.toFixed(1) + "°C"
                                            color: "#94A3B8"
                                            font.pixelSize: 9
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: qsTr("Torque: ") + root.motorTorqueY2.toFixed(1) + "%"
                                            color: "#94A3B8"
                                            font.pixelSize: 9
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // RIGHT COLUMN: PID Loop Parameters & Lifecycle Controls (380px)
            // -----------------------------------------------------------------
            Rectangle {
                Layout.preferredWidth: 380
                Layout.fillHeight: true
                radius: 9
                color: "#141A24"
                border.color: "#273244"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 3
                            height: 13
                            radius: 1.5
                            color: "#8B5CF6"
                        }

                        Text {
                            text: qsTr("LOOP PARAMETERS · RAM VOLATILE")
                            color: "#E2E8F0"
                            font.bold: true
                            font.pixelSize: 11
                            font.letterSpacing: 0.5
                            Layout.fillWidth: true
                        }

                        // Dirty Status Indicator
                        Rectangle {
                            visible: root.draftDirty
                            height: 18
                            Layout.preferredWidth: dirtyText.implicitWidth + 10
                            radius: 4
                            color: "#7C2D12"
                            border.color: "#EA580C"
                            border.width: 1

                            Text {
                                id: dirtyText
                                anchors.centerIn: parent
                                text: qsTr("UNSAVED DRAFT")
                                color: "#FED7AA"
                                font.bold: true
                                font.pixelSize: 9
                            }
                        }
                    }

                    // Status Text (Targeted by test)
                    Text {
                        id: thcStatus
                        objectName: "designer-thc-status"
                        Layout.fillWidth: true
                        text: root.previewState === "STOP"
                            ? qsTr("SAMPLE · STOP UNCONFIRMED — inspect recovery. No automatic Home or restart.")
                            : root.previewState === "OFFLINE"
                                ? qsTr("SAMPLE · OFFLINE / NO V53 TRANSPORT — controls disabled.")
                                : root.previewState === "HOLD"
                                    ? qsTr("SAMPLE · HOLDING appearance only — no operator lease or physical cycle.")
                                    : qsTr("SAMPLE · Safely homed IDLE appearance — not machine readiness.")
                        color: root.previewState === "STOP" ? root.red : "#94A3B8"
                        font.pixelSize: 9
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }

                    // 6 Parameters Grid (2 columns x 3 rows)
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 6

                        Repeater {
                            model: root.fields
                            Rectangle {
                                id: paramCard
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 52
                                radius: 6
                                color: "#0B0F17"
                                border.color: root.draft[paramCard.modelData.key] !== root.sampleValues[paramCard.modelData.key] ? "#F59E0B" : "#1E2838"
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: paramCard.modelData.title
                                            color: "white"
                                            font.bold: true
                                            font.pixelSize: 11
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: (root.sampleValues[paramCard.modelData.key]).toFixed(paramCard.modelData.digits)
                                            color: "#64748B"
                                            font.pixelSize: 9
                                            font.family: "Monospace"
                                        }
                                    }

                                    // SpinBox with Required Contract
                                    SpinBox {
                                        id: spin
                                        objectName: "designer-thc-" + paramCard.modelData.key
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        enabled: root.tuningEnabled && !root.confirmationVisible
                                        from: paramCard.modelData.minimum
                                        to: paramCard.modelData.maximum
                                        stepSize: paramCard.modelData.step
                                        value: Math.round(root.draft[paramCard.modelData.key] * 10000)
                                        editable: false

                                        textFromValue: function(value, locale) {
                                            return (value / 10000).toFixed(paramCard.modelData.digits)
                                        }
                                        onValueModified: root.editSample(paramCard.modelData.key, value / 10000)

                                        background: Rectangle {
                                            color: "#141A24"
                                            radius: 4
                                            border.color: spin.activeFocus ? "#0284C7" : "#2B374A"
                                            border.width: 1
                                        }

                                        contentItem: Text {
                                            text: spin.displayText
                                            color: root.tuningEnabled ? "white" : "#64748B"
                                            font.pixelSize: 11
                                            font.bold: true
                                            font.family: "Monospace"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Parameter Draft Action Buttons (Revert & Apply)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        PreviewButton {
                            id: queryBtn
                            objectName: "designer-thc-query"
                            Layout.fillWidth: true
                            text: qsTr("REVERT")
                            enabled: root.draftDirty && !root.confirmationVisible
                            actionColor: "#334155"
                            onClicked: root.loadSample()
                        }

                        PreviewButton {
                            id: applyBtn
                            objectName: "designer-thc-apply"
                            Layout.fillWidth: true
                            text: qsTr("APPLY DRAFT")
                            enabled: root.tuningEnabled && root.draftValid && root.draftDirty && !root.confirmationVisible
                            actionColor: "#059669"
                            onClicked: root.applySample()
                        }
                    }

                    // Lifecycle Actions
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        // Start / Confirm Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            PreviewButton {
                                id: startBtn
                                objectName: "designer-thc-start"
                                Layout.fillWidth: true
                                text: qsTr("START RECOVERY")
                                enabled: root.previewState === "IDLE" && !root.confirmationVisible && !root.draftDirty
                                actionColor: "#0284C7"
                                onClicked: root.confirmationVisible = true
                            }

                            PreviewButton {
                                id: confirmBtn
                                objectName: "designer-thc-confirm"
                                Layout.fillWidth: true
                                visible: root.confirmationVisible
                                text: qsTr("CONFIRM HOLD")
                                actionColor: "#D97706"
                                onClicked: {
                                    root.previewState = "HOLD"
                                    root.confirmationVisible = false
                                }
                            }
                        }

                        // Release / Stop Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            PreviewButton {
                                id: releaseBtn
                                objectName: "designer-thc-release"
                                Layout.fillWidth: true
                                text: qsTr("RELEASE HOLD")
                                enabled: root.previewState === "HOLD" && !root.confirmationVisible
                                actionColor: "#475569"
                                onClicked: root.previewState = "IDLE"
                            }

                            PreviewButton {
                                id: stopBtn
                                objectName: "designer-thc-stop"
                                Layout.fillWidth: true
                                text: qsTr("STOP (V46)")
                                enabled: root.previewState !== "STOP" && root.previewState !== "OFFLINE"
                                actionColor: "#DC2626"
                                onClicked: root.previewState = "STOP"
                            }
                        }
                    }
                }
            }
        }

        // =====================================================================
        // FOOTER / SAFETY BANNER (Height: 38px)
        // =====================================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: 7
            color: "#181410"
            border.color: "#78350F"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Text {
                    text: "⚠"
                    color: "#F59E0B"
                    font.bold: true
                    font.pixelSize: 13
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("V46 real ram movement recovery. Sampled 5 T is NOT a guaranteed force ceiling. Approach 45s, acquisition 60s, release 40s. Safety watchdogs active.")
                    color: "#FDE68A"
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                PreviewButton {
                    id: closeBottomBtn
                    objectName: "designer-thc-close"
                    Layout.preferredWidth: 90
                    Layout.preferredHeight: 28
                    text: qsTr("CLOSE")
                    actionColor: "#334155"
                    onClicked: root.closeRequested()
                }
            }
        }
    }
}