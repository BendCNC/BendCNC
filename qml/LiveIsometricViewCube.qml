pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic

// Fusion-style LIVE view selector. The front square is always the machine
// LEFT side (the LIVE picture plane). Corners and edges are real 3D cube
// corners/edges: their chamfer regions wrap onto every visible side face that
// meets there, and select the existing oblique LIVE views. The rest of each
// side face only illustrates the current camera and is not selectable.
FocusScope {
    id: cubeRoot

    signal orientationRequested(string orientation)

    property string orientation: "ISO_TOP_LEFT"
    property string hoveredTarget: ""
    property string focusedTarget: ""

    readonly property real faceSize: 62
    readonly property real faceX: 26
    readonly property real faceY: 26
    readonly property real bevel: 12
    readonly property real touchTolerance: 6
    // Cabinet projection: depth drawn at half length and 45 degrees, so the
    // selector reads as a cube (a longer or flatter recede looks like a bar).
    readonly property real recedeX: Math.round(faceSize * 0.5 * Math.SQRT1_2)
    readonly property real recedeY: recedeX
    // Fraction of a side face's depth that belongs to the shared edge/corner.
    readonly property real depthChamfer: 0.4
    readonly property bool mirrored: orientation === "ISO_BACK"
    readonly property var gridTargets: [
        ["ISO_TOP_LEFT", "ISO_TOP", "ISO_TOP_RIGHT"],
        ["ISO_LEFT", "ISO_FRONT", "ISO_RIGHT"],
        ["ISO_BOTTOM_LEFT", "ISO_BOTTOM", "ISO_BOTTOM_RIGHT"]
    ]
    readonly property var targetModel: buildTargetModel()

    implicitWidth: 132
    implicitHeight: 120
    activeFocusOnTab: true
    Accessible.role: Accessible.ComboBox
    Accessible.name: qsTr("LIVE view: %1").arg(orientationLabel(orientation))
    Accessible.description: qsTr("Choose a corner or edge of the cube to change only the LIVE display camera")

    function orientationLabel(value) {
        switch (String(value || "").toUpperCase()) {
        case "ISO_TOP_RIGHT": return qsTr("LEFT + TOP + FRONT")
        case "ISO_BOTTOM_LEFT": return qsTr("LEFT + BOTTOM + BACK")
        case "ISO_BOTTOM_RIGHT": return qsTr("LEFT + BOTTOM + FRONT")
        case "ISO_TOP": return qsTr("LEFT + TOP")
        case "ISO_BOTTOM": return qsTr("LEFT + BOTTOM")
        case "ISO_LEFT": return qsTr("LEFT + BACK")
        case "ISO_RIGHT": return qsTr("LEFT + FRONT")
        case "ISO_FRONT": return qsTr("LEFT SIDE (FLAT)")
        case "ISO_BACK": return qsTr("RIGHT SIDE (MIRRORED)")
        default: return qsTr("LEFT + TOP + BACK")
        }
    }

    // Screen direction in which the far (machine RIGHT) side recedes. Mirrors
    // the sign of isometricCameraBasis() in RunExecutionCanvas.qml, where screen
    // left is the BACK (backgauge) and screen right is the operator FRONT.
    function recedeVector(value) {
        switch (String(value || "").toUpperCase()) {
        case "ISO_TOP_RIGHT": return { x: recedeX, y: -recedeY }
        case "ISO_BOTTOM_LEFT": return { x: -recedeX, y: recedeY }
        case "ISO_BOTTOM_RIGHT": return { x: recedeX, y: recedeY }
        case "ISO_TOP": return { x: 0, y: -recedeY }
        case "ISO_BOTTOM": return { x: 0, y: recedeY }
        case "ISO_LEFT": return { x: -recedeX, y: 0 }
        case "ISO_RIGHT": return { x: recedeX, y: 0 }
        case "ISO_FRONT":
        case "ISO_BACK": return { x: 0, y: 0 }
        default: return { x: -recedeX, y: -recedeY }
        }
    }

    function sideFaces(value) {
        var recede = recedeVector(value)
        var faces = []
        if (recede.y < 0)
            faces.push("TOP")
        if (recede.y > 0)
            faces.push("BOTTOM")
        if (recede.x < 0)
            faces.push("BACK")
        if (recede.x > 0)
            faces.push("FRONT")
        return faces
    }

    // u: 0 BACK edge .. 1 FRONT edge, v: 0 TOP .. 1 BOTTOM, w: 0 LEFT side .. 1 RIGHT side.
    function project(u, v, w, recede) {
        return [faceX + u * faceSize + w * recede.x, faceY + v * faceSize + w * recede.y]
    }

    function chamferRange(index) {
        var c = bevel / faceSize
        if (index === 0)
            return [0, c]
        if (index === 2)
            return [1 - c, 1]
        return [c, 1 - c]
    }

    function leftFacePolygon(uRange, vRange) {
        var none = { x: 0, y: 0 }
        return [project(uRange[0], vRange[0], 0, none), project(uRange[1], vRange[0], 0, none),
                project(uRange[1], vRange[1], 0, none), project(uRange[0], vRange[1], 0, none)]
    }

    // Projected rectangle on a side face: TOP/BOTTOM span u x w, BACK/FRONT span v x w.
    function sideFacePolygon(face, range, w0, w1, recede) {
        if (face === "TOP" || face === "BOTTOM") {
            var v = face === "TOP" ? 0 : 1
            return [project(range[0], v, w0, recede), project(range[1], v, w0, recede),
                    project(range[1], v, w1, recede), project(range[0], v, w1, recede)]
        }
        var u = face === "BACK" ? 0 : 1
        return [project(u, range[0], w0, recede), project(u, range[1], w0, recede),
                project(u, range[1], w1, recede), project(u, range[0], w1, recede)]
    }

    function gridCell(value) {
        for (var row = 0; row < 3; row++) {
            var col = gridTargets[row].indexOf(value)
            if (col >= 0)
                return { row: row, col: col }
        }
        return null
    }

    function cellOf(value) {
        return gridCell(value) || { row: 1, col: 1 }
    }

    // Every visible piece of a corner/edge/face target for the current camera.
    function targetPolygons(value) {
        if (mirrored)
            return value === "ISO_BACK" ? [leftFacePolygon(chamferRange(1), chamferRange(1))] : []
        var cell = gridCell(value)
        if (!cell)
            return []
        var recede = recedeVector(orientation)
        var uRange = chamferRange(cell.col)
        var vRange = chamferRange(cell.row)
        var polygons = [leftFacePolygon(uRange, vRange)]
        if (cell.row === 0 && recede.y < 0)
            polygons.push(sideFacePolygon("TOP", uRange, 0, depthChamfer, recede))
        if (cell.row === 2 && recede.y > 0)
            polygons.push(sideFacePolygon("BOTTOM", uRange, 0, depthChamfer, recede))
        if (cell.col === 0 && recede.x < 0)
            polygons.push(sideFacePolygon("BACK", vRange, 0, depthChamfer, recede))
        if (cell.col === 2 && recede.x > 0)
            polygons.push(sideFacePolygon("FRONT", vRange, 0, depthChamfer, recede))
        return polygons
    }

    function buildTargetModel() {
        var model = []
        for (var row = 0; row < 3; row++) {
            for (var col = 0; col < 3; col++) {
                var value = gridTargets[row][col]
                var u = chamferRange(col)
                var v = chamferRange(row)
                var left = faceX + u[0] * faceSize
                var top = faceY + v[0] * faceSize
                var width = (u[1] - u[0]) * faceSize
                var height = (v[1] - v[0]) * faceSize
                model.push({
                    value: value, row: row, col: col,
                    left: left, top: top, width: width, height: height,
                    x: left + width / 2, y: top + height / 2,
                    label: qsTr("View %1").arg(orientationLabel(value))
                })
            }
        }
        return model
    }

    function pointInPolygon(x, y, points) {
        var inside = false
        for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
            var intersects = ((points[i][1] > y) !== (points[j][1] > y))
                && (x < (points[j][0] - points[i][0]) * (y - points[i][1])
                    / (points[j][1] - points[i][1]) + points[i][0])
            if (intersects)
                inside = !inside
        }
        return inside
    }

    function targetAt(x, y) {
        var candidates = mirrored ? ["ISO_BACK"] : [].concat(gridTargets[0], gridTargets[1], gridTargets[2])
        for (var i = 0; i < candidates.length; i++) {
            var polygons = targetPolygons(candidates[i])
            for (var p = 0; p < polygons.length; p++) {
                if (pointInPolygon(x, y, polygons[p]))
                    return candidates[i]
            }
        }
        // The remaining side-face area is not a view of its own.
        var recede = recedeVector(orientation)
        var faces = sideFaces(orientation)
        for (var f = 0; f < faces.length; f++) {
            if (pointInPolygon(x, y, sideFacePolygon(faces[f], [0, 1], 0, 1, recede)))
                return ""
        }
        // Touch tolerance just outside the LEFT square.
        var ix = x - faceX
        var iy = y - faceY
        if (ix < -touchTolerance || iy < -touchTolerance
                || ix > faceSize + touchTolerance || iy > faceSize + touchTolerance)
            return ""
        var col = ix < bevel ? 0 : (ix > faceSize - bevel ? 2 : 1)
        var row = iy < bevel ? 0 : (iy > faceSize - bevel ? 2 : 1)
        if (mirrored)
            return row === 1 && col === 1 ? "ISO_BACK" : ""
        return gridTargets[row][col]
    }

    function requestOrientation(value) {
        orientationRequested(value)
        forceActiveFocus()
    }

    function moveSelection(rowDelta, colDelta) {
        var cell = cellOf(orientation)
        var row = Math.max(0, Math.min(2, cell.row + rowDelta))
        var col = Math.max(0, Math.min(2, cell.col + colDelta))
        var target = gridTargets[row][col]
        if (target !== orientation)
            requestOrientation(target)
    }

    Keys.onLeftPressed: function(event) { moveSelection(0, -1); event.accepted = true }
    Keys.onRightPressed: function(event) { moveSelection(0, 1); event.accepted = true }
    Keys.onUpPressed: function(event) { moveSelection(-1, 0); event.accepted = true }
    Keys.onDownPressed: function(event) { moveSelection(1, 0); event.accepted = true }
    Keys.onSpacePressed: orientationMenu.open()
    Keys.onReturnPressed: orientationMenu.open()

    Canvas {
        id: cubeCanvas
        x: 0
        y: 0
        width: 114
        height: 114
        antialiasing: true
        Accessible.ignored: true

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            var s = cubeRoot.faceSize
            var x0 = cubeRoot.faceX
            var y0 = cubeRoot.faceY
            var b = cubeRoot.bevel
            var cw = cubeRoot.depthChamfer
            var recede = cubeRoot.recedeVector(cubeRoot.orientation)
            var faces = cubeRoot.sideFaces(cubeRoot.orientation)

            function path(points) {
                ctx.beginPath()
                ctx.moveTo(points[0][0], points[0][1])
                for (var i = 1; i < points.length; i++)
                    ctx.lineTo(points[i][0], points[i][1])
                ctx.closePath()
            }
            function gradient(x1, y1, x2, y2, from, to) {
                var g = ctx.createLinearGradient(x1, y1, x2, y2)
                g.addColorStop(0, from)
                g.addColorStop(1, to)
                return g
            }
            // Embossed label drawn in an affine frame on a face.
            function faceLabel(text, cx, cy, ax, ay, bx, by, maxWidth, pixelSize) {
                ctx.save()
                ctx.font = "700 " + pixelSize + "px sans-serif"
                var textWidth = Math.max(1, ctx.measureText(text).width)
                var fit = Math.min(1, maxWidth / textWidth)
                ctx.setTransform(ax * fit, ay * fit, bx, by, cx, cy)
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.fillStyle = "rgba(255, 255, 255, 0.85)"
                ctx.fillText(text, 0, 1)
                ctx.fillStyle = "#6b6b6b"
                ctx.fillText(text, 0, 0)
                ctx.restore()
            }
            function highlight(value, fill, stroke) {
                if (!value)
                    return
                var polygons = cubeRoot.targetPolygons(value)
                for (var i = 0; i < polygons.length; i++) {
                    path(polygons[i])
                    ctx.fillStyle = fill
                    ctx.fill()
                    ctx.strokeStyle = stroke
                    ctx.lineWidth = 1
                    ctx.stroke()
                }
            }

            // Side faces of the current camera, each with its chamfer strip
            // along the shared LEFT edge (part of the edge/corner targets).
            for (var f = 0; f < faces.length; f++) {
                var face = faces[f]
                var full = cubeRoot.sideFacePolygon(face, [0, 1], 0, 1, recede)
                var near = cubeRoot.project(0.5, 0.5, 0, recede)
                var far = cubeRoot.project(0.5, 0.5, 1, recede)
                path(full)
                if (face === "TOP")
                    ctx.fillStyle = gradient(0, y0 - cubeRoot.recedeY, 0, y0, "#f4f4f4", "#dedede")
                else if (face === "BOTTOM")
                    ctx.fillStyle = gradient(0, y0 + s, 0, y0 + s + cubeRoot.recedeY, "#c9c9c9", "#b6b6b6")
                else
                    ctx.fillStyle = gradient(near[0], 0, far[0], 0, "#d8d8d8", "#c4c4c4")
                ctx.fill()
                path(cubeRoot.sideFacePolygon(face, [0, 1], 0, cw, recede))
                ctx.fillStyle = "rgba(0, 0, 0, 0.06)"
                ctx.fill()
                ctx.strokeStyle = "#b0b0b0"
                ctx.lineWidth = 1
                ctx.stroke()
                path(cubeRoot.sideFacePolygon(face, cubeRoot.chamferRange(1), 0, cw, recede))
                ctx.stroke()
            }

            // LEFT square: chamfer ring (edges/corners) around the flat face.
            ctx.beginPath()
            ctx.rect(x0, y0, s, s)
            ctx.fillStyle = cubeRoot.mirrored
                ? gradient(0, y0, 0, y0 + s, "#dddddd", "#cfcfcf")
                : gradient(0, y0, 0, y0 + s, "#e4e4e4", "#c8c8c8")
            ctx.fill()
            ctx.beginPath()
            ctx.rect(x0 + b + 0.5, y0 + b + 0.5, s - 2 * b - 1, s - 2 * b - 1)
            ctx.fillStyle = gradient(0, y0 + b, 0, y0 + s - b, "#f8f8f8", "#e6e6e6")
            ctx.fill()
            ctx.strokeStyle = "#b0b0b0"
            ctx.lineWidth = 1
            ctx.stroke()
            if (!cubeRoot.mirrored) {
                ctx.beginPath()
                var inner = b + 0.5
                var outer = s - b - 0.5
                ctx.moveTo(x0 + inner, y0); ctx.lineTo(x0 + inner, y0 + b)
                ctx.moveTo(x0 + outer, y0); ctx.lineTo(x0 + outer, y0 + b)
                ctx.moveTo(x0 + inner, y0 + s); ctx.lineTo(x0 + inner, y0 + s - b)
                ctx.moveTo(x0 + outer, y0 + s); ctx.lineTo(x0 + outer, y0 + s - b)
                ctx.moveTo(x0, y0 + inner); ctx.lineTo(x0 + b, y0 + inner)
                ctx.moveTo(x0, y0 + outer); ctx.lineTo(x0 + b, y0 + outer)
                ctx.moveTo(x0 + s, y0 + inner); ctx.lineTo(x0 + s - b, y0 + inner)
                ctx.moveTo(x0 + s, y0 + outer); ctx.lineTo(x0 + s - b, y0 + outer)
                ctx.stroke()
            }

            highlight(cubeRoot.orientation, "rgba(80, 160, 255, 0.30)", "#3d8fd8")
            if (cubeRoot.hoveredTarget !== cubeRoot.orientation)
                highlight(cubeRoot.hoveredTarget, "rgba(80, 160, 255, 0.45)", "#3d8fd8")
            if (cubeRoot.focusedTarget !== cubeRoot.orientation)
                highlight(cubeRoot.focusedTarget, "rgba(80, 160, 255, 0.45)", "#1d6fb8")

            for (var o = 0; o < faces.length; o++) {
                path(cubeRoot.sideFacePolygon(faces[o], [0, 1], 0, 1, recede))
                ctx.strokeStyle = "#9a9a9a"
                ctx.lineWidth = 1
                ctx.stroke()
            }
            ctx.beginPath()
            ctx.rect(x0 + 0.5, y0 + 0.5, s - 1, s - 1)
            ctx.strokeStyle = "#9a9a9a"
            ctx.lineWidth = 1
            ctx.stroke()

            var labelDepth = (cw + 1) / 2
            for (var l = 0; l < faces.length; l++) {
                var name = faces[l]
                if (name === "TOP" || name === "BOTTOM") {
                    var hc = cubeRoot.project(0.5, name === "TOP" ? 0 : 1, labelDepth, recede)
                    faceLabel(name === "TOP" ? qsTr("TOP") : qsTr("BOTTOM"),
                              hc[0], hc[1], 1, 0, 0, 0.9, s - 14, 8)
                } else {
                    // Narrow vertical faces: run the label along the face height.
                    var vc = cubeRoot.project(name === "BACK" ? 0 : 1, 0.5, labelDepth, recede)
                    faceLabel(name === "BACK" ? qsTr("BACK") : qsTr("FRONT"),
                              vc[0], vc[1], 0, -1, 1, 0, s - 2 * b, 8)
                }
            }

            faceLabel(cubeRoot.mirrored ? qsTr("RIGHT") : qsTr("LEFT"),
                      x0 + s / 2, y0 + s / 2, 1, 0, 0, 1, s - 2 * b - 4, 11)
        }

        Connections {
            target: cubeRoot
            function onOrientationChanged() { cubeCanvas.requestPaint() }
            function onHoveredTargetChanged() { cubeCanvas.requestPaint() }
            function onFocusedTargetChanged() { cubeCanvas.requestPaint() }
        }

        MouseArea {
            objectName: "integratedCubePointer"
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: cubeRoot.hoveredTarget.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPositionChanged: function(mouse) { cubeRoot.hoveredTarget = cubeRoot.targetAt(mouse.x, mouse.y) }
            onExited: cubeRoot.hoveredTarget = ""
            onPressAndHold: orientationMenu.open()
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    orientationMenu.open()
                    return
                }
                var target = cubeRoot.targetAt(mouse.x, mouse.y)
                if (target.length > 0)
                    cubeRoot.requestOrientation(target)
            }
        }

        Repeater {
            model: cubeRoot.targetModel
            delegate: Item {
                required property var modelData
                objectName: "integratedTarget-" + modelData.value
                x: modelData.left
                y: modelData.top
                width: modelData.width
                height: modelData.height
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                Keys.onSpacePressed: cubeRoot.requestOrientation(modelData.value)
                Keys.onReturnPressed: cubeRoot.requestOrientation(modelData.value)
                onActiveFocusChanged: cubeRoot.focusedTarget = activeFocus ? modelData.value : ""
            }
        }
    }

    Item {
        id: menuButton
        objectName: "orientationMenuButton"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 18
        height: 16
        activeFocusOnTab: true
        Accessible.role: Accessible.ButtonMenu
        Accessible.name: qsTr("All LIVE views")
        Keys.onSpacePressed: orientationMenu.open()
        Keys.onReturnPressed: orientationMenu.open()

        Rectangle {
            anchors.fill: parent
            radius: 3
            color: menuMouse.containsMouse || orientationMenu.opened ? "#dbeafe" : "transparent"
            border.color: menuButton.activeFocus ? "#3d8fd8" : "transparent"
        }

        Canvas {
            anchors.centerIn: parent
            width: 10
            height: 7
            antialiasing: true
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.beginPath()
                ctx.moveTo(0.5, 0.5)
                ctx.lineTo(width - 0.5, 0.5)
                ctx.lineTo(width / 2, height - 0.5)
                ctx.closePath()
                ctx.fillStyle = "#6b6b6b"
                ctx.fill()
            }
        }

        MouseArea {
            id: menuMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: orientationMenu.open()
        }
    }

    Menu {
        id: orientationMenu
        objectName: "orientationMenu"
        x: cubeRoot.width - width
        y: cubeRoot.height
        width: 230
        margins: 4

        MenuItem {
            text: cubeRoot.orientationLabel("ISO_FRONT")
            font.bold: cubeRoot.orientation === "ISO_FRONT"
            onTriggered: cubeRoot.requestOrientation("ISO_FRONT")
        }
        MenuItem {
            text: cubeRoot.orientationLabel("ISO_BACK")
            font.bold: cubeRoot.orientation === "ISO_BACK"
            onTriggered: cubeRoot.requestOrientation("ISO_BACK")
        }
        MenuSeparator { }
        MenuItem {
            text: cubeRoot.orientationLabel("ISO_TOP")
            font.bold: cubeRoot.orientation === "ISO_TOP"
            onTriggered: cubeRoot.requestOrientation("ISO_TOP")
        }
        MenuItem {
            text: cubeRoot.orientationLabel("ISO_BOTTOM")
            font.bold: cubeRoot.orientation === "ISO_BOTTOM"
            onTriggered: cubeRoot.requestOrientation("ISO_BOTTOM")
        }
        MenuItem {
            text: cubeRoot.orientationLabel("ISO_LEFT")
            font.bold: cubeRoot.orientation === "ISO_LEFT"
            onTriggered: cubeRoot.requestOrientation("ISO_LEFT")
        }
        MenuItem {
            text: cubeRoot.orientationLabel("ISO_RIGHT")
            font.bold: cubeRoot.orientation === "ISO_RIGHT"
            onTriggered: cubeRoot.requestOrientation("ISO_RIGHT")
        }
        MenuSeparator { }
        MenuItem {
            text: qsTr("%1 (default)").arg(cubeRoot.orientationLabel("ISO_TOP_LEFT"))
            font.bold: cubeRoot.orientation === "ISO_TOP_LEFT"
            onTriggered: cubeRoot.requestOrientation("ISO_TOP_LEFT")
        }
        MenuItem {
            text: cubeRoot.orientationLabel("ISO_TOP_RIGHT")
            font.bold: cubeRoot.orientation === "ISO_TOP_RIGHT"
            onTriggered: cubeRoot.requestOrientation("ISO_TOP_RIGHT")
        }
        MenuItem {
            text: cubeRoot.orientationLabel("ISO_BOTTOM_LEFT")
            font.bold: cubeRoot.orientation === "ISO_BOTTOM_LEFT"
            onTriggered: cubeRoot.requestOrientation("ISO_BOTTOM_LEFT")
        }
        MenuItem {
            text: cubeRoot.orientationLabel("ISO_BOTTOM_RIGHT")
            font.bold: cubeRoot.orientation === "ISO_BOTTOM_RIGHT"
            onTriggered: cubeRoot.requestOrientation("ISO_BOTTOM_RIGHT")
        }
    }
}
