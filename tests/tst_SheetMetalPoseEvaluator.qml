import QtQuick
import QtTest
import "../qml/core/sheetmetal/SheetMetalPoseEvaluator.js" as Evaluator

Item {
    id: root
    width: 320
    height: 240

    TestCase {
        name: "SheetMetalPoseEvaluatorTests"
        when: windowShown

        function point(x, y) {
            return { x_in: x, y_in: y }
        }

        function panel(id, parentId, ownerId, points, holes) {
            return {
                panelId: id,
                parentPanelId: parentId,
                ownerBendId: ownerId,
                geometryAuthority: "planar-subdivision-v5",
                outerLoop: points,
                holeLoops: holes || []
            }
        }

        function edge(id, sourceId, sequence, parentId, childId, start, end, direction, side) {
            return {
                bendId: id,
                sourceBendId: sourceId,
                sequenceHint: sequence,
                parentPanelId: parentId,
                childPanelId: childId,
                hingeStart: start,
                hingeEnd: end,
                hingeSegments: [[start, end]],
                bendAngleDegrees: 90,
                foldAngleDegrees: 90,
                insideRadius_in: 0.1,
                thickness_in: 0.1,
                kFactor: 0.44,
                childSideSign: side,
                direction: direction
            }
        }

        function verticalGraph(direction, side) {
            return {
                schemaVersion: 5,
                rootPanelId: "root",
                geometryAuthority: "flat-pattern-planar-subdivision-v5",
                diagnostics: {
                    status: "qualified",
                    rootSelectionAmbiguous: false,
                    expectedMaterialArea_in2: 3.91,
                    partitionArea_in2: 3.91,
                    partitionAreaError_in2: 0
                },
                materialBoundary: {
                    outerLoop: [point(0, 0), point(2, 0), point(2, 2), point(0, 2)],
                    holeLoops: [[point(1.2, 0.5), point(1.5, 0.5), point(1.5, 0.8), point(1.2, 0.8)]]
                },
                panels: [
                    panel("root", null, null, [point(0, 0), point(1, 0), point(1, 2), point(0, 2)]),
                    panel("p1", "root", "bend-1", [point(1, 0), point(2, 0), point(2, 2), point(1, 2)],
                          [[point(1.2, 0.5), point(1.5, 0.5), point(1.5, 0.8), point(1.2, 0.8)]])
                ],
                bendEdges: [edge("e1", "bend-1", 1, "root", "p1", point(1, 0), point(1, 2), direction, side)]
            }
        }

        function horizontalGraph() {
            return {
                schemaVersion: 5,
                rootPanelId: "root",
                geometryAuthority: "flat-pattern-planar-subdivision-v5",
                diagnostics: {
                    status: "qualified",
                    rootSelectionAmbiguous: false,
                    expectedMaterialArea_in2: 4.0,
                    partitionArea_in2: 4.0,
                    partitionAreaError_in2: 0
                },
                materialBoundary: {
                    outerLoop: [point(0, 0), point(2, 0), point(2, 2), point(0, 2)],
                    holeLoops: []
                },
                panels: [
                    panel("root", null, null, [point(0, 0), point(2, 0), point(2, 1), point(0, 1)]),
                    panel("p1", "root", "bend-1", [point(0, 1), point(2, 1), point(2, 2), point(0, 2)])
                ],
                bendEdges: [edge("e1", "bend-1", 1, "root", "p1", point(0, 1), point(2, 1), "UP", 1)]
            }
        }

        function multilevelGraph() {
            let graph = verticalGraph("UP", 1)
            graph.panels.push(panel("p2", "p1", "bend-2", [point(2, 0), point(3, 0), point(3, 2), point(2, 2)]))
            graph.bendEdges.push(edge("e2", "bend-2", 2, "p1", "p2", point(2, 0), point(2, 2), "DOWN", -1))
            graph.materialBoundary.outerLoop = [point(0, 0), point(3, 0), point(3, 2), point(0, 2)]
            graph.diagnostics.expectedMaterialArea_in2 = 5.91
            graph.diagnostics.partitionArea_in2 = 5.91
            return graph
        }

        function nestedDownVGraph() {
            return {
                schemaVersion: 5,
                rootPanelId: "root",
                geometryAuthority: "flat-pattern-planar-subdivision-v5",
                diagnostics: {
                    status: "qualified",
                    rootSelectionAmbiguous: false,
                    expectedMaterialArea_in2: 20,
                    partitionArea_in2: 20,
                    partitionAreaError_in2: 0
                },
                materialBoundary: {
                    outerLoop: [point(0, 0), point(10, 0), point(10, 2), point(0, 2)],
                    holeLoops: []
                },
                panels: [
                    panel("root", null, null, [point(2, 0), point(8, 0), point(8, 2), point(2, 2)]),
                    panel("left", "root", "bend-3", [point(1, 0), point(2, 0), point(2, 2), point(1, 2)]),
                    panel("leftOuter", "left", "bend-1", [point(0, 0), point(1, 0), point(1, 2), point(0, 2)]),
                    panel("right", "root", "bend-4", [point(8, 0), point(9, 0), point(9, 2), point(8, 2)]),
                    panel("rightOuter", "right", "bend-2", [point(9, 0), point(10, 0), point(10, 2), point(9, 2)])
                ],
                bendEdges: [
                    edge("e3", "bend-3", 3, "root", "left", point(2, 2), point(2, 0), "DOWN", -1),
                    edge("e1", "bend-1", 1, "left", "leftOuter", point(1, 0), point(1, 2), "UP", 1),
                    edge("e4", "bend-4", 4, "root", "right", point(8, 2), point(8, 0), "DOWN", 1),
                    edge("e2", "bend-2", 2, "right", "rightOuter", point(9, 0), point(9, 2), "UP", -1)
                ]
            }
        }

        function bends() {
            return {
                "bend-1": { id: "bend-1", sequenceHint: 1 },
                "bend-2": { id: "bend-2", sequenceHint: 2 }
            }
        }

        function nestedDownVBends() {
            return {
                "bend-1": { id: "bend-1", sequenceHint: 1 },
                "bend-2": { id: "bend-2", sequenceHint: 2 },
                "bend-3": { id: "bend-3", sequenceHint: 3 },
                "bend-4": { id: "bend-4", sequenceHint: 4 }
            }
        }

        function close(actual, expected) {
            return Math.abs(actual - expected) < 1.0e-8
        }

        function worldParentCentroid(compiled, panelId) {
            let posed = Evaluator.poseCompiled(compiled, panelId)
            let result = { x: 0, y: 0, z: 0 }
            for (let pointIndex = 0; pointIndex < posed.worldPolygon.length; pointIndex++) {
                result.x += posed.worldPolygon[pointIndex].x
                result.y += posed.worldPolygon[pointIndex].y
                result.z += posed.worldPolygon[pointIndex].z
            }
            result.x /= posed.worldPolygon.length
            result.y /= posed.worldPolygon.length
            result.z /= posed.worldPolygon.length
            return result
        }

        function dotFromOrigin(pointValue, frame) {
            return (pointValue.x - frame.origin.x) * frame.horizontal.x
                    + (pointValue.y - frame.origin.y) * frame.horizontal.y
                    + (pointValue.z - frame.origin.z) * frame.horizontal.z
        }

        function verticalDotFromOrigin(pointValue, frame) {
            return (pointValue.x - frame.origin.x) * frame.vertical.x
                + (pointValue.y - frame.origin.y) * frame.vertical.y
                + (pointValue.z - frame.origin.z) * frame.vertical.z
        }

        function test_currentPhaseControlsOnlyCurrentBend() {
            let phases = [0, 45, 90]
            for (let i = 0; i < phases.length; i++) {
                let displayed = phases[i]
                let compiled = Evaluator.compile(verticalGraph("UP", 1), bends(), 1, function() { return displayed })
                verify(!!compiled, "Object exists")
                verify(close(compiled.anglesByChildId.p1, displayed * Math.PI / 180))
            }
        }

        function test_upDownAndChildSideControlRotationSign() {
            let up = Evaluator.compile(verticalGraph("UP", 1), bends(), 1, function() { return 90 })
            let down = Evaluator.compile(verticalGraph("DOWN", 1), bends(), 1, function() { return 90 })
            let negativeSide = Evaluator.compile(verticalGraph("UP", -1), bends(), 1, function() { return 90 })
            let upPoint = Evaluator.poseCompiled(up, "p1").worldPolygon[1]
            let downPoint = Evaluator.poseCompiled(down, "p1").worldPolygon[1]
            let negativePoint = Evaluator.poseCompiled(negativeSide, "p1").worldPolygon[1]

            verify(close(upPoint.z, -1))
            verify(close(downPoint.z, 1))
            verify(close(negativePoint.z, 1))
        }

        function test_horizontalAndVerticalAxesRotateInThreeDimensions() {
            let vertical = Evaluator.compile(verticalGraph("UP", 1), bends(), 1, function() { return 90 })
            let horizontal = Evaluator.compile(horizontalGraph(), bends(), 1, function() { return 90 })
            let verticalPoint = Evaluator.poseCompiled(vertical, "p1").worldPolygon[1]
            let horizontalPoint = Evaluator.poseCompiled(horizontal, "p1").worldPolygon[2]

            verify(close(verticalPoint.z, -1))
            verify(close(horizontalPoint.z, 1))
        }

        function test_multilevelCompositionAndFutureVisibility() {
            let atFirst = Evaluator.compile(multilevelGraph(), bends(), 1, function() { return 45 })
            let atSecond = Evaluator.compile(multilevelGraph(), bends(), 2, function() { return 30 })

            verify(close(atFirst.anglesByChildId.p1, Math.PI / 4))
            verify(close(atFirst.anglesByChildId.p2, 0))
            compare(Evaluator.poseVisiblePanels(atFirst, 1).length, 1)
            verify(close(atSecond.anglesByChildId.p1, Math.PI / 2))
            verify(close(atSecond.anglesByChildId.p2, Math.PI / 6))
            compare(Evaluator.poseVisiblePanels(atSecond, 2).length, 2)
            compare(Evaluator.poseAllPanels(atSecond).length, 3)
        }

        function test_holesAndMountEdgeUseSameRigidPose() {
            let compiled = Evaluator.compile(verticalGraph("UP", 1), bends(), 1, function() { return 90 })
            let posed = Evaluator.poseCompiled(compiled, "p1")

            compare(posed.worldHoleLoops.length, 1)
            compare(posed.worldHoleLoops[0].length, 4)
            compare(posed.worldMountEdge.length, 2)
            verify(close(posed.worldMountEdge[0].x, 1))
            verify(close(posed.worldMountEdge[0].z, 0))
            verify(close(posed.worldMountEdge[1].x, 1))
            verify(close(posed.worldMountEdge[1].z, 0))
            verify(close(posed.worldHoleLoops[0][0].z, -0.2))
        }

        function test_rootExposesIncidentHingeAsPosedAttachment() {
            let compiled = Evaluator.compile(verticalGraph("UP", 1), bends(), 1, function() { return 90 })
            let posed = Evaluator.poseCompiled(compiled, "root")

            compare(posed.worldMountEdge.length, 0)
            compare(posed.worldAttachmentEdges.length, 1)
            compare(posed.worldAttachmentEdges[0].edgeId, "e1")
            compare(posed.worldAttachmentEdges[0].role, "child")
            verify(close(posed.worldAttachmentEdges[0].start.x, 1))
            verify(close(posed.worldAttachmentEdges[0].start.z, 0))
            verify(close(posed.worldAttachmentEdges[0].end.x, 1))
            verify(close(posed.worldAttachmentEdges[0].end.z, 0))
        }

        function test_hingeSectionFrameIsFiniteForUpAndDown() {
            let directions = ["UP", "DOWN"]
            for (let i = 0; i < directions.length; i++) {
                let compiled = Evaluator.compile(verticalGraph(directions[i], 1), bends(), 1, function() { return 90 })
                let frame = Evaluator.hingeSectionFrame(compiled, compiled.model.edges[0])
                verify(!!frame, "Object exists")
                verify(isFinite(frame.horizontal.x))
                verify(isFinite(frame.horizontal.y))
                verify(isFinite(frame.horizontal.z))
                verify(isFinite(frame.vertical.x))
                verify(isFinite(frame.vertical.y))
                verify(isFinite(frame.vertical.z))
            }
        }

        function test_hingeSectionFrameKeepsParentOnPositiveDisplaySide() {
            let graph = verticalGraph("UP", 1)
            let compiled = Evaluator.compile(graph, bends(), 1, function() { return 0 })
            let frame = Evaluator.hingeSectionFrame(compiled, compiled.model.edges[0])
            let parentCentroid = worldParentCentroid(compiled, "root")

            verify(dotFromOrigin(parentCentroid, frame) > 0)
        }

        function test_nestedDownBendsRiseAsOperationV() {
            let graph = nestedDownVGraph()
            let bendMap = nestedDownVBends()
            for (let sequence of [3, 4]) {
                let compiled = Evaluator.compile(graph, bendMap, sequence, function() { return 60 })
                let activeEdge = null
                for (let edgeIndex = 0; edgeIndex < compiled.model.edges.length; edgeIndex++) {
                    if (compiled.model.edges[edgeIndex].sequenceHint === sequence) {
                        activeEdge = compiled.model.edges[edgeIndex]
                        break
                    }
                }
                verify(!!activeEdge)
                let frame = Evaluator.hingeSectionFrame(compiled, activeEdge)
                verify(!!frame)
                let parentCentroid = worldParentCentroid(compiled, activeEdge.parentPanelId)
                let childCentroid = worldParentCentroid(compiled, activeEdge.childPanelId)

                verify(verticalDotFromOrigin(parentCentroid, frame) > 0,
                       "B" + sequence + " parent leg must rise from the die")
                verify(verticalDotFromOrigin(childCentroid, frame) > 0,
                       "B" + sequence + " child leg must rise from the die")
            }
        }

        function test_reversedHingeEndpointsDoNotMirrorParentDisplaySide() {
            let forwardGraph = verticalGraph("UP", 1)
            let reversedGraph = verticalGraph("UP", 1)
            let reversedEdge = reversedGraph.bendEdges[0]
            let originalStart = reversedEdge.hingeStart
            reversedEdge.hingeStart = reversedEdge.hingeEnd
            reversedEdge.hingeEnd = originalStart
            reversedEdge.hingeSegments = [[reversedEdge.hingeStart, reversedEdge.hingeEnd]]

            let forward = Evaluator.compile(forwardGraph, bends(), 1, function() { return 0 })
            let reversed = Evaluator.compile(reversedGraph, bends(), 1, function() { return 0 })
            let forwardFrame = Evaluator.hingeSectionFrame(forward, forward.model.edges[0])
            let reversedFrame = Evaluator.hingeSectionFrame(reversed, reversed.model.edges[0])

            verify(dotFromOrigin(worldParentCentroid(forward, "root"), forwardFrame) > 0)
            verify(dotFromOrigin(worldParentCentroid(reversed, "root"), reversedFrame) > 0)
        }

        function test_invalidGraphDoesNotCompile() {
            let graph = verticalGraph("UP", 1)
            graph.bendEdges[0].hingeEnd = graph.bendEdges[0].hingeStart
            compare(Evaluator.compile(graph, bends(), 1, function() { return 90 }), null)
        }
    }
}