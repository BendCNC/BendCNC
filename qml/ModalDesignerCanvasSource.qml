import QtQuick

// Read-only data source for the Modal Design Lab live canvas. It feeds a
// preview AppState with the same persisted programs and tooling production
// reads at startup, so the real RunExecutionCanvas renders PLACEMENT/LIVE.
// The lab never writes storage: every AppState write is refused here.
QtObject {
    id: source
    property var appState: null
    property bool active: false
    property bool loaded: false
    readonly property DataStore dataStore: DataStore {
        storageIoOverride: source.readOnlyStorage
    }

    readonly property var readOnlyStorage: ({
        read: function(url) {
            if (typeof fileIo === "undefined" || fileIo === null)
                return null
            var text = fileIo.read(url)
            return (text === undefined || text === null || text === "") ? null : text
        },
        write: function(url) {
            console.info("MODAL-DESIGN-STORAGE write refused", url)
            return false
        },
        exists: function(url) {
            return typeof fileIo !== "undefined" && fileIo !== null && fileIo.exists(url)
        },
        storageFilePath: function(fileName) {
            if (typeof fileIo !== "undefined" && fileIo !== null)
                return fileIo.storageFilePath(fileName)
            return "data/current/" + fileName
        }
    })

    function load() {
        if (!appState || loaded)
            return
        dataStore.reload()
        var programs = dataStore.programs || []
        if (programs.length === 0) {
            console.info("MODAL-DESIGN-CANVAS programs=0 keeping sample program")
            return
        }
        // Same order as main.qml startup so the canvas matches production.
        appState.applyLocalSettings(dataStore.localSettings)
        appState.applyUserSettings(dataStore.userSettings)
        appState.setAllBends(dataStore.bends, dataStore.punches, dataStore.dies, dataStore.materials)
        appState.setProgramsFromStorage(programs, dataStore.bends, dataStore.punches,
                                        dataStore.dies, dataStore.materials, dataStore.localSettings)
        if (dataStore.localSettings && dataStore.localSettings.legacyRunUiEnabled === false)
            appState.legacyRunUiEnabled = false
        loaded = true
        console.info("MODAL-DESIGN-CANVAS programs=" + appState.programs.length
                     + " active=" + appState.activeProgram)
    }

    function attach() {
        if (appState)
            appState.storageIoOverride = readOnlyStorage
        if (active)
            load()
    }

    onAppStateChanged: attach()
    onActiveChanged: if (active) load()
    Component.onCompleted: attach()
}
