import QtQuick
import QtTest
import BendCNCPrototype

Item {
    id: root
    width: 320
    height: 240

    TestCase {
        name: "CanvasPainterRunRendererTests"
        when: windowShown

        function createRenderer() {
            try {
                return Qt.createQmlObject(
                    "import QtQuick; import BendCNCPrototype; "
                    + "CanvasPainterRunRenderer { width: 320; height: 240 }",
                    root,
                    "canvas-painter-test-renderer")
            } catch (error) {
                return null
            }
        }

        function pathCommand(order, overrides) {
            const command = {
                type: "path",
                order: order,
                subpaths: [{ points: [10, 10, 300, 10, 300, 220, 10, 220], closed: true }],
                fillRule: "winding",
                fillColor: "rgba(15,23,42,0.92)",
                strokeColor: "#38bdf8",
                lineWidth: 2,
                lineCap: "round",
                dash: [],
                composition: "source-over",
                clipSubpaths: [],
                clipFillRule: "winding"
            }
            for (const key in overrides)
                command[key] = overrides[key]
            return command
        }

        function polygonArea(points) {
            let area = 0
            for (let index = 0; index < points.length; index += 2) {
                const next = (index + 2) % points.length
                area += points[index] * points[next + 1]
                    - points[next] * points[index + 1]
            }
            return area * 0.5
        }

        function test_presentsOrderedPathTextClipDashAndErase() {
            if (root.GraphicsInfo.api === GraphicsInfo.Unknown
                    || root.GraphicsInfo.api === GraphicsInfo.Software)
                skip("Canvas Painter presentation requires a QRhi graphics backend")
            const renderer = createRenderer()
            if (!renderer)
                skip("Canvas Painter is unavailable in this Qt build")
            const clip = [{ points: [20, 20, 290, 20, 290, 210, 20, 210], closed: true }]
            verify(renderer.submitFrame([
                pathCommand(0, {}),
                pathCommand(1, {
                    subpaths: [
                        { points: [30, 30, 280, 30, 280, 200, 30, 200], closed: true },
                        { points: [100, 70, 210, 70, 210, 160, 100, 160], closed: true }
                    ],
                    fillRule: "oddEven",
                    fillColor: "#facc15",
                    strokeColor: "#713f12",
                    dash: [6, 4],
                    clipSubpaths: clip
                }),
                {
                    type: "text",
                    order: 2,
                    text: "4.575 TONS",
                    x: 155,
                    y: 115,
                    color: "#a82011",
                    pixelSize: 18,
                    bold: true,
                    align: "center",
                    baseline: "middle",
                    strokeColor: "rgba(248,250,252,0.95)",
                    strokeWidth: 2.2
                },
                pathCommand(3, {
                    subpaths: [{ points: [135, 90, 175, 90, 175, 140, 135, 140], closed: true }],
                    fillColor: "#000000",
                    strokeColor: "",
                    composition: "destination-out",
                    clipSubpaths: clip
                })
            ], 7))

            compare(renderer.packetValid, true)
            compare(renderer.packetError, "")
            compare(renderer.acceptedRevision, 7)
            tryCompare(renderer, "presentedRevision", 7, 2000)
            compare(renderer.batchCount, 4)

            const nextFrame = [pathCommand(0, {
                subpaths: [{ points: [18, 14, 306, 14, 306, 224, 18, 224], closed: true }],
                fillColor: "#0f766e"
            })]
            verify(renderer.submitFrame(nextFrame, 8))
            compare(renderer.acceptedRevision, 8)
            tryCompare(renderer, "presentedRevision", 8, 2000)
            compare(renderer.batchCount, 1)
        }

        function test_rejectsDuplicateAndInvalidOrdering() {
            const renderer = createRenderer()
            if (!renderer)
                skip("Canvas Painter is unavailable in this Qt build")
            verify(renderer.submitFrame([pathCommand(0, {})], 1))
            compare(renderer.submitFrame([pathCommand(0, {})], 1), false)
            compare(renderer.packetValid, false)
            verify(renderer.packetError.length > 0)
            compare(renderer.submitFrame([pathCommand(2, {})], 2), false)
            compare(renderer.acceptedRevision, 1)
        }

        function test_reusesPreparedCommandsByExactCacheKey() {
            if (root.GraphicsInfo.api === GraphicsInfo.Unknown
                    || root.GraphicsInfo.api === GraphicsInfo.Software)
                skip("Canvas Painter presentation requires a QRhi graphics backend")
            const renderer = createRenderer()
            if (!renderer)
                skip("Canvas Painter is unavailable in this Qt build")
            const commands = [pathCommand(0, {}), {
                type: "text",
                order: 1,
                text: "CACHE",
                x: 160,
                y: 120,
                color: "#f8fafc",
                pixelSize: 16,
                bold: true,
                align: "center",
                baseline: "middle",
                strokeColor: "",
                strokeWidth: 0
            }]

            verify(renderer.submitFrame(commands, 1, "pose-a|collision-none"))
            tryCompare(renderer, "presentedRevision", 1, 2000)
            tryCompare(renderer, "preparedCacheMisses", 1, 2000)
            compare(renderer.preparedCacheHits, 0)
            compare(renderer.preparedCommandCount, 2)

            verify(renderer.submitFrame(commands, 2, "pose-a|collision-none"))
            tryCompare(renderer, "presentedRevision", 2, 2000)
            tryCompare(renderer, "preparedCacheHits", 1, 2000)
            compare(renderer.preparedCacheMisses, 1)
            compare(renderer.preparedCommandCount, 2)

            verify(renderer.submitFrame(commands, 3, "pose-b|collision-none"))
            tryCompare(renderer, "presentedRevision", 3, 2000)
            tryCompare(renderer, "preparedCacheMisses", 2, 2000)
            compare(renderer.preparedCacheHits, 1)

            verify(renderer.submitFrame(commands, 4))
            tryCompare(renderer, "presentedRevision", 4, 2000)
            tryCompare(renderer, "preparedCacheMisses", 3, 2000)
            compare(renderer.preparedCacheHits, 1)
            compare(renderer.preparedCommandCount, 2)
        }

        function test_submitsCachedFrameWithoutCommandPayload() {
            if (root.GraphicsInfo.api === GraphicsInfo.Unknown
                    || root.GraphicsInfo.api === GraphicsInfo.Software)
                skip("Canvas Painter presentation requires a QRhi graphics backend")
            const renderer = createRenderer()
            if (!renderer)
                skip("Canvas Painter is unavailable in this Qt build")
            const commands = [pathCommand(0, { fillColor: "#1d4ed8" })]

            compare(renderer.hasCachedFrame("transport-a"), false)
            verify(renderer.submitFrame(commands, 1, "transport-a"))
            tryCompare(renderer, "presentedRevision", 1, 2000)
            compare(renderer.hasCachedFrame("transport-a"), true)
            compare(renderer.transportCacheHits, 0)
            compare(renderer.transportCacheMisses, 0)

            verify(renderer.submitCachedFrame("transport-a", 2))
            tryCompare(renderer, "presentedRevision", 2, 2000)
            compare(renderer.transportCacheHits, 1)
            compare(renderer.transportCacheMisses, 0)
            compare(renderer.preparedCacheHits, 1)
            compare(renderer.batchCount, 1)

            compare(renderer.submitCachedFrame("transport-missing", 3), false)
            compare(renderer.transportCacheMisses, 1)
            compare(renderer.acceptedRevision, 2)
            compare(renderer.packetValid, false)
            tryCompare(renderer, "presentedRevision", 2, 2000)
        }

        function test_preservesIndependentFilletAndHoleContours() {
            if (root.GraphicsInfo.api === GraphicsInfo.Unknown
                    || root.GraphicsInfo.api === GraphicsInfo.Software)
                skip("Canvas Painter presentation requires a QRhi graphics backend")
            const renderer = createRenderer()
            if (!renderer)
                skip("Canvas Painter is unavailable in this Qt build")
            const outer = [20, 20, 300, 20, 300, 220, 20, 220]
            const hole = [110, 80, 110, 160, 210, 160, 210, 80]
            verify(polygonArea(outer) * polygonArea(hole) < 0)
            verify(renderer.submitFrame([pathCommand(0, {
                subpaths: [
                    { points: outer, closed: true },
                    { points: hole, closed: true }
                ],
                fillRule: "winding",
                fillColor: "#16a34a",
                strokeColor: "#14532d"
            })], 1, "independent-contours"))
            tryCompare(renderer, "presentedRevision", 1, 2000)
            compare(renderer.batchCount, 1)
            compare(renderer.packetValid, true)
        }

        function test_retainsCompletePreparedPoseCycle() {
            if (root.GraphicsInfo.api === GraphicsInfo.Unknown
                    || root.GraphicsInfo.api === GraphicsInfo.Software)
                skip("Canvas Painter presentation requires a QRhi graphics backend")
            const renderer = createRenderer()
            if (!renderer)
                skip("Canvas Painter is unavailable in this Qt build")
            const poseCount = 192
            for (let pose = 0; pose < poseCount; ++pose) {
                verify(renderer.submitFrame([pathCommand(0, {
                    subpaths: [{
                        points: [10 + pose * 0.01, 10, 300, 10,
                                 300, 220, 10, 220],
                        closed: true
                    }]
                })], pose + 1, "cycle-" + pose))
                tryCompare(renderer, "presentedRevision", pose + 1, 2000)
            }
            compare(renderer.preparedCacheMisses, poseCount)
            compare(renderer.preparedCacheHits, 0)
            compare(renderer.preparedCacheEvictions, 0)
            compare(renderer.preparedCacheEntries, poseCount)

            verify(renderer.submitCachedFrame("cycle-0", poseCount + 1))
            tryCompare(renderer, "presentedRevision", poseCount + 1, 2000)
            compare(renderer.preparedCacheHits, 1)
            compare(renderer.preparedCacheMisses, poseCount)
            compare(renderer.preparedCacheEvictions, 0)
            verify(renderer.preparedCacheCost > 0)
            verify(renderer.largestPreparedFrameCost > 0)
        }
    }
}