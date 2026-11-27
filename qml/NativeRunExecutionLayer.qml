import QtQuick
import BendCNCPrototype

Item {
    id: nativeLayer
    clip: true

    property int textCommandCount: 0
    readonly property bool packetValid: renderer.packetValid
    readonly property string packetError: renderer.packetError
    readonly property int acceptedRevision: renderer.acceptedRevision
    readonly property int presentedRevision: renderer.presentedRevision
    readonly property int batchCount: renderer.batchCount
    readonly property int vertexCount: renderer.vertexCount
    readonly property int parseMilliseconds: renderer.parseMilliseconds
    readonly property int coalescedFrameCount: renderer.coalescedFrameCount
    readonly property int tessellationCacheHits: renderer.tessellationCacheHits
    readonly property int tessellationCacheMisses: renderer.tessellationCacheMisses
    readonly property int retainedTransformUpdates: renderer.retainedTransformUpdates
    readonly property int sceneGraphGeometryUpdates: renderer.sceneGraphGeometryUpdates
    readonly property int sceneGraphTransformUpdates: renderer.sceneGraphTransformUpdates
    readonly property string presentedGeometryDigest: renderer.presentedGeometryDigest
    readonly property string backendName: renderer.backendName

    function submitFrame(orderedCommands, textCount, revision, cacheKey) {
        if (!renderer.submitFrame(orderedCommands, revision))
            return false
        textCommandCount = textCount
        return true
    }

    function installOpaqueBatches(batchDefinitions) {
        if (!batchDefinitions || batchDefinitions.length === 0)
            return false
        if (!renderer.beginOpaqueBatchInstall(batchDefinitions.length))
            return false
        for (let index = 0; index < batchDefinitions.length; index++) {
            const batch = batchDefinitions[index]
            if (!batch || !renderer.appendOpaqueBatch(
                    NativeRunRenderer.OpaqueTriangles,
                    batch.xyVertices, batch.color)) {
                renderer.cancelOpaqueBatchInstall()
                return false
            }
        }
        if (!renderer.commitOpaqueBatchInstall()) {
            renderer.cancelOpaqueBatchInstall()
            return false
        }
        return true
    }

    function submitOpaqueTransform(batchCount, m11, m12, m21, m22, dx, dy,
                                   revision) {
        if (batchCount <= 0)
            return false
        return renderer.submitSharedOpaqueTransform(
                    m11, m12, m21, m22, dx, dy, revision)
    }

    function cancelOpaqueInstall() {
        renderer.cancelOpaqueBatchInstall()
    }

    NativeRunRenderer {
        id: renderer
        anchors.fill: parent
        timingSink: typeof runFrameTiming !== "undefined" ? runFrameTiming : null
    }
}