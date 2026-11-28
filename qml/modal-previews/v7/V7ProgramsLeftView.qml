import QtQuick
import QtQuick.Controls.Basic

// =============================================================================
// BENDCNC V7 PRECISION - PROGRAM LIBRARY LEFT PANEL (864 x 638)
//
// 1. Library deck: program count, name search and sort chips
//    (NAME / CREATED / UPDATED / BENDS; tap the active chip to flip direction).
// 2. Folder rail: ALL PROGRAMS, UNFILED and the operator's one-level folders
//    with live counts; create, rename and delete folders.
// 3. Program list: name, folder, origin, compatibility badge, bend count and
//    created / updated dates. The program loaded in RUN carries an IN RUN tag.
// 4. Action hub: OPEN IN RUN, RENAME, MOVE TO FOLDER, DUPLICATE, DELETE.
//
// The panel only organizes stored programs through AppState's program library
// functions. It never issues a machine command, and every mutation is refused
// by AppState while a program is running.
// =============================================================================

Item {
    id: root
    objectName: "programs-left-panel-v7"

    property var appState: null
    signal openInRunRequested()

    width: 864
    height: 638
    focus: true

    // -------------------------------------------------------------------------
    // Design Tokens (shared with the v7 Tools studio)
    // -------------------------------------------------------------------------
    readonly property color bgCanvas: "#E5E7EB"
    readonly property color cardBg: "#FFFFFF"
    readonly property color cardBgAlt: "#F8FAFC"
    readonly property color cardBorder: "#CBD5E1"
    readonly property color ink: "#1E232A"
    readonly property color textSecondary: "#475569"
    readonly property color textMuted: "#64748B"
    readonly property color redAccent: "#A82011"
    readonly property color blueAccent: "#2D83B2"
    readonly property color greenAccent: "#59A60C"
    readonly property color amberAccent: "#F59E0B"
    readonly property color charcoal: "#2B2C2B"

    // -------------------------------------------------------------------------
    // Library State
    // -------------------------------------------------------------------------
    readonly property var programsList: appState && appState.programs ? appState.programs : []
    readonly property var folderList: appState ? appState.programFolderNames() : []
    readonly property int runProgramIndex: appState ? appState.selectedProgramIndex : -1
    readonly property string busyReason: appState ? appState.programLibraryBusyReason() : ""
    readonly property bool canEdit: appState !== null && busyReason.length === 0

    // "all" | "unfiled" | "folder" (+ filterFolder)
    property string filterMode: "all"
    property string filterFolder: ""
    property string searchText: ""
    // "name" | "created" | "updated" | "bends"
    property string sortKey: "name"
    property bool sortDescending: false
    // Index into appState.programs of the highlighted program.
    property int pickedIndex: -1
    property bool movePickerOpen: false

    readonly property var pickedProgram: pickedIndex >= 0 && pickedIndex < programsList.length
                                         ? programsList[pickedIndex] : null
    readonly property string pickedName: pickedProgram ? String(pickedProgram.name || "") : ""
    readonly property bool realFolderSelected: filterMode === "folder" && filterFolder.length > 0

    readonly property var folderCounts: {
        var counts = { all: programsList.length, unfiled: 0, folders: ({}) }
        for (var i = 0; i < programsList.length; i++) {
            var folder = String(programsList[i] && programsList[i].folder || "").trim().toLowerCase()
            if (folder.length === 0)
                counts.unfiled++
            else
                counts.folders[folder] = (counts.folders[folder] || 0) + 1
        }
        return counts
    }

    readonly property var railEntries: {
        var entries = [
            { mode: "all", folder: "", label: qsTr("ALL PROGRAMS"), count: folderCounts.all },
            { mode: "unfiled", folder: "", label: qsTr("UNFILED"), count: folderCounts.unfiled }
        ]
        for (var i = 0; i < folderList.length; i++)
            entries.push({ mode: "folder", folder: folderList[i], label: folderList[i],
                           count: folderCounts.folders[folderList[i].toLowerCase()] || 0 })
        return entries
    }

    readonly property var rows: {
        var out = []
        var query = searchText.trim().toLowerCase()
        var wantedFolder = filterFolder.toLowerCase()
        for (var i = 0; i < programsList.length; i++) {
            var program = programsList[i] || {}
            var name = String(program.name || "")
            var folder = String(program.folder || "").trim()
            if (filterMode === "unfiled" && folder.length > 0)
                continue
            if (filterMode === "folder" && folder.toLowerCase() !== wantedFolder)
                continue
            if (query.length > 0 && name.toLowerCase().indexOf(query) < 0)
                continue
            out.push({
                programIndex: i,
                name: name,
                folder: folder,
                bends: program.bends ? program.bends.length : 0,
                created: stampMs(program.createdAt),
                updated: stampMs(program.updatedAt),
                compat: appState ? appState.programCompatibility(program) : null
            })
        }
        var key = sortKey
        var descending = sortDescending
        out.sort(function(a, b) {
            var delta = 0
            if (key === "bends") {
                delta = a.bends - b.bends
            } else if (key === "created" || key === "updated") {
                // Programs saved before dates existed always sort last.
                if (a[key] <= 0 && b[key] > 0) return 1
                if (b[key] <= 0 && a[key] > 0) return -1
                delta = a[key] - b[key]
            } else {
                delta = root.compareNames(a.name, b.name)
            }
            if (descending)
                delta = -delta
            return delta !== 0 ? delta : root.compareNames(a.name, b.name)
        })
        return out
    }

    function compareNames(a, b) {
        var left = String(a).toLowerCase()
        var right = String(b).toLowerCase()
        return left < right ? -1 : (left > right ? 1 : 0)
    }

    function stampMs(value) {
        var text = String(value === undefined || value === null ? "" : value)
        if (text.length === 0)
            return 0
        var parsed = Date.parse(text)
        return isFinite(parsed) ? parsed : 0
    }

    function stampText(ms) {
        return ms > 0 ? Qt.formatDateTime(new Date(ms), "yyyy-MM-dd HH:mm") : "\u2014"
    }

    function restoreSortPreference() {
        var model = appState ? appState.localSettingsModel : null
        var key = model ? String(model.programSortKey || "") : ""
        sortKey = ["name", "created", "updated", "bends"].indexOf(key) >= 0 ? key : "name"
        sortDescending = model ? model.programSortDescending === true : false
    }

    function chooseSort(key) {
        if (sortKey === key) {
            sortDescending = !sortDescending
        } else {
            sortKey = key
            // Dates open newest-first; name and bend count open ascending.
            sortDescending = key === "created" || key === "updated"
        }
        if (appState) {
            appState.persistLocalSetting("programSortKey", sortKey)
            appState.persistLocalSetting("programSortDescending", sortDescending)
        }
    }

    function selectFilter(mode, folder) {
        filterMode = mode
        filterFolder = mode === "folder" ? String(folder || "") : ""
    }

    onAppStateChanged: {
        restoreSortPreference()
        pickedIndex = appState ? appState.selectedProgramIndex : -1
    }
    onProgramsListChanged: {
        if (pickedIndex >= programsList.length)
            pickedIndex = -1
    }
    onFolderListChanged: {
        // The filtered folder was renamed or deleted elsewhere.
        if (filterMode !== "folder")
            return
        for (var i = 0; i < folderList.length; i++) {
            if (folderList[i].toLowerCase() === filterFolder.toLowerCase())
                return
        }
        selectFilter("all", "")
    }

    // -------------------------------------------------------------------------
    // Toast Feedback
    // -------------------------------------------------------------------------
    property string toastText: ""
    Timer {
        id: toastTimer
        interval: 2200
        repeat: false
        onTriggered: root.toastText = ""
    }
    function showToast(msg) {
        root.toastText = String(msg || "")
        toastTimer.restart()
    }
    function report(result, successText) {
        showToast(result && result.ok ? successText : (result ? result.reason : qsTr("Not available")))
        return result && result.ok === true
    }

    // -------------------------------------------------------------------------
    // Keyboard Target Helper
    // -------------------------------------------------------------------------
    TextInput { id: keyboardProxy; visible: false; width: 0; height: 0 }

    function openTextInput(title, initial, commit) {
        if (!appState || typeof appState.openOnScreenKeyboard !== "function")
            return false
        keyboardProxy.text = initial === undefined || initial === null ? "" : String(initial)
        return appState.openOnScreenKeyboard(keyboardProxy, false, title, commit, null, true)
    }

    // -------------------------------------------------------------------------
    // Actions
    // -------------------------------------------------------------------------
    function openPicked() {
        if (!appState || !pickedProgram)
            return
        var result = appState.openProgramInRun(pickedIndex)
        if (result.ok)
            root.openInRunRequested()
        else
            showToast(result.reason)
    }

    function renamePicked() {
        if (!canEdit || !pickedProgram)
            return
        var index = pickedIndex
        openTextInput(qsTr("RENAME PROGRAM"), pickedName, function(value) {
            root.report(root.appState.renameProgramAt(index, value), qsTr("Program renamed"))
        })
    }

    function duplicatePicked() {
        if (!canEdit || !pickedProgram)
            return
        var result = appState.duplicateProgramAt(pickedIndex)
        if (report(result, qsTr("Duplicated as %1").arg(result.name || "")))
            pickedIndex = result.index
    }

    function deletePicked() {
        if (!canEdit || !pickedProgram)
            return
        var index = pickedIndex
        var name = pickedName
        appState.showConfirmation(qsTr("DELETE PROGRAM"),
                                  qsTr("Delete \"%1\"?\nThis cannot be undone.").arg(name),
                                  function() {
            // The list may have changed while the confirmation was open.
            var current = root.programsList[index]
            if (!current || String(current.name || "") !== name) {
                root.showToast(qsTr("Program list changed; nothing deleted"))
                return
            }
            if (root.report(root.appState.deleteProgramAt(index), qsTr("Program deleted")))
                root.pickedIndex = -1
        }, null)
    }

    function movePickedTo(folder) {
        movePickerOpen = false
        if (!canEdit || !pickedProgram)
            return
        report(appState.moveProgramToFolder(pickedIndex, folder),
               folder.length > 0 ? qsTr("Moved to %1").arg(folder) : qsTr("Moved to UNFILED"))
    }

    function newFolder(thenMovePicked) {
        if (!appState)
            return
        var index = pickedIndex
        openTextInput(qsTr("NEW FOLDER"), "", function(value) {
            var result = root.appState.createProgramFolder(value)
            if (!root.report(result, qsTr("Folder created")))
                return
            if (thenMovePicked && index === root.pickedIndex)
                root.movePickedTo(result.name)
            else
                root.selectFilter("folder", result.name)
        })
    }

    function renameSelectedFolder() {
        if (!canEdit || !realFolderSelected)
            return
        var folder = filterFolder
        openTextInput(qsTr("RENAME FOLDER"), folder, function(value) {
            var result = root.appState.renameProgramFolder(folder, value)
            if (root.report(result, qsTr("Folder renamed")))
                root.selectFilter("folder", result.name)
        })
    }

    function deleteSelectedFolder() {
        if (!canEdit || !realFolderSelected)
            return
        var folder = filterFolder
        var count = folderCounts.folders[folder.toLowerCase()] || 0
        appState.showConfirmation(qsTr("DELETE FOLDER"),
                                  qsTr("Delete folder \"%1\"?\n%2 program(s) will move to UNFILED. No program is deleted.")
                                      .arg(folder).arg(count),
                                  function() {
            if (root.report(root.appState.deleteProgramFolder(folder), qsTr("Folder deleted")))
                root.selectFilter("all", "")
        }, null)
    }

    // -------------------------------------------------------------------------
    // Reusable Pieces
    // -------------------------------------------------------------------------
    component FolderGlyph: Item {
        property color tint: "#64748B"
        width: 16
        height: 13
        Rectangle { x: 0; y: 0; width: 7; height: 5; radius: 1.5; color: parent.tint }
        Rectangle { x: 0; y: 2; width: 16; height: 11; radius: 2; color: parent.tint }
    }

    component HubButton: Rectangle {
        id: hubButton
        property string label: ""
        property color fill: "#2B2C2B"
        property color labelColor: "#FFFFFF"
        property string iconSource: ""
        // Dark variant shown on the light disabled face (white icons vanish there).
        property string disabledIconSource: ""
        property string glyph: ""
        property bool folderIcon: false
        property bool active: true
        signal triggered()
        height: 38
        radius: 4
        color: !active ? "#E2E8F0" : (hubMouse.pressed ? Qt.darker(fill, 1.18) : fill)
        border.width: active ? 0 : 1
        border.color: "#CBD5E1"
        Row {
            anchors.centerIn: parent
            spacing: 7
            Image {
                visible: hubButton.iconSource.length > 0
                source: !hubButton.active && hubButton.disabledIconSource.length > 0
                        ? hubButton.disabledIconSource : hubButton.iconSource
                width: 13
                height: 13
                sourceSize.width: 13
                sourceSize.height: 13
                opacity: hubButton.active ? 1.0 : 0.35
                anchors.verticalCenter: parent.verticalCenter
            }
            FolderGlyph {
                visible: hubButton.folderIcon
                tint: hubButton.active ? hubButton.labelColor : "#94A3B8"
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: hubButton.glyph.length > 0
                text: hubButton.glyph
                font.pixelSize: 12
                font.bold: true
                color: hubButton.active ? hubButton.labelColor : "#94A3B8"
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: hubButton.label
                font.pixelSize: 11
                font.bold: true
                color: hubButton.active ? hubButton.labelColor : "#94A3B8"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: hubMouse
            anchors.fill: parent
            enabled: hubButton.active
            cursorShape: Qt.PointingHandCursor
            onClicked: hubButton.triggered()
        }
    }

    component SortChip: Rectangle {
        id: sortChip
        property string key: ""
        property string label: ""
        readonly property bool current: root.sortKey === key
        objectName: "programs-sort-" + key
        height: 30
        width: chipRow.implicitWidth + 20
        radius: 5
        color: current ? root.charcoal : "transparent"
        border.width: 1
        border.color: current ? root.charcoal : root.cardBorder
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5
            Text {
                text: sortChip.label
                font.pixelSize: 11
                font.bold: true
                color: sortChip.current ? "#FFFFFF" : root.textSecondary
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: sortChip.current
                text: root.sortDescending ? "\u25BC" : "\u25B2"
                font.pixelSize: 11
                color: "#FFFFFF"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.chooseSort(sortChip.key)
        }
    }

    component CompatBadge: Rectangle {
        property var info: null
        readonly property string status: info ? String(info.status || "") : ""
        readonly property string label: info ? String(info.label || "") : ""
        visible: label.length > 0
        width: visible ? compatText.implicitWidth + 12 : 0
        height: 18
        radius: 3
        color: status === "current" ? root.greenAccent
             : status === "old-revision" ? "#C98A00"
             : status === "degraded" ? "#D35400"
             : status === "manual" ? "#808080" : root.redAccent
        Text { id: compatText; anchors.centerIn: parent; text: parent.label; color: "white"; font.bold: true; font.pixelSize: 11 }
    }

    // -------------------------------------------------------------------------
    // Canvas
    // -------------------------------------------------------------------------
    Rectangle { anchors.fill: parent; color: root.bgCanvas }

    // ---- 1. Library deck ----------------------------------------------------
    Rectangle {
        id: deck
        x: 10
        y: 8
        width: 844
        height: 42
        radius: 6
        color: root.cardBg
        border.color: root.cardBorder
        border.width: 1

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            FolderGlyph { tint: root.redAccent; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: qsTr("PROGRAMS")
                font.pixelSize: 13
                font.bold: true
                color: root.ink
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                width: Math.max(26, deckCount.implicitWidth + 12)
                height: 18
                radius: 9
                color: "#E2E8F0"
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    id: deckCount
                    anchors.centerIn: parent
                    text: root.rows.length === root.programsList.length
                          ? String(root.programsList.length)
                          : root.rows.length + " / " + root.programsList.length
                    font.pixelSize: 11
                    font.bold: true
                    color: root.textSecondary
                }
            }
        }

        // Search pill
        Rectangle {
            id: searchPill
            objectName: "programs-search"
            x: 176
            anchors.verticalCenter: parent.verticalCenter
            width: 236
            height: 30
            radius: 15
            color: "#F1F5F9"
            border.width: 1
            border.color: root.searchText.length > 0 ? root.blueAccent : root.cardBorder
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: clearSearch.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: root.searchText.length > 0 ? root.searchText : qsTr("Search by name\u2026")
                font.pixelSize: 12
                font.bold: root.searchText.length > 0
                color: root.searchText.length > 0 ? root.ink : root.textMuted
                elide: Text.ElideRight
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openTextInput(qsTr("SEARCH PROGRAMS"), root.searchText,
                                              function(value) { root.searchText = String(value || "").trim() })
            }
            Item {
                id: clearSearch
                visible: root.searchText.length > 0
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                Image {
                    anchors.centerIn: parent
                    source: "../../icons/fa-times.svg"
                    width: 11
                    height: 11
                    sourceSize.width: 11
                    sourceSize.height: 11
                }
                MouseArea { anchors.fill: parent; onClicked: root.searchText = "" }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Text {
                text: qsTr("SORT")
                font.pixelSize: 11
                font.bold: true
                color: root.textMuted
                anchors.verticalCenter: parent.verticalCenter
            }
            SortChip { key: "name"; label: qsTr("NAME") }
            SortChip { key: "created"; label: qsTr("CREATED") }
            SortChip { key: "updated"; label: qsTr("UPDATED") }
            SortChip { key: "bends"; label: qsTr("BENDS") }
        }
    }

    // ---- 2. Folder rail -----------------------------------------------------
    Rectangle {
        id: rail
        x: 10
        y: 58
        width: 206
        height: 510
        radius: 6
        color: root.cardBg
        border.color: root.cardBorder
        border.width: 1

        Text {
            x: 12
            y: 12
            text: qsTr("FOLDERS")
            font.pixelSize: 11
            font.bold: true
            color: root.textMuted
        }
        Rectangle {
            objectName: "programs-new-folder"
            anchors.right: parent.right
            anchors.rightMargin: 8
            y: 6
            width: 62
            height: 26
            radius: 4
            color: newFolderMouse.pressed ? "#1E5E82" : root.blueAccent
            Row {
                anchors.centerIn: parent
                spacing: 5
                Image {
                    source: "../../icons/fa-plus.svg"
                    width: 10
                    height: 10
                    sourceSize.width: 10
                    sourceSize.height: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text { text: qsTr("NEW"); font.pixelSize: 11; font.bold: true; color: "#FFFFFF"; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { id: newFolderMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.newFolder(false) }
        }
        Rectangle { x: 8; y: 38; width: parent.width - 16; height: 1; color: "#E2E8F0" }

        ListView {
            id: railList
            objectName: "programs-folder-list"
            x: 6
            y: 44
            width: parent.width - 12
            height: parent.height - 44 - 50
            clip: true
            spacing: 3
            boundsBehavior: Flickable.StopAtBounds
            model: root.railEntries
            ScrollBar.vertical: ScrollBar { policy: railList.contentHeight > railList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff; width: 6 }
            delegate: Rectangle {
                readonly property bool current: root.filterMode === modelData.mode
                                                && (modelData.mode !== "folder"
                                                    || root.filterFolder.toLowerCase() === modelData.folder.toLowerCase())
                width: railList.width
                height: 38
                radius: 4
                color: current ? "#FDF1EF" : (railMouse.pressed ? "#F1F5F9" : "transparent")
                border.width: current ? 1 : 0
                border.color: root.redAccent
                Rectangle { visible: parent.current; x: 0; y: 6; width: 3; height: parent.height - 12; radius: 1.5; color: root.redAccent }
                FolderGlyph {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    tint: parent.current ? root.redAccent
                        : (modelData.mode === "folder" ? root.amberAccent : "#94A3B8")
                }
                Text {
                    x: 36
                    width: parent.width - 36 - 40
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    font.pixelSize: 12
                    font.bold: true
                    color: parent.current ? root.redAccent : root.ink
                    elide: Text.ElideRight
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(24, railCount.implicitWidth + 10)
                    height: 18
                    radius: 9
                    color: parent.current ? root.redAccent : "#E2E8F0"
                    Text {
                        id: railCount
                        anchors.centerIn: parent
                        text: String(modelData.count)
                        font.pixelSize: 11
                        font.bold: true
                        color: parent.parent.current ? "#FFFFFF" : root.textSecondary
                    }
                }
                MouseArea {
                    id: railMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectFilter(modelData.mode, modelData.folder)
                }
            }
        }

        Rectangle { x: 8; y: parent.height - 48; width: parent.width - 16; height: 1; color: "#E2E8F0" }
        Row {
            x: 8
            y: parent.height - 42
            spacing: 6
            HubButton {
                objectName: "programs-rename-folder"
                width: 92
                height: 34
                label: qsTr("RENAME")
                iconSource: "../../icons/fa-pen-white.svg"
                disabledIconSource: "../../icons/fa-pen.svg"
                fill: root.charcoal
                active: root.canEdit && root.realFolderSelected
                onTriggered: root.renameSelectedFolder()
            }
            HubButton {
                objectName: "programs-delete-folder"
                width: 92
                height: 34
                label: qsTr("DELETE")
                iconSource: "../../icons/fa-trash.svg"
                disabledIconSource: "../../icons/fa-trash-black.svg"
                fill: root.redAccent
                active: root.canEdit && root.realFolderSelected
                onTriggered: root.deleteSelectedFolder()
            }
        }
    }

    // ---- 3. Program list ----------------------------------------------------
    Rectangle {
        id: listCard
        x: 224
        y: 58
        width: 630
        height: 510
        radius: 6
        color: root.cardBg
        border.color: root.cardBorder
        border.width: 1

        // Column captions
        Item {
            id: captions
            x: 8
            y: 6
            width: parent.width - 16
            height: 22
            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: qsTr("PROGRAM"); font.pixelSize: 11; font.bold: true; color: root.textMuted }
            Text { x: parent.width - 232; width: 60; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter; text: qsTr("BENDS"); font.pixelSize: 11; font.bold: true; color: root.textMuted }
            Text { x: parent.width - 166; anchors.verticalCenter: parent.verticalCenter; text: qsTr("CREATED / UPDATED"); font.pixelSize: 11; font.bold: true; color: root.textMuted }
        }
        Rectangle { x: 8; y: 30; width: parent.width - 16; height: 1; color: "#E2E8F0" }

        // Read-only strip while a program runs or loads
        Rectangle {
            id: lockStrip
            visible: root.busyReason.length > 0
            x: 8
            y: 36
            width: parent.width - 16
            height: visible ? 28 : 0
            radius: 4
            color: "#FEF3C7"
            border.width: 1
            border.color: root.amberAccent
            Row {
                anchors.centerIn: parent
                spacing: 8
                Image { source: "../../icons/fa-exclamation-triangle.svg"; width: 13; height: 13; sourceSize.width: 13; sourceSize.height: 13; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: qsTr("LIBRARY LOCKED \u00B7 %1").arg(root.busyReason)
                    font.pixelSize: 11
                    font.bold: true
                    color: "#92400E"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        ListView {
            id: programList
            objectName: "programs-list"
            x: 8
            y: lockStrip.visible ? 70 : 36
            width: parent.width - 16
            height: parent.height - y - 8
            clip: true
            spacing: 5
            boundsBehavior: Flickable.StopAtBounds
            model: root.rows
            ScrollBar.vertical: ScrollBar { policy: programList.contentHeight > programList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff; width: 6 }
            delegate: Rectangle {
                id: programRow
                readonly property bool picked: modelData.programIndex === root.pickedIndex
                readonly property bool inRun: modelData.programIndex === root.runProgramIndex
                objectName: "programs-row-" + modelData.programIndex
                width: programList.width - 10
                height: 54
                radius: 5
                color: picked ? "#FDF1EF" : (rowMouse.pressed ? "#F1F5F9" : root.cardBgAlt)
                border.width: picked ? 2 : 1
                border.color: picked ? root.redAccent : "#E2E8F0"

                Rectangle {
                    visible: programRow.inRun
                    x: 2
                    y: 8
                    width: 4
                    height: parent.height - 16
                    radius: 2
                    color: root.greenAccent
                }

                Text {
                    id: rowName
                    x: 14
                    y: 8
                    width: Math.min(implicitWidth, parent.width - 14 - 250 - (inRunTag.visible ? inRunTag.width + 8 : 0))
                    text: modelData.name
                    font.pixelSize: 14
                    font.bold: true
                    color: root.ink
                    elide: Text.ElideRight
                }
                Rectangle {
                    id: inRunTag
                    visible: programRow.inRun
                    x: rowName.x + rowName.width + 8
                    y: 9
                    width: inRunText.implicitWidth + 12
                    height: 17
                    radius: 8.5
                    color: root.greenAccent
                    Text { id: inRunText; anchors.centerIn: parent; text: qsTr("IN RUN"); font.pixelSize: 11; font.bold: true; color: "#FFFFFF" }
                }

                Row {
                    x: 14
                    y: 31
                    spacing: 8
                    FolderGlyph {
                        scale: 0.75
                        tint: modelData.folder.length > 0 ? root.amberAccent : "#CBD5E1"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        width: Math.min(implicitWidth, 190)
                        text: modelData.folder.length > 0 ? modelData.folder : qsTr("Unfiled")
                        font.pixelSize: 11
                        font.bold: modelData.folder.length > 0
                        color: modelData.folder.length > 0 ? root.textSecondary : root.textMuted
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    CompatBadge { info: modelData.compat; height: 16; anchors.verticalCenter: parent.verticalCenter }
                }

                Text {
                    x: parent.width - 232
                    width: 60
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: String(modelData.bends)
                    font.pixelSize: 16
                    font.bold: true
                    font.family: "Consolas, monospace"
                    color: modelData.bends > 0 ? root.ink : root.textMuted
                }

                Column {
                    x: parent.width - 166
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Row {
                        spacing: 6
                        Text { width: 12; text: "C"; font.pixelSize: 11; font.bold: true; color: root.textMuted }
                        Text {
                            text: root.stampText(modelData.created)
                            font.pixelSize: 11
                            font.family: "Consolas, monospace"
                            font.bold: root.sortKey === "created"
                            color: root.sortKey === "created" ? root.ink : root.textSecondary
                        }
                    }
                    Row {
                        spacing: 6
                        Text { width: 12; text: "U"; font.pixelSize: 11; font.bold: true; color: root.textMuted }
                        Text {
                            text: root.stampText(modelData.updated)
                            font.pixelSize: 11
                            font.family: "Consolas, monospace"
                            font.bold: root.sortKey === "updated"
                            color: root.sortKey === "updated" ? root.ink : root.textSecondary
                        }
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickedIndex = modelData.programIndex
                    onDoubleClicked: {
                        root.pickedIndex = modelData.programIndex
                        root.openPicked()
                    }
                }
            }
        }

        Column {
            visible: root.rows.length === 0
            anchors.centerIn: programList
            spacing: 8
            FolderGlyph { scale: 2.0; tint: "#CBD5E1"; anchors.horizontalCenter: parent.horizontalCenter }
            Item { width: 1; height: 6 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.programsList.length === 0 ? qsTr("No programs stored")
                    : (root.searchText.length > 0 ? qsTr("No program matches \"%1\"").arg(root.searchText)
                                                  : qsTr("This folder is empty"))
                font.pixelSize: 14
                font.bold: true
                color: root.textSecondary
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.programsList.length === 0 ? qsTr("Create one in RUN or generate it from CAD.")
                    : (root.searchText.length > 0 ? qsTr("Clear the search to see every program.")
                                                  : qsTr("Pick a program and use MOVE TO FOLDER."))
                font.pixelSize: 11
                color: root.textMuted
            }
        }
    }

    // ---- 4. Action hub ------------------------------------------------------
    Rectangle {
        id: hub
        x: 10
        y: 576
        width: 844
        height: 54
        radius: 6
        color: root.cardBg
        border.color: root.cardBorder
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: 8
            HubButton {
                objectName: "programs-open-run"
                width: 244
                label: root.pickedProgram && root.pickedIndex === root.runProgramIndex
                       ? qsTr("VIEW IN RUN") : qsTr("OPEN IN RUN")
                glyph: "\u25B6"
                fill: root.greenAccent
                active: root.canEdit && root.pickedProgram !== null
                onTriggered: root.openPicked()
            }
            HubButton {
                objectName: "programs-rename"
                width: 132
                label: qsTr("RENAME")
                iconSource: "../../icons/fa-pen-white.svg"
                disabledIconSource: "../../icons/fa-pen.svg"
                fill: root.charcoal
                active: root.canEdit && root.pickedProgram !== null
                onTriggered: root.renamePicked()
            }
            HubButton {
                objectName: "programs-move"
                width: 172
                label: qsTr("MOVE TO FOLDER")
                folderIcon: true
                fill: root.blueAccent
                active: root.canEdit && root.pickedProgram !== null
                onTriggered: root.movePickerOpen = true
            }
            HubButton {
                objectName: "programs-duplicate"
                width: 140
                label: qsTr("DUPLICATE")
                iconSource: "../../icons/fa-file-black.svg"
                fill: root.amberAccent
                labelColor: root.ink
                active: root.canEdit && root.pickedProgram !== null
                onTriggered: root.duplicatePicked()
            }
            HubButton {
                objectName: "programs-delete"
                width: 116
                label: qsTr("DELETE")
                iconSource: "../../icons/fa-trash.svg"
                disabledIconSource: "../../icons/fa-trash-black.svg"
                fill: root.redAccent
                active: root.canEdit && root.pickedProgram !== null
                onTriggered: root.deletePicked()
            }
        }
    }

    // ---- Move-to-folder picker ---------------------------------------------
    Rectangle {
        id: movePicker
        objectName: "programs-move-picker"
        anchors.fill: parent
        visible: root.movePickerOpen && root.pickedProgram !== null
        color: "#990F172A"
        z: 50
        MouseArea { anchors.fill: parent; onClicked: root.movePickerOpen = false }

        Rectangle {
            anchors.centerIn: parent
            width: 400
            height: Math.min(470, 68 + moveList.contentHeight + 66)
            radius: 8
            color: root.cardBg
            border.color: root.cardBorder
            border.width: 1
            MouseArea { anchors.fill: parent }

            Text { x: 18; y: 14; text: qsTr("MOVE TO FOLDER"); font.pixelSize: 14; font.bold: true; color: root.ink }
            Text {
                x: 18
                y: 36
                width: parent.width - 36
                text: root.pickedName
                font.pixelSize: 12
                color: root.textSecondary
                elide: Text.ElideRight
            }
            Rectangle { x: 12; y: 60; width: parent.width - 24; height: 1; color: "#E2E8F0" }

            ListView {
                id: moveList
                x: 12
                y: 68
                width: parent.width - 24
                height: parent.height - 68 - 58
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: [""].concat(root.folderList)
                ScrollBar.vertical: ScrollBar { policy: moveList.contentHeight > moveList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff; width: 6 }
                delegate: Rectangle {
                    readonly property bool current: root.pickedProgram !== null
                        && String(root.pickedProgram.folder || "").trim().toLowerCase() === String(modelData).toLowerCase()
                    width: moveList.width - 8
                    height: 40
                    radius: 4
                    color: current ? "#EFF6FB" : (moveMouse.pressed ? "#F1F5F9" : root.cardBgAlt)
                    border.width: 1
                    border.color: current ? root.blueAccent : "#E2E8F0"
                    FolderGlyph {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        tint: String(modelData).length > 0 ? root.amberAccent : "#94A3B8"
                    }
                    Text {
                        x: 38
                        width: parent.width - 38 - 80
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(modelData).length > 0 ? modelData : qsTr("UNFILED")
                        font.pixelSize: 13
                        font.bold: true
                        color: root.ink
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: parent.current
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("CURRENT")
                        font.pixelSize: 11
                        font.bold: true
                        color: root.blueAccent
                    }
                    MouseArea {
                        id: moveMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.movePickedTo(String(modelData))
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - 48
                spacing: 8
                HubButton {
                    width: 184
                    label: qsTr("NEW FOLDER\u2026")
                    iconSource: "../../icons/fa-plus.svg"
                    fill: root.blueAccent
                    onTriggered: { root.movePickerOpen = false; root.newFolder(true) }
                }
                HubButton {
                    width: 184
                    label: qsTr("CANCEL")
                    fill: root.charcoal
                    onTriggered: root.movePickerOpen = false
                }
            }
        }
    }

    // ---- Toast --------------------------------------------------------------
    Rectangle {
        id: toast
        objectName: "programs-toast"
        anchors.horizontalCenter: parent.horizontalCenter
        y: 528
        z: 60
        width: Math.min(parent.width - 60, toastLabel.implicitWidth + 36)
        height: 32
        radius: 16
        color: "#0F172A"
        opacity: root.toastText.length > 0 ? 0.95 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Text {
            id: toastLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 24)
            text: root.toastText
            font.pixelSize: 12
            font.bold: true
            color: "#FFFFFF"
            elide: Text.ElideRight
        }
    }
}
