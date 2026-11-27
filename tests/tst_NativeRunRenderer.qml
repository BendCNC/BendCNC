import QtQuick
import QtTest
import BendCNCPrototype

TestCase {
    id: testCase
    name: "NativeRunRendererTests"
    when: windowShown
    width: 320
    height: 240

    Component {
        id: rendererComponent

        NativeRunRenderer {
            width: 320
            height: 240
        }
    }

    function test_acceptsAndPresentsTrianglePacket() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        verify(renderer.submitFrame([{
            type: "triangles",
            color: "#2563eb",
            vertices: [10, 10, 150, 10, 10, 120]
        }], 7))
        tryCompare(renderer, "acceptedRevision", 7)
        compare(renderer.packetValid, true)
        compare(renderer.packetError, "")
        compare(renderer.batchCount, 1)
        compare(renderer.vertexCount, 3)
        tryCompare(renderer, "presentedRevision", 7, 1000)
    }

    function test_rejectsDuplicateAndStaleRevisions() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        let command = {
            type: "triangles",
            color: "#2563eb",
            vertices: [10, 10, 150, 10, 10, 120]
        }
        verify(renderer.submitFrame([command], 7))
        compare(renderer.submitFrame([command], 7), false)
        compare(renderer.submitFrame([command], 6), false)
        tryCompare(renderer, "presentedRevision", 7, 1000)
        compare(renderer.submitFrame([command], 7), false)
        compare(renderer.submitFrame([command], 5), false)
        compare(renderer.acceptedRevision, 7)
    }

    function test_rejectsUnsupportedPacketWithoutReplacingAcceptedFrame() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        verify(renderer.submitFrame([{
            type: "triangles",
            color: "#16a34a",
            vertices: [0, 0, 20, 0, 0, 20]
        }], 3))
        tryCompare(renderer, "acceptedRevision", 3)
        verify(renderer.submitFrame([{ type: "unsupported" }], 4))
        tryCompare(renderer, "packetValid", false)
        verify(renderer.packetError.length > 0)
        compare(renderer.acceptedRevision, 3)
    }

    function test_acceptsPathStrokeClipAndErasePacket() {
        let rectangle = {
            type: "path",
            subpaths: [{ points: [0, 0, 200, 0, 200, 160, 0, 160], closed: true }],
            fillRule: "winding",
            fillColor: "#dcfce7",
            strokeColor: "#166534",
            lineWidth: 2,
            lineCap: "round",
            dash: [],
            composition: "source-over",
            clipSubpaths: [],
            clipFillRule: "winding"
        }
        let hole = {
            type: "path",
            subpaths: [{ points: [70, 50, 130, 50, 130, 110, 70, 110], closed: true }],
            fillRule: "winding",
            fillColor: "#000000",
            strokeColor: "#166534",
            lineWidth: 1,
            lineCap: "butt",
            dash: [4, 3],
            composition: "destination-out",
            clipSubpaths: [{ points: [0, 0, 200, 0, 200, 160, 0, 160], closed: true }],
            clipFillRule: "winding"
        }
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        verify(renderer.submitFrame([rectangle, hole], 9))
        tryCompare(renderer, "acceptedRevision", 9)
        verify(renderer.packetValid, renderer.packetError)
        verify(renderer.batchCount > 0)
        verify(renderer.vertexCount > 0)
        tryCompare(renderer, "presentedRevision", 9, 1000)
    }

    function test_acceptsOrderedRgbaTextAndGeometryPacket() {
        let item = createTemporaryObject(rendererComponent, testCase)
        verify(item !== null)
        verify(item.submitFrame([
            {
                type: "path",
                order: 0,
                subpaths: [{ points: [0, 0, 120, 0, 120, 80, 0, 80], closed: true }],
                fillRule: "winding",
                fillColor: "rgba(15,23,42,0.92)",
                strokeColor: "rgba(0,240,255,0.75)",
                lineWidth: 2,
                lineCap: "round",
                dash: [],
                composition: "source-over",
                clipSubpaths: [],
                clipFillRule: "winding"
            },
            {
                type: "text",
                order: 1,
                text: "4.575 TONS",
                x: 60,
                y: 40,
                color: "#a82011",
                pixelSize: 12,
                bold: true,
                align: "center",
                baseline: "middle",
                strokeColor: "rgba(248,250,252,0.95)",
                strokeWidth: 2.2
            }
        ], 4))

        tryCompare(item, "acceptedRevision", 4)
        compare(item.packetValid, true)
        verify(item.batchCount >= 3)
        verify(item.vertexCount > 6)
        tryCompare(item, "presentedRevision", 4, 1000)
    }

    function test_rapidSubmissionsPresentProgressWithoutStarvation() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        let latestRevision = 24
        for (let revision = 1; revision <= latestRevision; revision++) {
            let offset = revision * 0.25
            verify(renderer.submitFrame([{
                type: "path",
                subpaths: [{
                    points: [offset, 0, 250, offset, 250 - offset, 180, 0, 180 - offset],
                    closed: true
                }],
                fillRule: "winding",
                fillColor: "rgba(37,99,235,0.72)",
                strokeColor: "#0f172a",
                lineWidth: 2,
                lineCap: "round",
                dash: [4, 3],
                composition: "source-over",
                clipSubpaths: [],
                clipFillRule: "winding"
            }], revision))
        }

        tryVerify(function() { return renderer.presentedRevision > 0 }, 1000)
        tryCompare(renderer, "presentedRevision", latestRevision, 2000)
        compare(renderer.acceptedRevision, latestRevision)
        verify(renderer.coalescedFrameCount > 0)
    }

    function test_identicalPathReusesTessellationAndPresentsNewRevision() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        let command = {
            type: "path",
            subpaths: [{ points: [12, 10, 280, 22, 260, 210, 25, 195], closed: true }],
            fillRule: "winding",
            fillColor: "#2563eb",
            strokeColor: "",
            lineWidth: 1,
            lineCap: "butt",
            dash: [],
            composition: "source-over",
            clipSubpaths: [],
            clipFillRule: "winding"
        }

        verify(renderer.submitFrame([command], 1))
        tryCompare(renderer, "presentedRevision", 1, 1000)
        verify(renderer.tessellationCacheMisses > 0)
        compare(renderer.tessellationCacheHits, 0)

        verify(renderer.submitFrame([command], 2))
        tryCompare(renderer, "presentedRevision", 2, 1000)
        verify(renderer.tessellationCacheHits > 0)
        compare(renderer.sceneGraphGeometryUpdates, 0)
        compare(renderer.sceneGraphTransformUpdates, 0)
        compare(renderer.acceptedRevision, 2)
    }

    function test_translatedPathReusesLocalMeshAndUpdatesTransform() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        function translatedCommand(offsetX, offsetY) {
            return {
                type: "path",
                subpaths: [{
                    points: [12 + offsetX, 10 + offsetY,
                             280 + offsetX, 22 + offsetY,
                             260 + offsetX, 210 + offsetY,
                             25 + offsetX, 195 + offsetY],
                    closed: true
                }],
                fillRule: "winding",
                fillColor: "#2563eb",
                strokeColor: "",
                lineWidth: 1,
                lineCap: "butt",
                dash: [],
                composition: "source-over",
                clipSubpaths: [],
                clipFillRule: "winding"
            }
        }

        verify(renderer.submitFrame([translatedCommand(0, 0)], 1))
        tryCompare(renderer, "presentedRevision", 1, 1000)
        verify(renderer.tessellationCacheMisses > 0)

        verify(renderer.submitFrame([translatedCommand(31, 47)], 2))
        tryCompare(renderer, "presentedRevision", 2, 1000)
        verify(renderer.tessellationCacheHits > 0)
        verify(renderer.retainedTransformUpdates > 0)
        compare(renderer.sceneGraphGeometryUpdates, 0)
        compare(renderer.sceneGraphTransformUpdates, 1)
        compare(renderer.acceptedRevision, 2)
    }

    function test_rotatedRigidPathReusesLocalMeshAndUpdatesTransform() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        function rigidCommand(angleDegrees, offsetX, offsetY) {
            let radians = angleDegrees * Math.PI / 180
            let cosine = Math.cos(radians)
            let sine = Math.sin(radians)
            let localPoints = [0, 0, 180, 0, 180, 44, 0, 44]
            let points = []
            for (let index = 0; index < localPoints.length; index += 2) {
                let x = localPoints[index]
                let y = localPoints[index + 1]
                points.push(offsetX + x * cosine - y * sine,
                            offsetY + x * sine + y * cosine)
            }
            return {
                type: "path",
                subpaths: [{ points: points, closed: true }],
                fillRule: "winding",
                fillColor: "#2563eb",
                strokeColor: "",
                lineWidth: 1,
                lineCap: "butt",
                dash: [],
                composition: "source-over",
                clipSubpaths: [],
                clipFillRule: "winding"
            }
        }

        verify(renderer.submitFrame([rigidCommand(0, 15, 20)], 1))
        tryCompare(renderer, "presentedRevision", 1, 1000)
        verify(renderer.tessellationCacheMisses > 0)

        verify(renderer.submitFrame([rigidCommand(37, 92, 61)], 2))
        tryCompare(renderer, "presentedRevision", 2, 1000)
        verify(renderer.tessellationCacheHits > 0)
        verify(renderer.retainedTransformUpdates > 0)
        compare(renderer.sceneGraphGeometryUpdates, 0)
        compare(renderer.sceneGraphTransformUpdates, 1)
        compare(renderer.acceptedRevision, 2)
    }

    function test_rotatedRigidStrokeReusesLocalMeshAndUpdatesTransform() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        function rigidStroke(angleDegrees, offsetX, offsetY) {
            let radians = angleDegrees * Math.PI / 180
            let cosine = Math.cos(radians)
            let sine = Math.sin(radians)
            let localPoints = [0, 0, 110, 0, 154, 38]
            let points = []
            for (let index = 0; index < localPoints.length; index += 2) {
                let x = localPoints[index]
                let y = localPoints[index + 1]
                points.push(offsetX + x * cosine - y * sine,
                            offsetY + x * sine + y * cosine)
            }
            return {
                type: "path",
                subpaths: [{ points: points, closed: false }],
                fillRule: "winding",
                fillColor: "",
                strokeColor: "#0f172a",
                lineWidth: 2.5,
                lineCap: "round",
                dash: [5, 3],
                composition: "source-over",
                clipSubpaths: [],
                clipFillRule: "winding"
            }
        }

        verify(renderer.submitFrame([rigidStroke(0, 9, 14)], 1))
        tryCompare(renderer, "presentedRevision", 1, 1000)
        verify(renderer.tessellationCacheMisses > 0)

        verify(renderer.submitFrame([rigidStroke(-29, 67, 83)], 2))
        tryCompare(renderer, "presentedRevision", 2, 1000)
        verify(renderer.tessellationCacheHits > 0)
        compare(renderer.sceneGraphGeometryUpdates, 0)
        compare(renderer.sceneGraphTransformUpdates, 1)
    }

    function test_deformingPathDoesNotReuseRigidGeometry() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        function rectangle(widthValue, heightValue) {
            return {
                type: "path",
                subpaths: [{
                    points: [20, 20, 20 + widthValue, 20,
                             20 + widthValue, 20 + heightValue, 20, 20 + heightValue],
                    closed: true
                }],
                fillRule: "winding",
                fillColor: "#2563eb",
                strokeColor: "",
                lineWidth: 1,
                lineCap: "butt",
                dash: [],
                composition: "source-over",
                clipSubpaths: [],
                clipFillRule: "winding"
            }
        }

        verify(renderer.submitFrame([rectangle(120, 40)], 1))
        tryCompare(renderer, "presentedRevision", 1, 1000)
        verify(renderer.submitFrame([rectangle(120, 63)], 2))
        tryCompare(renderer, "presentedRevision", 2, 1000)
        verify(renderer.tessellationCacheMisses > 0)
        compare(renderer.sceneGraphGeometryUpdates, 1)
    }

    function test_warmTranslatedCommandCachePreservesLaterErase() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        function rectangle(offsetX, offsetY) {
            return {
                type: "path",
                subpaths: [{
                    points: [10 + offsetX, 10 + offsetY,
                             210 + offsetX, 10 + offsetY,
                             210 + offsetX, 170 + offsetY,
                             10 + offsetX, 170 + offsetY],
                    closed: true
                }],
                fillRule: "winding",
                fillColor: "#2563eb",
                strokeColor: "",
                lineWidth: 1,
                lineCap: "butt",
                dash: [],
                composition: "source-over",
                clipSubpaths: [],
                clipFillRule: "winding"
            }
        }
        function erase(offsetX, offsetY) {
            return {
                type: "path",
                subpaths: [{
                    points: [70 + offsetX, 50 + offsetY,
                             150 + offsetX, 50 + offsetY,
                             150 + offsetX, 130 + offsetY,
                             70 + offsetX, 130 + offsetY],
                    closed: true
                }],
                fillRule: "winding",
                fillColor: "#000000",
                strokeColor: "",
                lineWidth: 1,
                lineCap: "butt",
                dash: [],
                composition: "destination-out",
                clipSubpaths: [],
                clipFillRule: "winding"
            }
        }

        verify(renderer.submitFrame([rectangle(0, 0)], 1))
        tryCompare(renderer, "presentedRevision", 1, 1000)
        let fullVertexCount = renderer.vertexCount
        verify(fullVertexCount > 0)

        verify(renderer.submitFrame([rectangle(31, 27), erase(31, 27)], 2))
        tryCompare(renderer, "presentedRevision", 2, 1000)
        verify(renderer.packetValid, renderer.packetError)
        verify(renderer.tessellationCacheHits > 0)
        verify(renderer.retainedTransformUpdates > 0)
        verify(renderer.vertexCount > fullVertexCount,
             "The retained local painter path must be re-tessellated around its erased hole")
    }

    function test_newerValidPacketWinsOverPendingInvalidPacket() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        let invalidHeavyCommands = []
        for (let index = 0; index < 500; index++) {
            let offset = index * 0.01
            invalidHeavyCommands.push({
                type: "triangles",
                color: "#16a34a",
                vertices: [offset, 0, offset + 2, 0, offset, 2]
            })
        }
        invalidHeavyCommands.push({ type: "unsupported" })
        verify(renderer.submitFrame(invalidHeavyCommands, 11))
        verify(renderer.submitFrame([{
            type: "triangles",
            color: "#dc2626",
            vertices: [10, 10, 80, 10, 10, 80]
        }], 12))

        tryCompare(renderer, "acceptedRevision", 12, 3000)
        tryCompare(renderer, "presentedRevision", 12, 3000)
        compare(renderer.acceptedRevision, 12)
        compare(renderer.packetValid, true)
        compare(renderer.packetError, "")
        compare(renderer.batchCount, 1)
        compare(renderer.vertexCount, 3)
    }

    function test_destroyDuringHeavyParseDoesNotCrash() {
        let renderer = rendererComponent.createObject(testCase)
        verify(renderer !== null)
        let commands = []
        for (let index = 0; index < 36; index++) {
            let offset = index * 0.15
            commands.push({
                type: "path",
                subpaths: [{
                    points: [offset, 0, 310, offset, 310 - offset, 225, 0, 225 - offset],
                    closed: true
                }],
                fillRule: "winding",
                fillColor: "#7c3aed",
                strokeColor: "#2e1065",
                lineWidth: 2,
                lineCap: "round",
                dash: [5, 2],
                composition: "source-over",
                clipSubpaths: [],
                clipFillRule: "winding"
            })
        }
        verify(renderer.submitFrame(commands, 20))
        renderer.destroy()
        wait(1000)
        verify(true)
    }
}
