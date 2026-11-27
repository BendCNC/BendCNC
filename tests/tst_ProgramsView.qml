import QtQuick
import QtTest
import "../qml" as BendCNC

// PROGRAMS tab view: folder filter, search, sort and OPEN IN RUN wiring.
Item {
    id: root
    width: 864
    height: 638

    BendCNC.AppState { id: appState }

    BendCNC.ProgramsView {
        id: view
        anchors.fill: parent
        appState: appState
    }

    SignalSpy { id: openSpy; target: view; signalName: "openInRunRequested" }

    TestCase {
        name: "ProgramsViewTests"
        when: windowShown

        property var panel: null

        function findByName(item, name) {
            if (!item)
                return null
            if (item.objectName === name)
                return item
            let kids = item.children || []
            for (let i = 0; i < kids.length; i++) {
                let found = findByName(kids[i], name)
                if (found)
                    return found
            }
            return null
        }

        function names() {
            let out = []
            for (let i = 0; i < panel.rows.length; i++)
                out.push(panel.rows[i].name)
            return out
        }

        function program(name, folder, bends, created, updated) {
            let list = []
            for (let i = 0; i < bends; i++)
                list.push({ seq: i + 1, name: "Bend " + (i + 1), angle: "90.0" })
            return { id: "p-" + name, name: name, source: "qml", bends: list, cadPreviewJson: "",
                     folder: folder, createdAt: created, updatedAt: updated }
        }

        function init() {
            panel = findByName(view, "programs-left-panel-v7")
            verify(!!panel)
            appState.runActive = false
            appState.programFolders = ["Brackets", "Enclosures", "Prototypes"]
            appState.programs = [
                program("Wall Bracket 90", "Brackets", 2, "2026-03-01T08:00:00Z", "2026-10-20T15:30:00Z"),
                program("Enclosure Box - Electronics Module", "Enclosures", 6, "2026-05-12T09:15:00Z", "2026-11-02T11:05:00Z"),
                program("DIN Bracket", "Brackets", 4, "2026-08-06T13:40:00Z", "2026-08-06T13:40:00Z"),
                program("Battery Top Cover", "Enclosures", 9, "2026-09-18T10:00:00Z", "2026-11-10T17:45:00Z"),
                program("Legacy Tray", "", 3, "", ""),
                program("Test Coupon", "", 1, "2026-11-09T07:20:00Z", "2026-11-09T07:25:00Z")
            ]
            appState.selectedProgramIndex = 2
            appState.syncActiveProgramState()
            panel.selectFilter("all", "")
            panel.searchText = ""
            panel.sortKey = "name"
            panel.sortDescending = false
            panel.pickedIndex = 2
            openSpy.clear()
        }

        function test_sortByNameAndFlip() {
            compare(names(), ["Battery Top Cover", "DIN Bracket", "Enclosure Box - Electronics Module",
                              "Legacy Tray", "Test Coupon", "Wall Bracket 90"])
            panel.chooseSort("name")
            compare(names()[0], "Wall Bracket 90")
        }

        function test_sortByDatesKeepsUndatedLast() {
            panel.chooseSort("updated")
            verify(panel.sortDescending, "dates open newest first")
            compare(names(), ["Battery Top Cover", "Test Coupon", "Enclosure Box - Electronics Module",
                              "Wall Bracket 90", "DIN Bracket", "Legacy Tray"])
            panel.chooseSort("updated")
            compare(names()[0], "DIN Bracket")
            compare(names()[5], "Legacy Tray")
            panel.chooseSort("created")
            compare(names()[0], "Test Coupon")
            compare(names()[5], "Legacy Tray")
        }

        function test_sortByBends() {
            panel.chooseSort("bends")
            compare(names()[0], "Test Coupon")
            compare(names()[5], "Battery Top Cover")
        }

        function test_folderFilterSearchAndCounts() {
            compare(panel.railEntries.length, 5)
            compare(panel.railEntries[0].count, 6)
            compare(panel.railEntries[1].count, 2)
            compare(panel.railEntries[2].label, "Brackets")
            compare(panel.railEntries[2].count, 2)
            compare(panel.railEntries[4].count, 0, "empty folder is still listed")

            panel.selectFilter("folder", "Brackets")
            compare(names(), ["DIN Bracket", "Wall Bracket 90"])
            panel.selectFilter("unfiled", "")
            compare(names(), ["Legacy Tray", "Test Coupon"])
            panel.selectFilter("all", "")
            panel.searchText = "bracket"
            compare(names(), ["DIN Bracket", "Wall Bracket 90"])
        }

        function test_openInRunButton() {
            panel.pickedIndex = 3
            let button = findByName(panel, "programs-open-run")
            verify(!!button)
            mouseClick(button)
            compare(openSpy.count, 1)
            tryCompare(appState, "selectedProgramIndex", 3, 3000)
            compare(appState.activeProgram, "Battery Top Cover")
        }

        function test_lockedWhileRunning() {
            appState.runActive = true
            verify(!panel.canEdit)
            panel.pickedIndex = 0
            mouseClick(findByName(panel, "programs-open-run"))
            compare(openSpy.count, 0)
            compare(appState.selectedProgramIndex, 2)
            appState.runActive = false
        }

        function test_movePickerListsFoldersAndMoves() {
            panel.pickedIndex = 4
            panel.movePickerOpen = true
            verify(findChild(panel, "programs-move-picker").visible)
            panel.movePickedTo("Prototypes")
            compare(appState.programs[4].folder, "Prototypes")
            verify(!panel.movePickerOpen)
            compare(panel.railEntries[4].count, 1)
        }
    }
}
