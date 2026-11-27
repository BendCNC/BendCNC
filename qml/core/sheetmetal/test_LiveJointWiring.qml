// test_LiveJointWiring.qml — Phase 3.2 self-test for the live joint/contact graph
// wiring used by RunExecutionCanvas.qml.
//
// Verifies the data contract the canvas relies on: Qt-shaped orthogonalPanels
// ({corners:[{x,r}], bend, branch, label, badgeKey, labelPoint:{x,r}}) adapted into
// the LivePlacementJointMap / LiveBranchContactMapBuilder shape, plus the resolver
// closures (placementLineResolver / sameAxisResolver / liveJointPointResolver /
// parentIdentityResolver / visibleRootResolver / contactBuilder).
//
// Run: $env:QML_XHR_ALLOW_FILE_READ=1; C:\Qt\6.10.1\mingw_64\bin\qml.exe test_LiveJointWiring.qml

import QtQuick 2.15
import "LivePlacementJointMap.js" as LiveJointMap
import "LiveBranchContactMapBuilder.js" as LiveContactMap

Item {
    width: 100; height: 100

    // --- Replica of the canvas adapter (RunExecutionCanvas.liveJointMapPanels) ---
    function adaptPanels(orthogonalPanels) {
        var out = []
        for (var i = 0; orthogonalPanels && i < orthogonalPanels.length; i++) {
            var p = orthogonalPanels[i]
            if (!p || !p.corners || p.corners.length < 3) continue
            var polygon = []
            for (var c = 0; c < p.corners.length; c++) polygon.push({ x: p.corners[c].x, y: p.corners[c].r })
            var anchor = { attachStart: { x: p.corners[0].x, y: p.corners[0].r },
                           attachEnd: { x: p.corners[1].x, y: p.corners[1].r } }
            out.push({
                polygon: polygon,
                anchor: anchor,
                label: p.label,
                bendId: p.bend.id,
                labelPoint: p.labelPoint ? { x: p.labelPoint.x, y: p.labelPoint.r } : null,
                rootAnchorId: p.badgeKey || null
            })
        }
        return out
    }

    function buildResolvers(data, orthogonalPanels, scene) {
        var lineById = ({})
        var projected = data.projectedBends || []
        for (var i = 0; i < projected.length; i++) {
            var pb = projected[i]
            if (pb && pb.bend && pb.start && pb.end)
                lineById[pb.bend.id] = { start: { x: pb.start.x, y: pb.start.y }, end: { x: pb.end.x, y: pb.end.y } }
        }
        var pointById = ({})
        for (var pi = 0; orthogonalPanels && pi < orthogonalPanels.length; pi++) {
            var pan = orthogonalPanels[pi]
            if (pan && pan.bend && pan.labelPoint && pointById[pan.bend.id] === undefined)
                pointById[pan.bend.id] = { x: pan.labelPoint.x, y: pan.labelPoint.r }
        }
        var currentAxis = data.currentBend ? String(data.currentBend.axis || "X").toUpperCase() : "X"
        return {
            placementLineResolver: function (bend) { return lineById[bend.id] || null },
            sameAxisResolver: function (bend) {
                var src = bend && bend.source ? bend.source : bend
                return String((src && src.axis) || "X").toUpperCase() === currentAxis
            },
            liveJointPointResolver: function (bend) {
                var pt = pointById[bend.id]
                if (pt) return pt
                var line = lineById[bend.id]
                return line ? { x: (line.start.x + line.end.x) / 2, y: (line.start.y + line.end.y) / 2 } : null
            },
            parentIdentityResolver: function (bend) {
                var src = bend && bend.source ? bend.source : bend
                var pid = src ? (src.parentExactIdentity || "") : ""
                return pid && String(pid).length > 0 ? String(pid) : null
            },
            visibleRootResolver: function () {
                return LiveJointMap.resolveVisibleCompletedRootIdentities(scene, scene ? scene.currentBend : null)
            },
            contactBuilder: function (panels, joints) {
                var adapted = adaptPanels(panels)
                var contacts = LiveContactMap.build(adapted, joints)
                return { contacts: contacts, contactsByIdentity: LiveContactMap.indexByIdentity(contacts) }
            }
        }
    }

    function sceneData(bends, current) {
        var mapped = [], byId = ({})
        for (var i = 0; i < bends.length; i++) {
            var b = bends[i]
            var e = { id: b.id, sequenceHint: b.sequenceHint, closestSide: b.closestSide,
                      midXIn: b.midXIn || 0, midYIn: b.midYIn || 0,
                      bendLineInstanceId: b.bendLineInstanceId || "", source: b }
            mapped.push(e); byId[e.id] = e
        }
        return { currentBend: current, bends: mapped, bendById: byId, topologySnapshot: null }
    }

    Component.onCompleted: {
        var pass = 0, total = 0
        function check(name, cond) { total++; if (cond) { pass++; console.log("PASS  " + name) } else console.log("FAIL  " + name) }
        function approx(a, b) { return Math.abs(a - b) < 1e-6 }

        // Two bends: B1 (completed, sequence 1) and B2 (current, sequence 2).
        var bendB1 = { id: 1, sequenceHint: 1, closestSide: "NEG", axis: "X", midXIn: 0, midYIn: 1.0 }
        var bendB2 = { id: 2, sequenceHint: 2, closestSide: "POS", axis: "X", midXIn: 0, midYIn: 2.0 }
        var bends = [bendB1, bendB2]
        var current = { id: 2, sequenceHint: 2, closestSide: "POS", axis: "X" }

        // Qt-shaped panels (corners:[{x,r}]). One panel for the current bend B2.
        var orthogonalPanels = [
            {
                bend: bendB1, branch: { flangeId: "F1" }, label: "F1", badgeKey: "B1:F1",
                labelPoint: { x: 0.5, r: 1.0 },
                corners: [ { x: 0, r: 0.9 }, { x: 1, r: 0.9 }, { x: 1, r: 1.1 }, { x: 0, r: 1.1 } ],
                completed: true, current: false, down: false
            },
            {
                bend: bendB2, branch: { flangeId: "F2" }, label: "F2", badgeKey: "B2:F2",
                labelPoint: { x: 0.5, r: 2.0 },
                corners: [ { x: 0, r: 1.9 }, { x: 1, r: 1.9 }, { x: 1, r: 2.1 }, { x: 0, r: 2.1 } ],
                completed: false, current: true, down: false
            }
        ]

        var data = {
            currentBend: current,
            preview: { bends: bends },
            projectedBends: [
                { bend: bendB1, start: { x: -2, y: 1.0 }, end: { x: 2, y: 1.0 } },
                { bend: bendB2, start: { x: -2, y: 2.0 }, end: { x: 2, y: 2.0 } }
            ],
            topologySnapshot: null
        }

        // --- Adapter ---
        var adapted = adaptPanels(orthogonalPanels)
        check("adapter maps 2 panels", adapted.length === 2)
        check("adapter polygon uses y=r", approx(adapted[0].polygon[0].y, 0.9))
        check("adapter anchor attachStart=corner0", approx(adapted[0].anchor.attachStart.y, 0.9))
        check("adapter labelPoint y=r", approx(adapted[1].labelPoint.y, 2.0))
        check("adapter bendId", adapted[1].bendId === 2)
        check("adapter rootAnchorId from badgeKey", adapted[0].rootAnchorId === "B1:F1")

        // --- Joint graph ---
        var scene = sceneData(bends, current)
        var resolvers = buildResolvers(data, orthogonalPanels, scene)
        var graph = LiveJointMap.build(scene, orthogonalPanels, resolvers)

        check("graph has joints array", graph && Array.isArray(graph.joints))
        // Both bends are <= current sequence -> 2 joints.
        check("2 joints (seq<=current)", graph.joints.length === 2)

        var j1 = null, j2 = null
        for (var i = 0; i < graph.joints.length; i++) {
            if (graph.joints[i].bendId === 1) j1 = graph.joints[i]
            if (graph.joints[i].bendId === 2) j2 = graph.joints[i]
        }
        check("joint for B1 exists", j1 !== null)
        check("joint for B2 exists", j2 !== null)
        check("B1 livePoint from panel labelPoint x", j1 && approx(j1.livePoint.x, 0.5))
        check("B1 livePoint from panel labelPoint y=r", j1 && approx(j1.livePoint.y, 1.0))
        check("B2 livePoint from panel labelPoint", j2 && approx(j2.livePoint.x, 0.5) && approx(j2.livePoint.y, 2.0))
        check("B1 placementStart from projectedBends", j1 && approx(j1.placementStart.x, -2) && approx(j1.placementStart.y, 1.0))
        check("B2 projectionKind SEGMENT (same axis X)", j2 && j2.projectionKind === "SEGMENT")
        check("B2 visibleSide normalized POS", j2 && j2.visibleSide === "POS")
        check("B1 visibleSide normalized NEG", j1 && j1.visibleSide === "NEG")

        // --- Current-bend-only filter (renderer behavior) ---
        var currentId = current.id
        var drawn = 0
        for (var d = 0; d < graph.joints.length; d++)
            if (graph.joints[d].livePoint && graph.joints[d].bendId === currentId) drawn++
        check("only current bend drawn (1 dot)", drawn === 1)

        // --- Contacts ---
        check("graph has contacts array", graph && Array.isArray(graph.contacts))
        check("contactsByExactIdentity is object", graph && typeof graph.contactsByExactIdentity === "object")

        // --- Empty / defensive ---
        var empty = LiveJointMap.build(null, [], resolvers)
        check("null data -> empty graph", empty && empty.joints.length === 0)

        // --- Phase 3.3: skeleton edge resolvers (public wrappers) ---
        var skelPanel = adapted[1]   // current bend panel, polygon [{0,1.9},{1,1.9},{1,2.1},{0,2.1}]
        var mountEdge = LiveContactMap.resolveVisiblePanelMountEdge(skelPanel.polygon, skelPanel.anchor)
        check("mount edge resolved", mountEdge !== null && mountEdge.a && mountEdge.b)
        var freeEdge = LiveContactMap.resolveVisiblePanelFreeEdge(skelPanel.polygon, skelPanel.anchor)
        check("free edge resolved", freeEdge !== null && freeEdge.a && freeEdge.b)
        // mount edge falls back to anchor attach (corner0->corner1) when polygon has no clearer edge
        check("mount edge near anchor y", mountEdge && approx(mountEdge.a.y, 1.9))
        // free edge should be the opposite (far) edge, y ~ 2.1
        check("free edge far y", freeEdge && (approx(freeEdge.a.y, 2.1) || approx(freeEdge.b.y, 2.1)))

        var mid = LiveContactMap.midpoint({ x: 0, y: 0 }, { x: 2, y: 4 })
        check("midpoint", approx(mid.x, 1) && approx(mid.y, 2))
        var cp = LiveContactMap.closestPointOnSegment({ x: 0.5, y: 5 }, { x: 0, y: 2.1 }, { x: 1, y: 2.1 })
        check("closestPointOnSegment clamps to segment", approx(cp.x, 0.5) && approx(cp.y, 2.1))
        var cpEnd = LiveContactMap.closestPointOnSegment({ x: 5, y: 5 }, { x: 0, y: 2.1 }, { x: 1, y: 2.1 })
        check("closestPointOnSegment clamps past end", approx(cpEnd.x, 1.0) && approx(cpEnd.y, 2.1))

        // skeleton edges are distinct (mount != free) for a real panel
        check("mount and free edges distinct", mountEdge && freeEdge && !(approx(mountEdge.a.y, freeEdge.a.y) && approx(mountEdge.b.y, freeEdge.b.y)))

        console.log("RESULT " + pass + "/" + total)
        Qt.quit()
    }
}
