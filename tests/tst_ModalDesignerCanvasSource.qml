import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    width: 1024
    height: 768

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
        virtualInputMode: "NEVER"
        programs: [{ name: "Designer Sample", source: "sample", bends: [] }]
    }

    BendCNC.ModalDesignerCanvasSource {
        id: source
        appState: state
    }

    BendCNC.ModalDesignerSurface {
        id: surface
        width: 1366
        height: 768
        selection: "LEFT_0"
        appState: state
        dataStore: source.dataStore
    }

    TestCase {
        name: "ModalDesignerCanvasSourceTests"
        when: windowShown

        function test_storageIsReadOnly() {
            compare(state.storageIoOverride, source.readOnlyStorage)
            compare(source.readOnlyStorage.write("data/current/programs.json", "[]"), false)
            compare(state.persistEntities("programs", state.programs), false)
        }

        function test_activeLoadsStoredPrograms() {
            verify(!source.loaded)
            compare(state.programs[0].name, "Designer Sample")
            source.active = true
            const storedPrograms = source.readOnlyStorage.read("data/current/programs.json")
            if (!storedPrograms || storedPrograms.trim() === "[]")
                skip("requires stored programs (catalog not bundled)")
            tryVerify(function() { return source.loaded }, 3000)
            if (state.programs.length === 0)
                skip("requires stored programs (catalog not bundled)")
            verify(state.programs[0].name !== "Designer Sample")
            verify(source.dataStore.punches.length > 0)
        }

        function test_surfaceTogglesBlankCanvas() {
            var runPage = null
            tryVerify(function() {
                runPage = findRunPage(surface)
                return runPage !== null
            }, 5000)
            compare(runPage.designerBlankCanvas, true)
            compare(runPage.dataStore, source.dataStore)
            surface.liveCanvas = true
            compare(runPage.designerBlankCanvas, false)
            surface.liveCanvas = false
            compare(runPage.designerBlankCanvas, true)
        }

        function findRunPage(item) {
            if (!item)
                return null
            if (item.hasOwnProperty("designerBlankCanvas"))
                return item
            var children = item.children || []
            for (var i = 0; i < children.length; i++) {
                var found = findRunPage(children[i])
                if (found)
                    return found
            }
            return null
        }
    }
}
