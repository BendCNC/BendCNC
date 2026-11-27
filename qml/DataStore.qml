import QtQuick

QtObject {
    id: store

    property var punches: []
    property var dies: []
    property var materials: []
    property var bends: []
    property var programs: []
    property var localSettings: ({})
    property var userSettings: ({})
    // Tests may inject an in-memory implementation. Production uses FileIo,
    // exposed by main.cpp, and falls back to bundled qrc defaults when no
    // persistent override exists yet.
    property var storageIoOverride: null

    function loadJson(path, fallback) {
        try {
            var request = new XMLHttpRequest()
            request.open("GET", Qt.resolvedUrl(path), false)
            request.send()
            if (request.responseText && (request.status === 0 || request.status === 200 || request.status === undefined)) {
                return JSON.parse(request.responseText.replace(/:\s*NaN/g, ": null"))
            }
        } catch (error) {
            console.warn("Unable to load JSON", path, error)
        }
        return fallback
    }

    function storageBackend() {
        if (storageIoOverride !== null)
            return storageIoOverride
        if (typeof fileIo !== "undefined" && fileIo !== null)
            return fileIo
        return null
    }

    function persistentFilePath(fileName, backend) {
        if (backend && typeof backend.storageFilePath === "function")
            return backend.storageFilePath(fileName)
        return "data/current/" + fileName
    }

    function parseStoredJson(text) {
        if (text === undefined || text === null || String(text).length === 0)
            return undefined
        return JSON.parse(String(text).replace(/^\uFEFF/, "").replace(/:\s*NaN/g, ": null"))
    }

    function loadPersistentJson(fileName, resourcePath, fallback) {
        var backend = storageBackend()
        if (backend && typeof backend.read === "function") {
            var path = persistentFilePath(fileName, backend)
            var candidates = [path, path + ".bak"]
            for (var i = 0; i < candidates.length; i++) {
                try {
                    var parsed = parseStoredJson(backend.read(candidates[i]))
                    if (parsed !== undefined && parsed !== null)
                        return parsed
                } catch (error) {
                    console.warn("Unable to load persistent JSON", candidates[i], error)
                }
            }
        }
        return loadJson(resourcePath, fallback)
    }

    function reload() {
        punches = loadPersistentJson("punches.json", "data/current/punches.json", [])
        dies = loadPersistentJson("dies.json", "data/current/dies.json", [])
        materials = loadPersistentJson("materials.json", "data/current/materials.json", [])
        bends = loadPersistentJson("bends.json", "data/current/bends.json", [])
        programs = loadPersistentJson("programs.json", "data/current/programs.json", [])
        localSettings = loadPersistentJson("local-settings.json", "data/current/local-settings.json", ({}))
        userSettings = loadPersistentJson("user-settings.json", "data/current/user-settings.json", ({}))
    }

    Component.onCompleted: reload()
}
