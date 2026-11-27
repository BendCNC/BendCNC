// CAD import worker thread: JSON parse and schema-v5 topology validation are
// the heaviest pure steps of opening a .bend file, so they run off the GUI
// thread while CadImportView shows progress.
//
// Plain worker scripts cannot use .import, and the validator is a
// `.pragma library` file shared with the GUI thread, so its exact source is
// loaded once from the same resource and evaluated here (single source of
// truth, no copy to drift).
var SheetMetalPoseGraph = null

function loadPoseGraph(baseUrl) {
    var request = new XMLHttpRequest()
    request.open("GET", baseUrl + "sheetmetal/SheetMetalPoseGraph.js", false)
    request.send()
    var source = String(request.responseText || "").replace(/^\s*\.pragma\s+library\s*$/m, "")
    if (source.length === 0)
        throw new Error("SheetMetalPoseGraph.js not readable in worker")
    return (new Function(source + "\nreturn { validateAuthoritativePreview: validateAuthoritativePreview }"))()
}
function isDeclaredSchemaV5(payload) {
    if (!payload)
        return false
    var topologyVersion = parseFloat(String(payload.topologySchemaVersion || 0))
    var graphVersion = payload.sheetMetalGraph
            ? Number(payload.sheetMetalGraph.schemaVersion || 0) : 0
    return topologyVersion >= 5 || graphVersion >= 5
}

WorkerScript.onMessage = function(message) {
    var started = Date.now()
    var reply = { requestId: message.requestId, error: "", json: null, timing: null }
    try {
        if (!SheetMetalPoseGraph)
            SheetMetalPoseGraph = loadPoseGraph(message.baseUrl)
        var json = JSON.parse(message.text)
        var timing = ({})
        if (message.validateOnly) {
            reply.error = SheetMetalPoseGraph.validateAuthoritativePreview(
                json, "com.bendcnc.export", "1.1.0",
                message.acceptedRevisions, timing)
            reply.timing = timing
            WorkerScript.sendMessage(reply)
            return
        }
        if (isDeclaredSchemaV5(json)) {
            var error = json.sheetMetalGraph
                ? SheetMetalPoseGraph.validateAuthoritativePreview(
                      json, "com.bendcnc.export", "1.1.0",
                      message.acceptedRevisions, timing)
                : "missing-sheet-metal-graph"
            if (error.length > 0)
                reply.error = "Schema-v5 geometry is invalid: " + error
        }
        timing.totalMs = Date.now() - started
        reply.timing = timing
        if (reply.error.length === 0)
            reply.json = json
    } catch (exception) {
        reply.error = String(exception)
    }
    WorkerScript.sendMessage(reply)
}
