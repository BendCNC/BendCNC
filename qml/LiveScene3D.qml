import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import QtQuick.Window
import BendCNCPrototype

// LIVE 3D view (Qt Quick 3D). Same data as the 2D LIVE canvas: V5 compiled
// panel transforms + finite-radius bands, tooling profiles at their station
// runs, punch at pose.punchTipR and finger at the backgauge contact.
// Units: 1 scene unit = 1 inch * unitScale.
Item {
    id: root
    property var canvas: null
    readonly property real unitScale: 10
    property string toolingKey: ""
    property real lastFrameMs: 0
    property int framesSeen: 0
    // --live3d-fps-log: prints swapped frames/s, pose updates/s and timings every 5 s.
    readonly property bool fpsLog: Qt.application.arguments.indexOf("--live3d-fps-log") !== -1
    property int swapCount: 0
    property int poseCount: 0
    property real syncMsTotal: 0
    property real meshMsTotal: 0
    // Per-section syncFrame cost (only with --live3d-fps-log): feed, tooling, pose, seat/contact.
    property real feedMsTotal: 0
    property real toolMsTotal: 0
    property real poseMsTotal: 0
    property real seatMsTotal: 0
    property real seatToolMsTotal: 0
    property real seatLiftMsTotal: 0
    property real frameMsTotal: 0
    property real topoMsTotal: 0
    readonly property bool verboseLog: Qt.application.arguments.indexOf("--live3d-verbose") !== -1
    property real windowStartMs: Date.now()

    Connections {
        target: root.fpsLog ? root.Window.window : null
        function onFrameSwapped() { root.swapCount++ }
    }
    Timer {
        interval: 5000; repeat: true; running: root.fpsLog
        onTriggered: {
            var now = Date.now(), seconds = (now - root.windowStartMs) / 1000
            var poses = Math.max(1, root.poseCount)
            console.info("[live3d-fps] fps=" + (root.swapCount / seconds).toFixed(1)
                + " poses/s=" + (root.poseCount / seconds).toFixed(1)
                + " syncMs=" + (root.syncMsTotal / poses).toFixed(2)
                + " meshMs=" + (root.meshMsTotal / poses).toFixed(2)
                    + " feedMs=" + (root.feedMsTotal / poses).toFixed(2)
                    + " (frame=" + (root.frameMsTotal / poses).toFixed(2)
                    + " topo=" + (root.topoMsTotal / poses).toFixed(2) + ")"
                    + " toolMs=" + (root.toolMsTotal / poses).toFixed(2)
                    + " poseMs=" + (root.poseMsTotal / poses).toFixed(2)
                    + " seatMs=" + (root.seatMsTotal / poses).toFixed(2)
                + " seatToolMs=" + (root.seatToolMsTotal / poses).toFixed(2)
                + " seatLiftMs=" + (root.seatLiftMsTotal / poses).toFixed(2)
                + " tri=" + partGeom.triangleCount)
            root.swapCount = 0; root.poseCount = 0; root.syncMsTotal = 0
                root.feedMsTotal = 0; root.toolMsTotal = 0; root.poseMsTotal = 0; root.seatMsTotal = 0; root.seatToolMsTotal = 0; root.seatLiftMsTotal = 0
            root.meshMsTotal = 0; root.frameMsTotal = 0; root.topoMsTotal = 0; root.windowStartMs = now
        }
    }

    function syncTooling() {
        if (!canvas)
            return
        var tooling = canvas.live3DTooling()
        if (!tooling || tooling.key === toolingKey)
            return
        // Unfold viewer tool colours.
        tableGeom.setProfile(tooling.table.outer, [], tooling.table.runs, "#526b7d")
        holderGeom.setProfile(tooling.holder.outer, [], tooling.holder.runs, "#737d87")
        dieGeom.setProfile(tooling.die.outer, [], tooling.die.runs, "#ba956d")
        partGeom.setDieProfile(tooling.die.outer, tooling.die.runs || [])
        punchGeom.setProfile(tooling.punch.outer, [], tooling.punch.runs, "#8fabcc")
        punchExtraList = (tooling.punchExtras || []).filter(function(e) { return e.outer && e.outer.length >= 3 })
        fingerGeom.setProfile(tooling.finger.outer, tooling.finger.holes,
                              tooling.finger.runs, "#f1c653")
        fingerDepthIn = tooling.finger.depth || 1
        fingerUsesMesh = !!(tooling.finger.meshPoints && tooling.finger.meshTriangles)
        if (fingerUsesMesh) {
            fingerMeshLeft.setMesh(tooling.finger.meshPoints, tooling.finger.meshTriangles, false, "#f1c653")
            fingerMeshRight.setMesh(tooling.finger.meshPoints, tooling.finger.meshTriangles, true, "#f1c653")
        }
        toolingKey = tooling.key
        // Transfer park must clear the front of every tool (+x).
        var front = 0
        var profiles = [tooling.die.outer, tooling.punch.outer, tooling.holder.outer]
        for (var p = 0; p < profiles.length; ++p)
            for (var i = 0; profiles[p] && i < profiles[p].length; ++i) {
                var pt = profiles[p][i]
                var x = pt.x !== undefined ? pt.x : pt[0]
                if (x > front)
                    front = x
            }
        partGeom.transitionClearX = front
        // Segment width labels on the front faces (top views), like Placement.
        function frontTop(outer) {
            var fx = -1e9, ty = -1e9, by = 1e9
            for (var k = 0; outer && k < outer.length; ++k) {
                var q = outer[k]
                var qy = q.r !== undefined ? q.r : (q.y !== undefined ? q.y : q[1])
                fx = Math.max(fx, q.x !== undefined ? q.x : q[0])
                ty = Math.max(ty, qy)
                by = Math.min(by, qy)
            }
            return { x: fx, y: ty, mid: (ty + by) / 2 }
        }
        var labels = []
        var dieFt = frontTop(tooling.die.outer), punchFt = frontTop(tooling.punch.outer)
        var dieSeg = tooling.die.segments || [], punchSeg = tooling.punch.segments || []
        for (var s = 0; s < punchSeg.length && punchFt.x > -1e8; ++s)
            labels.push({ kind: "punch", x: punchFt.x, y: punchFt.mid, z: punchSeg[s].z, label: punchSeg[s].label })
        segmentLabels = labels
        if (fpsLog)
            console.info("[live3d] segment labels " + JSON.stringify(labels.map(function(l) { return l.kind + ":" + l.label })))
        if (transitionPhase === 0)
            needsFit = true
    }
    property bool needsFit: true
    property var punchExtraList: []
    // ORIGINAL finger: exact STEP mesh (left / mirrored right) instead of the
    // extruded side profile.
    property bool fingerUsesMesh: false
    // Split hinge: child panel of the next stage's span ("" = by sequence).
    property string nextChildId: ""
    property real fingerDepthIn: 1
    // Fingers sit on the part edge that actually touches the gauge (not the
    // punch span): two when that edge fits 2 fingers + 0.5 in gap, else one
    // centred on it.
    property string fingerLatchBend: ""
    function placeFingers(frame) {
        // Latch once per bend (first settled pose): the gauge stations do not
        // move sideways during the whole stroke; recomputing while the part
        // slides/lifts made the finger jump to another flange.
        // A frame still carrying the previous bend (canvas lags the selected
        // sequence) must not move the fingers: keep the current stations.
        var stale = frame && frame.renderedBend !== undefined && canvas
                && frame.renderedBend !== canvas.selectedBendIndex
        if (frame && (stale || fingerLatchBend === frame.bendLabel)) {
            fingerNode2.x = fingerNode.x
            fingerNode2.y = fingerNode.y
            return
        }
        // Contact at the finger face X (part-local), avoiding flanges that
        // protrude past the gauge (the finger would sit inside them).
        // Final seated pose (the entry transition offset is temporary), so the
        // stations are set as soon as the new bend appears, not after entry.
        var gaugeLocalX = frame ? frame.gaugeFaceX - partModel.x : NaN
        var span = partGeom.gaugeContactSpanAt(0.06, gaugeLocalX)
        var depth = fingerDepthIn, gap = canvas ? canvas.backgaugeFingerMinGapIn : 0.5
        fingerNode2.x = fingerNode.x
        fingerNode2.y = fingerNode.y
        // Only a real contact at the gauge X defines the stations. During
        // bump/retract (gauge away from the edge) the fallback
        // picks the outermost flange: keep the current stations instead.
        if (!span.exact) {
            if (fingerLatchBend !== "" || fingerNode.z !== 0)
                return
        } else {
            fingerLatchBend = frame.bendLabel
        }
        if (!span.found) {
            fingerNode.z = 0
            fingerNode2.visible = false
            return
        }
        var runs = span.spans || []
        // ORIGINAL finger: contact is the tongue tip (practically a point) at
        // z = +0.9 in of the left mesh (mirrored -0.9 for the right one). Place
        // the contact points, not the finger centres, as far apart as the
        // edge allows (margin 0.25 in) for a stable gauge.
        if (fingerUsesMesh) {
            var tipZ = 0.9, edge = 0.25
            var c0 = runs.length >= 2 ? runs[0].z0 : span.z0
            var c1 = runs.length >= 2 ? runs[runs.length - 1].z1 : span.z1
            var r0 = runs.length >= 2 ? runs[0] : span
            var r1 = runs.length >= 2 ? runs[runs.length - 1] : span
            var ca = Math.min(c0 + edge, (r0.z0 + r0.z1) / 2)
            var cb = Math.max(c1 - edge, (r1.z0 + r1.z1) / 2)
            if (cb - ca >= gap + 0.2) {
                fingerNode.z = (ca - tipZ) * unitScale
                fingerNode2.z = (cb + tipZ) * unitScale
                fingerNode2.visible = true
            } else {
                fingerNode.z = ((span.z0 + span.z1) / 2 - tipZ) * unitScale
                fingerNode2.visible = false
            }
            return
        }
        // Separate contact runs (e.g. two corner tabs): one finger on each
        // outermost run, pushed outward if needed while still overlapping it.
        if (runs.length >= 2) {
            var a = runs[0], b = runs[runs.length - 1]
            var za = a.z1 - a.z0 < depth ? (a.z0 + a.z1) / 2 : a.z0 + depth / 2
            var zb = b.z1 - b.z0 < depth ? (b.z0 + b.z1) / 2 : b.z1 - depth / 2
            if (zb - za < depth + gap) {
                var m = Math.min(0.12, (a.z1 - a.z0) / 2, (b.z1 - b.z0) / 2)
                za = Math.min(za, a.z1 - m - depth / 2)
                zb = Math.max(zb, b.z0 + m + depth / 2)
            }
            if (zb - za >= depth + gap - 1e-6) {
                fingerNode.z = za * unitScale
                fingerNode2.z = zb * unitScale
                fingerNode2.visible = true
                return
            }
        }
        var width = span.z1 - span.z0, mid = (span.z0 + span.z1) / 2
        if (width < 2 * depth + gap) {
            fingerNode.z = mid * unitScale
            fingerNode2.visible = false
            return
        }
        var offset = Math.min(width / 2 - depth / 2, Math.max((gap + depth) / 2, width / 4))
        fingerNode.z = (mid - offset) * unitScale
        fingerNode2.z = (mid + offset) * unitScale
        fingerNode2.visible = true
    }
    property var segmentLabels: []
    property bool showInfo: false
    // Settings -> LIVE Animation FPS Limit (0 = max).
    readonly property int maxFps: canvas ? canvas.liveMaxFps : 0
    property real transitionFrameAccum: 0

    // TEMP verification: horizontal curve-centre error vs punch axis (mm).
    property bool centerDebugEnabled: Qt.application.arguments.indexOf("--live3d-center-log") >= 0
    property string centerDbgBuf: ""
    property string centerDbgKey: ""
    function centerDbg(anchors, frame, shift) {
        if (typeof fileIo === "undefined" || !fileIo)
            return
        for (var i = 0; i < anchors.length; i++) {
            var a = anchors[i]
            if (!a.active)
                continue
            var ang = 0
            for (var k in frame.angles)
                ang = Math.max(ang, Math.abs(Number(frame.angles[k]) || 0))
            var key = frame.bendLabel + "|" + JSON.stringify(frame.angles)
            if (key === centerDbgKey)
                return
            centerDbgKey = key
            var hinge = (a.sx + a.ex) / 2
            centerDbgBuf += "bend=" + frame.bendLabel + " seq=" + a.sequence
                + " oldErrMm=" + ((a.cx - hinge) * 25.4).toFixed(3)
                + " newErrMm=" + ((a.cx + shift) * 25.4).toFixed(3)
                + " lift=" + partModel.y.toFixed(4)
                + " angles=" + JSON.stringify(frame.angles) + "\n"
            fileIo.write("live3d-center.txt", centerDbgBuf)
            return
        }
    }

    function syncFrame() {
        if (!canvas || !visible)
            return
        var syncStart = Date.now()
        // Exit / loading: keep the finished part parked; ignore everything
        // until the next bend is actually rendered (no mesh swap, no refit).
        if (transitionPhase === 1)
            return
        var frame = canvas.live3DFrame()
        if (!frame)
            return
        if (transitionPhase === 2 && (canvas.selectedBendIndex === transitionFromBend
                    || frame.renderedBend !== canvas.selectedBendIndex))
            return
        nextChildId = frame.nextChildId || ""
        var tTopo0 = Date.now()
        var topology = canvas.live3DTopology()
        if (fpsLog) { frameMsTotal += tTopo0 - syncStart; topoMsTotal += Date.now() - tTopo0 }
        var tFeed = Date.now()
        if (topology && topology.key !== partGeom.topologyKey) {
            partGeom.setTopology(topology.key, topology.panels, topology.edges)
            if (verboseLog) {
                for (var ei = 0; ei < topology.edges.length; ei++) {
                    var ed = topology.edges[ei], hs = {x: ed.hingeStart.x_in, y: ed.hingeStart.y_in}, he = {x: ed.hingeEnd.x_in, y: ed.hingeEnd.y_in}
                    var dx = he.x - hs.x, dy = he.y - hs.y, L = Math.sqrt(dx*dx+dy*dy)
                    var gap = {}
                    for (var pi = 0; pi < topology.panels.length; pi++) {
                        var pn = topology.panels[pi]
                        if (pn.id !== ed.childPanelId && pn.id !== ed.parentPanelId) continue
                        var m = 1e9
                        for (var vi = 0; vi < pn.outerLoop.length; vi++) {
                            var q = pn.outerLoop[vi], qx = q.x !== undefined ? q.x : (q.x_in !== undefined ? q.x_in : q[0]), qy = q.y !== undefined ? q.y : (q.y_in !== undefined ? q.y_in : q[1])
                            m = Math.min(m, Math.abs(((qx-hs.x)*dy-(qy-hs.y)*dx)/L))
                        }
                        gap[pn.id === ed.childPanelId ? "child" : "parent"] = m.toFixed(4)
                    }
                    console.info("[live3d] edge " + ed.sequenceHint + " R=" + ed.insideRadius_in + " t=" + ed.thickness_in + " k=" + ed.kFactor + " gap=" + JSON.stringify(gap) + " hs=" + JSON.stringify(hs))
                }
            }
            if (transitionPhase === 0)
                needsFit = true
        }
        var tTool0 = Date.now()
        syncTooling()
        var tPose0 = Date.now()
        partGeom.setPose(frame.transforms, frame.angles, frame.frame,
                         frame.centerX, frame.centerR, frame.panelStates)
        var tSeat0 = Date.now()
        // Rest the part on the die shoulders instead of sinking into it.
        var tooling = canvas.live3DTooling()
        var tSeatA = Date.now()
        // Bend line exactly under the punch: shift by the active hinge's x.
        var rawShift = 0
        var anchors = partGeom.bendAnchors
        var activeAnchor = null
        for (var ai = 0; ai < anchors.length; ai++) {
            if (anchors[ai].active) {
                activeAnchor = anchors[ai]
                // Centre the formed curve (not the flat hinge line) under the punch.
                rawShift = -(anchors[ai].cx !== undefined ? anchors[ai].cx
                             : (anchors[ai].sx + anchors[ai].ex) / 2)
                break
            }
        }
        // Stage change: pose of the new step not rendered yet. Keep the last
        // coherent placement instead of jumping. Once the frame belongs to the
        // selected bend, always centre it: a fixed distance gate left the part
        // parked off the tooling whenever the real shift exceeded it.
        var poseCoherent = activeAnchor !== null
                && (frame.renderedBend === undefined || frame.renderedBend === canvas.selectedBendIndex)
        if (!poseCoherent) {
            rawShift = partModel.x
            activeAnchor = null
        }
        var rawLift = tooling && tooling.die ? partGeom.seatLift(rawShift) : 0
        var tSeatB = Date.now()

        // The formed bend is centred on its hinge line (measured within
        // ~0.02 in), so the anchor shift is the seat; no tilt/balancing.
        // Lift rises at once (never sinks into the die), settles down smoothed;
        // snap on bend change.
        // Seat is a pure function of the pose: frame-rate independent and
        // stable when paused, and free to drop into the V as the angle grows.
        seatBend = frame.bendLabel
        partModel.x = rawShift
        partModel.y = rawLift
        if (centerDebugEnabled)
            centerDbg(anchors, frame, rawShift)
        if (verboseLog) {
            var cd = partGeom.lastContactDebug()
            console.info("[live3d] contact bend=" + frame.bendLabel + " lift=" + partModel.y.toFixed(4)
                + " punchTip=" + frame.punchTipR.toFixed(4) + " top0=" + (cd.top0 + partModel.y).toFixed(4)
                + " low0=" + (cd.low0 + partModel.y).toFixed(4) + " ang=" + JSON.stringify(frame.angles))
        }
        // Punch rests on the bend's inner surface: the part already sits on
        // the die shoulders, so a tip below it would cut through the sheet.
        // Contact only with the active band's inner face (final seated pose);
        // other formed flanges in the punch column are ignored here.
        var tipR = frame.punchTipR
        if (activeAnchor && activeAnchor.bandTop !== undefined) {
            var bandTop = activeAnchor.bandTop + partModel.y
            if (tipR < bandTop)
                tipR = bandTop
        }
        punchNode.y = tipR * unitScale
        fingerNode.x = frame.gaugeFaceX * unitScale
        fingerNode.y = frame.fingerContactR * unitScale
        placeFingers(frame)
        lastFrameMs = partGeom.updateMs
        if (transitionPhase === 2) {
            // First pose of the new bend: entry starts in this same frame.
            partGeom.resolveTransition()
            if (fpsLog)
                console.info("[live3d] resolve " + partGeom.transitionDebug())
            transitionPhase = 3
            transitionElapsed = 0
        }
        applyTransition()
        // Never refit the camera during a transfer: it reads as a jump.
        if (needsFit && transitionPhase === 0) {
            needsFit = false
            fitDeferTimer.restart()
        }
        badgeTick++
        framesSeen++
        if (fpsLog) {
            var tEnd = Date.now()
            poseCount++
            meshMsTotal += partGeom.updateMs
            feedMsTotal += tFeed - syncStart
            toolMsTotal += tPose0 - tTool0
            poseMsTotal += tSeat0 - tPose0
            seatMsTotal += tEnd - tSeat0
            seatToolMsTotal += tSeatA - tSeat0
            seatLiftMsTotal += tSeatB - tSeatA
            syncMsTotal += tEnd - syncStart
        }
    }

    Connections {
        target: root.canvas
        function onRunRenderFrameChanged() { root.syncFrame() }
        // Full-sequence SIM: animate the part from its finished placement to
        // the next bend's placement instead of jumping.
        function onSimulatedCycleEnding() {
            if (!root.canvas.simulatedFullSequence)
                return
            partGeom.captureTransitionStart()
            root.transitionFromBend = root.canvas.selectedBendIndex
            root.transitionElapsed = 0
            root.transitionPhase = 1
            if (root.fpsLog)
                console.info("[live3d] " + Date.now() + " sequence transition start")
        }
    }
    // After importing/loading a program the part frame can become ready
    // without any further runRenderFrameChanged (slow press: the compile
    // finishes after the first sync). Poll until the part mesh exists so the
    // piece is always visible without starting SIM RUN.
    Timer {
        interval: 250
        repeat: true
        running: root.visible && root.canvas !== null && root.transitionPhase === 0
                 && partGeom.triangleCount === 0
        onTriggered: {
            // Only refit once the mesh actually exists; refitting (and
            // forcing a tooling rebuild) every poll stalled ARM startup.
            root.syncFrame()
            if (partGeom.triangleCount > 0) {
                root.toolingKey = ""
                root.syncFrame()
                root.autoFitPending = true
                root.fitView()
            }
        }
    }
    property real transitionStartMs: 0
    // Armed at cycle end; the clock starts on the next bend's first pose
    // because switching bends can stall the GUI thread for a while.
    // 0 idle, 1 exit (old pose slides out), 2 loading next bend (parked),
    // 3 entry (reorient parked, slide in).
    property int transitionPhase: 0
    property int transitionFromBend: -1
    property real lastLoggedT: 0
    readonly property bool transitioning: transitionPhase > 0
    // Drive the transition every display frame: while SIM time is held no
    // new pose frames arrive, so syncFrame() alone would stall it.
    FrameAnimation {
        running: root.transitioning && root.visible
        onTriggered: {
            // Loading the next bend: on the press the new frame can arrive as
            // a cache hit (no runRenderFrame change) -> poll, and never wait
            // forever (SIM would stay held and the animation stop).
            if (root.transitionPhase === 2) {
                root.loadingElapsed += frameTime
                root.syncFrame()
                if (root.transitionPhase === 2 && root.loadingElapsed > 4)
                    root.abortTransition("loading timeout")
                return
            }
            if (root.maxFps > 0) {
                root.transitionFrameAccum += frameTime
                if (root.transitionFrameAccum < 1 / root.maxFps)
                    return
                var dt = root.transitionFrameAccum
                root.transitionFrameAccum = 0
                root.applyTransition(dt)
                return
            }
            root.applyTransition(frameTime)
        }
    }
    property real transitionElapsed: 0
    property real loadingElapsed: 0
    function abortTransition(reason) {
        console.warn("[live3d] transition aborted: " + reason)
        transitionPhase = 0
        transitionElapsed = 0
        loadingElapsed = 0
        lastLoggedT = 0
        partTransitionNode.position = Qt.vector3d(0, 0, 0)
        partTransitionNode.rotation = Qt.quaternion(1, 0, 0, 0)
        if (canvas)
            canvas.simulatedHoldSeconds = 0
        needsFit = true
        Qt.callLater(syncFrame)
    }
    // SEQ toggled / SIM stopped mid-transfer: release the hold.
    Connections {
        target: root.canvas
        function onSimulatedFullSequenceChanged() { if (root.transitioning) root.abortTransition("seq mode changed") }
        function onRunningChanged() { if (root.transitioning) root.abortTransition("run state changed") }
    }
    // Clock = accumulated frame time with dt clamped to 50 ms, so GUI-thread
    // stalls (bend switch) never skip the animation.
    function applyTransition(dt) {
        if (transitionPhase !== 1 && transitionPhase !== 3)
            return
        if (dt !== undefined) {
            if (fpsLog && dt > 0.1 && !(maxFps > 0 && maxFps <= 10))
                console.info("[live3d] " + Date.now() + " stall dt=" + dt.toFixed(3))
            transitionElapsed += Math.min(maxFps > 0 ? Math.max(0.05, 1.5 / maxFps) : 0.05,
                                          Math.max(0, dt))
        }
        var total = Math.max(0.2, canvas ? canvas.simulatedTransitionSeconds : 1.4)
        var duration = transitionPhase === 1 ? total * 0.3 : total * 0.7
        var t = Math.min(1, transitionElapsed / duration)
        var pose = transitionPhase === 1 ? partGeom.exitAt(t) : partGeom.transitionAt(t)
        partTransitionNode.position = pose.position
        partTransitionNode.rotation = pose.rotation
        if (fpsLog && (t >= 1 || lastLoggedT === 0 || Math.floor(t * 10) !== Math.floor(lastLoggedT * 10)))
            console.info("[live3d] " + Date.now() + " phase=" + transitionPhase + " t=" + t.toFixed(3)
                         + " world=" + partWorldBox())
        lastLoggedT = t
        if (t >= 1 && transitionPhase === 1) {
            // Parked: load the next bend (any stall happens here, visibly paused).
            lastLoggedT = 0
            transitionElapsed = 0
            loadingElapsed = 0
            transitionPhase = 2
            Qt.callLater(function() { if (root.canvas) root.canvas.finishSimulatedCycle() })
        } else if (t >= 1) {
            lastLoggedT = 0
            transitionElapsed = 0
            transitionPhase = 0
            if (canvas)
                canvas.simulatedHoldSeconds = 0
            partTransitionNode.position = Qt.vector3d(0, 0, 0)
            partTransitionNode.rotation = Qt.quaternion(1, 0, 0, 0)
        }
    }

    // ---- Unfold-style views -------------------------------------------
    // "iso" | "top" | "top-ortho" | "side-right" | "side-left"
    // --live3d-view=<mode> selects the initial view (captures/validation).
    property string viewMode: {
        var args = Qt.application.arguments
        for (var i = 0; i < args.length; i++)
            if (args[i].indexOf("--live3d-view=") === 0)
                return args[i].substring(14)
        return "top-ortho"
    }
    property bool partOnly: true
    property bool autoFitPending: true
    property string seatBend: ""
    property int badgeTick: 0
    // Unfold "translucent punch": tooling drawn at ~28% so the formed zone stays visible.
    // Follows Settings > Display > Tooling CAD Appearance (TRANSLUCENT = ghost).
    readonly property bool ghostTooling: canvas ? String(canvas.toolingAppearance).toUpperCase() === "TRANSLUCENT" : false
    // Scene z of the side-view background grids (just behind the part).
    property real gridZLo: -100
    property real gridZHi: 100
    readonly property string activeBendLabel: {
        var list = partGeom.bendAnchors
        for (var i = 0; i < list.length; i++)
            if (list[i].active)
                return list[i].label
        return ""
    }
    readonly property bool orthoView: viewMode === "top-ortho" || viewMode.indexOf("side") === 0
    readonly property var viewEuler: ({
        // Operator front is +x (backgauge/fingers at -x).
        "iso": Qt.vector3d(-24, 55, 0),
        // Top: looking down, fingers (-x) at the top of the screen.
        "top": Qt.vector3d(-90, 90, 0),
        "top-ortho": Qt.vector3d(-90, 90, 0),
        "side-right": Qt.vector3d(0, 180, 0),
        "side-left": Qt.vector3d(0, 0, 0)
    })
    readonly property bool topView: viewMode === "top" || viewMode === "top-ortho"
    readonly property int activeSequence: {
        var list = partGeom.bendAnchors
        for (var i = 0; i < list.length; i++)
            if (list[i].active)
                return list[i].sequence
        return 0
    }
    function bendRole(a) {
        if (a.active) return "now"
        if (nextChildId !== "") return a.childId === nextChildId ? "next" : "other"
        if (activeSequence > 0 && a.sequence === activeSequence + 1) return "next"
        return "other"
    }
    function screenOf(x, y, z) {
        var s = unitScale
        return view.mapFrom3DScene(Qt.vector3d(x * s, y * s, z * s + machineOffsetZ))
    }

    function unionBounds(models) {
        var lo = null, hi = null
        for (var i = 0; i < models.length; i++) {
            var b = models[i].bounds, s = models[i].sceneScale, o = models[i].parent.scenePosition
            if (!b || b.maximum.x < b.minimum.x)
                continue
            var mn = Qt.vector3d(b.minimum.x * s.x + o.x, b.minimum.y * s.y + o.y, b.minimum.z * s.z + o.z)
            var mx = Qt.vector3d(b.maximum.x * s.x + o.x, b.maximum.y * s.y + o.y, b.maximum.z * s.z + o.z)
            lo = lo ? Qt.vector3d(Math.min(lo.x, mn.x), Math.min(lo.y, mn.y), Math.min(lo.z, mn.z)) : mn
            hi = hi ? Qt.vector3d(Math.max(hi.x, mx.x), Math.max(hi.y, mx.y), Math.max(hi.z, mx.z)) : mx
        }
        return lo ? { lo: lo, hi: hi } : null
    }

    function partWorldBox() {
        var b = partModel.bounds
        var lo = partModel.mapPositionToScene(b.minimum), hi = partModel.mapPositionToScene(b.maximum)
        var f = function(v) { return "(" + v.x.toFixed(1) + "," + v.y.toFixed(1) + "," + v.z.toFixed(1) + ")" }
        return f(lo) + ".." + f(hi)
    }
    readonly property bool sideView: viewMode.indexOf("side") === 0
    // Set by touch/mouse camera gestures; side views stop auto-following then.
    property bool userAdjusted: false
    // Part box in scene units from its 8 mapped corners (includes the
    // transition node transform, unlike bounds + parent.position).
    function partSceneBox() {
        var b = partModel.bounds
        if (!b || b.maximum.x < b.minimum.x)
            return null
        var lo = null, hi = null
        for (var i = 0; i < 8; ++i) {
            var p = partModel.mapPositionToScene(Qt.vector3d(i & 1 ? b.maximum.x : b.minimum.x,
                i & 2 ? b.maximum.y : b.minimum.y, i & 4 ? b.maximum.z : b.minimum.z))
            lo = lo ? Qt.vector3d(Math.min(lo.x, p.x), Math.min(lo.y, p.y), Math.min(lo.z, p.z)) : p
            hi = hi ? Qt.vector3d(Math.max(hi.x, p.x), Math.max(hi.y, p.y), Math.max(hi.z, p.z)) : p
        }
        return { lo: lo, hi: hi }
    }
    // Side views frame the whole part (tooling/table may be cropped).
    function fitSideToPart() {
        var box = partSceneBox()
        if (!box)
            return false
        var w = box.hi.x - box.lo.x, h = box.hi.y - box.lo.y
        if (Math.max(w, h) < 1)
            return false
        cameraOrigin.eulerRotation = viewEuler[viewMode]
        cameraOrigin.position = Qt.vector3d((box.lo.x + box.hi.x) / 2, (box.lo.y + box.hi.y) / 2,
                                            (box.lo.z + box.hi.z) / 2)
        gridZLo = box.lo.z - 10
        gridZHi = box.hi.z + 10
        var depth = Math.max(w, h, box.hi.z - box.lo.z)
        orthoCamera.position = Qt.vector3d(0, 0, depth * 4 + 200)
        // 12% margin; the left button strip takes ~70 px.
        var mag = Math.max(0.01, Math.min((view.width - 70) / (w * 1.12), view.height / (h * 1.12)))
        orthoCamera.x = -35 / mag   // centre the part in the area right of the strip
        orthoCamera.horizontalMagnification = mag
        orthoCamera.verticalMagnification = mag
        autoFitPending = false
        badgeTick++
        return true
    }
    // Refit a side view when the bending part leaves the visible area.
    function followPartInSideView() {
        if (!sideView || userAdjusted || transitionPhase !== 0 || !visible)
            return
        var box = partSceneBox()
        if (!box)
            return
        var pts = [view.mapFrom3DScene(box.lo), view.mapFrom3DScene(box.hi)]
        var minX = Math.min(pts[0].x, pts[1].x), maxX = Math.max(pts[0].x, pts[1].x)
        var minY = Math.min(pts[0].y, pts[1].y), maxY = Math.max(pts[0].y, pts[1].y)
        if (minX < 70 || maxX > view.width - 4 || minY < 4 || maxY > view.height - 4)
            fitDeferTimer.restart()
    }
    // Automatic refits reuse the first framing of this part: the posed part
    // box changes every sequence and refitting made the table jump/zoom.
    property var frozenFit: null
    // The scene is in the active-station frame (table run = -stationOffset),
    // so the machine moves between sequences. The camera tracks the table
    // centre in depth: table/tooling stay fixed on screen, the part shifts.
    readonly property real machineOffsetZ: {
        var b = tableModel.bounds
        if (!b || b.maximum.z < b.minimum.z)
            return 0
        return -(b.minimum.z + b.maximum.z) / 2 * unitScale
    }
    function fitView(onlyPart) {
        if (onlyPart !== undefined) {
            partOnly = onlyPart
            userAdjusted = false
            frozenFit = null
        }
        if (sideView && fitSideToPart())
            return
        if (fpsLog)
            console.info("[live3d] " + Date.now() + " fitView phase=" + transitionPhase)
        // Orientation must follow viewMode even before the part has bounds
        // (after a tab switch the mesh can be re-uploading); otherwise TOP
        // keeps the previous angled rotation.
        cameraOrigin.eulerRotation = viewEuler[viewMode]
        var models = partOnly ? [partModel]
            : [partModel, dieModel, punchModel, fingerModel] // full-length bed excluded
        var box = unionBounds(models)
        var partBox = unionBounds([partModel])
        if (!box || !partBox)
            return
        // The part mesh arrives after the first resize: keep refitting on
        // bounds changes until a real part extent has been framed.
        if (Math.max(partBox.hi.x - partBox.lo.x, partBox.hi.z - partBox.lo.z) < 1)
            return
        autoFitPending = false
        if (frozenFit && frozenFit.key === partGeom.topologyKey && frozenFit.partOnly === partOnly) {
            applyFit(frozenFit.center, frozenFit.radius, frozenFit.zLo, frozenFit.zHi)
            return
        }
        // Tool runs span the whole bed along z: clamp depth to the part
        // (plus a margin) so the view stays close to part and tooling.
        var margin = (partBox.hi.z - partBox.lo.z) * 0.15 + 5
        box.lo = Qt.vector3d(box.lo.x, box.lo.y, Math.max(box.lo.z, partBox.lo.z - margin))
        box.hi = Qt.vector3d(box.hi.x, box.hi.y, Math.min(box.hi.z, partBox.hi.z + margin))
        var center = Qt.vector3d((box.lo.x + box.hi.x) / 2, (box.lo.y + box.hi.y) / 2,
                                 (box.lo.z + box.hi.z) / 2)
        var radius = Math.max(1, 0.5 * Math.sqrt(Math.pow(box.hi.x - box.lo.x, 2)
            + Math.pow(box.hi.y - box.lo.y, 2) + Math.pow(box.hi.z - box.lo.z, 2))) * 0.85
        // The scene is in the active-station frame: the table run moves by
        // -stationOffset per sequence. Anchor depth to the table centre so
        // the machine stays still and only the part shifts by its station.
        var bed = unionBounds([tableModel])
        if (bed) {
            var bedZ = (bed.lo.z + bed.hi.z) / 2
            center = Qt.vector3d(center.x, center.y, bedZ)
        }
        frozenFit = { key: partGeom.topologyKey, partOnly: partOnly, center: center, radius: radius,
                      zLo: partBox.lo.z - 10, zHi: partBox.hi.z + 10 }
        applyFit(center, radius, partBox.lo.z - 10, partBox.hi.z + 10)
    }
    function applyFit(center, radius, zLo, zHi) {
        cameraOrigin.position = center
        gridZLo = zLo
        gridZHi = zHi
        cameraOrigin.eulerRotation = viewEuler[viewMode]
        var halfFov = perspectiveCamera.fieldOfView * Math.PI / 360
        perspectiveCamera.position = Qt.vector3d(0, 0, radius / Math.sin(halfFov))
        orthoCamera.position = Qt.vector3d(0, 0, radius * 4)
        var mag = Math.max(0.01, Math.min(view.width, view.height) / (2 * radius))
        orthoCamera.horizontalMagnification = mag
        orthoCamera.verticalMagnification = mag
        badgeTick++
    }

    Timer { id: fitDeferTimer; interval: 0; repeat: false; onTriggered: root.fitView() }
    function setViewMode(mode) {
        viewMode = mode
        userAdjusted = false
        fitView()
    }
    onWidthChanged: fitDeferTimer.restart()
    onHeightChanged: fitDeferTimer.restart()
    onVisibleChanged: {
        if (!visible && transitioning)
            abortTransition("hidden")
        if (visible)
            autoFitPending = true
        toolingKey = ""
        syncFrame()
        if (visible)
            fitDeferTimer.restart()
    }
    Component.onCompleted: syncFrame()
    // The Loader assigns canvas after creation, when the frame is already
    // built and no runRenderFrameChanged will follow until a run starts.
    onCanvasChanged: {
        if (!canvas)
            return
        toolingKey = ""
        autoFitPending = true
        syncFrame()
        fitDeferTimer.restart()
    }

    // Unfold stage background (#273b4b centre -> #111b24 edge).
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1c2b38" }
            GradientStop { position: 0.4; color: "#273b4b" }
            GradientStop { position: 0.75; color: "#15212c" }
            GradientStop { position: 1.0; color: "#111b24" }
        }
    }

    View3D {
        id: view
        anchors.fill: parent
        // Inline: no offscreen texture + composite pass (cheaper on the
        // Orange Pi GPU, pixel-identical with NoAA).
        renderMode: View3D.Offscreen
        camera: root.orthoView ? orthoCamera : perspectiveCamera
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.NoAA
        }

        Node {
            id: cameraOrigin
            position: Qt.vector3d(0, 10, 0)
            eulerRotation: Qt.vector3d(-24, -40, 0)
            onScenePositionChanged: root.badgeTick++
            onSceneRotationChanged: root.badgeTick++
            PerspectiveCamera {
                id: perspectiveCamera
                position: Qt.vector3d(0, 0, 260)
                clipNear: 1
                clipFar: 10000
                fieldOfView: 36
                onPositionChanged: root.badgeTick++
                // The camera's scene transform is recomputed after its parent's
                // (cameraOrigin) signals fire; projecting on those alone read the
                // previous transform and badges lagged one frame (visible flicker).
                onScenePositionChanged: root.badgeTick++
                onSceneRotationChanged: root.badgeTick++
            }
            OrthographicCamera {
                id: orthoCamera
                position: Qt.vector3d(0, 0, 2000)
                clipNear: 1
                clipFar: 10000
                onScenePositionChanged: root.badgeTick++
                onSceneRotationChanged: root.badgeTick++
            }
        }

        // Unfold lights: hemisphere (sky #d7e9ff / ground #354c55) + key + fill.
        DirectionalLight {
            eulerRotation: Qt.vector3d(-50, -35, 0)
            brightness: 1.0
            ambientColor: Qt.rgba(0.42, 0.48, 0.54, 1)
        }
        DirectionalLight {
            eulerRotation: Qt.vector3d(-20, 140, 0)
            color: "#d7e9ff"
            brightness: 0.45
        }

        // Floor grid under the table (Unfold GridHelper 0x4b687a, opacity .22).
        Model {
            id: floorGrid
            y: tableModel.bounds.minimum.y * root.unitScale - 2
            eulerRotation.x: -90
            scale: Qt.vector3d(20, 20, 1)   // 2 in x 2 in cells
            geometry: GridGeometry {
                horizontalLines: 81
                verticalLines: 81
                horizontalStep: 1
                verticalStep: 1
            }
            materials: DefaultMaterial {
                lighting: DefaultMaterial.NoLighting
                diffuseColor: "#6b8ca0"
                opacity: 0.35
            }
        }

        // Side-view reference grid: 2 in x 2 in XY plane behind the part.
        // Right side looks toward +z, left side toward -z.
        Model {
            visible: root.viewMode.indexOf("side") === 0
            position: Qt.vector3d(Math.round(cameraOrigin.position.x / 20) * 20,
                                  Math.round(cameraOrigin.position.y / 20) * 20,
                                  root.viewMode === "side-right" ? root.gridZHi : root.gridZLo)
            scale: Qt.vector3d(20, 20, 1)
            geometry: GridGeometry {
                horizontalLines: 81
                verticalLines: 81
                horizontalStep: 1
                verticalStep: 1
            }
            materials: DefaultMaterial {
                lighting: DefaultMaterial.NoLighting
                diffuseColor: "#6b8ca0"
                opacity: 0.4
            }
        }

        DefaultMaterial {
            id: ghostMaterial
            vertexColorsEnabled: true
            cullMode: Material.NoCulling
            lighting: DefaultMaterial.FragmentLighting
            specularAmount: 0
            opacity: 0.28
            depthDrawMode: Material.NeverDepthDraw
        }

        DefaultMaterial {
            id: vertexMaterial
            vertexColorsEnabled: true
            cullMode: Material.NoCulling
            lighting: DefaultMaterial.FragmentLighting
            specularAmount: 0
        }

        // Machine frame: the table (machine) is the scene origin. Content is
        // built in the active-station frame (table run = -stationOffset), so
        // shift everything by the table centre; table/tooling never move and
        // the part shifts by its station.
        Node {
        id: machineFrame
        z: root.machineOffsetZ
        Node {
            scale: Qt.vector3d(root.unitScale, root.unitScale, root.unitScale)
            Model { id: tableModel; geometry: LiveProfileSolid { id: tableGeom } materials: [vertexMaterial] }
            Model { id: holderModel; geometry: LiveProfileSolid { id: holderGeom } materials: [vertexMaterial] }
            Model { id: dieModel; geometry: LiveProfileSolid { id: dieGeom } materials: [vertexMaterial] }
            Node {
                id: partTransitionNode
                Model { id: partModel; geometry: LivePartMesh { id: partGeom } materials: [vertexMaterial]
        onBoundsChanged: if (root.autoFitPending) fitDeferTimer.restart(); else root.followPartInSideView() }
            }
        }
        Node {
            id: punchNode
            scale: Qt.vector3d(root.unitScale, root.unitScale, root.unitScale)
            Model { id: punchModel; geometry: LiveProfileSolid { id: punchGeom }
                    materials: [root.ghostTooling ? ghostMaterial : vertexMaterial] }
            // Co-station punches (other planner banks): one solid per
            // station, each with its own profile/orientation.
            // Hidden in side views: stacked profiles hide which station is active.
            Repeater3D {
                model: root.sideView ? [] : root.punchExtraList
                delegate: Model {
                    id: extraPunch
                    required property var modelData
                    geometry: LiveProfileSolid {
                        Component.onCompleted: setProfile(extraPunch.modelData.outer, [],
                                                          extraPunch.modelData.runs, "#8fabcc")
                    }
                    materials: [root.ghostTooling ? ghostMaterial : vertexMaterial]
                }
            }
        }
        Node {
            id: fingerNode
            scale: Qt.vector3d(root.unitScale, root.unitScale, root.unitScale)
            Model { id: fingerModel; visible: !root.fingerUsesMesh; geometry: LiveProfileSolid { id: fingerGeom } materials: [vertexMaterial] }
            Model { visible: root.fingerUsesMesh; geometry: LiveTriangleMesh { id: fingerMeshLeft } materials: [vertexMaterial] }
        }
        // Second backgauge finger: same X/R as the first (moved together),
        // laterally spaced by hand; shown only when the contact edge fits two.
        Node {
            id: fingerNode2
            visible: false
            scale: Qt.vector3d(root.unitScale, root.unitScale, root.unitScale)
            Model { visible: !root.fingerUsesMesh; geometry: fingerGeom; materials: [vertexMaterial] }
            Model { visible: root.fingerUsesMesh; geometry: LiveTriangleMesh { id: fingerMeshRight } materials: [vertexMaterial] }
        }
        }
    }

    // Perspective: 1 finger / left drag orbits, 2 fingers pan + pinch zoom,
    // wheel zooms, right drag pans. Ortho: 1 finger pans, 2 fingers pan + zoom.
    DragHandler {
        enabled: !root.orthoView
        maximumPointCount: 1
        acceptedButtons: Qt.LeftButton
        target: null
        property point last
        onActiveChanged: { last = centroid.position; if (active) root.userAdjusted = true }
        onCentroidChanged: {
            if (!active)
                return
            var dx = centroid.position.x - last.x, dy = centroid.position.y - last.y
            last = centroid.position
            var r = cameraOrigin.eulerRotation
            cameraOrigin.eulerRotation = Qt.vector3d(Math.max(-89, Math.min(89, r.x - dy * 0.3)), r.y - dx * 0.3, r.z)
            root.badgeTick++
        }
    }
    WheelHandler {
        enabled: !root.orthoView
        onWheel: function(event) {
            var f = event.angleDelta.y > 0 ? 1 / 1.12 : 1.12
            perspectiveCamera.z = Math.max(5, perspectiveCamera.z * f)
            root.userAdjusted = true
            root.badgeTick++
        }
    }
    function panBy(dx, dy) {
        if (root.orthoView) {
            var m = orthoCamera.horizontalMagnification
            orthoCamera.x -= dx / m
            orthoCamera.y += dy / m
        } else {
            var dist = perspectiveCamera.scenePosition.minus(cameraOrigin.scenePosition).length()
            var k = dist * 2 * Math.tan(perspectiveCamera.fieldOfView * Math.PI / 360) / Math.max(1, root.height)
            cameraOrigin.position = cameraOrigin.position
                .plus(perspectiveCamera.right.times(-dx * k))
                .plus(perspectiveCamera.up.times(dy * k))
        }
        root.userAdjusted = true
        root.badgeTick++
    }
    function zoomBy(f) {
        if (root.orthoView) {
            orthoCamera.horizontalMagnification *= f
            orthoCamera.verticalMagnification *= f
        } else {
            perspectiveCamera.z = Math.max(5, perspectiveCamera.z / f)
        }
        root.userAdjusted = true
        root.badgeTick++
    }
    // Perspective pan: right-drag (mouse) slides the orbit origin in the view plane.
    // acceptedButtons does not filter touch: without restricting devices this
    // handler grabbed single-finger touch and stole orbit from the controller.
    DragHandler {
        enabled: !root.orthoView
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        acceptedButtons: Qt.RightButton
        target: null
        property point last
        onActiveChanged: last = centroid.position
        onCentroidChanged: {
            if (!active)
                return
            var dx = centroid.position.x - last.x, dy = centroid.position.y - last.y
            last = centroid.position
            root.panBy(dx, dy)
        }
    }
    WheelHandler {
        enabled: root.orthoView
        onWheel: function(event) { root.zoomBy(event.angleDelta.y > 0 ? 1.12 : 1 / 1.12) }
    }
    // Two fingers (all views): move together = pan, spread/close = zoom.
    PinchHandler {
        target: null
        minimumPointCount: 2
        maximumPointCount: 2
        property real lastScale: 1
        property point lastCentroid
        onActiveChanged: { lastScale = 1; lastCentroid = centroid.position }
        onActiveScaleChanged: {
            if (!active || lastScale <= 0)
                return
            var f = activeScale / lastScale
            lastScale = activeScale
            root.zoomBy(f)
        }
        onCentroidChanged: {
            if (!active)
                return
            var dx = centroid.position.x - lastCentroid.x, dy = centroid.position.y - lastCentroid.y
            lastCentroid = centroid.position
            root.panBy(dx, dy)
        }
    }
    DragHandler {
        enabled: root.orthoView
        maximumPointCount: 1
        target: null
        property point last
        onActiveChanged: last = centroid.position
        onCentroidChanged: {
            if (!active)
                return
            var dx = centroid.position.x - last.x, dy = centroid.position.y - last.y
            last = centroid.position
            var m = orthoCamera.horizontalMagnification
            orthoCamera.x -= dx / m
            orthoCamera.y += dy / m
            root.badgeTick++
        }
    }

    // Top views: hinge lines like Placement (orange = now, blue = next,
    // red/magenta = other bends by direction).
    // Integer models: setPose() replaces bendAnchors every frame; an array
    // model would destroy/recreate every delegate per frame.
    Repeater {
        model: root.topView && !root.transitioning ? partGeom.bendAnchors.length : 0
        delegate: Rectangle {
            required property int index
            readonly property var modelData: partGeom.bendAnchors[index] || ({})
            readonly property string role: root.bendRole(modelData)
            readonly property var ends: {
                root.badgeTick
                return [root.screenOf(modelData.sx, modelData.sy, modelData.sz),
                        root.screenOf(modelData.ex, modelData.ey, modelData.ez)]
            }
            readonly property real dx: ends[1].x - ends[0].x
            readonly property real dy: ends[1].y - ends[0].y
            x: ends[0].x
            y: ends[0].y - height / 2
            width: Math.sqrt(dx * dx + dy * dy)
            height: role === "other" ? 3 : 4
            transformOrigin: Item.Left
            rotation: Math.atan2(dy, dx) * 180 / Math.PI
            antialiasing: true
            color: role === "now" ? "#f59e0b" : role === "next" ? "#3b82f6"
                 : (String(modelData.direction).indexOf("DOWN") === 0 ? "#d946ef" : "#dc2626")
        }
    }

    // Bend badges (Unfold .label3d) at each hinge midpoint.
    // Top views: tooling segment widths on the die / punch front face.
    Repeater {
        model: root.showInfo && !root.transitioning ? root.segmentLabels : []
        delegate: Rectangle {
            required property var modelData
            readonly property point screen: {
                root.badgeTick
                var p = root.screenOf(modelData.x, punchNode.y / root.unitScale + modelData.y, modelData.z)
                return Qt.point(p.x, p.y)
            }
            visible: screen.x >= 0 && screen.y >= 0 && screen.x <= root.width && screen.y <= root.height
            x: screen.x - width / 2
            y: screen.y - height / 2
            width: segText.implicitWidth + 10
            height: segText.implicitHeight + 4
            radius: height / 2
            color: "#f7ffffff"
            border.width: 1
            border.color: modelData.kind === "punch" ? "#8fabcc" : "#ba956d"
            Text {
                id: segText
                anchors.centerIn: parent
                text: modelData.label
                color: "#0f172a"
                font.pixelSize: 11
                font.bold: true
            }
        }
    }

    Repeater {
        model: root.canvas && root.canvas.liveBendBadgesVisible ? partGeom.bendAnchors.length : 0
        delegate: Rectangle {
            required property int index
            readonly property var modelData: partGeom.bendAnchors[index] || ({})
            readonly property string role: root.bendRole(modelData)
            readonly property point screen: {
                root.badgeTick
                var s = root.unitScale
                var p = view.mapFrom3DScene(Qt.vector3d(modelData.x * s, modelData.y * s, modelData.z * s + root.machineOffsetZ))
                return Qt.point(p.x, p.y)
            }
            visible: root.visible && !root.transitioning && role !== "now" && screen.x >= 0 && screen.y >= 0
                     && screen.x <= root.width && screen.y <= root.height
            x: screen.x - width / 2
            y: screen.y - height / 2
            width: badgeText.implicitWidth + 12
            height: badgeText.implicitHeight + 8
            radius: 4
            color: role === "now" ? "#88dfc9" : role === "next" ? "#dbeafe" : "#db1d3638"
            border.width: 1
            border.color: role === "next" ? "#3b82f6" : "#628d85"
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: modelData.label + (parent.role === "now" ? " NOW"
                                         : parent.role === "next" ? " NEXT" : "")
                color: parent.role === "now" ? "#133d32" : parent.role === "next" ? "#1d4ed8" : "#adedd7"
                font.pixelSize: 11
                font.bold: modelData.active
            }
        }
    }

    // Active bend chip: fixed top-left so NOW never covers the bend zone.
    Rectangle {
        visible: root.visible && !root.transitioning && root.activeBendLabel !== ""
                 && root.canvas && root.canvas.liveBendBadgesVisible
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 8
        radius: 4
        color: "#cc88dfc9"
        border.width: 1
        border.color: "#628d85"
        width: nowText.implicitWidth + 12
        height: nowText.implicitHeight + 6
        Text {
            id: nowText
            anchors.centerIn: parent
            text: root.activeBendLabel + " NOW"
            color: "#133d32"
            font.pixelSize: 11
            font.bold: true
        }
    }

    // Camera buttons: vertical strip on the left (below the NOW badge).
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 40
        anchors.leftMargin: 6
        color: "#d91a2a38"
        radius: 5
        border.color: "#30404f"
        width: viewRow.implicitWidth + 6
        height: viewRow.implicitHeight + 6
        // Groups: framing | camera view | overlays. Thin dividers between them.
        Column {
            id: viewRow
            anchors.centerIn: parent
            spacing: 4
            Repeater {
                model: [
                    { label: qsTr("All"), fit: false },
                    { label: qsTr("Part"), fit: true },
                    { sep: true },
                    { label: qsTr("Top"), mode: "top" },
                    { label: qsTr("Ortho"), mode: "top-ortho" },
                    { label: qsTr("R"), mode: "side-right" },
                    { label: qsTr("L"), mode: "side-left" },
                    { label: qsTr("3D"), mode: "iso" },
                    { sep: true },
                    { label: qsTr("Tags"), badges: true },
                    { label: qsTr("Punch"), ghost: true }
                ]
                delegate: Item {
                    required property var modelData
                    readonly property bool isSep: modelData.sep === true
                    readonly property bool pressed: modelData.ghost ? !root.ghostTooling : modelData.badges ? (root.canvas ? root.canvas.liveBendBadgesVisible : false)
                        : modelData.info ? root.showInfo
                        : modelData.mode !== undefined
                        ? root.viewMode === modelData.mode
                        : root.partOnly === modelData.fit
                    width: 56
                    height: isSep ? 1 : btnText.implicitHeight + 16
                    Rectangle {
                        anchors.fill: parent
                        visible: parent.isSep
                        anchors.leftMargin: 3
                        anchors.rightMargin: 3
                        color: "#3e5365"
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: !parent.isSep
                        radius: 5
                        color: parent.pressed ? "#244841" : (btnMouse.containsMouse ? "#314a5d" : "#243443")
                        border.width: 1
                        border.color: parent.pressed ? "#86f3d2" : "#3e5365"
                        Text {
                            id: btnText
                            anchors.centerIn: parent
                            text: modelData.label || ""
                            color: parent.parent.pressed ? "#c6fff0" : "#cbdce8"
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: btnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !parent.parent.isSep
                            onClicked: {
                                if (modelData.ghost) {
                                    if (root.canvas)
                                        root.canvas.toolingAppearanceToggleRequested()
                                } else if (modelData.badges) {
                                    if (root.canvas)
                                        root.canvas.liveBendBadgesVisible = !root.canvas.liveBendBadgesVisible
                                } else if (modelData.info) {
                                    root.showInfo = !root.showInfo
                                } else if (modelData.mode !== undefined) {
                                    root.setViewMode(modelData.mode)
                                } else {
                                    root.fitView(modelData.fit)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        color: "#93a8b9"
        font.pixelSize: 11
        text: "3D  part " + partGeom.triangleCount + " tri  " + root.lastFrameMs.toFixed(2) + " ms"
    }
}
