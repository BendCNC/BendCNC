import QtQuick
import "modal-previews/v7" as V7

// Production SETTINGS tab: renders the v8 designer settings panel bound to the live AppState.
Item {
    id: root
    objectName: "settings-view"
    property var appState: null

    V7.V8SettingsLeftView {
        anchors.fill: parent
        appState: root.appState
    }
}
