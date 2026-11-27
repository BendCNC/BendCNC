import QtQuick
import QtQuick.Controls.Basic

ApplicationWindow {
    id: window
    property string previewVersion: bendcncModalPreviewVersion
    property int reloadRevision: 0
    property string reloadStatus: ""
    property var availablePreviewVersions: []
    property bool reloadPending: false
    property string pendingPreviewVersion: previewVersion
    // Shows the production placement/live canvas inside RUN previews. Scenes
    // opt in by declaring designerLiveCanvas; older candidates stay blank.
    property bool liveCanvasEnabled: Qt.application.arguments.indexOf("--modal-preview-canvas") >= 0
    readonly property bool sceneSupportsLiveCanvas: versionLoader.item !== null
        && versionLoader.item.hasOwnProperty("designerLiveCanvas")

    Component.onCompleted: refreshAvailableVersions()

    readonly property string capturePath: {
        for (var arg of Qt.application.arguments) {
            if (arg.indexOf("--modal-preview-capture=") === 0)
                return arg.substring("--modal-preview-capture=".length)
        }
        return ""
    }

    Timer {
        interval: 2400
        running: window.capturePath.length > 0
        onTriggered: (versionLoader.item || window.contentItem || versionLoader).grabToImage(function(result) {
            console.log("MODAL-DESIGN-CAPTURE", result.saveToFile(window.capturePath), window.capturePath)
            Qt.quit()
        })
    }

    function refreshAvailableVersions() {
        availablePreviewVersions = modalPreviewController.availableVersions()
    }

    function reloadDesign(targetVersion) {
        pendingPreviewVersion = targetVersion || previewVersion
        if (reloadPending)
            return
        reloadPending = true
        reloadStatus = qsTr("RELOADING…")
        refreshAvailableVersions()
        versionLoader.active = false
    }

    function finishReload() {
        if (!reloadPending || versionLoader.status !== Loader.Null
                || versionLoader.item !== null)
            return
        Qt.callLater(function() {
            previewVersion = pendingPreviewVersion
            modalPreviewController.trimUnusedComponentCache()
            reloadRevision++
            versionLoader.active = true
        })
    }
    width: 1600
    height: 840
    minimumWidth: 1600
    minimumHeight: 840
    maximumWidth: 1920
    maximumHeight: 1080
    visible: true
    title: qsTr("BendCNC Modal Design Lab · %1").arg(window.previewVersion)
    color: "#D5D7DA"

    Loader {
        id: versionLoader
        anchors.fill: parent
        source: "modal-previews/" + window.previewVersion
            + "/PreviewScene.qml?revision=" + window.reloadRevision
        onStatusChanged: {
            if (status === Loader.Null) {
                window.finishReload()
            } else if (status === Loader.Ready) {
                window.reloadPending = false
                window.reloadStatus = qsTr("RELOADED · %1").arg(
                    new Date().toLocaleTimeString(Qt.locale(), "HH:mm:ss"))
                reloadStatusTimer.restart()
            } else if (status === Loader.Error) {
                window.reloadPending = false
                window.reloadStatus = qsTr("RELOAD FAILED")
                console.error("MODAL-PREVIEW-LOAD-ERROR", source)
            }
        }
    }

    Binding {
        target: versionLoader.item
        property: "designerLiveCanvas"
        value: window.liveCanvasEnabled
        when: window.sceneSupportsLiveCanvas
    }

    Timer {
        id: reloadStatusTimer
        interval: 2400
        onTriggered: window.reloadStatus = ""
    }

    Shortcut {
        sequences: [StandardKey.Refresh]
        onActivated: window.reloadDesign(window.previewVersion)
    }

    Rectangle {
        objectName: "modal-design-live-canvas-toggle"
        z: 30000
        anchors.top: parent.top
        anchors.right: reloadButton.left
        anchors.topMargin: 12
        anchors.rightMargin: 8
        width: 190
        height: 48
        radius: 8
        color: window.liveCanvasEnabled && window.sceneSupportsLiveCanvas ? "#2F6F12" : "#232323"
        border.color: window.liveCanvasEnabled ? "#59A60C" : "#64748B"
        border.width: 1
        opacity: window.sceneSupportsLiveCanvas ? 1.0 : 0.4
        Column {
            anchors.centerIn: parent
            spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("LIVE CANVAS")
                color: "white"
                font.pixelSize: 13
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: !window.sceneSupportsLiveCanvas ? qsTr("NOT IN THIS CANDIDATE")
                    : window.liveCanvasEnabled ? qsTr("ON · READ-ONLY DATA") : qsTr("OFF · BLANK")
                color: "#CBD5E1"
                font.pixelSize: 9
                font.bold: true
            }
        }
        TapHandler {
            enabled: window.sceneSupportsLiveCanvas
            onTapped: window.liveCanvasEnabled = !window.liveCanvasEnabled
        }
    }

    Rectangle {
        id: reloadButton
        z: 30000
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 12
        anchors.rightMargin: 12
        width: 220
        height: 48
        radius: 8
        color: "#232323"
        border.color: "#FFFFFF"
        border.width: 1
        Row {
            anchors.centerIn: parent
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("↻")
                color: "white"
                font.pixelSize: 25
                font.bold: true
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("RELOAD DESIGN  ·  F5")
                color: "white"
                font.pixelSize: 14
                font.bold: true
            }
        }
        TapHandler {
            enabled: !window.reloadPending
            onTapped: window.reloadDesign(window.previewVersion)
        }
    }

    property bool versionMenuOpen: false

    readonly property int currentVersionIndex: {
        for (var i = 0; i < availablePreviewVersions.length; ++i) {
            if (availablePreviewVersions[i] === window.previewVersion) return i
        }
        return -1
    }
    readonly property string previousVersionName: currentVersionIndex > 0 ? availablePreviewVersions[currentVersionIndex - 1] : ""
    readonly property string nextVersionName: currentVersionIndex >= 0 && currentVersionIndex < availablePreviewVersions.length - 1 ? availablePreviewVersions[currentVersionIndex + 1] : ""
    readonly property string latestVersionName: availablePreviewVersions.length > 0 ? availablePreviewVersions[availablePreviewVersions.length - 1] : ""

    // Click-away backdrop to dismiss floating menu
    MouseArea {
        z: 35000
        anchors.fill: parent
        visible: window.versionMenuOpen
        onClicked: window.versionMenuOpen = false
    }

    // Modern Compact Version Bar
    Rectangle {
        id: versionBar
        z: 36000
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 12
        anchors.leftMargin: 210
        height: 48
        radius: 8
        color: "#232323"
        border.color: "#475569"
        border.width: 1
        width: versionBarRow.implicitWidth + 20

        Row {
            id: versionBarRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("CANDIDATE:")
                color: "#94A3B8"
                font.pixelSize: 10
                font.bold: true
            }

            // Step Backward
            Rectangle {
                width: 32
                height: 32
                radius: 6
                anchors.verticalCenter: parent.verticalCenter
                color: prevTap.pressed ? "#444444" : (prevHover.hovered && window.previousVersionName.length > 0 ? "#333C48" : "#2B2C2B")
                border.color: window.previousVersionName.length > 0 ? "#64748B" : "#383E48"
                opacity: window.previousVersionName.length > 0 && !window.reloadPending ? 1.0 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: "◀"
                    color: "white"
                    font.pixelSize: 10
                }

                HoverHandler { id: prevHover }
                TapHandler {
                    id: prevTap
                    enabled: window.previousVersionName.length > 0 && !window.reloadPending
                    onTapped: window.reloadDesign(window.previousVersionName)
                }
            }

            // Version Dropdown Trigger
            Rectangle {
                id: dropdownTrigger
                height: 32
                width: dropdownRow.implicitWidth + 18
                radius: 6
                anchors.verticalCenter: parent.verticalCenter
                color: window.versionMenuOpen ? "#2D83B2" : (triggerHover.hovered ? "#333C48" : "#1F2329")
                border.color: window.versionMenuOpen ? "white" : "#64748B"
                border.width: 1

                Row {
                    id: dropdownRow
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: window.previewVersion
                        color: "white"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: window.previewVersion === window.latestVersionName || window.previewVersion === "current"
                        height: 18
                        width: badgeText.implicitWidth + 8
                        radius: 4
                        color: window.previewVersion === window.latestVersionName ? "#59A60C" : "#D97706"
                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: window.previewVersion === window.latestVersionName ? qsTr("LATEST") : qsTr("PROD")
                            color: "white"
                            font.pixelSize: 8
                            font.bold: true
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: window.versionMenuOpen ? "▲" : "▼"
                        color: "#94A3B8"
                        font.pixelSize: 9
                    }
                }

                HoverHandler { id: triggerHover }
                TapHandler {
                    enabled: !window.reloadPending
                    onTapped: window.versionMenuOpen = !window.versionMenuOpen
                }
            }

            // Step Forward
            Rectangle {
                width: 32
                height: 32
                radius: 6
                anchors.verticalCenter: parent.verticalCenter
                color: nextTap.pressed ? "#444444" : (nextHover.hovered && window.nextVersionName.length > 0 ? "#333C48" : "#2B2C2B")
                border.color: window.nextVersionName.length > 0 ? "#64748B" : "#383E48"
                opacity: window.nextVersionName.length > 0 && !window.reloadPending ? 1.0 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: "▶"
                    color: "white"
                    font.pixelSize: 10
                }

                HoverHandler { id: nextHover }
                TapHandler {
                    id: nextTap
                    enabled: window.nextVersionName.length > 0 && !window.reloadPending
                    onTapped: window.reloadDesign(window.nextVersionName)
                }
            }

            // Separator
            Rectangle {
                width: 1
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                color: "#475569"
            }

            // Quick Shortcut: Production
            Rectangle {
                height: 28
                width: prodText.implicitWidth + 14
                radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: window.previewVersion === "current" ? "#2D83B2" : (prodHover.hovered ? "#383A3D" : "#1F2329")
                border.color: window.previewVersion === "current" ? "white" : "#475569"
                Text {
                    id: prodText
                    anchors.centerIn: parent
                    text: qsTr("Production")
                    color: "white"
                    font.pixelSize: 10
                    font.bold: window.previewVersion === "current"
                }
                HoverHandler { id: prodHover }
                TapHandler {
                    enabled: !window.reloadPending && window.previewVersion !== "current"
                    onTapped: window.reloadDesign("current")
                }
            }

            // Quick Shortcut: Latest
            Rectangle {
                visible: window.latestVersionName !== "" && window.latestVersionName !== "current"
                height: 28
                width: latestText.implicitWidth + 14
                radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: window.previewVersion === window.latestVersionName ? "#59A60C" : (latestHover.hovered ? "#383A3D" : "#1F2329")
                border.color: window.previewVersion === window.latestVersionName ? "white" : "#475569"
                Text {
                    id: latestText
                    anchors.centerIn: parent
                    text: qsTr("Latest (%1)").arg(window.latestVersionName.split("-")[0])
                    color: "white"
                    font.pixelSize: 10
                    font.bold: window.previewVersion === window.latestVersionName
                }
                HoverHandler { id: latestHover }
                TapHandler {
                    enabled: !window.reloadPending && window.previewVersion !== window.latestVersionName
                    onTapped: window.reloadDesign(window.latestVersionName)
                }
            }
        }
    }

    // Floating Version Selector Menu Card
    Rectangle {
        id: versionMenuCard
        z: 40000
        visible: window.versionMenuOpen
        anchors.top: versionBar.bottom
        anchors.left: versionBar.left
        anchors.topMargin: 8
        width: 380
        height: Math.min(420, versionListCol.implicitHeight + 60)
        radius: 10
        color: "#181A1F"
        border.color: "#3B82F6"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Row {
                width: parent.width
                spacing: 6
                Text {
                    text: qsTr("MODAL DESIGN CANDIDATES")
                    color: "#94A3B8"
                    font.pixelSize: 10
                    font.bold: true
                }
                Text {
                    text: qsTr("(%1 available)").arg(window.availablePreviewVersions.length)
                    color: "#64748B"
                    font.pixelSize: 10
                }
            }

            Rectangle { width: parent.width; height: 1; color: "#2B2F38" }

            Flickable {
                width: parent.width
                height: versionMenuCard.height - 50
                contentHeight: versionListCol.implicitHeight
                clip: true

                Column {
                    id: versionListCol
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: window.availablePreviewVersions
                        Rectangle {
                            id: verItem
                            required property string modelData
                            required property int index
                            width: versionListCol.width
                            height: 34
                            radius: 6
                            readonly property bool isCurrent: verItem.modelData === window.previewVersion
                            readonly property bool isLatest: verItem.modelData === window.latestVersionName
                            color: isCurrent ? "#233348" : (itemHover.hovered ? "#262930" : "transparent")
                            border.color: isCurrent ? "#2D83B2" : "transparent"
                            border.width: 1

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 10
                                spacing: 8

                                Text {
                                    text: verItem.isCurrent ? "●" : "○"
                                    color: verItem.isCurrent ? "#2D83B2" : "#475569"
                                    font.pixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: verItem.modelData
                                    color: verItem.isCurrent ? "white" : (itemHover.hovered ? "#F1F5F9" : "#CBD5E1")
                                    font.pixelSize: 11
                                    font.bold: verItem.isCurrent
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Item {
                                    width: 1
                                    height: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    visible: verItem.isLatest
                                    height: 16
                                    width: 44
                                    radius: 3
                                    color: "#59A60C"
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        anchors.centerIn: parent
                                        text: "LATEST"
                                        color: "white"
                                        font.pixelSize: 8
                                        font.bold: true
                                    }
                                }

                                Rectangle {
                                    visible: verItem.modelData === "current"
                                    height: 16
                                    width: 38
                                    radius: 3
                                    color: "#D97706"
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        anchors.centerIn: parent
                                        text: "PROD"
                                        color: "white"
                                        font.pixelSize: 8
                                        font.bold: true
                                    }
                                }
                            }

                            HoverHandler { id: itemHover }
                            TapHandler {
                                onTapped: {
                                    window.versionMenuOpen = false
                                    if (verItem.modelData !== window.previewVersion) {
                                        window.reloadDesign(verItem.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        z: 30000
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 66
        anchors.rightMargin: 12
        width: reloadStatusLabel.implicitWidth + 24
        height: 32
        radius: 6
        color: window.reloadStatus === qsTr("RELOAD FAILED") ? "#A82011" : "#2B2C2B"
        visible: window.reloadStatus.length > 0

        Text {
            id: reloadStatusLabel
            anchors.centerIn: parent
            text: window.reloadStatus
            color: "white"
            font.pixelSize: 12
            font.bold: true
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 760
        height: 180
        radius: 12
        color: "#F5F5F5"
        border.color: "#A82011"
        border.width: 3
        visible: versionLoader.status === Loader.Error
        Column {
            anchors.centerIn: parent
            spacing: 14
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("PREVIEW VERSION NOT FOUND")
                color: "#A82011"
                font.pixelSize: 26
                font.bold: true
            }
            Text {
                text: qsTr("Expected folder: qml/modal-previews/%1").arg(window.previewVersion)
                color: "#232323"
                font.pixelSize: 18
            }
        }
    }
}