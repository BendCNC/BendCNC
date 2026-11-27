import QtQuick
import QtTest
import "../qml/core/sheetmetal/SheetMetalPoseGraph.js" as PoseGraph

Item {
    id: root
    width: 320
    height: 240

    TestCase {
        name: "SheetMetalPoseGraphTests"
        when: windowShown

        function point(x, y) {
            return { x_in: x, y_in: y }
        }

        function panel(id, parentId, ownerId, x0, x1) {
            return {
                panelId: id,
                parentPanelId: parentId,
                ownerBendId: ownerId,
                geometryAuthority: "planar-subdivision-v5",
                outerLoop: [point(x0, 0), point(x1, 0), point(x1, 2), point(x0, 2)],
                holeLoops: []
            }
        }

        function edge(id, sourceId, sequence, parentId, childId, x) {
            return {
                bendId: id,
                sourceBendId: sourceId,
                sequenceHint: sequence,
                parentPanelId: parentId,
                childPanelId: childId,
                hingeStart: point(x, 0),
                hingeEnd: point(x, 2),
                hingeSegments: [[point(x, 0), point(x, 2)]],
                bendAngleDegrees: 90,
                foldAngleDegrees: 90,
                insideRadius_in: 0.1,
                thickness_in: 0.1,
                kFactor: 0.44,
                childSideSign: 1,
                direction: "UP"
            }
        }

        function validGraph() {
            let base = panel("root", null, null, 0, 1)
            base.holeLoops = [[point(0.2, 0.5), point(0.4, 0.5), point(0.4, 0.8), point(0.2, 0.8)]]
            return {
                schemaVersion: 5,
                rootPanelId: "root",
                geometryAuthority: "flat-pattern-planar-subdivision-v5",
                diagnostics: {
                    status: "qualified",
                    rootSelectionAmbiguous: false,
                    expectedMaterialArea_in2: 5.94,
                    partitionArea_in2: 5.94,
                    partitionAreaError_in2: 0
                },
                materialBoundary: {
                    outerLoop: [point(0, 0), point(3, 0), point(3, 2), point(0, 2)],
                    holeLoops: [[point(0.2, 0.5), point(0.4, 0.5), point(0.4, 0.8), point(0.2, 0.8)]]
                },
                panels: [base, panel("p1", "root", "bend-1", 1, 2), panel("p2", "p1", "bend-2", 2, 3)],
                bendEdges: [edge("e1", "bend-1", 1, "root", "p1", 1), edge("e2", "bend-2", 2, "p1", "p2", 2)]
            }
        }

        function clone(value) {
            return JSON.parse(JSON.stringify(value))
        }

        function test_acceptsQualifiedTreeWithHole() {
            let graph = validGraph()
            compare(PoseGraph.validateGraph(graph), "")
            verify(PoseGraph.graphIsQualified(graph))
            let normalized = PoseGraph.normalize(graph)
            verify(!!normalized, "Object exists")
            compare(normalized.rootPanelId, "root")
            compare(normalized.panelOrder.length, 3)
            compare(normalized.panelsById.root.holeLoops.length, 1)
        }

        function test_denseContourRemainsCheckedAfterCornerMoves() {
            let graph = validGraph()
            let outer = graph.materialBoundary.outerLoop
            let dense = []
            for (let i = 0; i < outer.length; i++) {
                let a = outer[i], b = outer[(i + 1) % outer.length]
                for (let j = 0; j < 8; j++)
                    dense.push(point(a.x_in + (b.x_in - a.x_in) * j / 8,
                                     a.y_in + (b.y_in - a.y_in) * j / 8))
            }
            graph.materialBoundary.outerLoop = dense
            compare(PoseGraph.validateGraph(graph), "")
            // A narrow triangular cut through the panel between existing vertices.
            dense[4].y_in = 0.2
            verify(PoseGraph.validateGraph(graph).indexOf("outside-material:") >= 0)
            dense[4].y_in = 0
            compare(PoseGraph.validateGraph(graph), "")
        }

        function test_authoritativePreviewAcceptsQualifiedSupportedRevision() {
            let preview = {
                generator: {
                    id: "com.bendcnc.export",
                    version: "1.1.0",
                    revision: "legacy-qualified-v5",
                    topologySchemaVersion: 5
                },
                flatPattern: {
                    preview2d: {
                        surfaceType: "plane",
                        loops: [
                            { points: [point(0, 0), point(3, 0), point(3, 2), point(0, 2), point(0, 0)] },
                            { points: [point(0.2, 0.5), point(0.4, 0.5), point(0.4, 0.8), point(0.2, 0.8), point(0.2, 0.5)] }
                        ],
                        loopIntegrity: [
                            { loopIndex: 0, pointCount: 4, closed: true },
                            { loopIndex: 1, pointCount: 4, closed: true }
                        ]
                    }
                },
                sheetMetalGraph: validGraph()
            }
            compare(PoseGraph.validateAuthoritativePreview(
                preview,
                "com.bendcnc.export",
                "1.1.0",
                ["current-v5", "legacy-qualified-v5"]), "")

            preview.generator.revision = "unsupported"
            compare(PoseGraph.validateAuthoritativePreview(
                preview,
                "com.bendcnc.export",
                "1.1.0",
                ["current-v5", "legacy-qualified-v5"]),
                "generator-provenance-not-current")
        }

        function test_acceptsCompoundOperationRelations() {
            let graph = validGraph()
            graph.bendEdges[1].sourceBendId = "bend-1"
            graph.bendEdges[1].sequenceHint = 1
            graph.panels[2].ownerBendId = "bend-1"
            graph.bendEdges[0].operationRelationIndex = 0
            graph.bendEdges[0].operationRelationCount = 2
            graph.bendEdges[1].operationRelationIndex = 1
            graph.bendEdges[1].operationRelationCount = 2

            compare(PoseGraph.validateGraph(graph), "")
            let normalized = PoseGraph.normalize(graph)
            compare(normalized.edges[0].operationRelationCount, 2)
            compare(normalized.edges[1].operationRelationIndex, 1)
        }

            function test_rejectsIncompleteAndMismatchedCompoundOperationRelations() {
                let graph = validGraph()
                graph.bendEdges[0].operationRelationIndex = 0
                graph.bendEdges[0].operationRelationCount = 2
                compare(PoseGraph.validateGraph(graph), "edge-operation-relation-missing:bend-1:1")

                graph = validGraph()
                graph.bendEdges[1].sourceBendId = "bend-1"
                graph.panels[2].ownerBendId = "bend-1"
                graph.bendEdges[0].operationRelationIndex = 0
                graph.bendEdges[0].operationRelationCount = 2
                graph.bendEdges[1].operationRelationIndex = 1
                graph.bendEdges[1].operationRelationCount = 3
                compare(PoseGraph.validateGraph(graph),
                    "edge-operation-relation-count-mismatch:bend-1")

                graph.bendEdges[1].operationRelationCount = 2
                graph.bendEdges[1].sequenceHint = 2
                compare(PoseGraph.validateGraph(graph),
                    "edge-operation-relation-metadata-mismatch:bend-1")
            }

        function test_visiblePanelsExcludeRootAndFutureBends() {
            let normalized = PoseGraph.normalize(validGraph())
            compare(PoseGraph.visiblePanelIds(normalized, 0).length, 0)
            compare(PoseGraph.visiblePanelIds(normalized, 1), ["p1"])
            compare(PoseGraph.visiblePanelIds(normalized, 2), ["p1", "p2"])
            compare(PoseGraph.physicalPanelIds(normalized), ["root", "p1", "p2"])
        }

        function test_rejectsDuplicatePanelId() {
            let graph = validGraph()
            graph.panels[2].panelId = "p1"
            compare(PoseGraph.validateGraph(graph), "duplicate-panel-id:p1")
        }

        function test_rejectsMissingParent() {
            let graph = validGraph()
            graph.panels[2].parentPanelId = "missing"
            compare(PoseGraph.validateGraph(graph), "panel-parent-does-not-exist:p2")
        }

        function test_rejectsDegenerateHinge() {
            let graph = validGraph()
            graph.bendEdges[0].hingeEnd = clone(graph.bendEdges[0].hingeStart)
            compare(PoseGraph.validateGraph(graph), "edge-hinge-degenerate:e1")
        }

        function test_rejectsDisconnectedCycleAsCycle() {
            let graph = validGraph()
            graph.panels[1].parentPanelId = "p2"
            graph.panels[1].ownerBendId = "bend-2"
            graph.panels[2].parentPanelId = "p1"
            graph.panels[2].ownerBendId = "bend-1"
            graph.bendEdges[0] = edge("e1", "bend-1", 1, "p1", "p2", 2)
            graph.bendEdges[1] = edge("e2", "bend-2", 2, "p2", "p1", 2)
            compare(PoseGraph.validateGraph(graph), "cycle-at-panel:p1")
        }

        function test_rejectsUnqualifiedAndUnsupportedAuthority() {
            let graph = validGraph()
            graph.diagnostics.status = "fallback"
            compare(PoseGraph.validateGraph(graph), "diagnostics-not-qualified")
            graph = validGraph()
            graph.geometryAuthority = "bbox-derived"
            compare(PoseGraph.validateGraph(graph), "geometry-authority-not-v5")
        }

        function test_requiresMaterialBoundaryAndRejectsPartitionGap() {
            let graph = validGraph()
            delete graph.materialBoundary
            compare(PoseGraph.validateGraph(graph), "material-boundary-missing")

            graph = validGraph()
            graph.panels[2].outerLoop = [point(2, 0), point(2.9, 0), point(2.9, 2), point(2, 2)]
            compare(PoseGraph.validateGraph(graph), "partition-area-proof-mismatch")
        }

        function test_rejectsAmbiguousRootAndInvalidDuplicateOperationRelation() {
            let graph = validGraph()
            delete graph.diagnostics.rootSelectionAmbiguous
            compare(PoseGraph.validateGraph(graph), "root-selection-not-proven-unambiguous")
            graph = validGraph()
            graph.bendEdges[1].sourceBendId = graph.bendEdges[0].sourceBendId
            compare(PoseGraph.validateGraph(graph), "edge-operation-relation-duplicate:bend-1:0")
        }

        function test_rejectsIncompleteHingeCoverage() {
            let graph = validGraph()
            graph.bendEdges[0].hingeSegments = [[point(1, 0), point(1, 1)]]
            compare(PoseGraph.validateGraph(graph), "edge-hinge-segments-incomplete:e1")
        }

        function test_rejectsHoleOutsidePanel() {
            let graph = validGraph()
            graph.panels[0].holeLoops = [[point(0.2, 0.5), point(1.2, 0.5), point(1.2, 0.8), point(0.2, 0.8)]]
            compare(PoseGraph.validateGraph(graph), "panel-hole-loop:root:0:outside-panel")
        }

        function test_rejectsOverlappingAndNestedHoles() {
            let graph = validGraph()
            graph.panels[0].holeLoops = [
                [point(0.1, 0.4), point(0.8, 0.4), point(0.8, 1.0), point(0.1, 1.0)],
                [point(0.7, 0.8), point(0.9, 0.8), point(0.9, 1.4), point(0.7, 1.4)]
            ]
            compare(PoseGraph.validateGraph(graph), "panel-holes-overlap-or-nest:root:0:1")

            graph = validGraph()
            graph.panels[0].holeLoops = [
                [point(0.1, 0.3), point(0.9, 0.3), point(0.9, 1.7), point(0.1, 1.7)],
                [point(0.3, 0.6), point(0.7, 0.6), point(0.7, 1.4), point(0.3, 1.4)]
            ]
            compare(PoseGraph.validateGraph(graph), "panel-holes-overlap-or-nest:root:0:1")
        }

        function test_rejectsFloatingHingeAndOverlappingPanels() {
            let graph = validGraph()
            graph.bendEdges[0].hingeStart = point(0.5, 0)
            graph.bendEdges[0].hingeEnd = point(0.5, 2)
            graph.bendEdges[0].hingeSegments = [[point(0.5, 0), point(0.5, 2)]]
            compare(PoseGraph.validateGraph(graph), "edge-hinge-not-shared-panel-boundary:e1:0")

            graph = validGraph()
            graph.panels[1].outerLoop = [point(0.5, 0), point(1.5, 0), point(1.5, 2), point(0.5, 2)]
            compare(PoseGraph.validateGraph(graph), "panel-interiors-overlap:root:p1")
        }
    }
}
