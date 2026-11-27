import QtQuick
import QtQuick.Controls

// Machine registration / license activation (access terms are set by the
// license server: open access, trial or license key). Only visible in licensed builds
// (BENDCNC_LICENSING=ON); unenforced builds never show it.
Item {
    id: root
    objectName: "license-panel"
    property var appState: null
    readonly property var lic: appState ? appState.licenseManager : null
    readonly property bool enforced: appState ? appState.licenseEnforced : false
    readonly property bool panelOpen: enforced && appState.licensePanelVisible
    anchors.fill: parent
    z: 9050
    visible: enforced

    function statusText() {
        if (!lic)
            return ""
        switch (String(lic.status)) {
        case "trial": return qsTr("TRIAL · %1 DAYS LEFT").arg(lic.daysLeft)
        case "licensed": return lic.plan === "open" ? qsTr("FULL ACCESS")
                                                     : qsTr("LICENSED · %1").arg(String(lic.plan).toUpperCase())
        case "expired": return lic.plan === "trial" ? qsTr("TRIAL ENDED") : qsTr("LICENSE EXPIRED")
        case "clock": return qsTr("SYSTEM CLOCK IS WRONG")
        case "invalid": return qsTr("LICENSE INVALID")
        default: return qsTr("NOT ACTIVATED")
        }
    }

    // Open automatically only when RUN is blocked or <= 5 days remain, and
    // only after startup settles (NTP sync + first check-in), so a power
    // cycle with internet never flashes the panel. Auto-opened panels close
    // again once the license is fine.
    readonly property bool needsAttention: enforced && !!lic
        && (!appState.licenseRunAllowed || Number(lic.daysLeft) <= 5)
    property bool startupSettled: false
    property bool autoOpened: false
    function syncAutoOpen() {
        if (!enforced || !startupSettled)
            return
        if (needsAttention && !appState.licensePanelVisible) {
            autoOpened = true
            appState.openLicensePanel()
        } else if (!needsAttention && autoOpened && appState.licensePanelVisible) {
            autoOpened = false
            appState.closeLicensePanel()
        }
    }
    onNeedsAttentionChanged: syncAutoOpen()
    // A never-registered machine has nothing to wait for: show registration at once.
    Component.onCompleted: {
        if (enforced && lic && String(lic.status) === "unactivated") {
            startupSettled = true
            syncAutoOpen()
        }
    }
    Timer {
        interval: 20000
        running: root.enforced
        onTriggered: { root.startupSettled = true; root.syncAutoOpen() }
    }

    QtObject { id: emailTarget; property string text: "" }
    QtObject { id: keyTarget; property string text: "" }

    function editField(target, title) {
        appState.openOnScreenKeyboard(target, false, title, function(value) {
            target.text = String(value).trim()
        }, null, true)
    }

    // Status chip (top-right) — entry point to the panel.
    Rectangle {
        objectName: "license-status-chip"
        // Only nag when it matters: trial with <=5 days left, or RUN blocked.
        visible: !root.panelOpen && !!root.lic
            && (!(root.appState && root.appState.licenseRunAllowed)
                || Number(root.lic.daysLeft) <= 5)
        // Top-center: clear of the right-hand header buttons.
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.margins: 6
        radius: 4
        height: 26
        width: chipText.implicitWidth + 20
        color: root.appState && root.appState.licenseRunAllowed ? "#2a3a2a" : "#7a1f1f"
        Text {
            id: chipText
            anchors.centerIn: parent
            text: root.statusText()
            color: "white"
            font.pixelSize: 13
            font.bold: true
        }
        MouseArea { anchors.fill: parent; onClicked: root.appState.openLicensePanel() }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.panelOpen
        color: "#b0000000"
        MouseArea { anchors.fill: parent } // modal

        Rectangle {
            anchors.centerIn: parent
            width: 620
            height: column.implicitHeight + 48
            radius: 8
            color: "#1e2329"
            border.color: "#3c4652"

            Column {
                id: column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                spacing: 14

                Text { text: qsTr("BENDCNC LICENSE"); color: "white"; font.pixelSize: 24; font.bold: true }
                Text {
                    objectName: "license-status-text"
                    text: root.statusText()
                    color: root.appState && root.appState.licenseRunAllowed ? "#7fd18b" : "#ff7b7b"
                    font.pixelSize: 20; font.bold: true
                }
                Text {
                    width: parent.width; wrapMode: Text.Wrap; color: "#b8c2cc"; font.pixelSize: 14
                    text: root.appState && !root.appState.licenseRunAllowed
                          ? qsTr("Physical RUN is disabled until this machine is registered or a license key is activated. Programs, CAD and simulation remain available.")
                          : qsTr("The license is checked when a run starts; a cycle in progress is never interrupted.")
                }

                Text { text: qsTr("REGISTER MACHINE"); color: "white"; font.pixelSize: 16; font.bold: true }
                Row {
                    spacing: 10
                    Button {
                        width: 400
                        text: emailTarget.text.length ? emailTarget.text : qsTr("Tap to enter email")
                        onClicked: root.editField(emailTarget, qsTr("ENTER EMAIL"))
                    }
                    Button {
                        objectName: "license-start-trial"
                        width: 150
                        text: qsTr("REGISTER")
                        enabled: root.lic && !root.lic.busy && emailTarget.text.indexOf("@") > 0
                        onClicked: root.lic.startTrial(emailTarget.text)
                    }
                }

                Text { text: qsTr("ACTIVATE LICENSE KEY"); color: "white"; font.pixelSize: 16; font.bold: true }
                Row {
                    spacing: 10
                    Button {
                        width: 400
                        text: keyTarget.text.length ? keyTarget.text : qsTr("Tap to enter license key")
                        onClicked: root.editField(keyTarget, qsTr("ENTER LICENSE KEY"))
                    }
                    Button {
                        objectName: "license-activate"
                        width: 150
                        text: qsTr("ACTIVATE")
                        enabled: root.lic && !root.lic.busy && keyTarget.text.length >= 8
                        onClicked: root.lic.redeemKey(keyTarget.text)
                    }
                }

                Text {
                    width: parent.width; wrapMode: Text.Wrap; color: "#ffd27f"; font.pixelSize: 14
                    visible: text.length > 0
                    text: root.lic ? (root.lic.busy ? qsTr("Contacting license server…") : String(root.lic.message)) : ""
                }
                Text {
                    color: "#7d8893"; font.pixelSize: 12
                    text: qsTr("Device ID: %1").arg(root.lic ? root.lic.deviceId : "")
                }
                Row {
                    spacing: 10
                    Button { text: qsTr("REFRESH"); enabled: root.lic && !root.lic.busy; onClicked: root.lic.checkIn() }
                    Button { objectName: "license-close"; text: qsTr("CLOSE"); onClicked: root.appState.closeLicensePanel() }
                }
            }
        }
    }
}
