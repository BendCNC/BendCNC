import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ApplicationWindow {
    id: win
    visible: true
    width: 1024; height: 600
    visibility: Qt.platform.os === "linux" ? Window.FullScreen : Window.Windowed
    title: "BendCNC Setup"
    color: bg

    readonly property color bg: "#0f1419"
    readonly property color card: "#1a2129"
    readonly property color line: "#2a333d"
    readonly property color text1: "#e8edf2"
    readonly property color text2: "#8a96a3"
    readonly property color accent: "#ff8a1f"
    readonly property color ok: "#3ecf8e"
    readonly property color err: "#ff5d5d"
    font.pixelSize: 18

    property bool eulaRead: false
    property int step: 0   // 0 welcome, 1 network, 2 eula, 3 email, 4 code, 5 install, 6 done
    readonly property var stepNames: ["Welcome", "Network", "License", "Email", "Verify", "Install", "Ready"]
    readonly property bool errorShown: setup.message.length > 0 && !setup.busy
    readonly property Item textTarget: activeFocusItem && activeFocusItem.hasOwnProperty("echoMode") ? activeFocusItem : null

    function shotFocus() {
        if (step === 3) { email.text = "you@company.com"; email.forceActiveFocus() }
        else if (step === 4) codeField.forceActiveFocus()
    }

    Connections {
        target: setup
        function onWifiDone(ok) { if (ok) setup.checkOnline() }
        function onOnlineDone(ok) { if (ok && win.step === 1) win.step = 2 }
        function onCodeSent() { win.step = 4; codeField.text = ""; codeField.forceActiveFocus() }
        function onVerified() { win.step = 5; setup.install() }
        function onInstallDone(ok) { if (ok) win.step = 6 }
    }

    component PrimaryButton: Button {
        id: b
        property bool secondary: false
        implicitHeight: 56
        implicitWidth: Math.max(170, label.implicitWidth + 48)
        font.pixelSize: 18; font.bold: true
        contentItem: Text {
            id: label
            text: b.text; font: b.font
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            color: b.secondary ? (b.enabled ? win.text1 : win.text2) : (b.enabled ? "#1a1004" : "#7a6650")
        }
        background: Rectangle {
            radius: 10
            color: b.secondary ? (b.down ? win.line : "transparent")
                               : (!b.enabled ? "#4a3520" : b.down ? "#e07410" : win.accent)
            border.color: b.secondary ? win.line : "transparent"; border.width: 2
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }

    component Field: TextField {
        id: f
        implicitHeight: 60
        font.pixelSize: 20; color: win.text1
        placeholderTextColor: "#56616d"; leftPadding: 18; rightPadding: 18
        selectionColor: win.accent
        background: Rectangle {
            radius: 10; color: "#11171d"
            border.width: 2; border.color: f.activeFocus ? win.accent : win.line
            Behavior on border.color { ColorAnimation { duration: 120 } }
        }
    }

    component Title: Text { color: win.text1; font.pixelSize: 30; font.bold: true; Layout.fillWidth: true; wrapMode: Text.Wrap }
    component Body: Text { color: win.text2; font.pixelSize: 18; Layout.fillWidth: true; wrapMode: Text.Wrap; lineHeight: 1.2 }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar with step progress
        Rectangle {
            Layout.fillHeight: true; Layout.preferredWidth: 260
            color: "#0b0f13"
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 28; spacing: 6
                Row {
                    spacing: 12; Layout.bottomMargin: 30
                    Rectangle {
                        width: 40; height: 40; radius: 9; color: win.accent
                        Text { anchors.centerIn: parent; text: "B"; font.pixelSize: 24; font.bold: true; color: "#1a1004" }
                    }
                    Column {
                        Text { text: "BendCNC"; color: win.text1; font.pixelSize: 20; font.bold: true }
                        Text { text: "Setup"; color: win.text2; font.pixelSize: 13 }
                    }
                }
                Repeater {
                    model: win.stepNames
                    delegate: RowLayout {
                        id: stepRow
                        required property int index
                        required property string modelData
                        readonly property bool done: index < win.step
                        readonly property bool current: index === win.step
                        spacing: 14; Layout.preferredHeight: 44
                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: stepRow.done ? win.ok : stepRow.current ? win.accent : "transparent"
                            border.width: 2
                            border.color: stepRow.done ? win.ok : stepRow.current ? win.accent : win.line
                            Text {
                                anchors.centerIn: parent
                                text: stepRow.done ? "\u2713" : stepRow.index + 1
                                font.pixelSize: 14; font.bold: true
                                color: stepRow.done || stepRow.current ? "#0b0f13" : win.text2
                            }
                        }
                        Text {
                            text: stepRow.modelData; font.pixelSize: 17; font.bold: stepRow.current
                            color: stepRow.current ? win.text1 : stepRow.done ? win.text2 : "#56616d"
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                Text { text: "Help: support@bendcnc.com"; color: "#56616d"; font.pixelSize: 13 }
            }
        }

        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            StackLayout {
                id: pages
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: osk.top }
                anchors.leftMargin: 48; anchors.rightMargin: 48
                anchors.topMargin: osk.visible ? 20 : 48; anchors.bottomMargin: osk.visible ? 64 : 24
                currentIndex: win.step

                // 0 Welcome
                ColumnLayout {
                    spacing: 16
                    Item { Layout.fillHeight: true }
                    Title { text: "Welcome to BendCNC"; font.pixelSize: 40 }
                    Body { text: "Let's get this machine ready. Setup takes a few minutes:" }
                    Repeater {
                        model: ["Connect to the internet (Wi-Fi or Ethernet)",
                                "Read and accept the license agreement",
                                "Confirm your email with a 6-digit code",
                                "Download and install BendCNC"]
                        delegate: RowLayout {
                            required property int index
                            required property string modelData
                            spacing: 14; Layout.fillWidth: true
                            Rectangle {
                                width: 30; height: 30; radius: 15; color: "transparent"; border.color: win.accent; border.width: 2
                                Text { anchors.centerIn: parent; text: index + 1; color: win.accent; font.pixelSize: 15; font.bold: true }
                            }
                            Text { text: modelData; color: win.text1; font.pixelSize: 19; Layout.fillWidth: true; wrapMode: Text.Wrap }
                        }
                    }
                    Body { text: "Keep the machine powered on until setup is complete."; color: "#56616d"; Layout.topMargin: 8 }
                    Item { Layout.fillHeight: true }
                }

                // 1 Network
                ColumnLayout {
                    spacing: 14
                    RowLayout {
                        Title { text: "Connect to the internet" }
                        PrimaryButton {
                            secondary: true; text: setup.busy ? "Scanning..." : "Rescan"
                            enabled: !setup.busy; onClicked: setup.scanWifi()
                        }
                    }
                    Body { text: "Choose a Wi-Fi network, or plug in an Ethernet cable and tap Use Ethernet." }
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        radius: 12; color: win.card; border.color: win.line
                        ListView {
                            id: nets
                            anchors.fill: parent; anchors.margins: 6; clip: true; currentIndex: -1
                            model: setup.networks
                            delegate: Rectangle {
                                id: netRow
                                required property int index
                                required property string modelData
                                width: ListView.view.width; height: 56; radius: 8
                                color: ListView.isCurrentItem ? "#2b2015" : ma.pressed ? win.line : "transparent"
                                border.color: ListView.isCurrentItem ? win.accent : "transparent"
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter; x: 18
                                    text: netRow.modelData; color: win.text1; font.pixelSize: 19
                                }
                                MouseArea {
                                    id: ma; anchors.fill: parent
                                    onClicked: { nets.currentIndex = netRow.index; wifiPass.forceActiveFocus() }
                                }
                            }
                            Text {
                                anchors.centerIn: parent; visible: nets.count === 0; color: win.text2
                                text: setup.busy ? "Searching..." : "No networks found"
                            }
                        }
                    }
                    Field {
                        id: wifiPass; Layout.fillWidth: true; echoMode: TextInput.Password
                        enabled: nets.currentIndex >= 0
                        placeholderText: nets.currentIndex >= 0 ? "Password for " + setup.networks[nets.currentIndex]
                                                                : "Select a network first"
                    }
                }

                // 2 License
                ColumnLayout {
                    spacing: 14
                    RowLayout {
                        Title { text: "License Agreement" }
                        Rectangle {
                            radius: 12; color: "#163628"
                            implicitWidth: gplTag.implicitWidth + 24; implicitHeight: gplTag.implicitHeight + 12
                            Text { id: gplTag; anchors.centerIn: parent; text: "GPL-3.0 open source"; color: win.ok; font.pixelSize: 14; font.bold: true }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        radius: 12; color: win.card; border.color: win.line
                        Flickable {
                            id: eulaScroll
                            anchors.fill: parent; anchors.margins: 18; anchors.rightMargin: 26; clip: true
                            contentHeight: eulaBody.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            readonly property bool atEnd: win.step === 2 && height > 100 && contentHeight > 100
                                                          && contentY + height >= contentHeight - 8
                            onAtEndChanged: if (atEnd) win.eulaRead = true
                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AlwaysOn; parent: eulaScroll.parent
                                anchors { top: eulaScroll.top; bottom: eulaScroll.bottom; right: parent.right; rightMargin: 6 }
                                contentItem: Rectangle { implicitWidth: 8; radius: 4; color: win.accent }
                            }
                            Text {
                                id: eulaBody
                                width: eulaScroll.width; text: setup.eulaText
                                color: win.text2; font.pixelSize: 16; wrapMode: Text.Wrap; lineHeight: 1.25
                            }
                        }
                    }
                    Body {
                        visible: !win.eulaRead; font.pixelSize: 15; color: win.accent
                        text: "Scroll to the end of the agreement to continue."
                    }
                    CheckBox {
                        id: accept
                        enabled: win.eulaRead
                        text: "I have read and accept the License Agreement"
                        indicator: Rectangle {
                            x: accept.leftPadding; anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 30; radius: 6
                            color: accept.checked ? win.accent : "transparent"; border.width: 2
                            border.color: accept.checked ? win.accent : win.line
                            Text {
                                anchors.centerIn: parent; text: "\u2713"; visible: accept.checked
                                color: "#1a1004"; font.bold: true; font.pixelSize: 18
                            }
                        }
                        contentItem: Text {
                            text: accept.text; color: accept.enabled ? win.text1 : "#56616d"; font.pixelSize: 18
                            leftPadding: accept.indicator.width + 14; verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                // 3 Account
                ColumnLayout {
                    spacing: 16
                    Title { text: "Your email" }
                    Body { text: "We'll send a 6-digit code to confirm it. This machine will be registered to this email for updates and support." }
                    Field {
                        id: email; Layout.fillWidth: true; Layout.topMargin: 10
                        placeholderText: "you@company.com"
                        inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
                    }
                    Item { Layout.fillHeight: true }
                }

                // 4 Verify
                ColumnLayout {
                    spacing: 16
                    Title { text: "Check your email"; horizontalAlignment: Text.AlignHCenter }
                    Body {
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.StyledText
                        text: "Enter the code we sent to <font color='#e8edf2'>" + email.text + "</font>. It expires in 10 minutes."
                    }
                    Field {
                        id: codeField
                        Layout.preferredWidth: 320; Layout.topMargin: 10; implicitHeight: 76
                        Layout.alignment: Qt.AlignHCenter
                        maximumLength: 6; inputMethodHints: Qt.ImhDigitsOnly
                        font.pixelSize: 38; font.letterSpacing: 14
                        horizontalAlignment: Text.AlignHCenter; placeholderText: "000000"
                        validator: RegularExpressionValidator { regularExpression: /\d{0,6}/ }
                        onTextChanged: if (/^\d{6}$/.test(text) && !setup.busy) { focus = false; setup.verifyCode(text) }
                    }
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 28
                        Text {
                            text: "Resend code"; color: win.accent; font.pixelSize: 16; font.underline: true
                            MouseArea { anchors.fill: parent; anchors.margins: -10; enabled: !setup.busy; onClicked: setup.registerEmail(email.text) }
                        }
                        Text {
                            text: "Use a different email"; color: win.text2; font.pixelSize: 16; font.underline: true
                            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: win.step = 3 }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // 5 Install
                ColumnLayout {
                    spacing: 22
                    Item { Layout.fillHeight: true }
                    Title { text: "Installing BendCNC"; horizontalAlignment: Text.AlignHCenter }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 10; radius: 5; color: win.line; clip: true
                        Rectangle {
                            id: sweep
                            height: parent.height; radius: 5; width: parent.width * 0.3; color: win.accent
                            visible: setup.busy
                            SequentialAnimation on x {
                                running: setup.busy; loops: Animation.Infinite
                                NumberAnimation { from: -sweep.width; to: pages.width; duration: 1400; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                    Body { text: setup.busy ? (setup.message || "Working...") : ""; horizontalAlignment: Text.AlignHCenter }
                    Body { text: "Do not turn off the machine."; color: "#56616d"; horizontalAlignment: Text.AlignHCenter; visible: setup.busy }
                    Item { Layout.fillHeight: true }
                }

                // 6 Ready
                ColumnLayout {
                    spacing: 18
                    Item { Layout.fillHeight: true }
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter; width: 96; height: 96; radius: 48; color: "#163628"
                        Text { anchors.centerIn: parent; text: "\u2713"; color: win.ok; font.pixelSize: 54; font.bold: true }
                    }
                    Title { text: "You're all set"; horizontalAlignment: Text.AlignHCenter }
                    Body {
                        horizontalAlignment: Text.AlignHCenter; textFormat: Text.StyledText
                        text: "BendCNC is installed and registered to <font color='#e8edf2'>" + email.text + "</font>."
                    }
                    Body {
                        horizontalAlignment: Text.AlignHCenter; color: "#56616d"; font.pixelSize: 16
                        text: "Updates are offered automatically from the app. Need help? support@bendcnc.com"
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // Error banner
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: osk.top; leftMargin: 48; rightMargin: 48; bottomMargin: 8 }
                height: 48; radius: 8; color: "#3a1a1c"; border.color: win.err
                visible: win.errorShown && win.step !== 6
                Text {
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                    text: setup.message; color: "#ffb4b4"; font.pixelSize: 16
                }
            }

            Keyboard {
                id: osk
                anchors { left: parent.left; right: parent.right; bottom: actionBar.top }
                target: win.textTarget
                visible: target !== null && [1, 3, 4].indexOf(win.step) >= 0
                height: visible ? (numeric ? 230 : 260) : 0
                onDone: if (target) target.focus = false
            }

            // Action bar
            Item {
                id: actionBar
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 96
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: win.line }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 48; anchors.rightMargin: 48; spacing: 14
                    PrimaryButton {
                        secondary: true; text: "Back"
                        visible: [2, 3, 4].indexOf(win.step) >= 0; enabled: !setup.busy
                        onClicked: win.step = win.step - 1
                    }
                    PrimaryButton {
                        secondary: true; text: "Use Ethernet"
                        visible: win.step === 1; enabled: !setup.busy
                        onClicked: setup.checkOnline()
                    }
                    Item { Layout.fillWidth: true }
                    BusyIndicator { running: setup.busy && win.step !== 5; visible: running; implicitWidth: 44; implicitHeight: 44 }
                    PrimaryButton {
                        visible: win.step !== 5 || (!setup.busy && win.errorShown)
                        text: ["Get started", "Connect", "Accept", "Send code", "Verify", "Retry", "Start BendCNC"][win.step]
                        enabled: !setup.busy && (win.step === 1 ? nets.currentIndex >= 0
                                               : win.step === 2 ? accept.checked
                                               : win.step === 3 ? /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.text)
                                               : win.step === 4 ? /^\d{6}$/.test(codeField.text) : true)
                        onClicked: {
                            switch (win.step) {
                            case 0: win.step = 1; setup.scanWifi(); break
                            case 3: email.focus = false; setup.registerEmail(email.text); break
                            case 1: setup.connectWifi(setup.networks[nets.currentIndex], wifiPass.text); break
                            case 2: win.step = 3; email.forceActiveFocus(); break
                            case 4: setup.verifyCode(codeField.text); break
                            case 5: setup.install(); break
                            case 6: setup.finish(); break
                            }
                        }
                    }
                }
            }
        }
    }
}
