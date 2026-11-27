import QtQuick
import QtTest
import "../qml" as BendCNC

// PROGRAMS tab: AppState program-library operations (folders, rename,
// duplicate, delete, open in RUN) against an in-memory storage backend.
Item {
    id: root
    width: 320
    height: 240

    TestCase {
        name: "ProgramLibraryTests"
        when: windowShown

        property var state: null
        property var files: ({})

        function fakeIo() {
            let store = files
            return {
                read: function(url) {
                    return Object.prototype.hasOwnProperty.call(store, url) ? store[url] : null
                },
                write: function(url, text) { store[url] = text; return true },
                exists: function(url) { return Object.prototype.hasOwnProperty.call(store, url) },
                storageFilePath: function(fileName) { return "mem://" + fileName }
            }
        }

        function bend(seq) {
            return { seq: seq, name: "Bend " + seq, angle: "90.0" }
        }

        function storedPrograms() {
            let text = files["mem://programs.json"]
            verify(text !== undefined, "programs.json was not written")
            let parsed = JSON.parse(text)
            return Array.isArray(parsed) ? parsed : (parsed.list || parsed.items || [])
        }

        function init() {
            files = ({})
            let component = Qt.createComponent("../qml/AppState.qml")
            verify(component.status === Component.Ready, component.errorString())
            state = component.createObject(root)
            verify(!!state)
            state.storageIoOverride = fakeIo()
            state.programFolders = []
            state.programs = [
                { id: "p-a", name: "Alpha", source: "qml", bends: [bend(1)], cadPreviewJson: "",
                  folder: "", createdAt: "2026-01-01T10:00:00.000Z", updatedAt: "2026-01-02T10:00:00.000Z" },
                { id: "p-b", name: "Bravo", source: "qml", bends: [bend(1), bend(2)], cadPreviewJson: "",
                  folder: "", createdAt: "2026-02-01T10:00:00.000Z", updatedAt: "2026-02-02T10:00:00.000Z" },
                { id: "p-c", name: "Charlie", source: "qml", bends: [], cadPreviewJson: "" }
            ]
            state.selectedProgramIndex = 1
            state.syncActiveProgramState()
        }

        function cleanup() {
            if (state)
                state.destroy()
            state = null
        }

        function test_folderLifecycle() {
            verify(state.createProgramFolder("  Brackets ").ok)
            compare(state.programFolders, ["Brackets"])
            verify(!state.createProgramFolder("brackets").ok, "case-insensitive duplicate")
            verify(!state.createProgramFolder("   ").ok)

            verify(state.moveProgramToFolder(0, "Brackets").ok)
            compare(state.programs[0].folder, "Brackets")
            compare(state.programs[0].updatedAt, "2026-01-02T10:00:00.000Z", "move is not an edit")
            compare(storedPrograms()[0].folder, "Brackets")
            verify(!state.moveProgramToFolder(0, "Missing").ok)

            let renamed = state.renameProgramFolder("Brackets", "Enclosures")
            verify(renamed.ok)
            compare(renamed.moved, 1)
            compare(state.programs[0].folder, "Enclosures")
            compare(state.programFolderNames(), ["Enclosures"])

            let removed = state.deleteProgramFolder("Enclosures")
            verify(removed.ok)
            compare(state.programs.length, 3, "deleting a folder never deletes programs")
            compare(state.programs[0].folder, "")
            compare(state.programFolderNames(), [])
        }

        function test_folderReferencedOnlyByProgramIsListed() {
            let next = state.programs.slice(0)
            next[2] = Object.assign({}, next[2], { folder: "Imported" })
            state.programs = next
            compare(state.programFolderNames(), ["Imported"])
        }

        function test_renameProgram() {
            verify(!state.renameProgramAt(0, "bravo").ok, "duplicate name refused")
            verify(!state.renameProgramAt(0, "  ").ok)
            let result = state.renameProgramAt(1, "Bravo 2")
            verify(result.ok)
            compare(state.programs[1].name, "Bravo 2")
            compare(state.activeProgram, "Bravo 2", "active program name follows the rename")
            verify(state.programs[1].updatedAt !== "2026-02-02T10:00:00.000Z")
            compare(state.programs[1].createdAt, "2026-02-01T10:00:00.000Z")
            compare(state.programs[1].id, "p-b")
            compare(storedPrograms()[1].name, "Bravo 2")
        }

        function test_duplicateProgram() {
            state.createProgramFolder("Shop")
            state.moveProgramToFolder(1, "Shop")
            let result = state.duplicateProgramAt(1)
            verify(result.ok)
            compare(result.index, 3)
            compare(state.programs.length, 4)
            let copy = state.programs[3]
            compare(copy.name, "Bravo COPY")
            compare(copy.folder, "Shop")
            compare(copy.bends.length, 2)
            verify(copy.id !== "p-b" && String(copy.id).length > 0)
            verify(copy.createdAt !== "2026-02-01T10:00:00.000Z")
            compare(state.selectedProgramIndex, 1, "duplicate does not change the RUN program")
            compare(state.duplicateProgramAt(1).name, "Bravo COPY 1")
        }

        function test_deleteKeepsRunProgram() {
            verify(state.deleteProgramAt(0).ok)
            compare(state.programs.length, 2)
            compare(state.selectedProgramIndex, 0, "index follows the same program")
            compare(state.activeProgram, "Bravo")

            verify(state.deleteProgramAt(1).ok)
            compare(state.selectedProgramIndex, 0)
            compare(state.activeProgram, "Bravo")
            compare(storedPrograms().length, 1)
        }

        function test_deleteRunProgramSelectsNeighbour() {
            verify(state.deleteProgramAt(1).ok)
            compare(state.programs.length, 2)
            compare(state.selectedProgramIndex, 0)
            compare(state.activeProgram, "Alpha")
            verify(state.deleteProgramAt(0).ok)
            verify(state.deleteProgramAt(0).ok)
            compare(state.programs.length, 0)
            compare(state.activeProgram, "No Program Loaded")
            verify(!state.deleteProgramAt(0).ok)
        }

        function test_lockedWhileRunning() {
            state.runActive = true
            verify(!state.renameProgramAt(0, "X").ok)
            verify(!state.deleteProgramAt(0).ok)
            verify(!state.duplicateProgramAt(0).ok)
            verify(!state.moveProgramToFolder(0, "").ok)
            verify(!state.openProgramInRun(0).ok)
            compare(state.programs.length, 3)
            compare(state.programs[0].name, "Alpha")
            compare(state.selectedProgramIndex, 1)
            state.runActive = false
        }

        function test_openInRunSwitchesProgram() {
            let same = state.openProgramInRun(1)
            verify(same.ok)
            verify(!state.runProgramSwitching, "already loaded: no switch")

            let result = state.openProgramInRun(0)
            verify(result.ok)
            compare(result.name, "Alpha")
            verify(state.runProgramSwitching)
            verify(!state.renameProgramAt(2, "Later").ok, "library locked while loading")
            tryCompare(state, "selectedProgramIndex", 0, 3000)
            compare(state.activeProgram, "Alpha")
            verify(!state.openProgramInRun(9).ok)
        }

        function test_storageRoundTripKeepsLibraryFields() {
            state.createProgramFolder("Shop")
            state.moveProgramToFolder(0, "Shop")
            let stored = storedPrograms()
            state.setProgramsFromStorage(stored, [], [], [], [], {})
            compare(state.programs[0].folder, "Shop")
            compare(state.programs[0].createdAt, "2026-01-01T10:00:00.000Z")
            compare(state.programs[0].updatedAt, "2026-01-02T10:00:00.000Z")
            compare(state.programs[2].createdAt, "", "legacy program without dates stays undated")
        }

        function test_bendEditStampsUpdatedAt() {
            verify(state.appendProgramBend(bend(3)))
            compare(state.programs[1].bends.length, 3)
            verify(state.programs[1].updatedAt !== "2026-02-02T10:00:00.000Z")
            compare(state.programs[1].createdAt, "2026-02-01T10:00:00.000Z")
        }

        function test_foldersRestoredFromLocalSettings() {
            state.applyLocalSettings({ programFolders: ["Shop", " shop ", "", "Brackets"] })
            compare(state.programFolders, ["Shop", "Brackets"])
        }
    }
}
