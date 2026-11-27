import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    id: root
    width: 640
    height: 480

    TestCase {
        name: "RunExecutionCanvasV5Tests"
        when: windowShown

        function point(x, y) {
            return { x_in: x, y_in: y }
        }

        function bend() {
            return {
                id: "bend-1",
                sequenceHint: 1,
                angle_deg: 90,
                direction: "UP",
                closestSide: "NEG",
                axis: "Y",
                start_x_in: 4,
                start_y_in: 0,
                end_x_in: 4,
                end_y_in: 2,
                mid_x_in: 4,
                mid_y_in: 1,
                thickness: 0.1,
                thickness_in: 0.1,
                radius_in: 0.1,
                vdieValue: 1.0
            }
        }

        function panel(id, parentId, ownerBendId, x0, x1, holeLoops) {
            return {
                panelId: id,
                parentPanelId: parentId,
                ownerBendId: ownerBendId,
                geometryAuthority: "planar-subdivision-v5",
                outerLoop: [point(x0, 0), point(x1, 0), point(x1, 2), point(x0, 2)],
                holeLoops: holeLoops || []
            }
        }

        function qualifiedPreview() {
            let activeBend = bend()
            return {
                part: { name: "IN-MEMORY-V5" },
                generator: {
                    id: "com.bendcnc.export",
                    version: "1.1.0",
                    revision: "2026-08-06-compound-operation-relations-v5",
                    topologySchemaVersion: 5
                },
                flatPattern: {
                    width_in: 6,
                    length_in: 2,
                    preview2d: {
                        sourceFace: "topFace",
                        surfaceType: "plane",
                        loops: [
                            { outer: true, points: [point(0, 0), point(6, 0), point(6, 2), point(0, 2), point(0, 0)] },
                            { outer: false, points: [point(1, 0.5), point(1.5, 0.5), point(1.5, 1), point(1, 1), point(1, 0.5)] }
                        ],
                        loopIntegrity: [
                            { loopIndex: 0, discontinuityCount: 0, closureGap_in: 0 },
                            { loopIndex: 1, discontinuityCount: 0, closureGap_in: 0 }
                        ]
                    }
                },
                bends: [activeBend],
                sheetMetalGraph: {
                    schemaVersion: 5,
                    rootPanelId: "root",
                    geometryAuthority: "flat-pattern-planar-subdivision-v5",
                    diagnostics: {
                        status: "qualified",
                        rootSelectionAmbiguous: false,
                        expectedMaterialArea_in2: 11.75,
                        partitionArea_in2: 11.75,
                        partitionAreaError_in2: 0
                    },
                    materialBoundary: {
                        outerLoop: [point(0, 0), point(6, 0), point(6, 2), point(0, 2)],
                        holeLoops: [[point(1, 0.5), point(1.5, 0.5), point(1.5, 1), point(1, 1)]]
                    },
                    panels: [
                        panel("root", null, null, 0, 4, [[point(1, 0.5), point(1.5, 0.5), point(1.5, 1), point(1, 1)]]),
                        panel("p1", "root", "bend-1", 4, 6)
                    ],
                    bendEdges: [{
                        bendId: "edge-1",
                        sourceBendId: "bend-1",
                        sequenceHint: 1,
                        parentPanelId: "root",
                        childPanelId: "p1",
                        hingeStart: point(4, 0),
                        hingeEnd: point(4, 2),
                        hingeSegments: [[point(4, 0), point(4, 2)]],
                        bendAngleDegrees: 90,
                        foldAngleDegrees: 90,
                        insideRadius_in: 0.1,
                        thickness_in: 0.1,
                        kFactor: 0.44,
                        childSideSign: 1,
                        direction: "UP"
                    }]
                }
            }
        }

        function mixedAxisStarPreview() {
            let preview = qualifiedPreview()
            let boundary = [
                point(1, 0), point(5, 0), point(5, 1), point(6, 1),
                point(6, 3), point(5, 3), point(5, 4), point(1, 4),
                point(1, 3), point(0, 3), point(0, 1), point(1, 1)
            ]
            preview.flatPattern.width_in = 6
            preview.flatPattern.length_in = 4
            preview.flatPattern.preview2d.loops = [{
                outer: true,
                points: boundary.concat([boundary[0]])
            }]
            preview.flatPattern.preview2d.loopIntegrity = [
                { loopIndex: 0, discontinuityCount: 0, closureGap_in: 0 }
            ]
            preview.sheetMetalGraph.materialBoundary = {
                outerLoop: boundary,
                holeLoops: []
            }
            preview.sheetMetalGraph.panels = [
                {
                    panelId: "root", parentPanelId: null, ownerBendId: null,
                    geometryAuthority: "planar-subdivision-v5",
                    outerLoop: [point(1, 1), point(5, 1), point(5, 3), point(1, 3)],
                    holeLoops: []
                },
                panel("p1", "root", "bend-1", 1, 5),
                {
                    panelId: "p2", parentPanelId: "root", ownerBendId: "bend-2",
                    geometryAuthority: "planar-subdivision-v5",
                    outerLoop: [point(1, 3), point(5, 3), point(5, 4), point(1, 4)],
                    holeLoops: []
                },
                {
                    panelId: "p3", parentPanelId: "root", ownerBendId: "bend-3",
                    geometryAuthority: "planar-subdivision-v5",
                    outerLoop: [point(0, 1), point(1, 1), point(1, 3), point(0, 3)],
                    holeLoops: []
                },
                {
                    panelId: "p4", parentPanelId: "root", ownerBendId: "bend-4",
                    geometryAuthority: "planar-subdivision-v5",
                    outerLoop: [point(5, 1), point(6, 1), point(6, 3), point(5, 3)],
                    holeLoops: []
                }
            ]
            // Replace p1's helper-generated y range with the bottom flange.
            preview.sheetMetalGraph.panels[1].outerLoop = [
                point(1, 0), point(5, 0), point(5, 1), point(1, 1)
            ]
            function starEdge(sequence, childId, start, end, side) {
                return {
                    bendId: "edge-" + sequence,
                    sourceBendId: "bend-" + sequence,
                    sequenceHint: sequence,
                    parentPanelId: "root",
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
                    direction: "UP"
                }
            }
            preview.sheetMetalGraph.bendEdges = [
                starEdge(1, "p1", point(1, 1), point(5, 1), -1),
                starEdge(2, "p2", point(5, 3), point(1, 3), 1),
                starEdge(3, "p3", point(1, 3), point(1, 1), 1),
                starEdge(4, "p4", point(5, 1), point(5, 3), 1)
            ]
            preview.sheetMetalGraph.diagnostics.expectedMaterialArea_in2 = 20
            preview.sheetMetalGraph.diagnostics.partitionArea_in2 = 20
            preview.sheetMetalGraph.diagnostics.partitionAreaError_in2 = 0
            preview.bends = []
            for (let bendIndex = 1; bendIndex <= 4; bendIndex++) {
                let value = bend()
                let edgeValue = preview.sheetMetalGraph.bendEdges[bendIndex - 1]
                value.id = "bend-" + bendIndex
                value.sequenceHint = bendIndex
                value.start_x_in = edgeValue.hingeStart.x_in
                value.start_y_in = edgeValue.hingeStart.y_in
                value.end_x_in = edgeValue.hingeEnd.x_in
                value.end_y_in = edgeValue.hingeEnd.y_in
                value.mid_x_in = (value.start_x_in + value.end_x_in) / 2
                value.mid_y_in = (value.start_y_in + value.end_y_in) / 2
                preview.bends.push(value)
            }
            return preview
        }

        function compoundOperationPreview() {
            let preview = qualifiedPreview()
            let relievedBoundary = [
                point(0, 0), point(6, 0), point(6, 1.8), point(4, 1.8),
                point(4, 2.2), point(6, 2.2), point(6, 4), point(0, 4)
            ]
            preview.flatPattern.width_in = 6
            preview.flatPattern.length_in = 4
            preview.flatPattern.preview2d.loops = [{
                outer: true,
                points: relievedBoundary.concat([relievedBoundary[0]])
            }]
            preview.flatPattern.preview2d.loopIntegrity = [
                { loopIndex: 0, discontinuityCount: 0, closureGap_in: 0 }
            ]
            preview.sheetMetalGraph.materialBoundary = {
                outerLoop: relievedBoundary,
                holeLoops: []
            }
            preview.sheetMetalGraph.panels = [
                {
                    panelId: "root", parentPanelId: null, ownerBendId: null,
                    geometryAuthority: "planar-subdivision-v5",
                    outerLoop: [point(0, 0), point(4, 0), point(4, 4), point(0, 4)],
                    holeLoops: []
                },
                {
                    panelId: "p1", parentPanelId: "root", ownerBendId: "bend-1",
                    geometryAuthority: "planar-subdivision-v5",
                    outerLoop: [point(4, 0), point(6, 0), point(6, 1.8), point(4, 1.8)],
                    holeLoops: []
                },
                {
                    panelId: "p2", parentPanelId: "root", ownerBendId: "bend-1",
                    geometryAuthority: "planar-subdivision-v5",
                    outerLoop: [point(4, 2.2), point(6, 2.2), point(6, 4), point(4, 4)],
                    holeLoops: []
                }
            ]
            preview.sheetMetalGraph.bendEdges = []
            for (let relationIndex = 0; relationIndex < 2; relationIndex++) {
                let y0 = relationIndex === 0 ? 0 : 2.2
                let y1 = relationIndex === 0 ? 1.8 : 4
                preview.sheetMetalGraph.bendEdges.push({
                    bendId: "edge-1-" + relationIndex,
                    sourceBendId: "bend-1",
                    sequenceHint: 1,
                    operationRelationIndex: relationIndex,
                    operationRelationCount: 2,
                    parentPanelId: "root",
                    childPanelId: "p" + (relationIndex + 1),
                    hingeStart: point(4, y0), hingeEnd: point(4, y1),
                    hingeSegments: [[point(4, y0), point(4, y1)]],
                    bendAngleDegrees: 90, foldAngleDegrees: 90,
                    insideRadius_in: 0.1, thickness_in: 0.1,
                    kFactor: 0.44, childSideSign: 1, direction: "UP"
                })
            }
            preview.sheetMetalGraph.diagnostics.expectedMaterialArea_in2 = 23.2
            preview.sheetMetalGraph.diagnostics.partitionArea_in2 = 23.2
            preview.sheetMetalGraph.diagnostics.partitionAreaError_in2 = 0
            preview.bends[0].start_y_in = 0
            preview.bends[0].end_y_in = 1.8
            preview.bends[0].mid_y_in = 0.9
            return preview
        }

        function asymmetricPlacementLiveParityPreview(reverseActiveHinge) {
            let preview = qualifiedPreview()
            let boundary = [
                point(0, 0), point(5, 0), point(5, 4),
                point(1, 4), point(1, 3), point(0, 3)
            ]
            let asymmetricHole = [
                point(4.0, 3.3), point(4.4, 3.3),
                point(4.4, 3.5), point(4.0, 3.5)
            ]
            preview.flatPattern.width_in = 5
            preview.flatPattern.length_in = 4
            preview.flatPattern.preview2d.loops = [
                { outer: true, points: boundary.concat([boundary[0]]) },
                { outer: false, points: asymmetricHole.concat([asymmetricHole[0]]) }
            ]
            preview.flatPattern.preview2d.loopIntegrity = [
                { loopIndex: 0, discontinuityCount: 0, closureGap_in: 0 },
                { loopIndex: 1, discontinuityCount: 0, closureGap_in: 0 }
            ]
            preview.sheetMetalGraph.materialBoundary = {
                outerLoop: boundary,
                holeLoops: [asymmetricHole]
            }
            preview.sheetMetalGraph.panels = [
                {
                    panelId: "root", parentPanelId: null, ownerBendId: null,
                    geometryAuthority: "planar-subdivision-v5",
                    outerLoop: [point(1, 0), point(5, 0), point(5, 3), point(1, 3)],
                    holeLoops: []
                },
                {
                    panelId: "p1", parentPanelId: "root", ownerBendId: "bend-1",
                    geometryAuthority: "planar-subdivision-v5",
                    outerLoop: [point(1, 3), point(5, 3), point(5, 4), point(1, 4)],
                    holeLoops: [asymmetricHole]
                },
                {
                    panelId: "p2", parentPanelId: "root", ownerBendId: "bend-2",
                    geometryAuthority: "planar-subdivision-v5",
                    outerLoop: [point(0, 0), point(1, 0), point(1, 3), point(0, 3)],
                    holeLoops: []
                }
            ]
            let activeStart = reverseActiveHinge ? point(1, 3) : point(1, 0)
            let activeEnd = reverseActiveHinge ? point(1, 0) : point(1, 3)
            preview.sheetMetalGraph.bendEdges = [
                {
                    bendId: "edge-1", sourceBendId: "bend-1", sequenceHint: 1,
                    parentPanelId: "root", childPanelId: "p1",
                    hingeStart: point(1, 3), hingeEnd: point(5, 3),
                    hingeSegments: [[point(1, 3), point(5, 3)]],
                    bendAngleDegrees: 90, foldAngleDegrees: 90,
                    insideRadius_in: 0.1, thickness_in: 0.1,
                    kFactor: 0.44, childSideSign: 1, direction: "UP"
                },
                {
                    bendId: "edge-2", sourceBendId: "bend-2", sequenceHint: 2,
                    parentPanelId: "root", childPanelId: "p2",
                    hingeStart: activeStart, hingeEnd: activeEnd,
                    hingeSegments: [[activeStart, activeEnd]],
                    bendAngleDegrees: 90, foldAngleDegrees: 90,
                    insideRadius_in: 0.1, thickness_in: 0.1,
                    kFactor: 0.44, childSideSign: 1, direction: "UP"
                }
            ]
            preview.sheetMetalGraph.diagnostics.expectedMaterialArea_in2 = 18.92
            preview.sheetMetalGraph.diagnostics.partitionArea_in2 = 18.92
            preview.sheetMetalGraph.diagnostics.partitionAreaError_in2 = 0
            let first = bend()
            first.id = "bend-1"
            first.sequenceHint = 1
            first.axis = "X"
            first.closestSide = "POS"
            first.start_x_in = 1
            first.start_y_in = 3
            first.end_x_in = 5
            first.end_y_in = 3
            first.mid_x_in = 3
            first.mid_y_in = 3
            let second = bend()
            second.id = "bend-2"
            second.sequenceHint = 2
            second.axis = "Y"
            second.closestSide = "NEG"
            second.start_x_in = activeStart.x_in
            second.start_y_in = activeStart.y_in
            second.end_x_in = activeEnd.x_in
            second.end_y_in = activeEnd.y_in
            second.mid_x_in = 1
            second.mid_y_in = 1.5
            preview.bends = [first, second]
            return preview
        }

        function createCanvas(preview, extraProperties) {
            let component = Qt.createComponent("../qml/RunExecutionCanvas.qml")
            verify(component.status === Component.Ready, component.errorString())
            let properties = {
                width: root.width,
                height: root.height,
                sceneMode: "LIVE",
                liveProjectionMode: "ISOMETRIC",
                running: false,
                selectedBendIndex: 0,
                selectedBend: preview.bends[0],
                programPreviewJson: JSON.stringify(preview)
            }
            for (let key in extraProperties || {})
                properties[key] = extraProperties[key]
            let canvas = component.createObject(root, properties)
            verify(!!canvas, "Canvas object exists")
            wait(100)
            return canvas
        }

        function pointToSegmentDistance(pointValue, start, end) {
            let dx = end.x - start.x
            let dr = end.r - start.r
            let lengthSquared = dx * dx + dr * dr
            if (lengthSquared <= 1.0e-12)
                return Math.hypot(pointValue.x - start.x, pointValue.r - start.r)
            let parameter = ((pointValue.x - start.x) * dx
                             + (pointValue.r - start.r) * dr) / lengthSquared
            parameter = Math.max(0, Math.min(1, parameter))
            return Math.hypot(pointValue.x - (start.x + parameter * dx),
                              pointValue.r - (start.r + parameter * dr))
        }

        function test_canvasLiveUsesRetainedStaticLayer() {
            let canvas = createCanvas(qualifiedPreview(), {
                sceneMode: "LIVE",
                nativeRenderEnabled: false
            })
            verify(canvas.canvasLiveLayerSplitActive)
            let staticLayer = findChild(canvas, "run-static-live-canvas")
            let dynamicLayer = findChild(canvas, "run-preview-canvas")
            verify(!!staticLayer)
            verify(!!dynamicLayer)
            verify(staticLayer.visible)
            verify(dynamicLayer.visible)

            canvas.sceneMode = "PLACEMENT"
            wait(0)
            verify(!canvas.canvasLiveLayerSplitActive)
            verify(!staticLayer.visible)
            canvas.destroy()
        }

        function test_acceleratedPlacementSelfIntersectionMatchesExhaustiveScan() {
            let canvas = createCanvas(qualifiedPreview())
            let seed = 12345
            function random() {
                seed = (seed * 16807) % 2147483647
                return seed / 2147483647
            }
            function starLoop(count, jitter, snap) {
                let loop = []
                for (let i = 0; i < count; i++) {
                    let angle = i * 2 * Math.PI / count
                    let radius = 10 + (random() - 0.5) * jitter
                    let x = radius * Math.cos(angle)
                    let y = radius * Math.sin(angle)
                    if (snap) {
                        x = Math.round(x * 4) / 4
                        y = Math.round(y * 4) / 4
                    }
                    loop.push({ x: x, y: y })
                }
                return loop
            }
            let cases = []
            for (let trial = 0; trial < 24; trial++) {
                let count = 64 + Math.floor(random() * 400)
                cases.push(starLoop(count, trial % 3 === 0 ? 0.5 : 30, trial % 4 === 1))
            }
            let shared = starLoop(200, 0.5, false)
            shared.splice(100, 0, { x: shared[20].x, y: shared[20].y })
            cases.push(shared)
            let crossing = starLoop(160, 0.5, false)
            let swap = crossing[40]
            crossing[40] = crossing[120]
            crossing[120] = swap
            cases.push(crossing)
            let crossings = 0
            for (let c = 0; c < cases.length; c++) {
                canvas.placementSelfIntersectionState.witness = null
                let expected = canvas.placementLoopSelfIntersectsExhaustive(cases[c])
                canvas.placementSelfIntersectionState.witness = null
                compare(canvas.placementLoopSelfIntersects(cases[c]), expected, "case " + c)
                compare(canvas.placementLoopSelfIntersects(cases[c]), expected, "witness case " + c)
                if (expected)
                    crossings++
            }
            verify(crossings > 0)
            verify(crossings < cases.length)
            canvas.destroy()
        }

        function test_liveCycleHitPreservesResidentInsertionOrder() {
            let canvas = createCanvas(qualifiedPreview())
            canvas.liveFrameCycleCache = ({
                first: { id: "first" },
                second: { id: "second" },
                third: { id: "third" }
            })
            canvas.liveFrameCycleCacheOrder = ["first", "second", "third"]
            let originalOrder = canvas.liveFrameCycleCacheOrder
            let hitsBefore = canvas.liveFrameCycleCacheHits

            compare(canvas.cachedLiveCycleFrame("first").id, "first")
            compare(canvas.liveFrameCycleCacheHits, hitsBefore + 1)
            compare(canvas.liveFrameCycleCacheOrder, originalOrder)
            compare(canvas.liveFrameCycleCacheOrder.join(","),
                    "first,second,third")
            canvas.destroy()
        }

        function test_immediateFrameCachePrecedesCycleLookup() {
            let canvas = createCanvas(qualifiedPreview(), {
                sceneMode: "LIVE",
                simulatedPlayback: true
            })
            let currentFrame = canvas.runRenderFrame.live
            verify(currentFrame.ready)
            verify(currentFrame.visualCacheKey.length > 0)
            let cycleHitsBefore = canvas.liveFrameCycleCacheHits

            let repeatedFrame = canvas.buildLiveRenderFrame(canvas.sceneData)

            compare(repeatedFrame, currentFrame)
            compare(canvas.liveFrameCycleCacheHits, cycleHitsBefore)
            canvas.destroy()
        }

        function verifyRepresentativeHingeContinuity(panelValue) {
            compare(panelValue.projectionMode, "representative-hinge-band")
            verify(!!panelValue.sectionSegment)
            verify(!!panelValue.representativeMountAnchor)
            compare(panelValue.representativeProjectedMountEdge.length, 2)
            verify(panelValue.representativePhysicalLength > 0)
            verify(panelValue.representativeProjectedLength > 0)
            verify(String(panelValue.representativeSource).indexOf("hinge-anchored-") === 0)
            verify(Math.hypot(panelValue.sectionSegment.start.x - panelValue.representativeMountAnchor.x,
                              panelValue.sectionSegment.start.r - panelValue.representativeMountAnchor.r) < 1.0e-7)
            verify(pointToSegmentDistance(panelValue.representativeMountAnchor,
                                          panelValue.representativeProjectedMountEdge[0],
                                          panelValue.representativeProjectedMountEdge[1]) < 1.0e-7)
            let hasMountCap = false
            for (let capIndex = 0; capIndex < panelValue.internalSharedCaps.length; capIndex++) {
                if (panelValue.internalSharedCaps[capIndex].representativeMount === true)
                    hasMountCap = true
            }
            verify(hasMountCap)
        }

        function verifyDirectPhaseFrame(canvas, expectedPhase) {
            canvas.refreshLiveRenderFrame()
            let frame = canvas.runRenderFrame.live
            verify(frame.ready)
            verify(frame.frameArtifacts.v5Direct)
            verify(!frame.frameArtifacts.v5AuthorityError)
            compare(frame.pose.phase, expectedPhase)
            compare(frame.frameArtifacts.v5PhysicalPanelCount, 2)
            compare(frame.frameArtifacts.orthogonalPanels.length, 2)
            compare(frame.frameArtifacts.orthogonalPanels[0].graphPanelId, "root")
            compare(frame.frameArtifacts.orthogonalPanels[1].graphPanelId, "p1")
            for (let panelIndex = 0; panelIndex < frame.frameArtifacts.orthogonalPanels.length; panelIndex++) {
                let panelValue = frame.frameArtifacts.orthogonalPanels[panelIndex]
                verify(panelValue.polygon.length >= 3)
                for (let pointIndex = 0; pointIndex < panelValue.polygon.length; pointIndex++) {
                    verify(isFinite(panelValue.polygon[pointIndex].x))
                    verify(isFinite(panelValue.polygon[pointIndex].r))
                }
                if (panelValue.sectionSegment) {
                    verify(isFinite(panelValue.sectionSegment.start.x))
                    verify(isFinite(panelValue.sectionSegment.start.r))
                    verify(isFinite(panelValue.sectionSegment.end.x))
                    verify(isFinite(panelValue.sectionSegment.end.r))
                }
            }
        }

        function test_nativeRecorderProducesPainterOrderedCommands() {
            let canvas = createCanvas(qualifiedPreview())
            let context = canvas.createNativeRecordingContext()
            context._livePaintRole = "background"
            context.beginPath()
            context.moveTo(0, 0)
            context.lineTo(10, 0)
            context.lineTo(10, 10)
            context.closePath()
            context.fill()
            context._livePaintRole = "label"
            context.fillText("X", 5, 5)
            context._livePaintRole = "foreground"
            context.beginPath()
            context.moveTo(1, 1)
            context.lineTo(9, 9)
            context.stroke()

            compare(context.commands.length, 2)
            compare(context.textCommands.length, 1)
            compare(context.orderedCommands.length, 3)
            compare(context.orderedCommands[0].type, "path")
            compare(context.orderedCommands[0].paintRole, "background")
            compare(context.orderedCommands[1].type, "text")
            compare(context.orderedCommands[2].type, "path")
            compare(context.orderedCommands[2].paintRole, "foreground")
            for (let index = 0; index < context.orderedCommands.length; index++)
                compare(context.orderedCommands[index].order, index)
            canvas.destroy()
        }

        function test_nativeRecorderOrderedStreamMatchesLegacyMerge() {
            let canvas = createCanvas(qualifiedPreview())
            let context = canvas.createNativeRecordingContext()
            context.fillRect(0, 0, 10, 10)
            context.fillText("A", 5, 5)
            context.strokeRect(1, 1, 8, 8)
            context.fillText("B", 6, 6)

            let legacyMerged = context.commands.concat(context.textCommands)
            legacyMerged.sort(function(a, b) { return a.order - b.order })
            compare(legacyMerged.length, context.orderedCommands.length)
            for (let index = 0; index < legacyMerged.length; index++) {
                compare(legacyMerged[index].type, context.orderedCommands[index].type)
                compare(legacyMerged[index].order, context.orderedCommands[index].order)
                compare(legacyMerged[index].paintRole || "",
                        context.orderedCommands[index].paintRole || "")
                compare(legacyMerged[index].text || "",
                        context.orderedCommands[index].text || "")
            }
            canvas.destroy()
        }

        function test_nativeRecorderKeepsRearCuesOutOfPunchForeground() {
            let canvas = createCanvas(qualifiedPreview())
            let context = canvas.createNativeRecordingContext()
            canvas.setNativePaintRole(context, "material-rear-cues")
            context.beginPath()
            context.moveTo(0, 0)
            context.lineTo(10, 0)
            context.stroke()
            canvas.setNativePaintRole(context, "punch-foreground")
            context.beginPath()
            context.moveTo(0, 0)
            context.lineTo(10, 0)
            context.lineTo(10, 10)
            context.closePath()
            context.fill()

            compare(context.orderedCommands.length, 2)
            compare(context.orderedCommands[0].paintRole, "material-rear-cues")
            compare(context.orderedCommands[1].paintRole, "punch-foreground")
            canvas.destroy()
        }

        function test_liveMaterialFaceLegendDescriptorCachePreservesCommands() {
            let canvas = createCanvas(qualifiedPreview())
            let presentation = {
                face: "TOP",
                symbol: "▲",
                label: "MATERIAL FACE TOP"
            }
            let firstContext = canvas.createNativeRecordingContext()
            canvas.drawLiveMaterialFaceLegend(
                firstContext, presentation, { name: "V12" })
            let firstCommands = JSON.stringify(firstContext.orderedCommands)
            let firstDescriptor = canvas.liveMaterialFaceLegendCache
            verify(!!firstDescriptor)
            compare(firstContext.orderedCommands.length, 9)
            compare(firstContext.textCommands.length, 5)

            let secondContext = canvas.createNativeRecordingContext()
            canvas.drawLiveMaterialFaceLegend(
                secondContext, presentation, { name: "V12" })
            compare(canvas.liveMaterialFaceLegendCache, firstDescriptor)
            compare(JSON.stringify(secondContext.orderedCommands), firstCommands)

            canvas.invalidateLiveRenderCaches()
            compare(canvas.liveMaterialFaceLegendCacheKey, "")
            compare(canvas.liveMaterialFaceLegendCache, null)
            canvas.destroy()
        }

        function test_liveMaterialFaceLegendDescriptorVariesByExactInputs() {
            let canvas = createCanvas(qualifiedPreview())
            let topPresentation = {
                face: "TOP",
                symbol: "▲",
                label: "MATERIAL FACE TOP"
            }
            let top = canvas.liveMaterialFaceLegendDescriptor(
                topPresentation, { name: "V12" })
            compare(top.border, "#0e7490")
            compare(top.accent, "#155e75")
            compare(top.title, "▲  MATERIAL FACE TOP")
            compare(top.view, "ISOMETRIC · TOP LEFT VIEW")
            compare(top.die, "DIE FACE V12")

            canvas.liveCameraOrientation = "ISO_BOTTOM_RIGHT"
            let bottomPresentation = {
                face: "BOTTOM",
                symbol: "▼",
                label: "MATERIAL FACE BOTTOM"
            }
            let bottom = canvas.liveMaterialFaceLegendDescriptor(
                bottomPresentation, { name: "V16" })
            verify(bottom !== top)
            compare(bottom.border, "#9a3412")
            compare(bottom.accent, "#9a3412")
            compare(bottom.title, "▼  MATERIAL FACE BOTTOM")
            compare(bottom.view, "ISOMETRIC · BOTTOM RIGHT VIEW")
            compare(bottom.die, "DIE FACE V16")
            canvas.destroy()
        }

        // Component.bend B3: one CAD bend split by a cut-out into two coaxial
        // spans (y 1.7942..3.6613 and 5.2795..7.1466). The planner centres the
        // whole line (y 1.7942..7.1466, mid 4.4704) on its punch stations;
        // centring on the selected span alone slid the part 1.7387 in along
        // the die so formed flanges landed under the punch.
        function test_splitHingeSectionCentresOnAllCoaxialSpans() {
            let canvas = createCanvas(qualifiedPreview())
            let identity = { m: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1] }
            function span(id, y0, y1) {
                return { bendId: "3:FACE:" + id, sourceBendId: "3", parentPanelId: "ROOT",
                         childPanelId: "FACE:" + id,
                         hingeStart: point(2.0011, y0), hingeEnd: point(2.0011, y1) }
            }
            let selected = span("D4CC", 5.2795, 7.1466)
            let compiled = {
                model: { edges: [selected, span("F186", 1.7942, 3.6613),
                                 { bendId: "4:FACE:C134", sourceBendId: "4", parentPanelId: "ROOT",
                                   childPanelId: "FACE:C134",
                                   hingeStart: point(11.825, 2.5137), hingeEnd: point(11.825, 7.1462) }] },
                transforms: { "ROOT": identity }
            }
            let frame = { origin: { x: 2.0011, y: 6.21305, z: 0 }, viewAxis: { x: 0, y: 1, z: 0 },
                          horizontal: { x: 1, y: 0, z: 0 }, vertical: { x: 0, y: 0, z: 1 } }
            let centred = canvas.v5CentreSectionOnCoaxialSpans({ preview: null }, compiled, selected, frame)
            fuzzyCompare(centred.origin.y, 4.4704, 1e-4)
            fuzzyCompare(centred.origin.x, 2.0011, 1e-9)
            fuzzyCompare(centred.coaxialSpanShift, -1.74265, 1e-4)
            // A single-span bend keeps its own midpoint.
            let single = compiled.model.edges[2]
            let singleFrame = { origin: { x: 11.825, y: 4.82995, z: 0 }, viewAxis: { x: 0, y: 1, z: 0 } }
            compare(canvas.v5CentreSectionOnCoaxialSpans({ preview: null }, compiled, single, singleFrame),
                    singleFrame)
            canvas.destroy()
        }

        function test_validGraphUsesDirectAuthorityAndAllPanels() {
            let canvas = createCanvas(qualifiedPreview())
            let frame = canvas.runRenderFrame.live
            verify(frame.ready)
            verify(frame.frameArtifacts.v5Direct)
            compare(frame.geometryAuthority, "flat-pattern-planar-subdivision-v5")
            compare(frame.frameArtifacts.v5PhysicalPanelCount, 2)
            compare(frame.frameArtifacts.orthogonalPanels.length, 2)
            compare(frame.frameArtifacts.v5RepresentativePanelIds.length, 0)
            for (let panelIndex = 0; panelIndex < frame.frameArtifacts.orthogonalPanels.length; panelIndex++) {
                let panelValue = frame.frameArtifacts.orthogonalPanels[panelIndex]
                compare(panelValue.projectionMode, "full-body-oblique-display")
                compare(panelValue.sectionSegment, null)
                verify(panelValue.polygon.length >= 3)
            }
            compare(frame.frameArtifacts.collisions.panelStatus, "INDETERMINATE")
            canvas.destroy()
        }

        function test_topologyDiagnosticIdentifiesQualifiedAndFallbackAuthority() {
            let qualified = qualifiedPreview()
            let canvas = createCanvas(qualified)
            let qualifiedLine = canvas.previewTopologyDiagnostic(qualified)
            verify(qualifiedLine.indexOf("status=PASS") >= 0)
            verify(qualifiedLine.indexOf("schema=5") >= 0)
            verify(qualifiedLine.indexOf("overlappingPanelRisk=false") >= 0)

            let fallback = JSON.parse(JSON.stringify(qualified))
            fallback.sheetMetalGraph.schemaVersion = 4
            fallback.sheetMetalGraph.diagnostics.status = "fallback"
            fallback.sheetMetalGraph.diagnostics.v5Status = "fallback"
            fallback.sheetMetalGraph.diagnostics.v5FailureReason = "invalid-panel-loop:1"
            fallback.sheetMetalGraph.diagnostics.geometryAuthority = "derived-preview-not-cad-panel-partition"
            let fallbackLine = canvas.previewTopologyDiagnostic(fallback)
            verify(fallbackLine.indexOf("status=FAIL") >= 0)
            verify(fallbackLine.indexOf("v5FailureReason=invalid-panel-loop:1") >= 0)
            verify(fallbackLine.indexOf("overlappingPanelRisk=true") >= 0)
            canvas.destroy()
        }

        function test_directFrameExposesCompleteDiagnosticBasis() {
            let canvas = createCanvas(qualifiedPreview())
            let artifacts = canvas.runRenderFrame.live.frameArtifacts
            verify(artifacts.v5Direct)
            verify(!!artifacts.v5SectionFrame)
            verify(!!artifacts.v5SectionFrame.origin)
            verify(!!artifacts.v5SectionFrame.hingeStart)
            verify(!!artifacts.v5SectionFrame.hingeEnd)
            verify(!!artifacts.v5SectionFrame.viewAxis)
            verify(!!artifacts.v5SectionFrame.horizontal)
            verify(!!artifacts.v5SectionFrame.vertical)
            verify(!!artifacts.v5SectionFrame.parentOutward)
            verify(!!artifacts.v5SectionFrame.childOutward)
            canvas.destroy()
        }

        function test_programTransitionInvalidatesStaleFrameAndSameLengthCacheEntry() {
            let first = qualifiedPreview()
            first.part.name = "PROGRAM-AAA"
            let second = JSON.parse(JSON.stringify(first))
            second.part.name = "PROGRAM-BBB"
            let firstJson = JSON.stringify(first)
            let secondJson = JSON.stringify(second)
            compare(firstJson.length, secondJson.length)

            let canvas = createCanvas(first, {
                programName: first.part.name,
                programPreviewJson: firstJson
            })
            verify(canvas.previewFrameReady)
            compare(canvas.renderedPreviewProgramName, first.part.name)

            canvas.programName = second.part.name
            canvas.programPreviewJson = secondJson
            verify(!canvas.previewFrameReady)
            verify(!canvas.sceneData.ready)
            verify(!canvas.runRenderFrame.ready)

            wait(50)
            verify(canvas.previewFrameReady)
            compare(canvas.renderedPreviewProgramName, second.part.name)
            compare(canvas.runRenderFrame.preview.part.name, second.part.name)
            compare(canvas.sceneData.preview.part.name, second.part.name)
            canvas.destroy()
        }

        function test_liveRevisionKeyHashesOnlyOncePerPreviewChange() {
            let first = qualifiedPreview()
            first.part.name = "PROGRAM-ÁAA"
            let second = JSON.parse(JSON.stringify(first))
            second.part.name = "PROGRAM-ÉBB"
            let firstJson = JSON.stringify(first)
            let secondJson = JSON.stringify(second)
            compare(firstJson.length, secondJson.length)

            let canvas = createCanvas(first, {
                programName: first.part.name,
                programPreviewJson: firstJson
            })
            let firstKey = canvas.liveRevisionKey()
            let firstBuildCount = canvas.liveRevisionState.buildCount
            compare(canvas.liveRevisionKey(), firstKey)
            compare(canvas.liveRevisionKey(), firstKey)
            compare(canvas.liveRevisionState.buildCount, firstBuildCount)

            canvas.programPreviewJson = secondJson
            let secondKey = canvas.liveRevisionKey()
            verify(secondKey !== firstKey)
            compare(canvas.liveRevisionState.buildCount, firstBuildCount + 1)
            compare(canvas.liveRevisionKey(), secondKey)
            compare(canvas.liveRevisionState.buildCount, firstBuildCount + 1)

            canvas.programPreviewJson = firstJson
            compare(canvas.liveRevisionKey(), firstKey)
            compare(canvas.liveRevisionState.buildCount, firstBuildCount + 2)
            canvas.destroy()
        }

        function test_v5StaticDescriptorsWarmHitPreservesIdentityAndOutput() {
            let canvas = createCanvas(qualifiedPreview())
            let first = canvas.v5StaticDescriptors(canvas.sceneData)
            verify(!!first)
            let topologyBuildCount = canvas.v5TopologyCacheBuildCount
            let descriptorJson = JSON.stringify(first.descriptors)
            let edgeJson = JSON.stringify(first.currentEdge)

            let second = canvas.v5StaticDescriptors(canvas.sceneData)
            compare(second, first)
            compare(JSON.stringify(second.descriptors), descriptorJson)
            compare(JSON.stringify(second.currentEdge), edgeJson)
            compare(second.bendKeys.join(","), first.bendKeys.join(","))
            compare(canvas.v5TopologyCacheBuildCount, topologyBuildCount)
            canvas.destroy()
        }

        function test_v5PlacementUsesMaterialBoundaryNotPanelPartition() {
            let preview = qualifiedPreview()
            let canvas = createCanvas(preview, { sceneMode: "PLACEMENT" })
            canvas.rebuildSceneData()
            wait(50)

            compare(canvas.sceneData.loops.length, 2)
            compare(canvas.sceneData.projectedLoops.length, 2)
            compare(canvas.sceneData.projectedLoops[0].outer, true)
            compare(canvas.sceneData.projectedLoops[1].outer, false)
            compare(canvas.sceneData.projectedLoops[0].renderRepair, "authoritative-v5")
            compare(canvas.sceneData.projectedBends.length, 1)
            compare(canvas.sceneData.projectedLoops[0].sourcePoints.length, 4)
            canvas.destroy()
        }

        function test_v5PlacementKeepsAuthoritativeCompoundLinesAfterReorder() {
            let canvas = createCanvas(qualifiedPreview(), { sceneMode: "PLACEMENT" })
            let sourceTwo = { id: "source-2", sequenceHint: 1 }
            let sourceOne = { id: "source-1", sequenceHint: 2 }
            let sourceThree = { id: "source-3", sequenceHint: 3 }
            let sourceFour = { id: "source-4", sequenceHint: 4 }
            let graphEdge = { sourceBendId: "source-1" }
            let lines = [
                { bend: sourceTwo, start: { x: 0, y: 1 }, end: { x: 10, y: 1 }, graphEdge: graphEdge },
                { bend: sourceTwo, start: { x: 5, y: 8 }, end: { x: 5, y: 8 }, graphEdge: graphEdge },
                { bend: sourceOne, start: { x: 0, y: 7 }, end: { x: 10, y: 7 }, graphEdge: graphEdge },
                { bend: sourceOne, start: { x: 5, y: 8 }, end: { x: 5, y: 8 }, graphEdge: graphEdge },
                { bend: sourceThree, start: { x: 1, y: 0 }, end: { x: 1, y: 8 }, graphEdge: graphEdge },
                { bend: sourceFour, start: { x: 9, y: 0 }, end: { x: 9, y: 8 }, graphEdge: graphEdge }
            ]
            let visible = canvas.visiblePlacementBends({ projectedBends: lines })
            compare(visible.length, 4)
            compare(canvas.placementDistance(visible[0].start, visible[0].end), 10)
            compare(canvas.placementDistance(visible[1].start, visible[1].end), 10)
            compare(visible[0].bend.sequenceHint, 1)
            compare(visible[1].bend.sequenceHint, 2)
            compare(visible[2].bend.sequenceHint, 3)
            compare(visible[3].bend.sequenceHint, 4)

            let legacyLine = { start: { x: 0, y: 4 }, end: { x: 10, y: 4 } }
            let degenerateBounds = [legacyLine,
                { start: { x: 5, y: 4 }, end: { x: 5, y: 4 } },
                { start: { x: 5, y: 4 }, end: { x: 5, y: 4 } }]
            let legacyVisible = canvas.trimPlacementBendLineToOrthogonalBounds(
                legacyLine, degenerateBounds)
            compare(canvas.placementDistance(legacyVisible.start, legacyVisible.end), 10)
            canvas.destroy()
        }

        function test_batteryPlateTopologyCardinalityKeepsFlatBoundaryAndLivePanelsSeparate() {
            let preview = qualifiedPreview()
            let holes = []
            for (let holeIndex = 0; holeIndex < 6; holeIndex++) {
                let x = 0.25 + holeIndex * 1.5
                holes.push([point(x, 0.4), point(x + 0.2, 0.4),
                            point(x + 0.2, 0.6), point(x, 0.6)])
            }
            preview.flatPattern.preview2d.loops = [
                { outer: true, points: [point(0, 0), point(10, 0), point(10, 4), point(0, 4), point(0, 0)] }
            ]
            for (let previewHoleIndex = 0; previewHoleIndex < holes.length; previewHoleIndex++) {
                let closedHole = holes[previewHoleIndex].slice(0)
                closedHole.push(closedHole[0])
                preview.flatPattern.preview2d.loops.push({ outer: false, points: closedHole })
            }
            preview.flatPattern.preview2d.loopIntegrity = []
            for (let integrityIndex = 0; integrityIndex < 7; integrityIndex++)
                preview.flatPattern.preview2d.loopIntegrity.push({ loopIndex: integrityIndex, discontinuityCount: 0, closureGap_in: 0 })
            preview.sheetMetalGraph.materialBoundary = {
                outerLoop: [point(0, 0), point(10, 0), point(10, 4), point(0, 4)],
                holeLoops: holes
            }
            function stripePanel(id, parentId, ownerBendId, x0, x1, stripeHoles) {
                return {
                    panelId: id,
                    parentPanelId: parentId,
                    ownerBendId: ownerBendId,
                    geometryAuthority: "planar-subdivision-v5",
                    outerLoop: [point(x0, 0), point(x1, 0), point(x1, 4), point(x0, 4)],
                    holeLoops: stripeHoles || []
                }
            }
            preview.sheetMetalGraph.panels = [
                stripePanel("p0", null, null, 0, 2, [holes[0], holes[1]]),
                stripePanel("p1", "p0", "bend-1", 2, 4, [holes[2]]),
                stripePanel("p2", "p1", "bend-2", 4, 6, [holes[3]]),
                stripePanel("p3", "p2", "bend-3", 6, 8, [holes[4], holes[5]]),
                stripePanel("p4", "p3", "bend-4", 8, 10)
            ]
            preview.sheetMetalGraph.diagnostics.expectedMaterialArea_in2 = 39.76
            preview.sheetMetalGraph.diagnostics.partitionArea_in2 = 39.76
            preview.sheetMetalGraph.diagnostics.partitionAreaError_in2 = 0
            preview.sheetMetalGraph.rootPanelId = "p0"
            preview.sheetMetalGraph.bendEdges = []
            for (let edgeIndex = 1; edgeIndex <= 4; edgeIndex++) {
                let x = edgeIndex * 2
                preview.sheetMetalGraph.bendEdges.push({
                    bendId: "edge-" + edgeIndex,
                    sourceBendId: "bend-" + edgeIndex,
                    sequenceHint: edgeIndex,
                    parentPanelId: "p" + (edgeIndex - 1),
                    childPanelId: "p" + edgeIndex,
                    hingeStart: point(x, 0), hingeEnd: point(x, 4),
                    hingeSegments: [[point(x, 0), point(x, 4)]],
                    bendAngleDegrees: 90, foldAngleDegrees: 90,
                    insideRadius_in: 0.1, thickness_in: 0.1,
                    kFactor: 0.44, childSideSign: 1, direction: "UP"
                })
            }
            preview.bends = []
            for (let bendIndex = 1; bendIndex <= 4; bendIndex++) {
                let bendValue = bend()
                bendValue.id = "bend-" + bendIndex
                bendValue.sequenceHint = bendIndex
                bendValue.start_x_in = bendIndex * 2
                bendValue.end_x_in = bendIndex * 2
                bendValue.end_y_in = 4
                preview.bends.push(bendValue)
            }

            let placementCanvas = createCanvas(preview, { sceneMode: "PLACEMENT", selectedBend: preview.bends[0] })
            placementCanvas.rebuildSceneData()
            wait(50)
            compare(placementCanvas.v5PreviewValidationError(preview), "")
            compare(placementCanvas.sceneData.projectedLoops.length, 7)
            compare(placementCanvas.sceneData.projectedBends.length, 4)
            placementCanvas.destroy()

            let liveCanvas = createCanvas(preview, { sceneMode: "LIVE", selectedBend: preview.bends[0] })
            let liveFrame = liveCanvas.runRenderFrame.live
            verify(liveFrame.frameArtifacts.v5Direct)
            compare(liveFrame.frameArtifacts.orthogonalPanels.length, 5)
            liveCanvas.destroy()
        }

        function test_declaredInvalidGraphBlocksLegacyFallback() {
            let preview = qualifiedPreview()
            preview.sheetMetalGraph.diagnostics.status = "fallback"
            let canvas = createCanvas(preview)
            let frame = canvas.runRenderFrame.live
            verify(frame.ready)
            verify(frame.frameArtifacts.v5Direct)
            verify(String(frame.frameArtifacts.v5AuthorityError).indexOf("declared-v5-invalid") === 0)
            compare(frame.frameArtifacts.orthogonalPanels.length, 0)
            compare(frame.geometryAuthority, "flat-pattern-planar-subdivision-v5-error")
            canvas.destroy()
        }

        function test_topLevelV5DeclarationWithoutGraphBlocksLegacyFallback() {
            let preview = qualifiedPreview()
            delete preview.sheetMetalGraph
            let canvas = createCanvas(preview)
            let frame = canvas.runRenderFrame.live
            verify(frame.ready)
            verify(frame.frameArtifacts.v5Direct)
            verify(String(frame.frameArtifacts.v5AuthorityError)
                   .indexOf("declared-v5-invalid:graph-missing") === 0)
            compare(frame.frameArtifacts.orthogonalPanels.length, 0)
            compare(frame.geometryAuthority, "flat-pattern-planar-subdivision-v5-error")
            canvas.destroy()
        }

        function test_segmentInventoryBuildsEveryConfiguredPunchAndDieSpan() {
            let tool = {
                id: "segmented", name: "Segmented Tool",
                segmentCount16In: 0, segmentCount8In: 1,
                segmentCount4In: 1, segmentCount2In: 1, segmentCount1In: 0
            }
            let canvas = createCanvas(qualifiedPreview())
            let punchLayout = canvas.placementPunchSegmentWidths(10, tool)
            let dieLayout = canvas.placementToolSegmentWidths(10, tool)
            compare(punchLayout.widths.length, 2)
            compare(dieLayout.widths.length, 2)
            compare(punchLayout.widths[0] + punchLayout.widths[1], 10)
            compare(dieLayout.widths[0] + dieLayout.widths[1], 10)
            let phase = {
                installedSegments: [
                    { startXIn: -5, endXIn: 3, widthIn: 8 },
                    { startXIn: 3, endXIn: 5, widthIn: 2 }
                ],
                installedDieSegments: [
                    { startXIn: -5, endXIn: 3, widthIn: 8 },
                    { startXIn: 3, endXIn: 5, widthIn: 2 }
                ]
            }
            canvas.runRenderFrame = {
                ready: true, preview: qualifiedPreview(),
                placement: { toolingPlan: { phase: phase } }, live: {}
            }
            compare(canvas.toolingSegmentsForLive("punch").length, 2)
            compare(canvas.toolingSegmentsForLive("die").length, 2)
            verify(Math.abs(canvas.toolingStationDisplayOffset(
                phase.installedSegments[0].startXIn, "ISOMETRIC").x) > 0)
            canvas.destroy()
        }

        function test_placementPlanUsesStoredToolIdsAndJavaBadgeKeys() {
            let preview = qualifiedPreview()
            let punch = {
                id: "punch-id", name: "Assigned Punch [BC-0001]",
                segmentCount16In: 0, segmentCount8In: 1,
                segmentCount4In: 1, segmentCount2In: 1, segmentCount1In: 0
            }
            let die = {
                id: "die-id", name: "Assigned Die [BC-0002]",
                segmentCount16In: 0, segmentCount8In: 1,
                segmentCount4In: 1, segmentCount2In: 1, segmentCount1In: 0
            }
            let canvas = createCanvas(preview, {
                sceneMode: "PLACEMENT",
                selectedBend: {
                    id: "storage-bend", punchId: punch.id, dieId: die.id,
                    punch: "Display name that does not match the catalog",
                    die: "Another display name", width: 10
                },
                punchCatalog: [punch],
                dieCatalog: [die]
            })
            preview.bends[0].start_y_in = -5
            preview.bends[0].end_y_in = 5
            canvas.programPreviewJson = JSON.stringify(preview)
            canvas.rebuildSceneData()
            wait(50)
            let plan = canvas.buildPlacementToolingPlan(canvas.sceneData)
            compare(plan.phase.punch.id, punch.id)
            compare(plan.phase.die.id, die.id)
            compare(plan.phase.installedSegments.length, 2)
            compare(plan.phase.installedSegments[0].widthIn, 8)
            compare(plan.phase.installedSegments[1].widthIn, 2)
                let firstSegment = plan.phase.installedSegments[0]
                compare(canvas.placementPunchBadgeKey(0, firstSegment),
                    "0:" + firstSegment.startXIn.toFixed(4) + ":"
                    + firstSegment.endXIn.toFixed(4) + ":8.0000")
            compare(canvas.trimRailNumber(8), "8")
            compare(canvas.trimRailNumber(1.25), "1.25")
            canvas.destroy()
        }

        function test_placementUsesPersistedCadPhaseInsteadOfPerBendMinimum() {
            let preview = qualifiedPreview()
            let punch = {
                id: "punch-id", name: "Assigned Punch",
                segmentCount16In: 0, segmentCount8In: 1,
                segmentCount4In: 1, segmentCount2In: 1, segmentCount1In: 1
            }
            let die = {
                id: "die-id", name: "Assigned Die",
                segmentCount16In: 0, segmentCount8In: 1,
                segmentCount4In: 1, segmentCount2In: 1, segmentCount1In: 1
            }
            preview.bends[0].start_y_in = -3.4045
            preview.bends[0].end_y_in = 3.4045
            let canvas = createCanvas(preview, {
                sceneMode: "PLACEMENT",
                punchCoverageSideToleranceIn: 0.5,
                selectedBend: {
                    id: "storage-bend", punchId: punch.id, dieId: die.id,
                    width: 6.809, toolingPhaseIndex: 0,
                    punchSegmentWidths: [8, 1], dieSegmentWidths: [8, 1],
                    punchSegmentStartIn: -4.5, dieSegmentStartIn: -4.5
                },
                punchCatalog: [punch],
                dieCatalog: [die]
            })
            canvas.programPreviewJson = JSON.stringify(preview)
            canvas.rebuildSceneData()
            wait(50)
            let plan = canvas.buildPlacementToolingPlan(canvas.sceneData)
            compare(plan.phase.installedSegments.length, 2)
            compare(plan.phase.installedSegments[0].widthIn, 8)
            compare(plan.phase.installedSegments[1].widthIn, 1)
            compare(plan.phase.installedSegments[0].startXIn, -4.5)
            compare(plan.phase.installedDieSegments[0].widthIn, 8)
            compare(plan.current.phaseIndex, 0)
            canvas.destroy()
        }

        function test_placementBadgeFocusSelectsNearestInstalledPunchSegment() {
            let preview = qualifiedPreview()
            let punch = {
                id: "punch-id", name: "Assigned Punch",
                segmentCount16In: 0, segmentCount8In: 1,
                segmentCount4In: 1, segmentCount2In: 1, segmentCount1In: 0
            }
            let canvas = createCanvas(preview, {
                width: 1060,
                height: 540,
                sceneMode: "PLACEMENT",
                selectedBend: { punchId: punch.id, width: 10 },
                punchCatalog: [punch]
            })
            canvas.rebuildSceneData()
            wait(50)
            let geometry = canvas.placementPunchRailGeometry(canvas.sceneData)
            verify(!!geometry)
            let first = geometry.phase.installedSegments[0]
            let centerX = geometry.left
                + (canvas.topMachineWidthIn / 2 + (first.startXIn + first.endXIn) / 2)
                    * geometry.scale
            verify(canvas.focusPlacementPunchBadge(centerX,
                                                    geometry.railY + geometry.railH / 2))
            compare(canvas.focusedPlacementPunchBadgeKey,
                    canvas.placementPunchBadgeKey(0, first))
            canvas.destroy()
        }

        function test_placementPunchCoverageToleranceMatchesJavaPerSideReduction() {
            let canvas = createCanvas(qualifiedPreview(), {
                punchCoverageSideToleranceIn: 0.25
            })
            let adjusted = canvas.applyPlacementPunchCoverageTolerance({
                startXIn: -5,
                endXIn: 5
            })
            compare(adjusted.startXIn, -4.75)
            compare(adjusted.endXIn, 4.75)
            canvas.punchCoverageSideToleranceIn = 10
            adjusted = canvas.applyPlacementPunchCoverageTolerance({
                startXIn: -1,
                endXIn: 1
            })
            compare(adjusted.startXIn, 0)
            compare(adjusted.endXIn, 0)
            canvas.destroy()
        }

        function test_placementBadgeStaticGlyphsRemainReadableAtMinimumSize() {
            let canvas = createCanvas(qualifiedPreview())
            let badgeSize = canvas.placementPunchBadgeSize(40, 12, false)
            compare(badgeSize, 14)
            verify(canvas.placementPunchBadgeFontSize(badgeSize, false) >= 9.5)
            let ellipseRect = canvas.placementPunchBadgeEllipseRect(12, 7, badgeSize)
            compare(ellipseRect.x, 12)
            compare(ellipseRect.y, 7)
            compare(ellipseRect.width, 14)
            compare(ellipseRect.height, 14)
            compare(canvas.placementPunchBadgeSize(40, 12, true), 28)
            verify(canvas.placementPunchBadgeFontSize(28, true) > 18)
            canvas.destroy()
        }

        function test_placementBadgeFocusUsesPhaseAndSupportsDiagnosticFocusAll() {
            let canvas = createCanvas(qualifiedPreview(), {
                width: 1060,
                height: 540,
                sceneMode: "PLACEMENT"
            })
            let segment = { startXIn: -4, endXIn: 4, widthIn: 8 }
            canvas.runRenderFrame = {
                ready: true,
                preview: qualifiedPreview(),
                placement: {
                    sceneData: canvas.sceneData,
                    toolingPlan: {
                        current: {
                            phaseIndex: 2,
                            requiredPunchSpan: { startXIn: -4, endXIn: 4 },
                            allowedPunchWindow: { startXIn: -14.5, endXIn: 14.5 },
                            forbiddenZones: []
                        },
                        phase: { installedSegments: [segment] }
                    }
                },
                live: {}
            }
            let geometry = canvas.placementPunchRailGeometry(canvas.sceneData)
            verify(!!geometry)
            let centerX = geometry.left
                + (canvas.topMachineWidthIn / 2 + (segment.startXIn + segment.endXIn) / 2)
                    * geometry.scale
            verify(canvas.focusPlacementPunchBadge(centerX,
                                                    geometry.railY + geometry.railH / 2))
            compare(canvas.focusedPlacementPunchBadgeKey,
                    canvas.placementPunchBadgeKey(2, segment))
            verify(canvas.focusAllPlacementPunchBadges())
            compare(canvas.focusedPlacementPunchBadgeKey, "*")
            canvas.destroy()
        }

        function test_liveSegmentRunsShareExteriorAndExposeOnlyInternalSeams() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC",
                toolingAppearance: "TRANSLUCENT"
            })
            let livePalette = canvas.liveToolingAppearancePalette()
            verify(livePalette.solid)
            compare(livePalette.punchFill, "#64748b")
            compare(livePalette.dieFill, "#1f2937")
            compare(livePalette.tableFill, "#4b5563")

            let runs = canvas.normalizedToolingSegmentRuns([
                { startXIn: 3, endXIn: 5 },
                { startXIn: -5, endXIn: 3 }
            ])
            compare(runs.length, 1)
            compare(runs[0].startXIn, -5)
            compare(runs[0].endXIn, 5)
            compare(runs[0].seamPositionsIn.length, 1)
            compare(runs[0].seamPositionsIn[0], 3)

            let span = canvas.toolingInstalledSpan([
                { startXIn: 3, endXIn: 5 },
                { startXIn: -5, endXIn: 3 }
            ])
            compare(span.startXIn, -5)
            compare(span.endXIn, 5)
            compare(span.widthIn, 10)
            compare(span.runCount, 1)

            let separated = canvas.normalizedToolingSegmentRuns([
                { startXIn: -5, endXIn: -1 },
                { startXIn: 1, endXIn: 5 }
            ])
            compare(separated.length, 2)
            compare(separated[0].seamPositionsIn.length, 0)
            compare(separated[1].seamPositionsIn.length, 0)
            canvas.destroy()
        }

        function test_materialFacePresentationCacheUsesExactBendIdentity() {
            let canvas = createCanvas(qualifiedPreview())
            let initialBuildCount = canvas.liveMaterialFacePresentationBuildCount
            let topBend = { id: "bend-1", materialFace: "TOP" }
            let first = canvas.cachedMaterialFacePresentation(topBend)
            let retained = canvas.cachedMaterialFacePresentation(topBend)
            compare(first, retained)
            compare(canvas.liveMaterialFacePresentationBuildCount,
                initialBuildCount + 1)
            compare(first.face, "TOP")

            let bottomBend = { id: "bend-1", materialFace: "BOTTOM" }
            let rebuilt = canvas.cachedMaterialFacePresentation(bottomBend)
            compare(canvas.liveMaterialFacePresentationBuildCount,
                initialBuildCount + 2)
            compare(rebuilt.face, "BOTTOM")
            compare(canvas.liveMaterialFacePresentationCacheMaterialFace, "BOTTOM")
            compare(canvas.liveMaterialFacePresentationCacheSheetFace, "")
            verify(canvas.liveMaterialFacePresentationCacheInputsValid)

            canvas.invalidateLiveRenderCaches()
            verify(!canvas.liveMaterialFacePresentationCacheInputsValid)
            compare(canvas.liveMaterialFacePresentationCache, null)
            canvas.destroy()
        }

        function test_materialFacesAreOpaqueToolingOccluders() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            compare(canvas.livePanelFacePalette({ current: true }).fill, "#bfdbfe")
            compare(canvas.livePanelFacePalette({ current: true,
                                                  oppositePhysicalFace: true }).fill,
                    "#709ccf")
            compare(canvas.livePanelFacePalette({ down: true }).fill, "#fde8d8")
            compare(canvas.livePanelFacePalette({}).fill, "#dcfce7")

            let calls = []
            let context = {
                save: function() { calls.push("save") },
                restore: function() { calls.push("restore") },
                beginPath: function() { calls.push("beginPath") },
                moveTo: function() { calls.push("moveTo") },
                lineTo: function() { calls.push("lineTo") },
                closePath: function() { calls.push("closePath") },
                fill: function() { calls.push("fill") },
                stroke: function() { calls.push("stroke") },
                fillRule: Qt.WindingFill,
                fillStyle: "",
                strokeStyle: "",
                lineWidth: 0
            }
            let panel = {
                liveContourNormalized: true,
                polygon: [
                    { x: 0, r: 0 }, { x: 4, r: 0 },
                    { x: 4, r: 3 }, { x: 0, r: 3 }
                ],
                corners: [],
                holeLoops: [[
                    { x: 1, r: 1 }, { x: 2, r: 1 },
                    { x: 2, r: 2 }, { x: 1, r: 2 }
                ]],
                internalSharedCaps: [],
                liveScreenGeometryId: "screen-geometry-test"
            }
            canvas.drawLiveOrthogonalPanelShape(
                context, panel, function(value) { return value },
                function(value) { return value }, "#dcfce7", "#166534")
            compare(context.fillRule, Qt.OddEvenFill)
            compare(calls.filter(function(call) { return call === "fill" }).length, 1)
            verify(!context.hasOwnProperty("globalCompositeOperation")
                   || context.globalCompositeOperation !== "destination-out")
            canvas.destroy()
        }

        function test_panelsArePartitionedAroundPunchDepth() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let layers = canvas.partitionLivePanelsAroundPunch([
                { graphPanelId: "rear", viewDepthMin: -7, viewDepthMax: -6 },
                { graphPanelId: "cross", viewDepthMin: -1, viewDepthMax: 1 },
                { graphPanelId: "front", viewDepthMin: 7, viewDepthMax: 8 }
            ], [{ startXIn: -5, endXIn: 5 }])
            compare(layers.punchDepth, 0)
            compare(layers.behind.length, 1)
            compare(layers.behind[0].graphPanelId, "rear")
            compare(layers.straddling.length, 1)
            compare(layers.straddling[0].graphPanelId, "cross")
            compare(layers.front.length, 1)
            compare(layers.front[0].graphPanelId, "front")

            canvas.liveCameraOrientation = "ISO_BACK"
            compare(canvas.livePanelPunchDepthLayer(
                { viewDepthMin: -7, viewDepthMax: -6 }, 0), "FRONT")
            compare(canvas.livePanelPunchDepthLayer(
                { viewDepthMin: 6, viewDepthMax: 7 }, 0), "BEHIND")
            canvas.destroy()
        }

        function test_centeredPunchRunUsesContactPlaneNotNearestCap() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            compare(canvas.punchDepthReference([
                { startXIn: -14.5, endXIn: 14.5 }
            ]), 0)
            let layers = canvas.partitionLivePanelsAroundPunch([{
                graphPanelId: "b3-sheet",
                viewDepthMin: -14.03685,
                viewDepthMax: 14.03685
            }], [{ startXIn: -14.5, endXIn: 14.5 }])
            compare(layers.behind.length, 0)
            compare(layers.front.length, 0)
            compare(layers.straddling.length, 1)
            compare(layers.straddling[0].graphPanelId, "b3-sheet")
            canvas.destroy()
        }

        function test_panelPunchPaintPlanIsRetainedByVisualFrame() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let artifacts = {}
            let panels = [{
                graphPanelId: "cross",
                viewDepthMin: -1,
                viewDepthMax: 1
            }]
            let segments = [{ startXIn: -5, endXIn: 5 }]
            let first = canvas.retainedLivePanelPunchPaintPlan(
                artifacts, panels, segments)
            let retained = canvas.retainedLivePanelPunchPaintPlan(
                artifacts, panels, segments)
            compare(retained, first)
            compare(retained.fullStraddlingRear[0], panels[0])

            let changedPanels = panels.slice(0)
            let rebuilt = canvas.retainedLivePanelPunchPaintPlan(
                artifacts, changedPanels, segments)
            verify(rebuilt !== first)
            compare(rebuilt.fullStraddlingRear[0], panels[0])
            canvas.destroy()
        }

        function test_straddlingFlangeKeepsCompleteRearBody() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let flange = {
                graphPanelId: "B3",
                viewDepthMin: -2,
                viewDepthMax: 2
            }
            let plan = canvas.livePanelPunchPaintPlan(
                [flange], [{ startXIn: -5, endXIn: 5 }])
            compare(plan.behind.length, 0)
            compare(plan.front.length, 0)
            compare(plan.fullStraddlingRear.length, 1)
            compare(plan.fullStraddlingRear[0], flange)
            compare(plan.clippedStraddlingFront.length, 1)
            compare(plan.clippedStraddlingFront[0], flange)
            canvas.destroy()
        }

        function test_completedPanelsRespectPunchDepthPartition() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let b2 = {
                graphPanelId: "B2",
                completed: true,
                ownerSequence: 2,
                viewDepthMin: -4,
                viewDepthMax: -1,
                viewDepthCentroid: -2
            }
            let layers = canvas.partitionLivePanelsAroundPunch(
                [b2], [{ startXIn: -1, endXIn: 1 }])
            compare(layers.behind.length, 1)
            compare(layers.behind[0], b2)
            compare(layers.straddling.length, 0)
            compare(layers.front.length, 0)
            canvas.destroy()
        }

        function test_completedSiblingOrderCrossesPunchFrontLayers() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let b1 = {
                graphPanelId: "B1",
                completed: true,
                ownerSequence: 1,
                viewDepthMin: 3,
                viewDepthMax: 4,
                viewDepthCentroid: 3.5
            }
            let b3 = {
                graphPanelId: "B3",
                completed: true,
                ownerSequence: 3,
                viewDepthMin: -2,
                viewDepthMax: 2,
                viewDepthCentroid: 0
            }
            let b2 = {
                graphPanelId: "B2",
                completed: true,
                ownerSequence: 2,
                viewDepthMin: -4,
                viewDepthMax: -3,
                viewDepthCentroid: -3.5
            }
            let plan = canvas.livePanelPunchPaintPlan(
                [b1, b3, b2], [{ startXIn: -5, endXIn: 5 }])
            let frontEntries = canvas.livePanelPunchFrontPaintEntries(plan)
            compare(canvas.livePanelPunchFrontPaintEntries(plan), frontEntries)
            compare(plan.behind.length, 1)
            compare(plan.behind[0], b2)
            compare(frontEntries.length, 2)
            compare(frontEntries[0].panel, b3)
            verify(frontEntries[0].clipToPunch)
            compare(frontEntries[1].panel, b1)
            verify(!frontEntries[1].clipToPunch)
            canvas.destroy()
        }

        function test_completedSiblingOrderUsesTopologySequenceBeforeDepth() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let earlier = {
                graphPanelId: "B1", completed: true, ownerSequence: 1,
                viewDepthMin: -1, viewDepthMax: 1, viewDepthCentroid: 0
            }
            let later = {
                graphPanelId: "B3", completed: true, ownerSequence: 3,
                viewDepthMin: 2, viewDepthMax: 4, viewDepthCentroid: 3
            }
            let ordered = canvas.orderedLivePanelsForPaint([earlier, later])
            compare(ordered[0], later)
            compare(ordered[1], earlier)
            canvas.destroy()
        }

        function test_overlappingFlangesPaintByCameraNearExtent() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let longFlange = {
                graphPanelId: "long",
                viewDepthMin: -14,
                viewDepthMax: 14,
                viewDepthCentroid: 0.2
            }
            let shortFlange = {
                graphPanelId: "short",
                viewDepthMin: 2.5,
                viewDepthMax: 4,
                viewDepthCentroid: 3.3
            }
            let ordered = canvas.orderedLivePanelsForPaint(
                [longFlange, shortFlange])
            compare(ordered[0], shortFlange)
            compare(ordered[1], longFlange)
            canvas.destroy()
        }

        function test_filletCuesAreFilteredByPhysicalPanelLayer() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let strokes = 0
            let dashCalls = []
            let context = {
                save: function() {}, restore: function() {},
                beginPath: function() {}, moveTo: function() {},
                lineTo: function() {}, stroke: function() { strokes++ },
                setLineDash: function(values) { dashCalls.push(values.slice(0)) },
                lineCap: "", strokeStyle: "",
                lineWidth: 0
            }
            let cues = [
                { panelId: "B1", contact: "PUNCH", lines: [
                    { a: { x: 0, r: 0 }, b: { x: 1, r: 1 } }
                ] },
                { panelId: "B2", contact: "DIE", lines: [
                    { a: { x: 2, r: 0 }, b: { x: 3, r: 1 } }
                ] }
            ]
            canvas.drawQualifiedV5FilletCues(
                context, function(value) { return value },
                function(value) { return value }, cues, { B1: true })
            compare(strokes, 1)
            verify(dashCalls.every(function(values) { return values.length === 0 }))
            canvas.destroy()
        }

        function test_straddlingFilletCueStaysBehindPunchAndFrontMaterial() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let b1 = {
                graphPanelId: "B1", completed: true, ownerSequence: 1,
                viewDepthMin: 3, viewDepthMax: 4, viewDepthCentroid: 3.5
            }
            let b3 = {
                graphPanelId: "B3", completed: true, ownerSequence: 3,
                viewDepthMin: -2, viewDepthMax: 2, viewDepthCentroid: 0
            }
            let plan = canvas.livePanelPunchPaintPlan(
                [b1, b3], [{ startXIn: -5, endXIn: 5 }])
            let cueLayers = canvas.livePanelCueLayerIds(plan)
            verify(cueLayers.rear.B3)
            verify(!cueLayers.front.B3)
            verify(!cueLayers.rear.B1)
            verify(cueLayers.front.B1)
            canvas.destroy()
        }

        function test_edgeOnDepthBandRetainsSignedDepthPlane() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let polygon = canvas.liveSectionSegmentPolygon({
                start: { x: 0, r: 0 },
                end: { x: 4, r: 0 },
                halfThickness: 0.05
            }, 2.5)
            compare(polygon.length, 4)
            verify(polygon.every(function(pointValue) {
                return pointValue.viewDepth === 2.5
            }))
            let identity = function(value) { return value }
            let plane = canvas.livePanelScreenDepthPlane({
                polygon: polygon,
                corners: polygon
            }, identity, identity)
            verify(!!plane)
            verify(Math.abs(plane.a) < 1.0e-8)
            verify(Math.abs(plane.b) < 1.0e-8)
            verify(Math.abs(plane.c - 2.5) < 1.0e-8)
            canvas.destroy()
        }

        function test_straddlingPanelSplitsIntoRearAndFrontDepthClips() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let panel = {
                polygon: [
                    { x: 0, r: 0, viewDepth: -2 },
                    { x: 4, r: 0, viewDepth: 2 },
                    { x: 4, r: 2, viewDepth: 2 },
                    { x: 0, r: 2, viewDepth: -2 }
                ],
                corners: []
            }
            let identity = function(value) { return value }
            let plane = canvas.livePanelScreenDepthPlane(
                panel, identity, identity)
            verify(!!plane)
            let screen = panel.polygon.map(function(point) {
                return { x: point.x, y: point.r }
            })
            let rear = canvas.clipScreenPolygonByDepth(
                screen, plane, 0, false)
            let front = canvas.clipScreenPolygonByDepth(
                screen, plane, 0, true)
            compare(rear.length, 4)
            compare(front.length, 4)
            verify(rear.every(function(point) { return point.x <= 2.000001 }))
            verify(front.every(function(point) { return point.x >= 1.999999 }))
            canvas.destroy()
        }

        function test_segmentedSolidPaintsOneExteriorPerContiguousRun() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let model = {
                polylines: [{
                    closed: true,
                    points: [
                        { x: 0, y: 0 }, { x: 2, y: 0 },
                        { x: 2, y: 1 }, { x: 0, y: 1 }
                    ]
                }],
                lines: [], circles: [], arcs: []
            }
            let calls = []
            let context = {
                save: function() {}, restore: function() {},
                beginPath: function() { calls.push("beginPath") },
                closePath: function() {}, moveTo: function() {},
                lineTo: function() {}, fill: function() { calls.push("fill") },
                stroke: function() { calls.push("stroke") },
                ellipse: function() {}, fillText: function() {},
                fillStyle: "", strokeStyle: "", lineWidth: 0,
                font: "", textAlign: "", textBaseline: ""
            }
            verify(canvas.drawLiveSegmentedDxfModel(
                context, model, function(value) { return value },
                function(value) { return value }, 1, 0, 0, 0, 1,
                "#111827", "#64748b", false, false, 0,
                [{ startXIn: -5, endXIn: 3 },
                 { startXIn: 3, endXIn: 5 }], true))
            // One contiguous run has one rear closed fill and one front closed
            // fill. Its four side walls fill once each; a second complete
            // profile for the adjacent inventory segment would add another
            // front/rear pair.
            compare(calls.filter(function(call) { return call === "fill" }).length, 6)
            canvas.destroy()
        }

        function test_dxfBulgePolylinePreservesCurvedToolingProfile() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let points = [
                { x: 0, y: 0 }, { x: 2, y: 0 },
                { x: 2, y: 1 }, { x: 0, y: 1 }
            ]
            let expanded = canvas.dxfBulgePolylinePoints(
                points, [1, 0, 0, 0], true)
            verify(expanded.length > points.length)
            compare(expanded[0].x, 0)
            compare(expanded[0].y, 0)
            let last = expanded[expanded.length - 1]
            verify(Math.abs(last.x - points[0].x) < 1.0e-9)
            verify(Math.abs(last.y - points[0].y) < 1.0e-9)
            verify(expanded.some(function(pointValue) {
                return Math.abs(pointValue.y) > 0.01
            }))
            canvas.destroy()
        }

        function test_punchPaintPlanCachesStaticGeometryAcrossAnimatedTranslation() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let model = {
                _cachePath: "test-punch.dxf",
                polylines: [{
                    closed: true,
                    points: [
                        { x: 0, y: 0 }, { x: 2, y: 0 },
                        { x: 2, y: 1 }, { x: 1, y: 1.5 }, { x: 0, y: 1 }
                    ]
                }],
                lines: [], circles: [], arcs: []
            }
            let profile = { tipLocalX: 1, tipLocalY: 0 }
            let segments = [
                { startXIn: -4, endXIn: 2 },
                { startXIn: 0, endXIn: 4 }
            ]
            let firstKey = canvas.punchPaintPlanKey(model, profile, segments)
            let plan = canvas.buildLivePunchPaintPlan(model, profile, segments)
            verify(!!plan)
            compare(plan.face.polylines.length, 1)
            compare(plan.face.polylines[0].points.length, 5)
            compare(plan.runs.length, 1)
            verify(plan.runs[0].visibleEdges.length > 0)
            compare(plan.runs[0].seamOffsets.length, 1)
            compare(canvas.punchPaintPlanKey(model, profile, segments), firstKey)
            let retainedScene = { punchModel: model, punchProfile: profile }
            canvas.livePunchPaintPlanCache = plan
            canvas.livePunchPaintPlanCacheKey = firstKey
            canvas.livePunchPaintPlanScene = retainedScene
            compare(canvas.livePunchPaintPlanScene, retainedScene)
            // pose.punchTipR is deliberately absent from the cache key and
            // retained plan; it is applied only by the drawing functions.
            verify(firstKey.indexOf("punchTipR") < 0)
            canvas.destroy()
        }

        function triangleListArea(vertices) {
            let area = 0
            for (let index = 0; index < vertices.length; index += 6) {
                area += Math.abs(
                    (vertices[index + 2] - vertices[index])
                        * (vertices[index + 5] - vertices[index + 1])
                    - (vertices[index + 3] - vertices[index + 1])
                        * (vertices[index + 4] - vertices[index])) * 0.5
            }
            return area
        }

        function test_retainedPunchTriangulatesConcaveClosedPolygonExactly() {
            let canvas = createCanvas(qualifiedPreview())
            let polygon = [
                { x: 0, r: 0 }, { x: 3, r: 0 }, { x: 3, r: 3 },
                { x: 1.5, r: 1.5 }, { x: 0, r: 3 }, { x: 0, r: 0 }
            ]
            let triangles = canvas.triangulateRetainedPunchPolygon(polygon)
            verify(!!triangles)
            compare(triangles.length, (5 - 2) * 6)
            verify(Math.abs(triangleListArea(triangles)
                            - Math.abs(canvas.retainedPunchPolygonArea(
                                polygon.slice(0, polygon.length - 1)))) < 1.0e-7)
            canvas.destroy()
        }

        function test_retainedPunchTriangulationRejectsSelfIntersection() {
            let canvas = createCanvas(qualifiedPreview())
            compare(canvas.triangulateRetainedPunchPolygon([
                { x: 0, r: 0 }, { x: 2, r: 2 },
                { x: 0, r: 2 }, { x: 2, r: 0 }
            ]), null)
            canvas.destroy()
        }

        function test_retainedPunchTriangulationRejectsAdjacentRetrace() {
            let canvas = createCanvas(qualifiedPreview())
            compare(canvas.triangulateRetainedPunchPolygon([
                { x: 0, r: 0 }, { x: 3, r: 0 },
                { x: 1, r: 0 }, { x: 3, r: 2 }, { x: 0, r: 2 }
            ]), null)
            canvas.destroy()
        }

        function test_retainedPunchCompilerBuildsOpaqueRigidBatches() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let model = {
                _cachePath: "retained-test-punch.dxf",
                polylines: [{
                    closed: true,
                    points: [
                        { x: 0, y: 0 }, { x: 3, y: 0 },
                        { x: 3, y: 2 }, { x: 1.5, y: 1 }, { x: 0, y: 2 }
                    ]
                }],
                lines: [], circles: [], arcs: []
            }
            let profile = { tipLocalX: 1.5, tipLocalY: 0 }
            let segments = [{ startXIn: -3, endXIn: 3 }]
            let plan = canvas.buildLivePunchPaintPlan(model, profile, segments)
            let batches = canvas.buildRetainedOpaquePunchBatches(
                plan, canvas.liveToolingAppearancePalette())
            verify(!!batches)
            verify(batches.length > 0)
            verify(batches.length <= plan.runs.length * 2)
            for (let index = 0; index < batches.length; index++) {
                verify(batches[index].xyVertices.length >= 6)
                compare(batches[index].xyVertices.length % 6, 0)
                verify(String(batches[index].color).indexOf("rgba") !== 0)
            }
            let firstKey = canvas.punchPaintPlanKey(model, profile, segments)
            compare(canvas.punchPaintPlanKey(model, profile, segments), firstKey)
            verify(firstKey.indexOf("punchTipR") < 0)
            canvas.destroy()
        }

        function test_retainedPunchViewportTransformMatchesCanvasProjection() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveCameraOrientation: "ISO_BACK"
            })
            let frame = {
                bounds: { minX: -4, maxX: 6, minR: -2, maxR: 8 },
                pose: { punchTipR: 1.25 }
            }
            let transform = canvas.retainedPunchViewportTransform(frame)
            verify(!!transform)
            verify(transform.m11 < 0)
            let scale = Math.min((canvas.width - 16) / 10,
                                 (canvas.height - 12) / 10)
            let sceneWidth = 10 * scale
            let sceneHeight = 10 * scale
            let left = (canvas.width - sceneWidth) * 0.5
            let top = Math.max(6, canvas.height - 6 - sceneHeight)
            let canonical = { x: 2.5, r: 3.5 }
            let projectedX = transform.m11 * canonical.x + transform.dx
            let projectedY = transform.m22 * canonical.r + transform.dy
            let basis = canvas.isometricCameraBasis()
            let expectedX = basis.screenXSign < 0
                ? left + (frame.bounds.maxX - canonical.x) * scale
                : left + (canonical.x - frame.bounds.minX) * scale
            let expectedY = top + (frame.bounds.maxR
                                    - canonical.r - frame.pose.punchTipR) * scale
            verify(Math.abs(projectedX - expectedX) < 1.0e-7)
            verify(Math.abs(projectedY - expectedY) < 1.0e-7)
            canvas.destroy()
        }

        function test_retainedPunchCompilerFailsClosedOnOpenFace() {
            let canvas = createCanvas(qualifiedPreview())
            let plan = {
                contour: [],
                runs: [{
                    visibleEdges: [], nearOffset: { x: 0, r: 0 },
                    farOffset: { x: 0, r: 0 }
                }],
                face: {
                    polylines: [{
                        closed: false,
                        points: [{ x: 0, r: 0 }, { x: 1, r: 0 },
                                 { x: 1, r: 1 }]
                    }]
                }
            }
            compare(canvas.buildRetainedOpaquePunchBatches(
                        plan, canvas.liveToolingAppearancePalette()), null)
            canvas.destroy()
        }

        function test_backgaugeFingerGeometryRetainsStaticProfile() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            if (!canvas.liveBackgaugeFingerGeometry().profile)
                skip("backgauge finger DXF asset not bundled")
            let first = canvas.liveBackgaugeFingerGeometry()
            verify(!!first)
            verify(!!first.profile)
            compare(canvas.liveBackgaugeFingerGeometry(), first)
            verify(first.profile.outerLoop.length > 20)
            compare(first.profile.holeLoops.length, 1)
            canvas.destroy()
        }

        function test_livePanelPaintOrderCacheIsScopedToOnePaint() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let panels = [
                { graphPanelId: "panel-b", completed: false,
                  polygon: [{ x: 0, r: 0 }, { x: 1, r: 0 }, { x: 1, r: 1 }] },
                { graphPanelId: "panel-a", completed: false,
                  polygon: [{ x: 2, r: 0 }, { x: 3, r: 0 }, { x: 3, r: 1 }] }
            ]
            let first = canvas.orderedLivePanelsForPaint(panels)
            let second = canvas.orderedLivePanelsForPaint(panels)
            compare(first, second)
            compare(first.length, panels.length)
            canvas.livePaintOrderCache = []
            let nextPaint = canvas.orderedLivePanelsForPaint(panels)
            verify(nextPaint !== first)
            compare(nextPaint[0].graphPanelId, first[0].graphPanelId)
            canvas.destroy()
        }

        function test_internalRepeatedPreviewVertexStillBlocksAuthority() {
            let preview = qualifiedPreview()
            preview.flatPattern.preview2d.loops[0].points.splice(2, 0, point(0, 0))
            let canvas = createCanvas(preview)
            verify(String(canvas.runRenderFrame.live.frameArtifacts.v5AuthorityError)
                   .indexOf("declared-v5-invalid:flat-pattern-loop-integrity-invalid:0") === 0)
            compare(canvas.runRenderFrame.live.frameArtifacts.orthogonalPanels.length, 0)
            canvas.destroy()
        }

        function test_liveReadoutsMatchJavaIntegratedPresentation() {
            let preview = qualifiedPreview()
            let selected = preview.bends[0]
            selected.tonnage = 4.575
            let canvas = createCanvas(preview, { selectedBend: selected })
            compare(canvas.liveTonnageText(), "4.575 T")

            let fingerCommands = []
            let context = {
                save: function() { fingerCommands.push("save") },
                restore: function() { fingerCommands.push("restore") },
                strokeText: function(text) {
                    fingerCommands.push("stroke:" + String(text))
                },
                fillText: function(text) {
                    fingerCommands.push("fill:" + String(text))
                },
                font: "", textAlign: "", textBaseline: "",
                strokeStyle: "", fillStyle: "", lineWidth: 0
            }
            canvas.drawBackgaugeFingerReadout(
                context, function(value) { return value * 30 },
                function(value) { return -value * 30 },
                -0.25, 0.04, 0.9494)
            compare(fingerCommands.length, 4)
            compare(fingerCommands[0], "save")
            compare(fingerCommands[1], "stroke:X 0.9494 in")
            compare(fingerCommands[2], "fill:X 0.9494 in")
            compare(fingerCommands[3], "restore")

            let staticScene = {
                tableModel: { bounds: { minX: -2, maxX: 2, minY: -1, maxY: 0 } },
                tableAnchorY: 0,
                stack: { tableTopR: -0.5 }
            }
            let badgePoint = canvas.tableTonnagePoint(staticScene)
            verify(badgePoint.r < staticScene.stack.tableTopR)
            verify(badgePoint.r > staticScene.stack.tableTopR - 1)
            canvas.destroy()
        }

        function test_backgaugeReadoutInjectedGeometryPreservesCommands() {
            let canvas = createCanvas(qualifiedPreview())
            let geometry = canvas.liveBackgaugeFingerGeometry()

            function recordReadout(injectedGeometry) {
                let commands = []
                let context = {
                    save: function() { commands.push(["save"]) },
                    restore: function() { commands.push(["restore"]) },
                    strokeText: function(text, x, y) {
                        commands.push(["strokeText", String(text), x, y])
                    },
                    fillText: function(text, x, y) {
                        commands.push(["fillText", String(text), x, y])
                    },
                    font: "", textAlign: "", textBaseline: "",
                    strokeStyle: "", fillStyle: "", lineWidth: 0
                }
                canvas.drawBackgaugeFingerReadout(
                    context,
                    function(value) { return value * 30 },
                    function(value) { return -value * 30 },
                    -0.25, 0.04, 0.9494, injectedGeometry)
                return commands
            }

            compare(JSON.stringify(recordReadout(undefined)),
                    JSON.stringify(recordReadout(geometry)))
            canvas.destroy()
        }

        function test_staleGeneratorAndMismatchedSourceBoundaryBlockAuthority() {
            let stale = qualifiedPreview()
            stale.generator.revision = "2026-08-02-planar-face-graph-v2"
            let canvas = createCanvas(stale)
            verify(String(canvas.runRenderFrame.live.frameArtifacts.v5AuthorityError)
                   .indexOf("declared-v5-invalid:generator-provenance-not-current") === 0)
            compare(canvas.runRenderFrame.live.frameArtifacts.orthogonalPanels.length, 0)
            canvas.destroy()

            let mismatched = qualifiedPreview()
            mismatched.flatPattern.preview2d.loops[0].points[2].x_in = 6.1
            canvas = createCanvas(mismatched)
            verify(String(canvas.runRenderFrame.live.frameArtifacts.v5AuthorityError)
                   .indexOf("declared-v5-invalid:material-boundary-preview-outer-mismatch") === 0)
            compare(canvas.runRenderFrame.live.frameArtifacts.orthogonalPanels.length, 0)
            canvas.destroy()
        }

        function test_directAuthoritySurvivesAllAnimationPhases() {
            let canvas = createCanvas(qualifiedPreview())
            canvas.running = true

            canvas.elapsedSeconds = 0.0
            verifyDirectPhaseFrame(canvas, "RUN / CLAMP")

            canvas.elapsedSeconds = 1.45
            verifyDirectPhaseFrame(canvas, "RUN / BEND")

            canvas.elapsedSeconds = 3.20
            verifyDirectPhaseFrame(canvas, "RUN / BEND")

            canvas.elapsedSeconds = 3.70
            verifyDirectPhaseFrame(canvas, "RUN / RETRACT")

            canvas.destroy()
        }

        function test_simulatedPlaybackClockAdvancesWhileCanvasPaintIsBackpressured() {
            let canvas = createCanvas(qualifiedPreview(), {
                simulatedPlayback: true
            })
            canvas.running = true
            canvas.livePaintPending = true
            let startedAt = Date.now()
            let elapsedAtStart = canvas.elapsedSeconds

            tryVerify(function() {
                return canvas.elapsedSeconds - elapsedAtStart >= 0.1
            }, 1000)
            let wallClockSeconds = (Date.now() - startedAt) / 1000
            let simulatedDelta = canvas.elapsedSeconds - elapsedAtStart
            verify(simulatedDelta >= 0.1,
                   "simulation must advance even when paint submission is blocked")
            verify(simulatedDelta >= wallClockSeconds * 0.45,
                   "simulation time must remain tied to wall-clock time")

            canvas.destroy()
        }

        function test_mixedAxisStarRepresentsEveryPhysicalPanelAcrossAllBendsAndPhases() {
            let preview = mixedAxisStarPreview()
            let phaseTimes = [0.0, 1.45, 3.70]
            let physicalIds = ["p1", "p2", "p3", "p4", "root"]
            for (let bendIndex = 0; bendIndex < preview.bends.length; bendIndex++) {
                let canvas = createCanvas(preview, {
                    selectedBendIndex: bendIndex,
                    selectedBend: preview.bends[bendIndex],
                    liveProjectionMode: "ISOMETRIC",
                    running: true
                })
                for (let phaseIndex = 0; phaseIndex < phaseTimes.length; phaseIndex++) {
                    canvas.elapsedSeconds = phaseTimes[phaseIndex]
                    canvas.refreshLiveRenderFrame()
                    let frame = canvas.runRenderFrame.live
                    verify(frame.frameArtifacts.v5Direct)
                    compare(frame.frameArtifacts.v5PhysicalPanelCount, 5)
                    compare(frame.frameArtifacts.v5Pose.model.panelOrder.length, 5)
                    let rendered = ({})
                    let edgeOnCount = 0
                    for (let panelIndex = 0; panelIndex < frame.frameArtifacts.orthogonalPanels.length; panelIndex++) {
                        let panelValue = frame.frameArtifacts.orthogonalPanels[panelIndex]
                        rendered[panelValue.graphPanelId] = true
                        verify(panelValue.polygon.length >= 3 || !!panelValue.sectionSegment)
                        if (panelValue.projectionMode === "display-edge-on-thickness-band")
                            edgeOnCount++
                        else
                            compare(panelValue.projectionMode, "full-body-oblique-display")
                        if (panelValue.graphPanelId === "p3" || panelValue.graphPanelId === "p4") {
                            compare(panelValue.projectionMode, "full-body-oblique-display")
                            verify(panelValue.polygon.length >= 4)
                            let minX = Math.min.apply(null, panelValue.polygon.map(function(value) { return value.x }))
                            let maxX = Math.max.apply(null, panelValue.polygon.map(function(value) { return value.x }))
                            let minR = Math.min.apply(null, panelValue.polygon.map(function(value) { return value.r }))
                            let maxR = Math.max.apply(null, panelValue.polygon.map(function(value) { return value.r }))
                            verify((maxX - minX) * (maxR - minR) > 0.1)
                        }
                    }
                    compare(Object.keys(rendered).sort().join(","), physicalIds.join(","))
                    compare(frame.frameArtifacts.v5OffSectionPanelIds.length, 0)
                    compare(frame.frameArtifacts.v5RepresentativePanelIds.length, edgeOnCount)
                }
                compare(canvas.v5TopologyCacheBuildCount, 1)
                canvas.destroy()
            }
        }

        function test_compoundOperationPosesEveryRelationInIsometric() {
            let preview = compoundOperationPreview()
            let canvas = createCanvas(preview, {
                liveProjectionMode: "ISOMETRIC",
                running: true,
                elapsedSeconds: 1.45
            })
            canvas.refreshLiveRenderFrame()
            let frame = canvas.runRenderFrame.live
                 verify(frame.frameArtifacts.v5Direct,
                     String(frame.frameArtifacts.v5AuthorityError || "")
                     + " validation=" + canvas.v5PreviewValidationError(preview))
                 verify(frame.frameArtifacts.v5PhysicalPanelCount !== undefined,
                     "reason=" + String(frame.frameArtifacts.v5Reason)
                     + " direct=" + String(frame.frameArtifacts.v5Direct)
                     + " panels=" + String(frame.frameArtifacts.orthogonalPanels.length))
            compare(frame.frameArtifacts.v5PhysicalPanelCount, 3)
            compare(frame.frameArtifacts.orthogonalPanels.length, 3)
            compare(canvas.v5CurrentGraphEdge(preview.sheetMetalGraph,
                                              preview.bends[0]).operationRelationIndex, 0)
            let rendered = ({})
            for (let panelIndex = 0; panelIndex < frame.frameArtifacts.orthogonalPanels.length; panelIndex++) {
                let panelValue = frame.frameArtifacts.orthogonalPanels[panelIndex]
                rendered[panelValue.graphPanelId] = true
                compare(panelValue.liveProjectionMode, "ISOMETRIC")
                compare(panelValue.projectionMode, "full-body-oblique-display")
                verify(panelValue.polygon.length >= 3)
            }
            compare(Object.keys(rendered).sort().join(","), "p1,p2,root")
            let transforms = frame.frameArtifacts.v5Pose.transforms
            verify(!!transforms.p1)
            verify(!!transforms.p2)
            for (let matrixIndex = 0; matrixIndex < 16; matrixIndex++)
                verify(Math.abs(transforms.p1.m[matrixIndex] - transforms.p2.m[matrixIndex]) < 1.0e-8)
            canvas.destroy()
        }

        function test_sideAndIsometricProjectionModesRemainDistinctAndComplete() {
            let preview = mixedAxisStarPreview()
            let sideCanvas = createCanvas(preview, {
                selectedBendIndex: 2,
                selectedBend: preview.bends[2],
                liveProjectionMode: "SIDE",
                running: true,
                elapsedSeconds: 1.45
            })
            sideCanvas.refreshLiveRenderFrame()
            let sideFrame = sideCanvas.runRenderFrame.live
            compare(sideFrame.frameArtifacts.v5PhysicalPanelCount, 5)
            let sideIds = ({}), sideEdgeOn = 0
            for (let sideIndex = 0; sideIndex < sideFrame.frameArtifacts.orthogonalPanels.length; sideIndex++) {
                let sidePanel = sideFrame.frameArtifacts.orthogonalPanels[sideIndex]
                sideIds[sidePanel.graphPanelId] = true
                compare(sidePanel.liveProjectionMode, "SIDE")
                verify(sidePanel.projectionMode === "orthographic-side-display"
                       || sidePanel.projectionMode === "display-edge-on-thickness-band")
                if (sidePanel.projectionMode === "display-edge-on-thickness-band")
                    sideEdgeOn++
            }
            compare(Object.keys(sideIds).sort().join(","), "p1,p2,p3,p4,root")
            verify(sideEdgeOn > 0)

            sideCanvas.liveProjectionMode = "ISOMETRIC"
            wait(50)
            sideCanvas.refreshLiveRenderFrame()
            let isoFrame = sideCanvas.runRenderFrame.live
            compare(isoFrame.frameArtifacts.v5PhysicalPanelCount, 5)
            compare(isoFrame.frameArtifacts.v5RepresentativePanelIds.length, 0)
            for (let isoIndex = 0; isoIndex < isoFrame.frameArtifacts.orthogonalPanels.length; isoIndex++) {
                compare(isoFrame.frameArtifacts.orthogonalPanels[isoIndex].liveProjectionMode, "ISOMETRIC")
                compare(isoFrame.frameArtifacts.orthogonalPanels[isoIndex].projectionMode,
                        "full-body-oblique-display")
            }
            sideCanvas.destroy()
        }

        function test_isometricFacePresentationSeparatesMaterialAndDieFaces() {
            let preview = qualifiedPreview()
            let canvas = createCanvas(preview, {
                liveProjectionMode: "ISOMETRIC"
            })

            let topPresentation = canvas.materialFacePresentation(preview.bends[0])
            compare(topPresentation.face, "TOP")
            compare(topPresentation.label, "MATERIAL FACE TOP")
            compare(topPresentation.symbol, "▲")
            compare(topPresentation.pattern, "chevron")

            preview.flatPattern.preview2d.sourceFace = "bottomFace"
            canvas.programPreviewJson = JSON.stringify(preview)
            wait(50)
            let bottomPresentation = canvas.materialFacePresentation(preview.bends[0])
            compare(bottomPresentation.face, "BOTTOM")
            compare(bottomPresentation.label, "MATERIAL FACE BOTTOM")
            compare(bottomPresentation.symbol, "▼")
            compare(bottomPresentation.pattern, "cross")

            let explicitMaterialFace = JSON.parse(JSON.stringify(preview.bends[0]))
            explicitMaterialFace.materialFace = "TOP"
            compare(canvas.operationMaterialFace(explicitMaterialFace), "TOP")
            explicitMaterialFace.materialFace = "BOTTOM"
            compare(canvas.operationMaterialFace(explicitMaterialFace), "BOTTOM")
            preview.flatPattern.preview2d.sourceFace = "sideFace"
            canvas.programPreviewJson = JSON.stringify(preview)
            wait(50)
            compare(canvas.operationMaterialFace({ face: "BOTTOM" }), "UNKNOWN")
            compare(canvas.materialFacePresentation({ face: "BOTTOM" }).pattern, "dash")

            let topSegments = canvas.materialFacePatternSegments("chevron", 10, 20, 4)
            let bottomSegments = canvas.materialFacePatternSegments("cross", 10, 20, 4)
            compare(topSegments.length, 0)
            compare(bottomSegments.length, 2)
            canvas.destroy()
        }

        function test_isometricPhysicalFaceClassificationAndPalette() {
            let preview = qualifiedPreview()
            let canvas = createCanvas(preview, {
                liveProjectionMode: "ISOMETRIC"
            })
            let frame = canvas.runRenderFrame.live.frameArtifacts
            let sectionFrame = frame.v5SectionFrame
            let ray = canvas.isometricViewingRay(sectionFrame)
            verify(Math.abs(Math.hypot(ray.x, ray.y, ray.z) - 1) < 1.0e-8)

            let rootPanel = null
            for (let panelIndex = 0; panelIndex < frame.orthogonalPanels.length; panelIndex++) {
                if (frame.orthogonalPanels[panelIndex].graphPanelId === "root")
                    rootPanel = frame.orthogonalPanels[panelIndex]
            }
            verify(!!rootPanel)
            compare(rootPanel.physicalFace, "INITIAL_TOP")
            verify(!rootPanel.oppositePhysicalFace)

            let same = canvas.v5PhysicalFaceClassification(
                rootPanel.worldFaceNormal, sectionFrame, rootPanel.worldFaceNormal)
            compare(same.side, "INITIAL_TOP")
            verify(!same.opposite)
            let reversedNormal = {
                x: -rootPanel.worldFaceNormal.x,
                y: -rootPanel.worldFaceNormal.y,
                z: -rootPanel.worldFaceNormal.z
            }
            let opposite = canvas.v5PhysicalFaceClassification(
                reversedNormal, sectionFrame, rootPanel.worldFaceNormal)
            compare(opposite.side, "OPPOSITE")
            verify(opposite.opposite)

            let lightPalette = canvas.livePanelFacePalette({ current: true })
            let darkPalette = canvas.livePanelFacePalette({
                current: true, oppositePhysicalFace: true
            })
            compare(lightPalette.fill, "#bfdbfe")
            compare(darkPalette.fill, "#709ccf")
            compare(lightPalette.stroke, darkPalette.stroke)

            let top = canvas.materialFacePresentation({ materialFace: "TOP" })
            let visibleOpposite = canvas.panelMaterialFacePresentation(
                top, { oppositePhysicalFace: true })
            compare(visibleOpposite.face, "BOTTOM")
            compare(visibleOpposite.pattern, "none")
            compare(canvas.materialFacePatternSegments(
                visibleOpposite.pattern, 10, 20, 4).length, 0)
            compare(canvas.v5PunchContactFace({ direction: "UP" }), "INITIAL_TOP")
            compare(canvas.v5PunchContactFace({ direction: "DOWN" }), "OPPOSITE")

            canvas.liveProjectionMode = "SIDE"
            let sidePalette = canvas.livePanelFacePalette({
                current: true, oppositePhysicalFace: true
            })
            compare(sidePalette.fill, lightPalette.fill)
            canvas.destroy()
        }

        function test_completedFilletCuesAreContactStyledAndDisplayOnly() {
            function collect(reverseFirstHinge) {
                let preview = asymmetricPlacementLiveParityPreview(false)
                if (reverseFirstHinge) {
                    let edge = preview.sheetMetalGraph.bendEdges[0]
                    let start = edge.hingeStart
                    edge.hingeStart = edge.hingeEnd
                    edge.hingeEnd = start
                    edge.hingeSegments = [[edge.hingeStart, edge.hingeEnd]]
                    edge.childSideSign = -edge.childSideSign
                }
                let canvas = createCanvas(preview, {
                    selectedBendIndex: 1,
                    selectedBend: preview.bends[1],
                    liveProjectionMode: "ISOMETRIC"
                })
                let artifacts = canvas.runRenderFrame.live.frameArtifacts
                let snapshot = []
                for (let cueIndex = 0; cueIndex < artifacts.v5FilletCues.length; cueIndex++) {
                    let cue = artifacts.v5FilletCues[cueIndex]
                    compare(cue.sequenceHint, 1)
                    compare(cue.lines.length, 2)
                    verify(!cue.dashed)
                    compare(cue.geometryAuthority, "renderer-contact-limit-cue")
                    snapshot.push({
                        panelId: cue.panelId,
                        contact: cue.contact,
                        dashed: cue.dashed,
                        zoneWidth: Number(cue.zoneWidth.toFixed(6))
                    })
                }
                verify(snapshot.length > 0)
                snapshot.sort(function(a, b) {
                    return a.panelId.localeCompare(b.panelId)
                })
                let polygons = artifacts.orthogonalPanels.map(function(panelValue) {
                    return {
                        panelId: panelValue.graphPanelId,
                        polygon: panelValue.polygon
                    }
                })
                canvas.destroy()
                return { cues: snapshot, polygons: polygons }
            }

            let forward = collect(false)
            let reversed = collect(true)
            compare(JSON.stringify(reversed.cues), JSON.stringify(forward.cues))
            compare(JSON.stringify(reversed.polygons), JSON.stringify(forward.polygons))

            let preview = asymmetricPlacementLiveParityPreview(false)
            let sideCanvas = createCanvas(preview, {
                selectedBendIndex: 1,
                selectedBend: preview.bends[1],
                liveProjectionMode: "SIDE"
            })
            compare(sideCanvas.runRenderFrame.live.frameArtifacts.v5FilletCues.length, 0)
            sideCanvas.destroy()

            let firstCanvas = createCanvas(preview, {
                selectedBendIndex: 0,
                selectedBend: preview.bends[0],
                liveProjectionMode: "ISOMETRIC"
            })
            compare(firstCanvas.runRenderFrame.live.frameArtifacts.v5FilletCues.length, 0)
            firstCanvas.destroy()
        }

        function test_toolingExtrusionUsesSharedIsometricDepthBasisOnlyInIso() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "SIDE"
            })
            let sideVector = canvas.isometricToolingExtrusionVector("SIDE")
            compare(sideVector.x, 0)
            compare(sideVector.r, 0)

            let isoVector = canvas.isometricToolingExtrusionVector("ISOMETRIC")
            verify(isoVector.x < 0)
            verify(isoVector.r > 0)
            compare(isoVector.x / isoVector.r,
                    canvas.isometricDepthXPerIn / canvas.isometricDepthRPerIn)
            let sharedVector = canvas.isometricDisplayDepthVector(
                canvas.toolingVisualDepthIn, "ISOMETRIC")
            compare(isoVector.x, -sharedVector.x)
            compare(isoVector.r, -sharedVector.r)

            let explicitPositive = canvas.isometricToolingExtrusionVector(
                "ISOMETRIC", 1)
            compare(explicitPositive.x, sharedVector.x)
            compare(explicitPositive.r, sharedVector.r)

            let envelope = canvas.isometricMachineEnvelope(
                -2, 3, -4, 5, canvas.toolingVisualDepthIn, "ISOMETRIC")
            compare(envelope.front.length, 4)
            compare(envelope.rear.length, 4)
            for (let envelopeIndex = 0; envelopeIndex < 4; envelopeIndex++) {
                compare(envelope.rear[envelopeIndex].x - envelope.front[envelopeIndex].x,
                        isoVector.x)
                compare(envelope.rear[envelopeIndex].r - envelope.front[envelopeIndex].r,
                        isoVector.r)
            }

            let drawCalls = []
            let drawContext = {
                save: function() {}, restore: function() {},
                beginPath: function() {}, closePath: function() {},
                moveTo: function(x, y) { drawCalls.push({ x: x, y: y }) },
                lineTo: function(x, y) { drawCalls.push({ x: x, y: y }) },
                fill: function() {}, stroke: function() {},
                fillStyle: "", strokeStyle: "", lineWidth: 0
            }
            canvas.liveProjectionMode = "ISOMETRIC"
            verify(canvas.drawIsometricMachineEnvelope(
                drawContext, function(value) { return value },
                function(value) { return value }, -2, 3, -4, 5))
            for (let drawIndex = 0; drawIndex < drawCalls.length; drawIndex++) {
                verify(drawCalls[drawIndex].x >= -2 - 1.0e-9)
                verify(drawCalls[drawIndex].x <= 3 + 1.0e-9)
                verify(drawCalls[drawIndex].y >= -4 - 1.0e-9)
                verify(drawCalls[drawIndex].y <= 5 + 1.0e-9)
            }

            let closedModel = {
                polylines: [{
                    closed: true,
                    points: [
                        { x: 0, y: 0 }, { x: 4, y: 0 },
                        { x: 4, y: 1 }, { x: 0, y: 1 }
                    ]
                }, {
                    closed: true,
                    points: [
                        { x: 1, y: 0.2 }, { x: 2, y: 0.2 },
                        { x: 2, y: 0.4 }, { x: 1, y: 0.4 }
                    ]
                }],
                lines: [], circles: [], arcs: []
            }
            compare(canvas.dxfOuterClosedPolyline(closedModel),
                    closedModel.polylines[0].points)
            compare(canvas.dxfOuterClosedPolyline({
                polylines: [{
                    closed: false,
                    points: [{ x: 0, y: 0 }, { x: 1, y: 0 }]
                }]
            }), null)
            canvas.destroy()
        }

        function test_toolingStationsUseTheSameSignedCameraBasisAsExtrusion() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC",
                liveCameraOrientation: "ISO_TOP_LEFT"
            })
            for (let station of [-5, -1, 1, 5]) {
                let offset = canvas.toolingStationDisplayOffset(station, "ISOMETRIC")
                let extrusion = canvas.isometricToolingExtrusionVector(
                    "ISOMETRIC", -1, Math.abs(station))
                let sign = station < 0 ? -1 : 1
                compare(offset.x, extrusion.x * sign)
                compare(offset.r, extrusion.r * sign)
            }
            let sideOffset = canvas.toolingStationDisplayOffset(5, "SIDE")
            compare(sideOffset.x, 0)
            compare(sideOffset.r, 0)
            canvas.destroy()
        }

        function test_isometricCameraOrientationsShareMaterialAndToolingSigns() {
            let orientations = ({
                ISO_TOP_LEFT: [0.32, -0.18, 1, 1],
                ISO_TOP_RIGHT: [-0.32, -0.18, 1, 1],
                ISO_BOTTOM_LEFT: [0.32, 0.18, 1, 1],
                ISO_BOTTOM_RIGHT: [-0.32, 0.18, 1, 1],
                ISO_TOP: [0, -0.18, 1, 1],
                ISO_BOTTOM: [0, 0.18, 1, 1],
                ISO_LEFT: [0.32, 0, 1, 1],
                ISO_RIGHT: [-0.32, 0, 1, 1],
                ISO_FRONT: [0, 0, 1, 1],
                ISO_BACK: [0, 0, -1, -1]
            })
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            for (let orientation in orientations) {
                canvas.liveCameraOrientation = orientation
                let basis = canvas.isometricCameraBasis()
                compare(basis.orientation, orientation)
                fuzzyCompare(basis.depthXPerIn, orientations[orientation][0], 0.000001)
                fuzzyCompare(basis.depthRPerIn, orientations[orientation][1], 0.000001)
                compare(basis.viewAxisSign, orientations[orientation][2])
                compare(basis.screenXSign, orientations[orientation][3])
                let display = canvas.isometricDisplayDepthVector(
                    1, "ISOMETRIC", orientation)
                let tooling = canvas.isometricToolingExtrusionVector(
                    "ISOMETRIC", -1, 1, orientation)
                compare(tooling.x, -display.x)
                compare(tooling.r, -display.r)
                let station = canvas.toolingStationDisplayOffset(1, "ISOMETRIC")
                compare(station.x, tooling.x)
                compare(station.r, tooling.r)
                verify(isFinite(basis.depthXPerIn))
                verify(isFinite(basis.depthRPerIn))
            }
            compare(canvas.normalizedLiveCameraOrientation("invalid"), "ISO_TOP_LEFT")
            canvas.destroy()
        }

        function test_cameraOrientationIsPartOfTheLiveFrameCacheKey() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC",
                liveCameraOrientation: "ISO_TOP_LEFT"
            })
            let frame = canvas.runRenderFrame.live
            let leftKey = canvas.liveFrameCacheKeyFor(
                canvas.sceneData, frame.staticScene, frame.pose)
            canvas.liveCameraOrientation = "ISO_TOP_RIGHT"
            let rightKey = canvas.liveFrameCacheKeyFor(
                canvas.sceneData, frame.staticScene, frame.pose)
            verify(leftKey !== rightKey)
            verify(rightKey.indexOf("orientation=ISO_TOP_RIGHT") >= 0)
            canvas.destroy()
        }

        function test_projectedV5PanelsReuseNarrowGeometryState() {
            let preview = qualifiedPreview()
            let canvas = createCanvas(preview, {
                liveProjectionMode: "ISOMETRIC",
                liveCameraOrientation: "ISO_TOP_LEFT"
            })
            let pose = canvas.runRenderFrame.live.pose
            let first = canvas.buildQualifiedV5LivePanels(canvas.sceneData, pose)
            verify(first.panels.length > 0)
            let hitsBefore = canvas.v5ProjectedPanelArtifactCacheHits
            let readoutOnlyPose = Object.assign({}, pose, {
                gaugeFaceX: pose.gaugeFaceX - 2,
                punchTipR: pose.punchTipR + 1,
                phase: "RUN / RETRACT"
            })
            let retained = canvas.buildQualifiedV5LivePanels(
                canvas.sceneData, readoutOnlyPose)
            compare(canvas.v5ProjectedPanelArtifactCacheHits, hitsBefore + 1)
            compare(retained.panels, first.panels)
            compare(retained.panelFaces, first.panelFaces)
            compare(retained.projectedPanelBounds, first.projectedPanelBounds)

            let missesBefore = canvas.v5ProjectedPanelArtifactCacheMisses
            let movedMaterialPose = Object.assign({}, pose, {
                centerR: pose.centerR + 0.05
            })
            let rebuilt = canvas.buildQualifiedV5LivePanels(
                canvas.sceneData, movedMaterialPose)
            compare(canvas.v5ProjectedPanelArtifactCacheMisses, missesBefore + 1)
            verify(rebuilt.panels !== first.panels)

            missesBefore = canvas.v5ProjectedPanelArtifactCacheMisses
            let changedAnglePose = Object.assign({}, pose, {
                armRiseDeg: pose.armRiseDeg + 2
            })
            rebuilt = canvas.buildQualifiedV5LivePanels(
                canvas.sceneData, changedAnglePose)
            compare(canvas.v5ProjectedPanelArtifactCacheMisses, missesBefore + 1)
            verify(rebuilt.panels !== first.panels)

            canvas.liveCameraOrientation = "ISO_TOP_RIGHT"
            rebuilt = canvas.buildQualifiedV5LivePanels(canvas.sceneData, pose)
            compare(canvas.v5ProjectedPanelArtifactCacheMisses, 1)
            verify(rebuilt.panels !== first.panels)
            canvas.destroy()
        }

        function test_projectedV5PanelBoundsPreserveExactSceneBounds() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "SIDE",
                liveCameraOrientation: "ISO_TOP_LEFT"
            })
            let orientations = ["ISO_TOP_LEFT", "ISO_BOTTOM_RIGHT"]
            let angles = [0, 45, 90]
            for (let orientationIndex = 0;
                    orientationIndex < orientations.length;
                    orientationIndex++) {
                canvas.liveProjectionMode = orientationIndex === 0
                    ? "SIDE" : "ISOMETRIC"
                canvas.liveCameraOrientation = orientations[orientationIndex]
                for (let angleIndex = 0; angleIndex < angles.length;
                        angleIndex++) {
                    canvas.invalidateLiveRenderCaches()
                    let basePose = canvas.runRenderFrame.live.pose
                    let pose = Object.assign({}, basePose, {
                        armRiseDeg: angles[angleIndex],
                        gaugeFaceX: basePose.gaugeFaceX - angleIndex * 0.4,
                        punchTipR: basePose.punchTipR + angleIndex * 0.3
                    })
                    let projected = canvas.buildQualifiedV5LivePanels(
                        canvas.sceneData, pose)
                    verify(projected.panels.length > 0)
                    verify(isFinite(projected.projectedPanelBounds.minX))
                    verify(isFinite(projected.projectedPanelBounds.maxX))
                    verify(isFinite(projected.projectedPanelBounds.minR))
                    verify(isFinite(projected.projectedPanelBounds.maxR))
                    let scannedPanelBounds = {
                        minX: Infinity, maxX: -Infinity,
                        minR: Infinity, maxR: -Infinity
                    }
                    for (let panelIndex = 0;
                            panelIndex < projected.panels.length; panelIndex++) {
                        let panelValue = projected.panels[panelIndex]
                        let panelPoints = panelValue.polygon.length >= 2
                            ? panelValue.polygon
                            : panelValue.corners
                        for (let pointIndex = 0;
                                pointIndex < panelPoints.length; pointIndex++) {
                            scannedPanelBounds.minX = Math.min(
                                scannedPanelBounds.minX, panelPoints[pointIndex].x)
                            scannedPanelBounds.maxX = Math.max(
                                scannedPanelBounds.maxX, panelPoints[pointIndex].x)
                            scannedPanelBounds.minR = Math.min(
                                scannedPanelBounds.minR, panelPoints[pointIndex].r)
                            scannedPanelBounds.maxR = Math.max(
                                scannedPanelBounds.maxR, panelPoints[pointIndex].r)
                        }
                    }
                    compare(projected.projectedPanelBounds.minX,
                            scannedPanelBounds.minX)
                    compare(projected.projectedPanelBounds.maxX,
                            scannedPanelBounds.maxX)
                    compare(projected.projectedPanelBounds.minR,
                            scannedPanelBounds.minR)
                    compare(projected.projectedPanelBounds.maxR,
                            scannedPanelBounds.maxR)
                    let geometry = canvas.buildLiveSectionGeometryFromData(
                        canvas.sceneData, pose, canvas.sceneData.currentBend)
                    let staticScene = canvas.runRenderFrame.live.staticScene
                    let scanned = canvas.resolveLiveSceneBounds(
                        canvas.sceneData, staticScene, pose, geometry, [],
                        projected.panels)
                    let retained = canvas.resolveLiveSceneBounds(
                        canvas.sceneData, staticScene, pose, geometry, [],
                        projected.panels, projected.projectedPanelBounds)
                    compare(retained.minX, scanned.minX)
                    compare(retained.maxX, scanned.maxX)
                    compare(retained.minR, scanned.minR)
                    compare(retained.maxR, scanned.maxR)

                    let invalidBounds = {
                        minX: NaN, maxX: 1, minR: 0, maxR: 1
                    }
                    let fallback = canvas.resolveLiveSceneBounds(
                        canvas.sceneData, staticScene, pose, geometry, [],
                        projected.panels, invalidBounds)
                    compare(fallback.minX, scanned.minX)
                    compare(fallback.maxX, scanned.maxX)
                    compare(fallback.minR, scanned.minR)
                    compare(fallback.maxR, scanned.maxR)
                }
            }
            canvas.destroy()
        }

        function test_liveStaticAndToolingIdentityKeysReuseResolvedValues() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC",
                liveCameraOrientation: "ISO_TOP_LEFT"
            })
            let staticScene = canvas.resolveLiveStaticScene()
            let staticKey = canvas.liveStaticSceneCacheKey
            let toolingKey = canvas.liveToolingBoundsIdentityKey
            verify(staticScene !== null)
            verify(staticKey.length > 0)
            verify(toolingKey.indexOf(staticKey) === 0)
                compare(canvas.liveStaticSceneBendIdentity,
                    canvas.currentSelectedBendValue())
            compare(canvas.liveStaticSceneKeyFor(), staticKey)

            let pose = canvas.runRenderFrame.live.pose
            let cachedBounds = canvas.liveToolingBoundsCache
            let cachedBoundsKey = canvas.liveToolingBoundsCacheKey
            let bounds = {
                minX: Infinity, maxX: -Infinity,
                minR: Infinity, maxR: -Infinity
            }
            canvas.includeLiveToolingBounds(bounds, pose, staticScene)
            compare(canvas.liveToolingBoundsIdentityKey, toolingKey)
            compare(canvas.liveToolingBoundsCache, cachedBounds)
            compare(canvas.liveToolingBoundsCacheKey, cachedBoundsKey)

            let originalBend = canvas.selectedBend
            canvas.selectedBend = Object.assign({}, originalBend, {
                id: "key-invalidation-probe"
            })
            verify(canvas.liveStaticSceneKeyFor() !== staticKey)
            canvas.selectedBend = originalBend

            canvas.punchCatalog = [{ id: "catalog-invalidation-probe" }]
            compare(canvas.liveStaticSceneCacheKey, "")
            compare(canvas.liveStaticSceneBendIdentity, null)
            compare(canvas.liveToolingBoundsIdentityKey, "")

            canvas.resolveLiveStaticScene()
            verify(canvas.liveStaticSceneCacheKey.length > 0)
            canvas.dieCatalog = [{ id: "catalog-invalidation-probe" }]
            compare(canvas.liveStaticSceneCacheKey, "")
            compare(canvas.liveStaticSceneBendIdentity, null)
            compare(canvas.liveToolingBoundsIdentityKey, "")

            canvas.invalidateLiveRenderCaches()
            compare(canvas.liveStaticSceneCacheKey, "")
            compare(canvas.liveStaticSceneBendIdentity, null)
            compare(canvas.liveToolingBoundsIdentityKey, "")
            compare(canvas.liveToolingBoundsCacheKey, "")
            canvas.destroy()
        }

        function test_projectedHingeEndpointReusePreservesExactCaps() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC",
                liveCameraOrientation: "ISO_TOP_LEFT"
            })
            let pose = canvas.runRenderFrame.live.pose
            let staticDescriptors = canvas.v5StaticDescriptors(canvas.sceneData)
            let direct = canvas.buildQualifiedV5LivePanels(
                canvas.sceneData, pose)
            let renderGeometry = canvas.v5PreparedRenderGeometry(canvas.sceneData)
            let edge = direct.compiled.model.edges[0]
            let parentPanel = null
            for (let panelIndex = 0; panelIndex < direct.panels.length;
                    panelIndex++) {
                if (direct.panels[panelIndex].graphPanelId === edge.parentPanelId
                        && !direct.panels[panelIndex].sectionSegment) {
                    parentPanel = direct.panels[panelIndex]
                    break
                }
            }
            verify(!!parentPanel)
            let directSpans = canvas.v5ProjectedDisplayHingeSegments(
                direct.compiled, edge, direct.sectionFrame, pose)
            let reusedSpans = canvas
                .v5ProjectedDisplayHingeSegmentsFromPanelProjection(edge, {
                    points: parentPanel.polygon,
                    indexByPointKey: renderGeometry.byPanelId[edge.parentPanelId]
                        .outerVertexIndexByCoordinate
                })
            compare(JSON.stringify(reusedSpans), JSON.stringify(directSpans))

            let firstSpan = edge.hingeSegments[0]
            let startKey = canvas.v5PreparedPointKey(firstSpan[0])
            let partialIndex = Object.assign({},
                renderGeometry.byPanelId[edge.parentPanelId]
                    .outerVertexIndexByCoordinate)
            delete partialIndex[startKey]
            compare(canvas.v5ProjectedDisplayHingeSegmentsFromPanelProjection(
                edge, {
                    points: parentPanel.polygon,
                    indexByPointKey: partialIndex
                }), null)
            partialIndex[startKey] = -1
            compare(canvas.v5ProjectedDisplayHingeSegmentsFromPanelProjection(
                edge, {
                    points: parentPanel.polygon,
                    indexByPointKey: partialIndex
                }), null)

            let raw = canvas.v5LiveInternalEdges(
                direct.compiled, direct.sectionFrame, pose,
                staticDescriptors.currentSequence, true)
            let incomplete = ({})
            incomplete[edge.parentPanelId] = {
                points: parentPanel.polygon, indexByPointKey: ({})
            }
            let fallback = canvas.v5LiveInternalEdges(
                direct.compiled, direct.sectionFrame, pose,
                staticDescriptors.currentSequence, true, incomplete)
            compare(JSON.stringify(fallback), JSON.stringify(raw))
            canvas.destroy()
        }

        function test_projectedV5PanelsDoNotReuseDepartedExactAngle() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC",
                liveCameraOrientation: "ISO_TOP_LEFT"
            })
            canvas.invalidateLiveRenderCaches()
            let basePose = canvas.runRenderFrame.live.pose
            let poseA = Object.assign({}, basePose, { armRiseDeg: 5.005 })
            let poseB = Object.assign({}, basePose, { armRiseDeg: 5.03 })
            let poseAPrime = Object.assign({}, basePose, { armRiseDeg: 5.02 })

            let frameA = canvas.buildQualifiedV5LivePanels(canvas.sceneData, poseA)
            compare(canvas.v5ProjectedPanelArtifactCacheMisses, 1)
            let frameB = canvas.buildQualifiedV5LivePanels(canvas.sceneData, poseB)
            compare(canvas.v5ProjectedPanelArtifactCacheMisses, 2)
            verify(frameB.panels !== frameA.panels)
            let frameAPrime = canvas.buildQualifiedV5LivePanels(
                canvas.sceneData, poseAPrime)
            compare(canvas.v5ProjectedPanelArtifactCacheMisses, 3)
            compare(canvas.v5ProjectedPanelArtifactCacheHits, 0)
            verify(frameAPrime.panels !== frameA.panels)

            let warmGeometry = JSON.stringify(frameAPrime.panels)
            canvas.invalidateLiveRenderCaches()
            let coldFrameAPrime = canvas.buildQualifiedV5LivePanels(
                canvas.sceneData, poseAPrime)
            compare(JSON.stringify(coldFrameAPrime.panels), warmGeometry)
            compare(JSON.stringify(coldFrameAPrime.panelFaces),
                    JSON.stringify(frameAPrime.panelFaces))
            compare(JSON.stringify(coldFrameAPrime.offSectionPanelIds),
                    JSON.stringify(frameAPrime.offSectionPanelIds))
            compare(JSON.stringify(coldFrameAPrime.representativePanelIds),
                    JSON.stringify(frameAPrime.representativePanelIds))
            canvas.destroy()
        }

        function test_projectedV5PanelCacheEvictsOldestArtifact() {
            let canvas = createCanvas(qualifiedPreview())
            canvas.invalidateLiveRenderCaches()
            canvas.v5ProjectedPanelArtifactCacheLimit = 2
            let basePose = canvas.runRenderFrame.live.pose
            let firstPose = Object.assign({}, basePose, { centerR: 0.10 })
            canvas.buildQualifiedV5LivePanels(canvas.sceneData, firstPose)
            canvas.buildQualifiedV5LivePanels(
                canvas.sceneData, Object.assign({}, basePose, { centerR: 0.20 }))
            canvas.buildQualifiedV5LivePanels(
                canvas.sceneData, Object.assign({}, basePose, { centerR: 0.30 }))
            compare(canvas.v5ProjectedPanelArtifactCacheOrder.length, 2)
            let missesBefore = canvas.v5ProjectedPanelArtifactCacheMisses
            canvas.buildQualifiedV5LivePanels(canvas.sceneData, firstPose)
            compare(canvas.v5ProjectedPanelArtifactCacheMisses, missesBefore + 1)
            compare(canvas.v5ProjectedPanelArtifactCacheOrder.length, 2)
            canvas.destroy()
        }

        function test_isometricDepthDirectionIsIndependentOfAxisAndHingeOrder() {
            let preview = asymmetricPlacementLiveParityPreview(false)
            let xCanvas = createCanvas(preview, {
                selectedBendIndex: 0,
                selectedBend: preview.bends[0],
                liveProjectionMode: "ISOMETRIC"
            })
            let xVector = xCanvas.isometricToolingExtrusionVector("ISOMETRIC")
            verify(xVector.x < 0)
            verify(xVector.r > 0)
            xCanvas.destroy()

            for (let reversed of [false, true]) {
                let yPreview = asymmetricPlacementLiveParityPreview(reversed)
                let yCanvas = createCanvas(yPreview, {
                    selectedBendIndex: 1,
                    selectedBend: yPreview.bends[1],
                    liveProjectionMode: "ISOMETRIC"
                })
                let yVector = yCanvas.isometricToolingExtrusionVector("ISOMETRIC")
                compare(yVector.x, xVector.x)
                compare(yVector.r, xVector.r)
                let frame = yCanvas.runRenderFrame.live.frameArtifacts.v5SectionFrame
                verify(frame.viewAxis.y > 0.99)
                yCanvas.destroy()
            }
        }

        function test_toolingAppearanceProvidesOpaqueAndTranslucentPalettes() {
            let canvas = createCanvas(qualifiedPreview(), {
                toolingAppearance: "SOLID"
            })
            let solid = canvas.toolingAppearancePalette()
            verify(solid.solid)
            compare(solid.tableFill, "#4b5563")
            compare(solid.dieFill, "#1f2937")
            compare(solid.punchFill, "#64748b")
            compare(solid.sideFill, "#64748b")

            canvas.toolingAppearance = "TRANSLUCENT"
            let translucent = canvas.toolingAppearancePalette()
            verify(!translucent.solid)
            verify(translucent.tableFill.indexOf("rgba(") === 0)
            verify(translucent.dieFill.indexOf("rgba(") === 0)
            verify(translucent.punchFill.indexOf("rgba(") === 0)
            verify(translucent.sideFill.indexOf("rgba(") === 0)

            canvas.toolingAppearance = "invalid"
            compare(canvas.normalizedToolingAppearance(), "SOLID")
            canvas.destroy()
        }

        function test_openFingerDxfBuildsAppearanceAwareSolidWithoutMovingContact() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC",
                toolingAppearance: "SOLID"
            })
            let model = {
                bounds: { minX: 0, maxX: 4, minY: 0, maxY: 0.75 },
                polylines: [], circles: [{ cx: 0.375, cy: 0.375, radius: 0.15625 }],
                arcs: [{ cx: 0.375, cy: 0.375, radius: 0.375,
                         startDeg: 90, endDeg: 270 }],
                lines: [
                    { x1: 0.375, y1: 0, x2: 3.95, y2: 0 },
                    { x1: 0.375, y1: 0.75, x2: 2.95, y2: 0.75 },
                    { x1: 4, y1: 0, x2: 4, y2: 0.375 }
                ]
            }
            compare(canvas.dxfOuterClosedPolyline(model), null)
            let profile = canvas.fingerSideSolidProfile(model)
            verify(!!profile)
            compare(profile.anchorLocalX, 4)
            compare(profile.anchorLocalY, 0)
            // Original STEP finger silhouette: 7 straight vertices + 21 hinge-arc samples.
            compare(profile.outerLoop.length, 28)
            compare(profile.holeLoops.length, 1)
            compare(profile.holeLoops[0].length, 28)

            let fills = 0
            let destinationOutFills = 0
            let compositeStack = []
            let context = {
                save: function() {
                    compositeStack.push(this.globalCompositeOperation)
                },
                restore: function() {
                    this.globalCompositeOperation = compositeStack.pop()
                },
                beginPath: function() {}, closePath: function() {},
                moveTo: function() {}, lineTo: function() {},
                fill: function() {
                    fills++
                    if (this.globalCompositeOperation === "destination-out")
                        destinationOutFills++
                },
                stroke: function() {},
                fillStyle: "", strokeStyle: "", lineWidth: 0,
                globalCompositeOperation: "source-over"
            }
            let faceX = -0.9634
            let contactR = 0.018
            let solid = canvas.drawBackgaugeFingerSolid(
                context, profile, function(value) { return value },
                function(value) { return value }, faceX, contactR)
            verify(solid.drawn)
            verify(solid.extruded)
            compare(solid.outerWalls, 30)
            compare(solid.holeWalls, 28)
            verify(solid.vector.x < 0)
            verify(solid.vector.r > 0)
            verify(fills >= 62)
            compare(destinationOutFills, 2)
            compare(profile.anchorLocalX, 4)

            let solidPalette = canvas.backgaugeFingerAppearancePalette("SOLID")
            verify(solidPalette.solid)
            verify(solidPalette.frontFill.indexOf("rgba(") !== 0)
            let translucentPalette = canvas.backgaugeFingerAppearancePalette("TRANSLUCENT")
            verify(!translucentPalette.solid)
            verify(translucentPalette.frontFill.indexOf("rgba(") === 0)

            canvas.liveProjectionMode = "SIDE"
            let side = canvas.drawBackgaugeFingerSolid(
                context, profile, function(value) { return value },
                function(value) { return value }, faceX, contactR)
            verify(side.drawn)
            verify(!side.extruded)
            compare(side.outerWalls, 0)
            compare(side.holeWalls, 0)
            compare(side.vector.x, 0)
            compare(side.vector.r, 0)
            canvas.destroy()
        }

        function test_preparedBackgaugeFingerPreservesExactCommandStream() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC",
                toolingAppearance: "SOLID"
            })
            if (!canvas.liveBackgaugeFingerGeometry().profile)
                skip("backgauge finger DXF asset not bundled")
            let geometry = canvas.liveBackgaugeFingerGeometry()
            verify(!!geometry.profile)
            verify(!!geometry.preparedProfile)
            compare(canvas.liveBackgaugeFingerGeometry().preparedProfile,
                    geometry.preparedProfile)

            function recordingContext() {
                let calls = []
                let compositeStack = []
                return {
                    calls: calls,
                    save: function() {
                        calls.push("save")
                        compositeStack.push(this.globalCompositeOperation)
                    },
                    restore: function() {
                        calls.push("restore")
                        this.globalCompositeOperation = compositeStack.pop()
                    },
                    beginPath: function() { calls.push("begin") },
                    closePath: function() { calls.push("close") },
                    moveTo: function(x, y) { calls.push("M:" + x + ":" + y) },
                    lineTo: function(x, y) { calls.push("L:" + x + ":" + y) },
                    fill: function() {
                        calls.push("fill:" + this.globalCompositeOperation)
                    },
                    stroke: function() { calls.push("stroke") },
                    fillStyle: "",
                    strokeStyle: "",
                    lineWidth: 0,
                    globalCompositeOperation: "source-over"
                }
            }

            let directContext = recordingContext()
            let preparedContext = recordingContext()
            let sx = function(value) { return value * 37.25 + 11.125 }
            let sy = function(value) { return 97.875 - value * 29.5 }
            let faceX = -0.9634
            let contactR = 0.018
            let direct = canvas.drawBackgaugeFingerSolid(
                directContext, geometry.profile, sx, sy, faceX, contactR)
            let prepared = canvas.drawPreparedBackgaugeFingerSolid(
                preparedContext, geometry.preparedProfile,
                sx, sy, faceX, contactR)
            compare(prepared.drawn, direct.drawn)
            compare(prepared.extruded, direct.extruded)
            compare(prepared.outerWalls, direct.outerWalls)
            compare(prepared.holeWalls, direct.holeWalls)
            compare(preparedContext.calls.length, directContext.calls.length)
            for (let callIndex = 0;
                    callIndex < directContext.calls.length; callIndex++) {
                compare(preparedContext.calls[callIndex],
                        directContext.calls[callIndex],
                        "command mismatch at " + callIndex)
            }
            canvas.destroy()
        }

        function test_preparedBackgaugeFingerMatchesNativeCommandsAcrossViews() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC",
                liveCameraOrientation: "ISO_TOP_LEFT",
                toolingAppearance: "SOLID"
            })
            let modes = [
                { projection: "ISOMETRIC", orientation: "ISO_TOP_LEFT" },
                { projection: "ISOMETRIC", orientation: "ISO_TOP_RIGHT" },
                { projection: "ISOMETRIC", orientation: "ISO_BOTTOM_LEFT" },
                { projection: "ISOMETRIC", orientation: "ISO_BOTTOM_RIGHT" },
                { projection: "ISOMETRIC", orientation: "ISO_TOP" },
                { projection: "ISOMETRIC", orientation: "ISO_BOTTOM" },
                { projection: "ISOMETRIC", orientation: "ISO_LEFT" },
                { projection: "ISOMETRIC", orientation: "ISO_RIGHT" },
                { projection: "ISOMETRIC", orientation: "ISO_FRONT" },
                { projection: "ISOMETRIC", orientation: "ISO_BACK" },
                { projection: "SIDE", orientation: "ISO_TOP_LEFT" }
            ]
            for (let modeIndex = 0; modeIndex < modes.length; ++modeIndex) {
                canvas.liveProjectionMode = modes[modeIndex].projection
                canvas.liveCameraOrientation = modes[modeIndex].orientation
                let geometry = canvas.liveBackgaugeFingerGeometry()
                let directContext = canvas.createNativeRecordingContext()
                let preparedContext = canvas.createNativeRecordingContext()
                let sx = function(value) { return value * 37.25 + 11.125 }
                let sy = function(value) { return 97.875 - value * 29.5 }
                let direct = canvas.drawBackgaugeFingerSolid(
                    directContext, geometry.profile, sx, sy, -0.9634, 0.018)
                let prepared = canvas.drawPreparedBackgaugeFingerSolid(
                    preparedContext, geometry.preparedProfile,
                    sx, sy, -0.9634, 0.018)
                compare(prepared.drawn, direct.drawn)
                compare(JSON.stringify(preparedContext.orderedCommands),
                        JSON.stringify(directContext.orderedCommands),
                        "native stream mismatch for "
                        + modes[modeIndex].projection + "/"
                        + modes[modeIndex].orientation)
            }
            canvas.destroy()
        }

        function test_preparedBackgaugeFingerProductionPathFallsBackExactly() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC",
                liveCameraOrientation: "ISO_TOP_LEFT",
                toolingAppearance: "SOLID"
            })
            if (!canvas.liveBackgaugeFingerGeometry().profile)
                skip("backgauge finger DXF asset not bundled")
            let geometry = canvas.liveBackgaugeFingerGeometry()
            let retainedPrepared = geometry.preparedProfile
            let sx = function(value) { return value * 37.25 + 11.125 }
            let sy = function(value) { return 97.875 - value * 29.5 }
            let expectedContext = canvas.createNativeRecordingContext()
            canvas.drawBackgaugeFingerSide(
                expectedContext, sx, sy, -0.9634, 0.018)

            geometry.preparedProfile = null
            let absentContext = canvas.createNativeRecordingContext()
            canvas.drawBackgaugeFingerSide(
                absentContext, sx, sy, -0.9634, 0.018)
            compare(JSON.stringify(absentContext.orderedCommands),
                    JSON.stringify(expectedContext.orderedCommands))

            geometry.preparedProfile = {
                outerLoop: [], holeLoops: [],
                isometricVector: retainedPrepared.isometricVector,
                outerVisibleEdges: [], holeVisibleEdges: []
            }
            let failedContext = canvas.createNativeRecordingContext()
            canvas.drawBackgaugeFingerSide(
                failedContext, sx, sy, -0.9634, 0.018)
            compare(JSON.stringify(failedContext.orderedCommands),
                    JSON.stringify(expectedContext.orderedCommands))
            canvas.destroy()
        }

        function test_liveBadgeTextMetricsCachePreservesExactCommands() {
            let directCanvas = createCanvas(qualifiedPreview())
            let cachedCanvas = createCanvas(qualifiedPreview())
            let directContext = directCanvas.createNativeRecordingContext()
            let cachedContext = cachedCanvas.createNativeRecordingContext()
            let directMeasureCount = 0
            let cachedMeasureCount = 0
            let directMeasure = directContext.measureText
            let cachedMeasure = cachedContext.measureText
            directContext.measureText = function(text) {
                directMeasureCount++
                return directMeasure(text)
            }
            cachedContext.measureText = function(text) {
                cachedMeasureCount++
                return cachedMeasure(text)
            }
            directCanvas.drawBadge(
                directContext, 72.375, 48.625, "B3",
                "#dcfce7", "#166534",
                3.25, 4.75, 180.5, 120.25, [])
            directCanvas.liveBadgeTextWidthCache = ({})
            directCanvas.liveBadgeTextWidthCacheCount = 0
            directCanvas.drawBadge(
                directContext, 112.125, 75.875, "B3",
                "#dcfce7", "#166534",
                3.25, 4.75, 180.5, 120.25, [])
            cachedCanvas.drawBadge(
                cachedContext, 72.375, 48.625, "B3",
                "#dcfce7", "#166534",
                3.25, 4.75, 180.5, 120.25, [])
            cachedCanvas.drawBadge(
                cachedContext, 112.125, 75.875, "B3",
                "#dcfce7", "#166534",
                3.25, 4.75, 180.5, 120.25, [])
            compare(directMeasureCount, 2)
            compare(cachedMeasureCount, 1)
            compare(JSON.stringify(cachedContext.orderedCommands),
                    JSON.stringify(directContext.orderedCommands))
            cachedCanvas.invalidateLiveRenderCaches()
            compare(cachedCanvas.liveBadgeTextWidthCacheCount, 0)
            compare(Object.keys(cachedCanvas.liveBadgeTextWidthCache).length, 0)
            directCanvas.destroy()
            cachedCanvas.destroy()
        }

        function test_liveBadgeTextMetricsCacheSeparatesRendererBackends() {
            let canvas = createCanvas(qualifiedPreview())
            let canvasMeasureCount = 0
            let nativeMeasureCount = 0
            let canvasContext = {
                _liveBadgeMetricsNamespace: "canvas-context2d",
                measureText: function(text) {
                    canvasMeasureCount++
                    return { width: 31.375 }
                }
            }
            let nativeContext = {
                _liveBadgeMetricsNamespace: "native-recorder",
                measureText: function(text) {
                    nativeMeasureCount++
                    return { width: 12.25 }
                }
            }
            compare(canvas.measuredLiveBadgeTextWidth(
                        canvasContext, "B3"), 31.375)
            compare(canvas.measuredLiveBadgeTextWidth(
                        nativeContext, "B3"), 12.25)
            compare(canvas.measuredLiveBadgeTextWidth(
                        canvasContext, "B3"), 31.375)
            compare(canvas.measuredLiveBadgeTextWidth(
                        nativeContext, "B3"), 12.25)
            compare(canvasMeasureCount, 1)
            compare(nativeMeasureCount, 1)
            canvas.liveBadgeTextWidthCache = ({})
            canvas.liveBadgeTextWidthCacheCount = 63
            canvas.measuredLiveBadgeTextWidth(canvasContext, "B1")
            canvas.measuredLiveBadgeTextWidth(canvasContext, "B2")
            compare(canvas.liveBadgeTextWidthCacheCount, 1)
            compare(Object.keys(canvas.liveBadgeTextWidthCache).length, 1)
            canvas.destroy()
        }

        function test_liveFlangeBadgeLayoutRetainsExactCommandsPerViewport() {
            let uncachedCanvas = createCanvas(qualifiedPreview())
            let retainedCanvas = createCanvas(qualifiedPreview())
            let panels = [
                {
                    completed: true,
                    badgeKey: "panel-b2",
                    label: "B2",
                    labelPoint: { x: 0.75, r: 0.65 },
                    polygon: [
                        { x: -1.5, r: -0.5 }, { x: 2.0, r: -0.25 },
                        { x: 1.75, r: 1.5 }, { x: -1.25, r: 1.25 }
                    ]
                },
                {
                    completed: true,
                    badgeKey: "panel-b3",
                    label: "B3",
                    labelPoint: { x: 0.95, r: 0.75 },
                    polygon: [
                        { x: -0.5, r: -0.25 }, { x: 2.75, r: 0 },
                        { x: 2.5, r: 1.75 }, { x: -0.25, r: 1.5 }
                    ]
                }
            ]
            let sx = function(value) { return value * 37.25 + 113.125 }
            let sy = function(value) { return 91.875 - value * 28.5 }
            let uncachedArtifacts = { orthogonalPanels: panels }
            let retainedArtifacts = { orthogonalPanels: panels }
            let uncachedBuildStart = uncachedCanvas.liveBadgeLayoutBuildCount
            let retainedBuildStart = retainedCanvas.liveBadgeLayoutBuildCount
            let uncachedContext = uncachedCanvas.createNativeRecordingContext()
            uncachedContext.font = "11px serif"
            uncachedContext.fillStyle = "#123456"
            uncachedContext.strokeStyle = "#654321"
            uncachedContext.lineWidth = 4.25
            uncachedContext.textAlign = "right"
            uncachedContext.textBaseline = "bottom"
            uncachedContext.measureText = function(text) {
                return {
                    width: uncachedContext.font === "bold 10px sans-serif"
                        ? 31.375 : 83.625
                }
            }
            uncachedCanvas.drawLiveFlangePanelBadges(
                uncachedContext, sx, sy, uncachedArtifacts)
            uncachedArtifacts.liveBadgeLayout = null
            uncachedCanvas.drawLiveFlangePanelBadges(
                uncachedContext, sx, sy, uncachedArtifacts)

            let retainedContext = retainedCanvas.createNativeRecordingContext()
            retainedContext.font = "11px serif"
            retainedContext.fillStyle = "#123456"
            retainedContext.strokeStyle = "#654321"
            retainedContext.lineWidth = 4.25
            retainedContext.textAlign = "right"
            retainedContext.textBaseline = "bottom"
            let retainedMeasureText = retainedContext.measureText
            retainedContext.measureText = function(text) {
                return {
                    width: retainedContext.font === "bold 10px sans-serif"
                        ? 31.375 : 83.625
                }
            }
            retainedCanvas.drawLiveFlangePanelBadges(
                retainedContext, sx, sy, retainedArtifacts)
            let layout = retainedArtifacts.liveBadgeLayout
            verify(layout !== null)
            compare(layout.badges[0].w, 45.375)
            compare(retainedContext.font, "11px serif")
            compare(retainedContext.fillStyle, "#123456")
            compare(retainedContext.strokeStyle, "#654321")
            compare(retainedContext.lineWidth, 4.25)
            compare(retainedContext.textAlign, "right")
            compare(retainedContext.textBaseline, "bottom")
            compare(uncachedContext.font, "11px serif")
            retainedCanvas.drawLiveFlangePanelBadges(
                retainedContext, sx, sy, retainedArtifacts)
            compare(retainedArtifacts.liveBadgeLayout, layout)
            compare(retainedCanvas.liveBadgeLayoutBuildCount - retainedBuildStart, 1)
            compare(uncachedCanvas.liveBadgeLayoutBuildCount - uncachedBuildStart, 2)
            compare(JSON.stringify(retainedContext.orderedCommands),
                    JSON.stringify(uncachedContext.orderedCommands))

            let movedContext = retainedCanvas.createNativeRecordingContext()
            let movedSx = function(value) { return value * 37.25 + 114.125 }
            retainedCanvas.drawLiveFlangePanelBadges(
                movedContext, movedSx, sy, retainedArtifacts)
            verify(retainedArtifacts.liveBadgeLayout !== layout)
            compare(retainedCanvas.liveBadgeLayoutBuildCount - retainedBuildStart, 2)
            retainedCanvas.invalidateLiveRenderCaches()
            compare(retainedCanvas.liveBadgeLayoutBuildCount, 0)
            retainedContext.measureText = retainedMeasureText
            uncachedCanvas.destroy()
            retainedCanvas.destroy()
        }

        function test_liveFlangeBadgeBatchPreservesStandalonePaintCommands() {
            let batchedCanvas = createCanvas(qualifiedPreview())
            let standaloneCanvas = createCanvas(qualifiedPreview())
            let panels = [
                {
                    completed: true,
                    badgeKey: "batch-b2",
                    label: "B2",
                    labelPoint: { x: 0.75, r: 0.65 },
                    polygon: [
                        { x: -1.5, r: -0.5 }, { x: 2.0, r: -0.25 },
                        { x: 1.75, r: 1.5 }, { x: -1.25, r: 1.25 }
                    ]
                },
                {
                    completed: true,
                    badgeKey: "batch-b3",
                    label: "B3",
                    labelPoint: { x: 0.95, r: 0.75 },
                    polygon: [
                        { x: -0.5, r: -0.25 }, { x: 2.75, r: 0 },
                        { x: 2.5, r: 1.75 }, { x: -0.25, r: 1.5 }
                    ]
                }
            ]
            let sx = function(value) { return value * 37.25 + 113.125 }
            let sy = function(value) { return 91.875 - value * 28.5 }
            let artifacts = { orthogonalPanels: panels }
            let batchedContext = batchedCanvas.createNativeRecordingContext()
            let batchSaveCount = 0
            let batchRestoreCount = 0
            let originalBatchSave = batchedContext.save
            let originalBatchRestore = batchedContext.restore
            batchedContext.save = function() {
                batchSaveCount++
                originalBatchSave()
            }
            batchedContext.restore = function() {
                batchRestoreCount++
                originalBatchRestore()
            }
            batchedCanvas.drawLiveFlangePanelBadges(
                batchedContext, sx, sy, artifacts)

            let standaloneContext = standaloneCanvas.createNativeRecordingContext()
            let standaloneSaveCount = 0
            let standaloneRestoreCount = 0
            let originalStandaloneSave = standaloneContext.save
            let originalStandaloneRestore = standaloneContext.restore
            standaloneContext.save = function() {
                standaloneSaveCount++
                originalStandaloneSave()
            }
            standaloneContext.restore = function() {
                standaloneRestoreCount++
                originalStandaloneRestore()
            }
            for (let badgeIndex = 0;
                    badgeIndex < artifacts.liveBadgeLayout.badges.length;
                    badgeIndex++) {
                let badge = artifacts.liveBadgeLayout.badges[badgeIndex]
                standaloneCanvas.drawPlacedBadge(
                    standaloneContext, badge, badge.text,
                    "#dcfce7", "#166534")
            }
            compare(JSON.stringify(batchedContext.orderedCommands),
                    JSON.stringify(standaloneContext.orderedCommands))
            compare(batchSaveCount, 2)
            compare(batchRestoreCount, 2)
            compare(standaloneSaveCount, artifacts.liveBadgeLayout.badges.length)
            compare(standaloneRestoreCount,
                    artifacts.liveBadgeLayout.badges.length)
            batchedCanvas.destroy()
            standaloneCanvas.destroy()
        }

        function test_livePanelScreenGeometryRetainsExactPaintCommands() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let panel = {
                liveScreenGeometryId: "test-artifact|panel=face-1|section=0",
                liveContourNormalized: true,
                current: true,
                polygon: [
                    { x: -1.25, r: -0.75 },
                    { x: 2.5, r: -0.25 },
                    { x: 2.0, r: 1.75 },
                    { x: -1.0, r: 1.25 }
                ],
                corners: [
                    { x: -1.25, r: -0.75 },
                    { x: 2.5, r: -0.25 },
                    { x: 2.0, r: 1.75 },
                    { x: -1.0, r: 1.25 }
                ],
                holeLoops: [[
                    { x: 0.25, r: 0.10 },
                    { x: 0.75, r: 0.15 },
                    { x: 0.70, r: 0.65 },
                    { x: 0.20, r: 0.60 }
                ]],
                internalSharedCaps: []
            }
            let sx = function(value) { return value * 37.25 + 113.125 }
            let sy = function(value) { return 91.875 - value * 28.5 }
            let presentation = canvas.materialFacePresentation({
                materialFace: "BOTTOM"
            })

            panel.liveScreenGeometryId = ""
            let uncachedContext = canvas.createNativeRecordingContext()
            canvas.drawLiveOrthogonalPanel(
                uncachedContext, panel, sx, sy, presentation)
            panel.liveScreenGeometryId =
                "test-artifact|panel=face-1|section=0"
            let firstContext = canvas.createNativeRecordingContext()
            canvas.drawLiveOrthogonalPanel(
                firstContext, panel, sx, sy, presentation)
            compare(JSON.stringify(firstContext.orderedCommands),
                    JSON.stringify(uncachedContext.orderedCommands))
            let retained = canvas.livePanelScreenGeometry(panel, sx, sy)
            verify(retained !== null)
            let secondContext = canvas.createNativeRecordingContext()
            canvas.drawLiveOrthogonalPanel(
                secondContext, panel, sx, sy, presentation)
            compare(canvas.livePanelScreenGeometry(panel, sx, sy), retained)
            compare(JSON.stringify(secondContext.orderedCommands),
                    JSON.stringify(firstContext.orderedCommands))

            let movedContext = canvas.createNativeRecordingContext()
            let movedSx = function(value) { return value * 37.25 + 114.125 }
            canvas.drawLiveOrthogonalPanel(
                movedContext, panel, movedSx, sy, presentation)
            let moved = canvas.livePanelScreenGeometry(panel, movedSx, sy)
            verify(moved.viewportKey !== retained.viewportKey)
            canvas.destroy()
        }

        function test_isometricPatternBatchesStrokesWithoutDestructiveHoleCutout() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let calls = []
            let context = {
                save: function() { calls.push("save") },
                restore: function() { calls.push("restore") },
                beginPath: function() { calls.push("begin") },
                moveTo: function() {},
                lineTo: function() {},
                closePath: function() {},
                clip: function() { calls.push("clip") },
                stroke: function() { calls.push("stroke") },
                fill: function() { calls.push("fill:" + String(this.globalCompositeOperation)) },
                strokeStyle: "",
                fillStyle: "",
                lineWidth: 0,
                globalCompositeOperation: "source-over"
            }
            let panelValue = {
                polygon: [
                    { x: 0, r: 0 }, { x: 96, r: 0 },
                    { x: 96, r: 96 }, { x: 0, r: 96 }
                ],
                holeLoops: [[
                    { x: 30, r: 30 }, { x: 50, r: 30 },
                    { x: 50, r: 50 }, { x: 30, r: 50 }
                ]]
            }
            canvas.drawLiveMaterialFacePattern(
                context, panelValue, function(value) { return value },
                function(value) { return value },
                canvas.materialFacePresentation({ materialFace: "TOP" }),
                "#123456")
            compare(calls.filter(function(call) { return call === "save" }).length, 1)
            compare(calls.filter(function(call) { return call === "restore" }).length, 1)
            compare(calls.filter(function(call) { return call === "stroke" }).length, 1)
            verify(calls.indexOf("clip") >= 0)
            verify(calls.indexOf("fill:destination-out") < 0)
            canvas.destroy()
        }

        function test_isometricToolingBoundsIncludeTranslatedGeometryOnly() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let bounds = { minX: -100, maxX: 100, minR: -100, maxR: 100 }
            let model = {
                polylines: [{
                    closed: false,
                    points: [{ x: 0, y: 0 }, { x: 2, y: 1 }]
                }],
                lines: [], circles: [], arcs: []
            }
            let vector = canvas.isometricToolingExtrusionVector("ISOMETRIC")
            canvas.includeTransformedDxfBounds(
                bounds, model, 0, 0, 10, 20, false, false, 0, 1, vector)
            compare(bounds.minX, -100)
            compare(bounds.maxX, 100)
            compare(bounds.minR, -100)
            compare(bounds.maxR, 100)

            let toolingBounds = {
                minX: Infinity, maxX: -Infinity,
                minR: Infinity, maxR: -Infinity
            }
            canvas.includeTransformedDxfBounds(
                toolingBounds, model, 0, 0, 10, 20, false, false, 0, 1, vector)
            compare(toolingBounds.minX, Math.min(10, 10 + vector.x))
            compare(toolingBounds.maxX, Math.max(12, 12 + vector.x))
            compare(toolingBounds.minR, Math.min(20, 20 + vector.r))
            compare(toolingBounds.maxR, Math.max(21, 21 + vector.r))
            canvas.destroy()
        }

        function test_isometricExtrusionAddsCircularPrimitiveSideWall() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let fills = 0
            let context = {
                save: function() {}, restore: function() {},
                beginPath: function() {}, closePath: function() {},
                moveTo: function() {}, lineTo: function() {},
                fill: function() { fills++ }, stroke: function() {},
                fillStyle: "", strokeStyle: "", lineWidth: 0
            }
            let model = {
                polylines: [{
                    closed: true,
                    points: [
                        { x: 0, y: 0 }, { x: 2, y: 0 },
                        { x: 2, y: 1 }, { x: 0, y: 1 }
                    ]
                }],
                lines: [],
                circles: [{ cx: 1, cy: 0.5, radius: 0.15 }],
                arcs: []
            }
            let sideCount = canvas.drawDxfExtrusionSides(
                context, model, function(value) { return value },
                function(value) { return value }, 0, 0, 0, 0, 1,
                false, false, 0,
                canvas.isometricToolingExtrusionVector("ISOMETRIC"),
                "#123456")
            compare(sideCount, 5)
            compare(fills, 5)
            canvas.destroy()
        }

        function test_isometricGridRangeCoversAllCanvasCorners() {
            let canvas = createCanvas(qualifiedPreview(), {
                liveProjectionMode: "ISOMETRIC"
            })
            let range = canvas.isometricGridOffsetRange(640, 480, 24)
            let corners = [
                { x: 0, y: 0 }, { x: 640, y: 0 },
                { x: 0, y: 480 }, { x: 640, y: 480 }
            ]
            for (let index = 0; index < corners.length; index++) {
                let offset = corners[index].x * range.normalX
                    + corners[index].y * range.normalY
                verify(offset >= range.min)
                verify(offset <= range.max)
            }
            canvas.destroy()
        }

        function test_sideViewPlacesParentBodyAwayFromBackgaugeFinger() {
            let preview = qualifiedPreview()
            let canvas = createCanvas(preview, {
                liveProjectionMode: "SIDE",
                running: false
            })
            canvas.refreshLiveRenderFrame()
            let frame = canvas.runRenderFrame.live
            let panelsById = ({})
            for (let panelIndex = 0; panelIndex < frame.frameArtifacts.orthogonalPanels.length; panelIndex++) {
                let panelValue = frame.frameArtifacts.orthogonalPanels[panelIndex]
                panelsById[panelValue.graphPanelId] = panelValue
            }

            verify(!!panelsById.root)
            verify(!!panelsById.p1)
            let rootX = panelsById.root.polygon.map(function(value) { return value.x })
            let childX = panelsById.p1.polygon.map(function(value) { return value.x })
            verify(Math.min.apply(null, rootX) >= -1.0e-7)
            verify(Math.max.apply(null, childX) <= 1.0e-7)
            verify(frame.pose.gaugeFaceX < 0)
            canvas.destroy()
        }

        function test_directV5DebugOverlayUsesPosedHingeAndChildDirection() {
            let preview = qualifiedPreview()
            let canvas = createCanvas(preview, {
                liveProjectionMode: "SIDE",
                running: false
            })
            canvas.refreshLiveRenderFrame()
            let frame = canvas.runRenderFrame.live
            let overlay = frame.frameArtifacts.v5DebugOverlay

            compare(overlay.authority, "posed-v5")
            compare(overlay.legacyPositionReferences, false)
            compare(frame.frameArtifacts.placementJointGraph, null)
            compare(overlay.hinges.length, 1)
            compare(overlay.directions.length, 1)
            compare(overlay.hinges[0].edgeId, "edge-1")
            compare(overlay.hinges[0].childPanelId, "p1")
            compare(overlay.hinges[0].current, true)
            verify(Math.abs(overlay.hinges[0].a.x) < 1.0e-7)
            verify(Math.abs(overlay.hinges[0].b.x) < 1.0e-7)
            verify(Math.abs(overlay.directions[0].from.x) < 1.0e-7)
            verify(overlay.directions[0].to.x < -0.5)
            canvas.destroy()
        }

        function test_reversedActiveHingeKeepsV5OverlayOnPosedChildSide() {
            let preview = qualifiedPreview()
            let edgeValue = preview.sheetMetalGraph.bendEdges[0]
            let originalStart = edgeValue.hingeStart
            edgeValue.hingeStart = edgeValue.hingeEnd
            edgeValue.hingeEnd = originalStart
            edgeValue.hingeSegments = [[edgeValue.hingeStart, edgeValue.hingeEnd]]
            preview.bends[0].start_x_in = edgeValue.hingeStart.x_in
            preview.bends[0].start_y_in = edgeValue.hingeStart.y_in
            preview.bends[0].end_x_in = edgeValue.hingeEnd.x_in
            preview.bends[0].end_y_in = edgeValue.hingeEnd.y_in

            let canvas = createCanvas(preview, {
                liveProjectionMode: "SIDE",
                running: false
            })
            canvas.refreshLiveRenderFrame()
            let overlay = canvas.runRenderFrame.live.frameArtifacts.v5DebugOverlay

            compare(overlay.authority, "posed-v5")
            compare(overlay.directions.length, 1)
            verify(overlay.directions[0].to.x < overlay.directions[0].from.x)
            canvas.destroy()
        }

        function test_asymmetricCompletedPanelKeepsPlacementLiveSideAcrossPhases() {
            let phaseTimes = [0.0, 1.45, 3.70]
            let reverseValues = [false, true]
            for (let reverseIndex = 0; reverseIndex < reverseValues.length; reverseIndex++) {
                let preview = asymmetricPlacementLiveParityPreview(reverseValues[reverseIndex])
                let placementCanvas = createCanvas(preview, {
                    sceneMode: "PLACEMENT",
                    selectedBendIndex: 1,
                    selectedBend: preview.bends[1]
                })
                placementCanvas.rebuildSceneData()
                wait(50)
                compare(placementCanvas.v5PreviewValidationError(preview), "")
                let placementHole = placementCanvas.sceneData.projectedLoops[1].points
                let placementHoleX = placementHole.reduce(function(total, value) {
                    return total + value.x
                }, 0) / placementHole.length
                let currentLine = placementCanvas.sceneData.projectedBends.filter(function(value) {
                    return value.bend.id === "bend-2"
                })[0]
                let placementHingeX = (currentLine.start.x + currentLine.end.x) * 0.5
                verify(placementHoleX < placementHingeX)
                placementCanvas.destroy()

                let liveCanvas = createCanvas(preview, {
                    selectedBendIndex: 1,
                    selectedBend: preview.bends[1],
                    liveProjectionMode: "SIDE",
                    running: true
                })
                for (let phaseIndex = 0; phaseIndex < phaseTimes.length; phaseIndex++) {
                    liveCanvas.elapsedSeconds = phaseTimes[phaseIndex]
                    liveCanvas.refreshLiveRenderFrame()
                    let liveFrame = liveCanvas.runRenderFrame.live
                    let parity = liveFrame.frameArtifacts.v5OrientationParity
                    compare(parity.authority, "topology-witness-v5")
                    compare(parity.status, "PASS")
                    compare(parity.witnessPanelId, "p1")
                    compare(parity.witnessSequence, 1)
                    verify(Math.abs(parity.placementDepthDelta) > 0.01)
                    verify(parity.liveDeltaX > 0)
                    verify(parity.parentLiveDeltaX > 0)
                    verify(parity.gaugeFaceX < 0)

                    let livePanel = liveFrame.frameArtifacts.orthogonalPanels.filter(function(value) {
                        return value.graphPanelId === "p1"
                    })[0]
                    compare(livePanel.holeLoops.length, 1)
                    let panelX = livePanel.polygon.reduce(function(total, value) {
                        return total + value.x
                    }, 0) / livePanel.polygon.length
                    let holeX = livePanel.holeLoops[0].reduce(function(total, value) {
                        return total + value.x
                    }, 0) / livePanel.holeLoops[0].length
                    verify(holeX > panelX)
                }
                liveCanvas.destroy()
            }
        }

        function test_placementSetupFrameUsesAxisAndGaugeSideWithoutSequenceHistory() {
            let preview = asymmetricPlacementLiveParityPreview(false)
            let third = bend()
            third.id = "bend-3"
            third.sequenceHint = 3
            third.axis = "Y"
            third.closestSide = "POS"
            third.start_x_in = 5
            third.start_y_in = 3
            third.end_x_in = 5
            third.end_y_in = 1
            preview.bends.push(third)

            let canvas = createCanvas(preview, {
                selectedBendIndex: 1,
                selectedBend: preview.bends[1]
            })
            compare(canvas.shouldMirrorPlacementLine(preview, preview.bends[0]), true)
            compare(canvas.shouldMirrorPlacementLine(preview, preview.bends[1]), true)
            compare(canvas.shouldMirrorPlacementLine(preview, preview.bends[2]), false)

            let firstStart = preview.bends[0].start_x_in
            preview.bends[0].start_x_in = preview.bends[0].end_x_in
            preview.bends[0].end_x_in = firstStart
            compare(canvas.shouldMirrorPlacementLine(preview, preview.bends[1]), true)

            let originalStart = third.start_y_in
            third.start_y_in = third.end_y_in
            third.end_y_in = originalStart
            compare(canvas.shouldMirrorPlacementLine(preview, third), false)

            let unknownSide = bend()
            unknownSide.id = "bend-unknown"
            unknownSide.sequenceHint = 4
            unknownSide.axis = "Y"
            unknownSide.closestSide = ""
            preview.bends.push(unknownSide)
            compare(canvas.shouldMirrorPlacementLine(preview, unknownSide), false)
            delete unknownSide.closestSide
            compare(canvas.shouldMirrorPlacementLine(preview, unknownSide), false)

            let invalidSide = bend()
            invalidSide.id = "bend-invalid"
            invalidSide.sequenceHint = 5
            invalidSide.axis = "X"
            invalidSide.closestSide = "UNKNOWN"
            preview.bends.push(invalidSide)
            compare(canvas.shouldMirrorPlacementLine(preview, invalidSide), false)

            let reorderedPreview = asymmetricPlacementLiveParityPreview(false)
            reorderedPreview.bends.unshift(invalidSide)
            compare(canvas.shouldMirrorPlacementLine(reorderedPreview, third), false)
            canvas.destroy()
        }

        function test_isometricLongitudinalAxisMatchesPlacementOperationSide() {
            let preview = asymmetricPlacementLiveParityPreview(false)
            let third = bend()
            third.id = "bend-3"
            third.sequenceHint = 3
            third.axis = "Y"
            third.closestSide = "POS"
            preview.bends.push(third)

            let canvas = createCanvas(preview, {
                selectedBendIndex: 1,
                selectedBend: preview.bends[1],
                liveProjectionMode: "ISOMETRIC"
            })
            let b1Axis = canvas.v5IsometricOperationLongitudinalAxis(preview.bends[0])
            let b2Axis = canvas.v5IsometricOperationLongitudinalAxis(preview.bends[1])
            let b3Axis = canvas.v5IsometricOperationLongitudinalAxis(preview.bends[2])
            verify(b1Axis.x > 0.99)
            verify(b2Axis.y > 0.99)
            verify(b3Axis.y < -0.99)

            let b2Frame = canvas.runRenderFrame.live.frameArtifacts.v5SectionFrame
            verify(b2Frame.viewAxis.y > 0.99)
            let b2Horizontal = JSON.stringify(b2Frame.horizontal)
            let b2Vertical = JSON.stringify(b2Frame.vertical)
            let b2Origin = JSON.stringify(b2Frame.origin)

            let synthetic = {
                origin: b2Frame.origin,
                hingeStart: b2Frame.hingeStart,
                hingeEnd: b2Frame.hingeEnd,
                viewAxis: { x: 0, y: 1, z: 0 },
                horizontal: b2Frame.horizontal,
                vertical: b2Frame.vertical,
                parentOutward: b2Frame.parentOutward,
                childOutward: b2Frame.childOutward,
                angleRadians: b2Frame.angleRadians
            }
            let b3Frame = canvas.v5OrientSectionViewAxisForIsometricOperation(
                preview.bends[2], synthetic)
            verify(b3Frame.viewAxis.y < -0.99)
            compare(JSON.stringify(b3Frame.horizontal), b2Horizontal)
            compare(JSON.stringify(b3Frame.vertical), b2Vertical)
            compare(JSON.stringify(b3Frame.origin), b2Origin)

            canvas.liveProjectionMode = "SIDE"
            let sideFrame = canvas.v5OrientSectionViewAxisForIsometricOperation(
                preview.bends[1], synthetic)
            compare(sideFrame, synthetic)
            canvas.destroy()
        }

        function test_sameFaceOppositeGaugeSideRotatesPlacementEndForEnd() {
            let preview = asymmetricPlacementLiveParityPreview(false)
            let third = bend()
            third.id = "bend-3"
            third.sequenceHint = 3
            third.axis = "Y"
            third.closestSide = "POS"
            third.start_x_in = 5
            third.start_y_in = 3
            third.end_x_in = 5
            third.end_y_in = 0
            third.mid_x_in = 5
            third.mid_y_in = 1.5
            preview.bends.push(third)

            function holeLineOffset(currentIndex) {
                let placementCanvas = createCanvas(preview, {
                    sceneMode: "PLACEMENT",
                    selectedBendIndex: currentIndex,
                    selectedBend: preview.bends[currentIndex]
                })
                placementCanvas.rebuildSceneData()
                wait(50)
                let hole = placementCanvas.sceneData.projectedLoops[1].points
                let centerX = hole.reduce(function(total, value) {
                    return total + value.x
                }, 0) / hole.length
                let result = centerX - placementCanvas.topMachineWidthIn / 2
                placementCanvas.destroy()
                return result
            }

            let b2HoleLineOffset = holeLineOffset(1)
            let b3HoleLineOffset = holeLineOffset(2)
            verify(Math.abs(b2HoleLineOffset) > 0.1)
            verify(Math.abs(b3HoleLineOffset) > 0.1)
            verify(b2HoleLineOffset * b3HoleLineOffset < 0)
        }

        function test_leftViewLongitudinalSignPreservesSideCameraAcrossPhases() {
            let phaseTimes = [0.0, 1.45, 3.70]
            let reverseValues = [false, true]
            for (let reverseIndex = 0; reverseIndex < reverseValues.length; reverseIndex++) {
                let preview = asymmetricPlacementLiveParityPreview(reverseValues[reverseIndex])
                let canvas = createCanvas(preview, {
                    selectedBendIndex: 1,
                    selectedBend: preview.bends[1],
                    liveProjectionMode: "SIDE",
                    running: true
                })
                for (let phaseIndex = 0; phaseIndex < phaseTimes.length; phaseIndex++) {
                    canvas.elapsedSeconds = phaseTimes[phaseIndex]
                    canvas.refreshLiveRenderFrame()
                    let frame = canvas.runRenderFrame.live
                    let sectionFrame = frame.frameArtifacts.v5SectionFrame
                    verify(sectionFrame.viewAxis.y < -0.99)
                    verify(Math.abs(sectionFrame.viewAxis.x * sectionFrame.horizontal.x
                                    + sectionFrame.viewAxis.y * sectionFrame.horizontal.y
                                    + sectionFrame.viewAxis.z * sectionFrame.horizontal.z) < 1.0e-7)
                    compare(frame.frameArtifacts.v5OrientationAlignment.flipped, false)
                    verify(frame.frameArtifacts.v5OrientationParity.parentLiveDeltaX > 0)
                    verify(frame.pose.gaugeFaceX < 0)
                }
                canvas.destroy()
            }

            let xPreview = asymmetricPlacementLiveParityPreview(false)
            let xCanvas = createCanvas(xPreview, {
                selectedBendIndex: 0,
                selectedBend: xPreview.bends[0],
                liveProjectionMode: "SIDE",
                running: true,
                elapsedSeconds: 1.45
            })
            let xFrame = xCanvas.runRenderFrame.live.frameArtifacts.v5SectionFrame
            verify(xFrame.viewAxis.x > 0.99)
            verify(Math.abs(xFrame.viewAxis.x * xFrame.horizontal.x
                            + xFrame.viewAxis.y * xFrame.horizontal.y
                            + xFrame.viewAxis.z * xFrame.horizontal.z) < 1.0e-7)

            let synthetic = {
                origin: { x: 0, y: 0, z: 0 },
                hingeStart: { x: 0, y: 0, z: 0 },
                hingeEnd: { x: 0, y: 1, z: 0 },
                viewAxis: { x: 0, y: 1, z: 0 },
                horizontal: { x: 1, y: 0, z: 0 },
                vertical: { x: 0, y: 0, z: 1 },
                parentOutward: { x: 1, y: 0, z: 0 },
                childOutward: { x: -1, y: 0, z: 0 },
                angleRadians: 0
            }
            let oriented = xCanvas.v5OrientSectionViewAxisFromLeft(
                        xPreview.bends[1], synthetic)
            verify(oriented.viewAxis.y < -0.99)
            compare(oriented.horizontal, synthetic.horizontal)
            compare(oriented.vertical, synthetic.vertical)
            compare(oriented.origin, synthetic.origin)
            xCanvas.destroy()
        }

        function test_liveToPlacementRebuildRestoresContourAndBendLines() {
            let preview = asymmetricPlacementLiveParityPreview(false)
            let canvas = createCanvas(preview, {
                sceneMode: "LIVE",
                selectedBendIndex: 1,
                selectedBend: preview.bends[1]
            })
            compare(canvas.sceneData.projectedLoops.length, 0)

            canvas.sceneMode = "PLACEMENT"
            wait(100)

            verify(canvas.previewFrameReady)
            compare(canvas.renderedPreviewSceneMode, "PLACEMENT")
            verify(canvas.sceneData.projectedLoops.length >= 2)
            verify(canvas.sceneData.projectedLoops[0].points.length >= 6)
            verify(canvas.sceneData.projectedBends.length >= 2)
            for (let bendIndex = 0; bendIndex < canvas.sceneData.projectedBends.length; bendIndex++) {
                verify(!!canvas.sceneData.projectedBends[bendIndex].start)
                verify(!!canvas.sceneData.projectedBends[bendIndex].end)
                verify(isFinite(canvas.sceneData.projectedBends[bendIndex].start.x))
                verify(isFinite(canvas.sceneData.projectedBends[bendIndex].start.y))
                verify(isFinite(canvas.sceneData.projectedBends[bendIndex].end.x))
                verify(isFinite(canvas.sceneData.projectedBends[bendIndex].end.y))
            }
            canvas.destroy()
        }

        function test_b3UsesNewestDepthWitnessWithoutMirroringParentToFinger() {
            let preview = asymmetricPlacementLiveParityPreview(false)
            let expandedBoundary = [
                point(0, 0), point(6, 0), point(6, 3), point(5, 3),
                point(5, 4), point(1, 4), point(1, 3), point(0, 3)
            ]
            preview.flatPattern.width_in = 6
            preview.flatPattern.preview2d.loops[0] = {
                outer: true,
                points: expandedBoundary.concat([expandedBoundary[0]])
            }
            preview.sheetMetalGraph.materialBoundary.outerLoop = expandedBoundary
            let third = bend()
            third.id = "bend-3"
            third.sequenceHint = 3
            third.axis = "Y"
            third.closestSide = "POS"
            third.start_x_in = 5
            third.start_y_in = 0
            third.end_x_in = 5
            third.end_y_in = 3
            third.mid_x_in = 5
            third.mid_y_in = 1.5
            preview.bends.push(third)
            preview.sheetMetalGraph.panels.push({
                panelId: "p3", parentPanelId: "root", ownerBendId: "bend-3",
                geometryAuthority: "planar-subdivision-v5",
                outerLoop: [point(5, 0), point(6, 0), point(6, 3), point(5, 3)],
                holeLoops: []
            })
            preview.sheetMetalGraph.bendEdges.push({
                bendId: "edge-3", sourceBendId: "bend-3", sequenceHint: 3,
                parentPanelId: "root", childPanelId: "p3",
                hingeStart: point(5, 3), hingeEnd: point(5, 0),
                hingeSegments: [[point(5, 3), point(5, 0)]],
                bendAngleDegrees: 90, foldAngleDegrees: 90,
                insideRadius_in: 0.1, thickness_in: 0.1,
                kFactor: 0.44, childSideSign: 1, direction: "UP"
            })
            preview.sheetMetalGraph.diagnostics.expectedMaterialArea_in2 += 3
            preview.sheetMetalGraph.diagnostics.partitionArea_in2 += 3

            let canvas = createCanvas(preview, {
                selectedBendIndex: 2,
                selectedBend: preview.bends[2],
                liveProjectionMode: "SIDE",
                running: true
            })
            let phaseTimes = [0.0, 1.45, 3.70]
            for (let phaseIndex = 0; phaseIndex < phaseTimes.length; phaseIndex++) {
                canvas.elapsedSeconds = phaseTimes[phaseIndex]
                canvas.refreshLiveRenderFrame()
                let alignment = canvas.runRenderFrame.live.frameArtifacts.v5OrientationAlignment
                let parity = canvas.runRenderFrame.live.frameArtifacts.v5OrientationParity
                compare(alignment.witnessPanelId, "p2")
                compare(alignment.witnessSequence, 2)
                compare(alignment.status, "PASS")
                compare(alignment.flipped, false)
                verify(alignment.placementDepthDelta * alignment.alignedLiveDeltaX > 0)
                compare(parity.witnessPanelId, "p2")
                compare(parity.status, "PASS")
                verify(parity.placementDepthDelta * parity.liveDeltaX > 0)
                verify(parity.parentLiveDeltaX > 0)
                verify(parity.gaugeFaceX < 0)
            }
            canvas.destroy()
        }

        function test_toolUuidResolvesThroughCatalogToRealDxfAsset() {
            let preview = qualifiedPreview()
            preview.bends[0].punchId = "f2d6994c-50ef-4f6f-996b-48f383b75462"
            preview.bends[0].dieId = "35a9cdc8-8eb3-4417-9749-5b7258e74f97"
            delete preview.bends[0].punch
            delete preview.bends[0].die
            let canvas = createCanvas(preview, {
                punchCatalog: [{
                    id: "f2d6994c-50ef-4f6f-996b-48f383b75462",
                    name: "Acute 30° Punch [BC-9302]"
                }],
                dieCatalog: [{
                    id: "35a9cdc8-8eb3-4417-9749-5b7258e74f97",
                    name: "4 Way Die (0.630in) + Riser [BC-4387]"
                }]
            })

            compare(canvas.selectedToolToken("punch"), "Acute 30° Punch [BC-9302]")
            compare(canvas.selectedToolToken("die"), "4 Way Die (0.630in) + Riser [BC-4387]")
            verify(canvas.dxfAssetPath("punch", canvas.selectedToolToken("punch")).indexOf("9302") >= 0)
            verify(canvas.dxfAssetPath("die", canvas.selectedToolToken("die")).indexOf("4387") >= 0)
            canvas.destroy()
        }

        function test_physicalPunchUsesCalibratedRamTravelWithoutPhaseNormalization() {
            let preview = qualifiedPreview()
            let selected = preview.bends[0]
            selected.thickness = 0.1
            selected.punchToMaterialClearance = 0.1
            selected.startPosition = 5.7
            selected.clampPosition = 5.6
            selected.finalPosition = 5.3
            let canvas = createCanvas(preview, {
                selectedBend: selected,
                simulatedPlayback: false,
                physicalTelemetryFresh: true,
                physicalExecutionPhase: "BEND_MOVE",
                physicalRamToTableOpening: 8.3,
                physicalStartPosition: -2.6,
                physicalClampPosition: -2.7,
                physicalFinalPosition: -3.0,
                physicalRamPosition: -2.8
            })

            let atStart = canvas.physicalPunchTipR(-2.6, -2.6, 0.1)
            let atClamp = canvas.physicalPunchTipR(-2.7, -2.6, 0.1)
            let belowClamp = canvas.physicalPunchTipR(-2.8, -2.6, 0.1)
            let atFinal = canvas.physicalPunchTipR(-3.0, -2.6, 0.1)
            fuzzyCompare(atStart, 0.2, 0.000001)
            fuzzyCompare(atClamp, 0.1, 0.000001)
            fuzzyCompare(belowClamp, 0.0, 0.000001)
            fuzzyCompare(atFinal, -0.2, 0.000001)
            verify(atStart > atClamp)
            verify(atClamp > belowClamp)
            verify(belowClamp > atFinal)

            let pose = canvas.physicalPose(selected, null)
            fuzzyCompare(pose.punchTipR, belowClamp, 0.000001)
            canvas.physicalExecutionPhase = "BACK_GAUGE_AND_RAM_RETRACT_MOVE"
            canvas.physicalRamPosition = -2.65
            pose = canvas.physicalPose(selected, null)
            fuzzyCompare(pose.punchTipR, 0.15, 0.000001)

            canvas.physicalRamToTableOpening = 9.0
            canvas.physicalStartPosition = -3.3
            canvas.physicalClampPosition = -3.4
            fuzzyCompare(canvas.physicalPunchTipR(-3.5, -3.3, 0.1), belowClamp, 0.000001)
            canvas.destroy()
        }

        function test_physicalPunchCalibrationGatePreservesLegacyFallback() {
            let preview = qualifiedPreview()
            let selected = preview.bends[0]
            selected.thickness = 0.1
            let canvas = createCanvas(preview, {
                selectedBend: selected,
                physicalRamToTableOpening: NaN,
                physicalStartPosition: -2.6,
                physicalClampPosition: -2.7,
                physicalRamPosition: -2.65
            })
            fuzzyCompare(canvas.physicalPunchTipR(-2.65, -2.6, 0.1), 1.125, 0.000001)
            canvas.destroy()
        }

        function test_physicalPunchDerivesMissingClearanceWithConfiguredClampRate() {
            let preview = qualifiedPreview()
            let selected = preview.bends[0]
            selected.thickness = 0.1
            delete selected.punchToMaterialClearance
            let canvas = createCanvas(preview, {
                selectedBend: selected,
                physicalRamToTableOpening: 8.3,
                physicalMaterialClampRatePercentage: 20.0,
                physicalStartPosition: -2.6,
                physicalClampPosition: -2.72
            })

            fuzzyCompare(canvas.physicalPunchTipR(-2.6, -2.6, 0.1), 0.2, 0.000001)
            fuzzyCompare(canvas.physicalPunchTipR(-2.72, -2.6, 0.1), 0.08, 0.000001)
            canvas.destroy()
        }

        function test_certifiedBlackContourRetraceIsSkippedWithoutTouchingBends() {
            let canvas = createCanvas(qualifiedPreview())
            let contour = [
                { x: 0.03, y: 0.10 },
                { x: 0.03, y: 0.70 },
                { x: 0.03, y: 0.70 },
                { x: 0.03, y: 0.10 },
                { x: 0.00, y: 0.00 }
            ]
            for (let i = 0; i < 250; i++)
                contour.push({ x: 10.0 * i / 249.0, y: 8.0 })
            contour.push({ x: 10.0, y: 0.0 })

            let bounds = canvas.placementBounds(contour)
            compare(canvas.placementRetracedCornerStemEdgeSkipReason(
                        contour[0], contour[1], contour, bounds, 0),
                    "retraced-corner-stem")
            verify(canvas.placementStrokeSkipConfidence("retraced-corner-stem") >= 0.98)
            let stroke = canvas.placementStrokeSegments(contour, true, [])
            verify(stroke.skipped >= 1)
            canvas.destroy()
        }

        function test_cornerStemRetraceUsesCertifiedReasonButOrdinaryExteriorEdgeRemains() {
            let canvas = createCanvas(qualifiedPreview())
            let contour = [
                { x: 0.02, y: 0.08 },
                { x: 0.02, y: 0.66 },
                { x: 0.02, y: 0.10 }
            ]
            for (let sample = 0; sample < 247; sample++)
                contour.push({ x: 10.0 * sample / 246.0, y: 8.0 })
            contour.push({ x: 10.0, y: 0.0 })
            let bounds = canvas.placementBounds(contour)
            compare(canvas.placementCornerStemEdgeSkipReason(
                        contour[0], contour[1], contour, bounds, 0),
                    "retraced-corner-stem")
            verify(canvas.placementStrokeSkipConfidence("retraced-corner-stem") >= 0.98)
            compare(canvas.placementCornerStemEdgeSkipReason(
                        contour[100], contour[101], contour, bounds, 100), "")
            let stroke = canvas.placementStrokeSegments(contour, true, [])
            verify(stroke.skipped >= 1)
            canvas.destroy()
        }

        function test_hingeJunctionReliefStrokeIsHiddenButOrdinaryShortEdgeRemains() {
            let canvas = createCanvas(qualifiedPreview())
            let physicalEdge = {
                thickness_in: 0.06,
                insideRadius_in: 0.06
            }
            let bendLines = [
                {
                    start: { x: -2, y: 0 }, end: { x: 0, y: 0 },
                    graphEdge: physicalEdge
                },
                {
                    start: { x: 0, y: 0 }, end: { x: 0, y: 2 },
                    graphEdge: physicalEdge
                }
            ]
            compare(canvas.placementHingeJunctionReliefEdgeSkipReason(
                        { x: -0.03, y: -0.02 }, { x: 0.03, y: -0.02 }, bendLines),
                    "hinge-junction-relief")
            verify(canvas.placementStrokeSkipConfidence("hinge-junction-relief") >= 0.97)
            compare(canvas.placementHingeJunctionReliefEdgeSkipReason(
                        { x: 1.0, y: 1.0 }, { x: 1.06, y: 1.0 }, bendLines), "")
            compare(canvas.placementHingeJunctionReliefEdgeSkipReason(
                        { x: -0.03, y: -0.02 }, { x: 0.03, y: -0.02 }, [bendLines[0]]), "")
            canvas.destroy()
        }

        function test_activeBendProximityAloneDoesNotHideExteriorFlangeCap() {
            let canvas = createCanvas(qualifiedPreview())
            let panelValue = {
                completed: true,
                corners: [
                    { x: 0.02, r: 0.02 }, { x: 4.02, r: 0.02 },
                    { x: 4.02, r: 1.02 }, { x: 0.02, r: 1.02 }
                ],
                polygon: [
                    { x: 0.02, r: 0.02 }, { x: 4.02, r: 0.02 },
                    { x: 4.02, r: 1.02 }, { x: 0.02, r: 1.02 }
                ]
            }
            let liveGeometry = {
                halfThickness: 0.05,
                dieHalfWidth: 0.5,
                sheetPolygon: [
                    { x: -2, r: -2 }, { x: -1, r: -2 },
                    { x: -1, r: -1 }, { x: -2, r: -1 }
                ]
            }
            canvas.classifyLivePanelInternalSharedCaps(
                        [panelValue], liveGeometry, { centerX: 0, centerR: 0 })
            compare(panelValue.internalSharedCaps.length, 0)
            canvas.destroy()
        }

        function test_unresolvedLegacyVisibleRootCannotDeleteDetailedPanel() {
            let canvas = createCanvas(qualifiedPreview())
            let unresolved = canvas.unresolvedPlacementVisibleRoots(
                        ["BEND:3:FLANGE:1"],
                        [{
                            completed: true,
                            bend: { id: "1" },
                            badgeKey: "BEND:1:FLANGE:1"
                        }])
            compare(unresolved.length, 1)
            compare(unresolved[0], "BEND:3:FLANGE:1")
            canvas.destroy()
        }

        function test_coarseSegmentCannotMaskKnownDetailedRoot() {
            let canvas = createCanvas(qualifiedPreview())
            let rootIdentity = "BEND:3:FLANGE:1"
            let topologyBranches = ({})
            topologyBranches[rootIdentity] = {
                exactIdentity: rootIdentity,
                outerLoop: [{ x: 0, y: 0 }, { x: 2, y: 0 }, { x: 2, y: 1 }, { x: 0, y: 1 }]
            }
            compare(canvas.liveSegmentMayRepresentExpectedRoot(rootIdentity, topologyBranches), false)
            compare(canvas.liveSegmentMayRepresentExpectedRoot("BEND:9:FLANGE:1", topologyBranches), true)
            canvas.destroy()
        }
    }
}