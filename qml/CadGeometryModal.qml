import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Read-only CAD geometry viewer: dimensioned flat pattern and the folded 3D
// model rebuilt from the imported sheetMetalGraph (panels + bend hinges).
Popup {
    id: root
    objectName: "cad-geometry-modal"
    property var cadJson: null
    property int mode: 0            // 0 = flat pattern, 1 = 3D model
    property real yaw: -35
    property real pitch: 30
    property real zoom: 1.0

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: parent ? Math.min(1100, parent.width - 40) : 1000
    height: parent ? Math.min(640, parent.height - 40) : 600
    modal: true
    closePolicy: Popup.CloseOnEscape
    background: Rectangle { color: "#1E293B"; radius: 8; border.color: "#475569"; border.width: 1 }

    readonly property var flat: buildFlat(cadJson)
    readonly property var folded: buildFolded(cadJson)

    onOpened: { yaw = -35; pitch = 30; zoom = 1.0; repaint() }
    onModeChanged: repaint()
    onCadJsonChanged: repaint()
    function repaint() { flatCanvas.requestPaint(); modelCanvas.requestPaint() }

    function pt(p) { return { x: Number(p.x_in), y: Number(p.y_in) } }
    function loopPoints(loop) {
        var raw = Array.isArray(loop) ? loop : (loop && (loop.points || loop.loop)) || []
        var out = []
        for (var i = 0; i < raw.length; ++i) out.push(pt(raw[i]))
        return out
    }
    function area(pts) {
        var a = 0
        for (var i = 0; i < pts.length; ++i) {
            var p = pts[i], q = pts[(i + 1) % pts.length]
            a += p.x * q.y - q.x * p.y
        }
        return a / 2
    }
    function fmt(v) { return Number(v).toFixed(3) }

    function bendEdges(json) {
        return json && json.sheetMetalGraph && json.sheetMetalGraph.bendEdges
               ? json.sheetMetalGraph.bendEdges : []
    }

    // Flat pattern: loops, bend lines and measurements.
    function buildFlat(json) {
        var fp = json && json.flatPattern
        var pv = fp && fp.preview2d
        if (!pv || !pv.loops) return null
        var loops = [], outer = -1, best = 0
        for (var i = 0; i < pv.loops.length; ++i) {
            var pts = loopPoints(pv.loops[i])
            if (pts.length < 3) continue
            loops.push(pts)
            var a = Math.abs(area(pts))
            if (a > best) { best = a; outer = loops.length - 1 }
        }
        var b = pv.bounds || {}
        var minX = Number(b.min_x_in), maxX = Number(b.max_x_in)
        var minY = Number(b.min_y_in), maxY = Number(b.max_y_in)
        if (!isFinite(minX)) {
            minX = minY = 1e9; maxX = maxY = -1e9
            for (var l = 0; l < loops.length; ++l) for (var k = 0; k < loops[l].length; ++k) {
                var p = loops[l][k]
                minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x)
                minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y)
            }
        }
        var bends = []
        var edges = bendEdges(json)
        for (var e = 0; e < edges.length; ++e) {
            var ed = edges[e]
            var segs = ed.hingeSegments && ed.hingeSegments.length ? ed.hingeSegments
                                                                   : [[ed.hingeStart, ed.hingeEnd]]
            var s0 = pt(segs[0][0]), s1 = pt(segs[segs.length - 1][segs[segs.length - 1].length - 1])
            var lines = []
            for (var s = 0; s < segs.length; ++s) lines.push([pt(segs[s][0]), pt(segs[s][segs[s].length - 1])])
            var vertical = Math.abs(s1.x - s0.x) < Math.abs(s1.y - s0.y)
            bends.push({
                id: ed.sourceBendId || String(e + 1),
                angle: Number(ed.bendAngleDegrees || ed.foldAngleDegrees || 0),
                direction: String(ed.direction || ""),
                radius: Number(ed.insideRadius_in || 0),
                lines: lines,
                vertical: vertical,
                // Distance of the bend line from the nearest flat-blank edge.
                offset: vertical ? Math.min(s0.x - minX, maxX - s0.x) : Math.min(s0.y - minY, maxY - s0.y),
                length: Math.hypot(s1.x - s0.x, s1.y - s0.y)
            })
        }
        return {
            loops: loops, outer: outer, bends: bends,
            minX: minX, maxX: maxX, minY: minY, maxY: maxY,
            width: maxX - minX, length: maxY - minY,
            holes: Math.max(0, loops.length - 1),
            area: best
        }
    }

    // Folded 3D: walk the panel tree from ROOT, rotating each child about its
    // hinge (Rodrigues) composed with the parent transform.
    function mulMat(a, b) {
        var r = []
        for (var i = 0; i < 3; ++i) {
            r.push([])
            for (var j = 0; j < 4; ++j) {
                var v = j === 3 ? a[i][3] : 0
                for (var k = 0; k < 3; ++k) v += a[i][k] * b[k][j]
                r[i].push(v)
            }
        }
        return r
    }
    function apply(m, x, y, z) {
        return [m[0][0] * x + m[0][1] * y + m[0][2] * z + m[0][3],
                m[1][0] * x + m[1][1] * y + m[1][2] * z + m[1][3],
                m[2][0] * x + m[2][1] * y + m[2][2] * z + m[2][3]]
    }
    function hingeRotation(p0, t, ang) {
        var c = Math.cos(ang), s = Math.sin(ang), C = 1 - c
        var x = t[0], y = t[1], z = t[2]
        var R = [[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                 [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                 [z * x * C - y * s, z * y * C + x * s, c + z * z * C]]
        // translation so that the hinge line stays fixed: p0 - R p0
        var m = []
        for (var i = 0; i < 3; ++i) {
            var rp = R[i][0] * p0.x + R[i][1] * p0.y
            m.push([R[i][0], R[i][1], R[i][2], (i === 0 ? p0.x : i === 1 ? p0.y : 0) - rp])
        }
        return m
    }
    function centroid(pts) {
        var x = 0, y = 0
        for (var i = 0; i < pts.length; ++i) { x += pts[i].x; y += pts[i].y }
        return { x: x / pts.length, y: y / pts.length }
    }
    function buildFolded(json) {
        var g = json && json.sheetMetalGraph
        if (!g || !g.panels || !g.panels.length) return null
        var panels = {}, order = []
        for (var i = 0; i < g.panels.length; ++i) {
            var p = g.panels[i]
            var holes = []
            var hl = p.holeLoops || []
            for (var h = 0; h < hl.length; ++h) holes.push(loopPoints(hl[h]))
            panels[p.panelId] = { id: p.panelId, outer: loopPoints(p.outerLoop), holes: holes }
            order.push(p.panelId)
        }
        var childEdges = {}
        var edges = g.bendEdges || []
        for (var e = 0; e < edges.length; ++e) {
            var pid = edges[e].parentPanelId
            if (!childEdges[pid]) childEdges[pid] = []
            childEdges[pid].push(edges[e])
        }
        var identity = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]]
        var rootId = g.rootPanelId || order[0]
        var xf = {}
        xf[rootId] = identity
        var queue = [rootId]
        while (queue.length) {
            var parentId = queue.shift()
            var list = childEdges[parentId] || []
            for (var c = 0; c < list.length; ++c) {
                var ed = list[c]
                var child = panels[ed.childPanelId]
                if (!child || xf[ed.childPanelId]) continue
                var a = pt(ed.hingeStart), b = pt(ed.hingeEnd)
                var len = Math.hypot(b.x - a.x, b.y - a.y) || 1
                var t = [(b.x - a.x) / len, (b.y - a.y) / len, 0]
                // Side of the hinge holding the child: (t x n) = side * z.
                var cc = centroid(child.outer)
                var side = (t[0] * (cc.y - a.y) - t[1] * (cc.x - a.x)) >= 0 ? 1 : -1
                var ang = Number(ed.foldAngleDegrees || ed.bendAngleDegrees || 0) * Math.PI / 180
                var up = String(ed.direction || ed.flatPatternDirection || "UP").toUpperCase() !== "DOWN"
                var local = hingeRotation(a, t, (up ? 1 : -1) * side * ang)
                xf[ed.childPanelId] = mulMat(xf[parentId], local)
                queue.push(ed.childPanelId)
            }
        }
        var faces = []
        var minV = [1e9, 1e9, 1e9], maxV = [-1e9, -1e9, -1e9]
        for (var o = 0; o < order.length; ++o) {
            var pn = panels[order[o]]
            var m = xf[pn.id]
            if (!m) continue
            var rings = [pn.outer].concat(pn.holes)
            var out = []
            for (var r = 0; r < rings.length; ++r) {
                var ring = []
                for (var q = 0; q < rings[r].length; ++q) {
                    var v = apply(m, rings[r][q].x, rings[r][q].y, 0)
                    for (var d = 0; d < 3; ++d) { minV[d] = Math.min(minV[d], v[d]); maxV[d] = Math.max(maxV[d], v[d]) }
                    ring.push(v)
                }
                out.push(ring)
            }
            faces.push({ id: pn.id, rings: out, root: pn.id === rootId })
        }
        return {
            faces: faces,
            center: [(minV[0] + maxV[0]) / 2, (minV[1] + maxV[1]) / 2, (minV[2] + maxV[2]) / 2],
            size: [maxV[0] - minV[0], maxV[1] - minV[1], maxV[2] - minV[2]],
            panelCount: faces.length, bendCount: edges.length
        }
    }

    contentItem: ColumnLayout {
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: "CAD GEOMETRY"
                color: "white"; font.pixelSize: 15; font.bold: true
            }
            Repeater {
                model: ["FLAT PATTERN", "3D MODEL"]
                delegate: Button {
                    required property int index
                    required property string modelData
                    objectName: index === 0 ? "cad-geometry-flat-tab" : "cad-geometry-3d-tab"
                    text: modelData
                    onClicked: root.mode = index
                    contentItem: Text {
                        text: parent.text; color: "white"; font.pixelSize: 12; font.bold: true
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitWidth: 120; implicitHeight: 28; radius: 4
                        color: root.mode === index ? "#0D9488" : "#334155"
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: "#CBD5E1"; font.pixelSize: 11
                text: root.mode === 0
                      ? (root.flat ? ("Blank " + root.fmt(root.flat.width) + " x " + root.fmt(root.flat.length)
                                      + " in   bends " + root.flat.bends.length + "   holes/cutouts " + root.flat.holes) : "")
                      : (root.folded ? ("Folded envelope " + root.fmt(root.folded.size[0]) + " x " + root.fmt(root.folded.size[1])
                                        + " x " + root.fmt(root.folded.size[2]) + " in   panels " + root.folded.panelCount
                                        + "   drag to rotate, wheel to zoom") : "")
            }
            Button {
                objectName: "cad-geometry-close"
                text: "CLOSE"
                onClicked: root.close()
                contentItem: Text { text: parent.text; color: "white"; font.pixelSize: 12; font.bold: true
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { implicitWidth: 80; implicitHeight: 28; radius: 4; color: "#475569" }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#0F172A"; radius: 6; clip: true

            Text {
                anchors.centerIn: parent
                visible: root.mode === 0 ? !root.flat : !root.folded
                text: root.mode === 0 ? "No flat-pattern geometry in this file"
                                      : "No sheet-metal graph in this file (schema v5 export required)"
                color: "#94A3B8"; font.pixelSize: 13
            }

            Canvas {
                id: flatCanvas
                anchors.fill: parent
                visible: root.mode === 0 && !!root.flat
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var f = root.flat
                    if (!f) return
                    var margin = 70
                    var sc = Math.min((width - 2 * margin) / Math.max(f.width, 1e-6),
                                      (height - 2 * margin) / Math.max(f.length, 1e-6))
                    var ox = (width - f.width * sc) / 2, oy = (height - f.length * sc) / 2
                    function X(x) { return ox + (x - f.minX) * sc }
                    function Y(y) { return oy + (f.maxY - y) * sc }

                    ctx.beginPath()
                    for (var l = 0; l < f.loops.length; ++l) {
                        var pts = f.loops[l]
                        ctx.moveTo(X(pts[0].x), Y(pts[0].y))
                        for (var i = 1; i < pts.length; ++i) ctx.lineTo(X(pts[i].x), Y(pts[i].y))
                        ctx.closePath()
                    }
                    ctx.fillStyle = "#334155"
                    ctx.fillRule = Qt.OddEvenFill
                    ctx.fill()
                    ctx.strokeStyle = "#E2E8F0"; ctx.lineWidth = 1.2
                    ctx.stroke()

                    // Bend lines with labels.
                    ctx.font = "bold 11px sans-serif"
                    for (var b = 0; b < f.bends.length; ++b) {
                        var bd = f.bends[b]
                        var up = bd.direction.toUpperCase() !== "DOWN"
                        ctx.strokeStyle = up ? "#22D3EE" : "#F59E0B"
                        ctx.lineWidth = 1.5
                        ctx.setLineDash ? ctx.setLineDash([6, 4]) : 0
                        ctx.beginPath()
                        for (var s = 0; s < bd.lines.length; ++s) {
                            ctx.moveTo(X(bd.lines[s][0].x), Y(bd.lines[s][0].y))
                            ctx.lineTo(X(bd.lines[s][1].x), Y(bd.lines[s][1].y))
                        }
                        ctx.stroke()
                        ctx.setLineDash ? ctx.setLineDash([]) : 0
                        var m0 = bd.lines[0][0], m1 = bd.lines[bd.lines.length - 1][1]
                        var mx = X((m0.x + m1.x) / 2), my = Y((m0.y + m1.y) / 2)
                        ctx.fillStyle = ctx.strokeStyle
                        var label = "B" + bd.id + " " + bd.angle.toFixed(0) + "° " + (up ? "UP" : "DN")
                                    + "  @" + root.fmt(bd.offset)
                        ctx.save()
                        ctx.translate(mx, my)
                        if (bd.vertical) ctx.rotate(-Math.PI / 2)
                        ctx.fillText(label, 4, -4)
                        ctx.restore()
                    }

                    // Overall dimensions.
                    ctx.strokeStyle = "#A3E635"; ctx.fillStyle = "#A3E635"; ctx.lineWidth = 1
                    ctx.font = "bold 12px sans-serif"
                    var by = Y(f.minY) + 28
                    ctx.beginPath()
                    ctx.moveTo(X(f.minX), by); ctx.lineTo(X(f.maxX), by)
                    ctx.moveTo(X(f.minX), by - 6); ctx.lineTo(X(f.minX), by + 6)
                    ctx.moveTo(X(f.maxX), by - 6); ctx.lineTo(X(f.maxX), by + 6)
                    var bx = X(f.maxX) + 28
                    ctx.moveTo(bx, Y(f.minY)); ctx.lineTo(bx, Y(f.maxY))
                    ctx.moveTo(bx - 6, Y(f.minY)); ctx.lineTo(bx + 6, Y(f.minY))
                    ctx.moveTo(bx - 6, Y(f.maxY)); ctx.lineTo(bx + 6, Y(f.maxY))
                    ctx.stroke()
                    ctx.textAlign = "center"
                    ctx.fillText(root.fmt(f.width) + " in", (X(f.minX) + X(f.maxX)) / 2, by + 16)
                    ctx.save()
                    ctx.translate(bx + 16, (Y(f.minY) + Y(f.maxY)) / 2)
                    ctx.rotate(-Math.PI / 2)
                    ctx.fillText(root.fmt(f.length) + " in", 0, 0)
                    ctx.restore()
                    ctx.textAlign = "start"
                }
            }

            Canvas {
                id: modelCanvas
                anchors.fill: parent
                visible: root.mode === 1 && !!root.folded
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var m = root.folded
                    if (!m) return
                    var cy = Math.cos(root.yaw * Math.PI / 180), sy = Math.sin(root.yaw * Math.PI / 180)
                    var cp = Math.cos(root.pitch * Math.PI / 180), sp = Math.sin(root.pitch * Math.PI / 180)
                    var span = Math.max(m.size[0], m.size[1], m.size[2], 1e-6)
                    var sc = Math.min(width, height) * 0.8 / span * root.zoom
                    function view(v) {
                        var x = v[0] - m.center[0], y = v[1] - m.center[1], z = v[2] - m.center[2]
                        var x1 = cy * x - sy * y, y1 = sy * x + cy * y
                        // camera: screen X = x1, screen Y = z/y1 mix, depth = y1
                        var sY = cp * z - sp * y1, depth = sp * z + cp * y1
                        return [width / 2 + x1 * sc, height / 2 - sY * sc, depth]
                    }
                    var light = [0.35, -0.5, 0.8]
                    var drawn = []
                    for (var f = 0; f < m.faces.length; ++f) {
                        var face = m.faces[f]
                        var rings = [], depth = 0, n = 0
                        for (var r = 0; r < face.rings.length; ++r) {
                            var ring = []
                            for (var i = 0; i < face.rings[r].length; ++i) {
                                var p = view(face.rings[r][i])
                                ring.push(p)
                                if (r === 0) { depth += p[2]; ++n }
                            }
                            rings.push(ring)
                        }
                        // Face normal from the first three non-collinear world points.
                        var w = face.rings[0]
                        var a = w[0], b = w[Math.floor(w.length / 3)], c = w[Math.floor(2 * w.length / 3)]
                        var u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v2 = [c[0] - a[0], c[1] - a[1], c[2] - a[2]]
                        var nx = u[1] * v2[2] - u[2] * v2[1], ny = u[2] * v2[0] - u[0] * v2[2], nz = u[0] * v2[1] - u[1] * v2[0]
                        var nl = Math.hypot(nx, ny, nz) || 1
                        var shade = Math.abs((nx * light[0] + ny * light[1] + nz * light[2]) / nl)
                        drawn.push({ rings: rings, depth: n ? depth / n : 0, shade: shade, root: face.root })
                    }
                    drawn.sort(function (l, r) { return r.depth - l.depth })
                    for (var d = 0; d < drawn.length; ++d) {
                        var item = drawn[d]
                        ctx.beginPath()
                        for (var rr = 0; rr < item.rings.length; ++rr) {
                            var pts = item.rings[rr]
                            ctx.moveTo(pts[0][0], pts[0][1])
                            for (var k = 1; k < pts.length; ++k) ctx.lineTo(pts[k][0], pts[k][1])
                            ctx.closePath()
                        }
                        var level = Math.round(70 + 120 * item.shade)
                        ctx.fillStyle = item.root ? Qt.rgba(level / 255 * 0.55, level / 255 * 0.8, level / 255, 0.92)
                                                  : Qt.rgba(level / 255 * 0.7, level / 255 * 0.78, level / 255 * 0.85, 0.92)
                        ctx.fillRule = Qt.OddEvenFill
                        ctx.fill()
                        ctx.strokeStyle = "#E2E8F0"; ctx.lineWidth = 1
                        ctx.stroke()
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    property real lastX: 0
                    property real lastY: 0
                    onPressed: function (mouse) { lastX = mouse.x; lastY = mouse.y }
                    onPositionChanged: function (mouse) {
                        root.yaw += (mouse.x - lastX) * 0.5
                        root.pitch = Math.max(-89, Math.min(89, root.pitch + (mouse.y - lastY) * 0.5))
                        lastX = mouse.x; lastY = mouse.y
                        modelCanvas.requestPaint()
                    }
                    onWheel: function (wheel) {
                        root.zoom = Math.max(0.3, Math.min(5, root.zoom * (wheel.angleDelta.y > 0 ? 1.1 : 0.9)))
                        modelCanvas.requestPaint()
                    }
                }
            }
        }

        // Bend table for the flat pattern view.
        Flow {
            Layout.fillWidth: true
            visible: root.mode === 0 && !!root.flat
            spacing: 14
            Repeater {
                model: root.flat ? root.flat.bends : []
                delegate: Text {
                    required property var modelData
                    color: "#CBD5E1"; font.pixelSize: 11
                    text: "B" + modelData.id + ": " + modelData.angle.toFixed(1) + "° " + modelData.direction
                          + "  R " + root.fmt(modelData.radius) + "  L " + root.fmt(modelData.length)
                          + "  edge→line " + root.fmt(modelData.offset) + " in"
                }
            }
        }
    }
}
