import QtQuick
import QtTest
import BendCNCPrototype

TestCase {
    id: testCase
    name: "NativeRunRendererTransportTests"
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

    function installTriangle(renderer, vertices, color) {
        verify(renderer.beginOpaqueBatchInstall(1), renderer.packetError)
        verify(renderer.appendOpaqueBatch(1, vertices, color), renderer.packetError)
        verify(renderer.commitOpaqueBatchInstall(), renderer.packetError)
    }

    function test_installsAndPresentsOpaqueTrianglesWithoutParsing() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        installTriangle(renderer, [10, 10, 150, 10, 10, 120], "#2563eb")
        verify(renderer.submitOpaqueRevision(1), renderer.packetError)
        compare(renderer.acceptedRevision, 1)
        compare(renderer.parseMilliseconds, 0)
        compare(renderer.packetValid, true)
        compare(renderer.packetError, "")
        compare(renderer.batchCount, 1)
        compare(renderer.vertexCount, 3)
        tryCompare(renderer, "presentedRevision", 1, 1000)
        compare(renderer.sceneGraphGeometryUpdates, 1)
    }

    function test_transformOnlyRevisionRetainsGeometry() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        installTriangle(renderer, [0, 0, 100, 0, 0, 80], "#f59e0b")
        verify(renderer.submitOpaqueRevision(1), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 1, 1000)
        verify(renderer.setOpaqueBatchTransform(0, 1, 0, 0, 1, 31, 47),
               renderer.packetError)
        verify(renderer.submitOpaqueRevision(2), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 2, 1000)
        compare(renderer.sceneGraphGeometryUpdates, 0)
        compare(renderer.sceneGraphTransformUpdates, 1)
        compare(renderer.vertexCount, 3)
        compare(renderer.batchCount, 1)
    }

    function test_realisticPunchBatchesShareTransformAndRetainDigest() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        verify(renderer.beginOpaqueBatchInstall(2))
        verify(renderer.appendOpaqueBatch(1, [
            -2, 0, 2, 0, 2, 5,
            -2, 0, 2, 5, -2, 5
        ], "#64748b"), renderer.packetError)
        verify(renderer.appendOpaqueBatch(1, [
            -1, 5, 1, 5, 0, 7
        ], "#64748b"), renderer.packetError)
        verify(renderer.commitOpaqueBatchInstall(), renderer.packetError)
        for (let index = 0; index < 2; index++)
            verify(renderer.setOpaqueBatchTransform(
                       index, 18, 0, 0, -18, 160, 180), renderer.packetError)
        verify(renderer.submitOpaqueRevision(1), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 1, 1000)
        let digest = renderer.presentedGeometryDigest
        verify(digest.length > 0)

        for (let index = 0; index < 2; index++)
            verify(renderer.setOpaqueBatchTransform(
                       index, 18, 0, 0, -18, 160, 144), renderer.packetError)
        verify(renderer.submitOpaqueRevision(2), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 2, 1000)
        compare(renderer.presentedGeometryDigest, digest)
        compare(renderer.sceneGraphGeometryUpdates, 0)
        compare(renderer.sceneGraphTransformUpdates, 2)
        compare(renderer.parseMilliseconds, 0)
    }

    function test_sharedTransformSubmissionIsAtomicAcrossBatches() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        verify(renderer.beginOpaqueBatchInstall(2))
        verify(renderer.appendOpaqueBatch(1,
            [0, 0, 40, 0, 0, 40], "#16a34a"), renderer.packetError)
        verify(renderer.appendOpaqueBatch(1,
            [50, 0, 90, 0, 50, 40], "#2563eb"), renderer.packetError)
        verify(renderer.commitOpaqueBatchInstall(), renderer.packetError)

        verify(renderer.submitSharedOpaqueTransform(
            18, 0, 0, -18, 160, 180, 1), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 1, 1000)
        compare(renderer.sceneGraphGeometryUpdates, 2)
        compare(renderer.sceneGraphTransformUpdates, 2)

        compare(renderer.submitSharedOpaqueTransform(
            NaN, 0, 0, -18, 160, 144, 2), false)
        compare(renderer.acceptedRevision, 1)
        compare(renderer.presentedRevision, 1)

        verify(renderer.submitSharedOpaqueTransform(
            18, 0, 0, -18, 160, 144, 2), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 2, 1000)
        compare(renderer.sceneGraphGeometryUpdates, 0)
        compare(renderer.sceneGraphTransformUpdates, 2)
    }

    function test_unchangedTransformDoesNotTouchSceneGraph() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        installTriangle(renderer, [0, 0, 100, 0, 0, 80], "#f59e0b")
        verify(renderer.setOpaqueBatchTransform(0, 1, 0, 0, 1, 7, 9),
               renderer.packetError)
        verify(renderer.submitOpaqueRevision(1), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 1, 1000)
        verify(renderer.submitOpaqueRevision(2), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 2, 1000)
        compare(renderer.sceneGraphGeometryUpdates, 0)
        compare(renderer.sceneGraphTransformUpdates, 0)
    }

    function test_rejectsTransparentMalformedAndNonfiniteDefinitions() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        verify(renderer.beginOpaqueBatchInstall(1))
        compare(renderer.appendOpaqueBatch(1, [0, 0, 10, 0, 0, 10],
                                           Qt.rgba(1, 0, 0, 0.5)), false)
        compare(renderer.packetValid, false)
        verify(renderer.packetError.length > 0)
        renderer.cancelOpaqueBatchInstall()

        verify(renderer.beginOpaqueBatchInstall(1))
        compare(renderer.appendOpaqueBatch(1, [0, 0, 10, 0], "#ffffff"), false)
        renderer.cancelOpaqueBatchInstall()

        verify(renderer.beginOpaqueBatchInstall(1))
        compare(renderer.appendOpaqueBatch(1, [0, 0, NaN, 0, 0, 10],
                                           "#ffffff"), false)
        compare(renderer.acceptedRevision, 0)
    }

    function test_failedReplacementPreservesCommittedGeometry() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        let source = [0, 0, 100, 0, 0, 80]
        installTriangle(renderer, source, "#16a34a")
        source[0] = 999999

        verify(renderer.beginOpaqueBatchInstall(1))
        compare(renderer.appendOpaqueBatch(2, [0, 0, 10, 0, 0, 10],
                                           "#ffffff"), false)
        compare(renderer.commitOpaqueBatchInstall(), false)
        renderer.cancelOpaqueBatchInstall()

        verify(renderer.submitOpaqueRevision(1), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 1, 1000)
        let retainedDigest = renderer.presentedGeometryDigest
        verify(retainedDigest.length > 0)
        compare(renderer.batchCount, 1)
        compare(renderer.vertexCount, 3)
        verify(renderer.submitOpaqueRevision(2), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 2, 1000)
        compare(renderer.presentedGeometryDigest, retainedDigest)
    }

    function test_missingInstallAndBadTransformFailClosed() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        compare(renderer.submitOpaqueRevision(1), false)
        compare(renderer.acceptedRevision, 0)
        installTriangle(renderer, [0, 0, 100, 0, 0, 80], "#16a34a")
        compare(renderer.setOpaqueBatchTransform(1, 1, 0, 0, 1, 0, 0), false)
        compare(renderer.setOpaqueBatchTransform(0, NaN, 0, 0, 1, 0, 0), false)
        compare(renderer.acceptedRevision, 0)
    }

    function test_multibatchTransformFailureRollsBackWholeRevision() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        verify(renderer.beginOpaqueBatchInstall(2))
        verify(renderer.appendOpaqueBatch(1, [0, 0, 40, 0, 0, 40], "#16a34a"))
        verify(renderer.appendOpaqueBatch(1, [50, 0, 90, 0, 50, 40], "#2563eb"))
        verify(renderer.commitOpaqueBatchInstall(), renderer.packetError)
        verify(renderer.submitOpaqueRevision(1), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 1, 1000)

        verify(renderer.setOpaqueBatchTransform(0, 1, 0, 0, 1, 20, 30))
        compare(renderer.setOpaqueBatchTransform(1, 1e100, 0, 0, 1, 0, 0), false)
        compare(renderer.setOpaqueBatchTransform(0, 1, 0, 0, 1, 60, 70), false)
        compare(renderer.submitOpaqueRevision(2), false)
        compare(renderer.acceptedRevision, 1)
        compare(renderer.presentedRevision, 1)

        verify(renderer.submitOpaqueRevision(2), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 2, 1000)
        compare(renderer.sceneGraphGeometryUpdates, 0)
        compare(renderer.sceneGraphTransformUpdates, 0)
    }

    function test_stagedInstallEnforcesAggregateVertexBudget() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        verify(renderer.beginOpaqueBatchInstall(3))
        let vertices = []
        for (let index = 0; index < 196608; index++)
            vertices.push(index % 3, Math.floor(index / 3) % 3)
        for (let batch = 0; batch < 2; batch++)
            verify(renderer.appendOpaqueBatch(1, vertices, "#16a34a"),
                   renderer.packetError)
        compare(renderer.appendOpaqueBatch(1, vertices, "#16a34a"), false)
        verify(renderer.packetError.indexOf("vertex budget") >= 0)
        compare(renderer.commitOpaqueBatchInstall(), false)
        renderer.cancelOpaqueBatchInstall()
        compare(renderer.acceptedRevision, 0)
    }

    function test_rejectsFiniteButUnrenderableTransform() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        installTriangle(renderer, [0, 0, 100, 0, 0, 80], "#16a34a")
        compare(renderer.setOpaqueBatchTransform(0, 1e100, 0, 0, 1, 0, 0), false)
        compare(renderer.submitOpaqueRevision(1), false)
        compare(renderer.acceptedRevision, 0)
    }

    function test_legacyAndTypedSubmissionsCoexist() {
        let renderer = createTemporaryObject(rendererComponent, testCase)
        verify(renderer !== null)
        installTriangle(renderer, [0, 0, 100, 0, 0, 80], "#16a34a")
        verify(renderer.submitOpaqueRevision(1), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 1, 1000)

        verify(renderer.submitFrame([{
            type: "triangles",
            color: "#2563eb",
            vertices: [10, 10, 150, 10, 10, 120]
        }], 2))
        tryCompare(renderer, "acceptedRevision", 2, 1000)
        tryCompare(renderer, "presentedRevision", 2, 1000)
        compare(renderer.packetValid, true)

        verify(renderer.submitOpaqueRevision(3), renderer.packetError)
        tryCompare(renderer, "presentedRevision", 3, 1000)
        compare(renderer.parseMilliseconds, 0)
    }
}
