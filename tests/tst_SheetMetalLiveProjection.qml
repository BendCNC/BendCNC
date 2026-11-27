import QtQuick
import QtTest
import "../qml/core/sheetmetal/SheetMetalLiveProjection.js" as Projection

Item {
    width: 320
    height: 240

    TestCase {
        name: "SheetMetalLiveProjectionTests"
        when: windowShown

        function world(x, y, z) {
            return { x: x, y: y, z: z }
        }

        function sectionFrame() {
            return {
                origin: world(0, 0, 0),
                viewAxis: world(0, 1, 0),
                horizontal: world(1, 0, 0),
                vertical: world(0, 0, 1)
            }
        }

        function close(actual, expected) {
            return Math.abs(actual - expected) < 1.0e-8
        }

        function test_areaFacePreservesPolygonAndHole() {
            let panel = {
                worldPolygon: [world(0, 0, 0), world(2, 0, 0), world(2, 0, 1), world(0, 0, 1)],
                worldHoleLoops: [[world(0.5, 0, 0.25), world(1.0, 0, 0.25), world(1.0, 0, 0.75), world(0.5, 0, 0.75)]]
            }
            let projected = Projection.projectPosedPanel(panel, sectionFrame(), 3, 4, 0.05)

            verify(projected.ok)
            verify(projected.visible)
            compare(projected.reason, "coplanar-section")
            compare(projected.polygon.length, 4)
            compare(projected.holeLoops.length, 1)
            compare(projected.sectionSegment, null)
            verify(close(projected.labelPoint.x, 4))
            verify(close(projected.labelPoint.r, 4.5))
        }

        function test_displayProjectionPreservesOffSectionBodyAndHole() {
            let panel = {
                worldPolygon: [world(0, 2, 0), world(2, 2, 0),
                               world(2, 2, 1), world(0, 2, 1)],
                worldHoleLoops: [[world(0.5, 2, 0.25), world(1.0, 2, 0.25),
                                  world(1.0, 2, 0.75), world(0.5, 2, 0.75)]]
            }
            let projected = Projection.projectPosedPanelForDisplay(
                        panel, sectionFrame(), 3, 4, 0.05)

            verify(projected.ok)
            verify(projected.visible)
            compare(projected.reason, "full-body-oblique-display")
            compare(projected.polygon.length, 4)
            compare(projected.holeLoops.length, 1)
            compare(projected.sectionSegment, null)
            verify(projected.projectedArea > 1.9)
            verify(close(projected.polygon[0].x, 3.64))
            verify(close(projected.polygon[0].r, 3.64))
            verify(close(projected.polygon[0].viewDepth, 2))
            verify(close(projected.holeLoops[0][0].viewDepth, 2))
            verify(close(projected.viewDepthMin, 2))
            verify(close(projected.viewDepthMax, 2))
            verify(close(projected.viewDepthCentroid, 2))
        }

        function test_displayProjectionReportsSignedDepthRange() {
            let panel = {
                worldPolygon: [world(0, -2, 0), world(2, -2, 0),
                               world(2, 3, 1), world(0, 3, 1)],
                worldHoleLoops: []
            }
            let projected = Projection.projectPosedPanelForDisplay(
                        panel, sectionFrame(), 0, 0, 0.05)

            verify(projected.ok)
            verify(close(projected.viewDepthMin, -2))
            verify(close(projected.viewDepthMax, 3))
            verify(close(projected.viewDepthCentroid, 0.5))
        }

        function test_displayProjectionUsesWorldDepthToKeepOrthogonalFaceVisible() {
            let panel = {
                worldPolygon: [world(0, 0, 0), world(0, 2, 0),
                               world(0, 2, 3), world(0, 0, 3)],
                worldHoleLoops: []
            }
            let projected = Projection.projectPosedPanelForDisplay(
                        panel, sectionFrame(), 0, 0, 0.07)

            verify(projected.ok)
            compare(projected.reason, "full-body-oblique-display")
            compare(projected.polygon.length, 4)
            compare(projected.sectionSegment, null)
            verify(projected.projectedArea > 1.0)
            verify(Math.abs(projected.polygon[1].x - projected.polygon[0].x) > 0.5)
        }

        function test_sideProjectionIgnoresDepthAndUsesThicknessOnlyWhenEdgeOn() {
            let face = {
                worldPolygon: [world(0, 2, 0), world(2, 2, 0),
                               world(2, 2, 1), world(0, 2, 1)],
                worldHoleLoops: []
            }
            let projectedFace = Projection.projectPosedPanelForDisplay(
                        face, sectionFrame(), 0, 0, 0.05, undefined, 0, 0)
            verify(projectedFace.ok)
            compare(projectedFace.reason, "orthographic-side-display")
            compare(projectedFace.polygon.length, 4)
            verify(projectedFace.projectedArea > 1.9)
            verify(close(projectedFace.polygon[0].x, 0))
            verify(close(projectedFace.polygon[0].r, 0))

            let edgeOn = {
                worldPolygon: [world(0, 0, 0), world(0, 2, 0),
                               world(0, 2, 3), world(0, 0, 3)],
                worldHoleLoops: []
            }
            let projectedEdge = Projection.projectPosedPanelForDisplay(
                        edgeOn, sectionFrame(), 0, 0, 0.07, undefined, 0, 0)
            verify(projectedEdge.ok)
            compare(projectedEdge.reason, "display-edge-on-thickness-band")
            verify(!!projectedEdge.sectionSegment)
        }

        function test_edgeOnFaceBecomesPhysicalThicknessBand() {
            let panel = {
                worldPolygon: [world(0, 0, 0), world(0, 2, 0), world(0, 2, 3), world(0, 0, 3)],
                worldHoleLoops: []
            }
            let projected = Projection.projectPosedPanel(panel, sectionFrame(), 0, 0, 0.07)

            verify(projected.ok)
            verify(projected.visible)
            compare(projected.reason, "section-intersection")
            verify(!!projected.sectionSegment, "Object exists")
            verify(close(projected.sectionSegment.halfThickness, 0.07))
            verify(close(projected.sectionSegment.start.x, 0))
            verify(close(projected.sectionSegment.end.x, 0))
            verify(close(Math.abs(projected.sectionSegment.end.r - projected.sectionSegment.start.r), 3))
        }

        function test_offSectionFaceUsesMountAnchoredThicknessBand() {
            let panel = {
                worldPolygon: [world(0, 2, 0), world(2, 2, 0), world(2, 2, 1), world(0, 2, 1)],
                worldHoleLoops: [],
                worldMountEdge: [world(0, 2, 0), world(0, 2, 1)]
            }
            let projected = Projection.projectPosedPanel(panel, sectionFrame(), 0, 0, 0.05)

            verify(projected.ok)
            verify(projected.visible)
            compare(projected.reason, "representative-hinge-band")
            compare(projected.polygon.length, 0)
            compare(projected.holeLoops.length, 0)
            compare(projected.sectionSegments.length, 1)
            verify(!!projected.sectionSegment)
            compare(projected.sectionSegment.source, "hinge-anchored-face-extent")
            verify(close(projected.sectionSegment.halfThickness, 0.05))
            verify(close(projected.sectionSegment.start.x, 0))
            verify(close(projected.sectionSegment.end.x, 2))
            verify(close(projected.sectionSegment.start.r, projected.sectionSegment.end.r))
            verify(close(projected.sectionSegment.physicalLength, 2))
            verify(close(projected.sectionSegment.mountAnchor.x, 0))
            verify(close(projected.sectionSegment.projectedMountEdge[0].x, 0))
            verify(close(projected.sectionSegment.projectedMountEdge[1].x, 0))
        }

        function test_offSectionEdgeOnFaceUsesProjectedMountEdgeBand() {
            let panel = {
                worldPolygon: [world(2, 2, 0), world(2, 4, 0),
                               world(2, 4, 3), world(2, 2, 3)],
                worldHoleLoops: [],
                worldMountEdge: [world(2, 2, 0), world(2, 2, 3)]
            }
            let projected = Projection.projectPosedPanel(panel, sectionFrame(), 0, 0, 0.07)

            verify(projected.ok)
            verify(projected.visible)
            compare(projected.reason, "representative-hinge-band")
            compare(projected.polygon.length, 0)
            compare(projected.sectionSegments.length, 1)
            verify(!!projected.sectionSegment)
            compare(projected.sectionSegment.source, "hinge-anchored-edge-on")
            verify(close(projected.sectionSegment.halfThickness, 0.07))
            verify(close(projected.sectionSegment.start.x, 2))
            verify(close(projected.sectionSegment.end.x, 2))
            verify(close(Math.abs(projected.sectionSegment.end.r - projected.sectionSegment.start.r), 3))
            verify(close(projected.sectionSegment.physicalLength, 3))
            verify(close(projected.sectionSegment.start.x,
                         projected.sectionSegment.mountAnchor.x))
            verify(close(projected.sectionSegment.start.r,
                         projected.sectionSegment.mountAnchor.r))
        }

        function test_offSectionFaceWithoutPhysicalHingeFailsClosed() {
            let panel = {
                worldPolygon: [world(0, 2, 0), world(2, 2, 0),
                               world(2, 2, 1), world(0, 2, 1)],
                worldHoleLoops: []
            }
            let projected = Projection.projectPosedPanel(panel, sectionFrame(), 0, 0, 0.05)

            verify(!projected.ok)
            verify(!projected.visible)
            compare(projected.reason, "representative-hinge-anchor-missing")
            compare(projected.polygon.length, 0)
            compare(projected.holeLoops.length, 0)
            compare(projected.sectionSegments.length, 0)
        }

        function test_crossingHoleSplitsMaterialIntoTwoSectionBands() {
            let panel = {
                worldPolygon: [world(0, -1, 0), world(4, -1, 0),
                               world(4, 1, 0), world(0, 1, 0)],
                worldHoleLoops: [[world(1, -0.5, 0), world(2, -0.5, 0),
                                  world(2, 0.5, 0), world(1, 0.5, 0)]]
            }
            let projected = Projection.projectPosedPanel(panel, sectionFrame(), 0, 0, 0.05)

            verify(projected.ok)
            verify(projected.visible)
            compare(projected.reason, "section-intersection")
            compare(projected.sectionSegment, null)
            compare(projected.sectionSegments.length, 2)
            let lengths = projected.sectionSegments.map(function(segment) {
                return Math.abs(segment.end.x - segment.start.x)
            }).sort(function(a, b) { return a - b })
            verify(close(lengths[0], 1))
            verify(close(lengths[1], 2))
        }

        function test_nonFiniteProjectionFailsClosed() {
            let panel = {
                worldPolygon: [world(0, 0, 0), world(NaN, 0, 0), world(1, 0, 1)],
                worldHoleLoops: []
            }
            let projected = Projection.projectPosedPanel(panel, sectionFrame(), 0, 0, 0.05)

            verify(!projected.ok)
            compare(projected.reason, "world-polygon-projection-failed")
        }
    }
}