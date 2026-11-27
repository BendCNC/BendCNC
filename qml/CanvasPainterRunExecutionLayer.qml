import QtQuick
import BendCNCPrototype

Item {
    id: painterLayer
    clip: true

    property int textCommandCount: 0
    readonly property bool packetValid: renderer.packetValid
    readonly property string packetError: renderer.packetError
    readonly property int acceptedRevision: renderer.acceptedRevision
    readonly property int presentedRevision: renderer.presentedRevision
    readonly property int batchCount: renderer.batchCount
    readonly property int preparedCacheHits: renderer.preparedCacheHits
    readonly property int preparedCacheMisses: renderer.preparedCacheMisses
    readonly property int preparedCommandCount: renderer.preparedCommandCount
    readonly property real prepareMilliseconds: renderer.prepareMilliseconds
    readonly property int preparedCacheEntries: renderer.preparedCacheEntries
    readonly property int preparedCacheCost: renderer.preparedCacheCost
    readonly property int preparedCacheEvictions: renderer.preparedCacheEvictions
    readonly property int largestPreparedFrameCost: renderer.largestPreparedFrameCost
    readonly property int transportCacheHits: renderer.transportCacheHits
    readonly property int transportCacheMisses: renderer.transportCacheMisses
    readonly property int vertexCount: 1
    readonly property string backendName: renderer.backendName

    function commandTextCount(textCommands) {
        return textCommands && textCommands.length !== undefined
            ? textCommands.length : Number(textCommands || 0)
    }

    function submitFrame(orderedCommands, textCommands, revision, cacheKey) {
        if (!renderer.submitFrame(orderedCommands, revision, cacheKey))
            return false
        textCommandCount = commandTextCount(textCommands)
        return true
    }

    function submitCachedFrame(textCommands, revision, cacheKey) {
        if (!renderer.submitCachedFrame(cacheKey, revision))
            return false
        textCommandCount = commandTextCount(textCommands)
        return true
    }

    function hasCachedFrame(cacheKey) {
        return renderer.hasCachedFrame(cacheKey)
    }

    CanvasPainterRunRenderer {
        id: renderer
        anchors.fill: parent
    }
}