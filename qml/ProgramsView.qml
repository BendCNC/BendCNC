import QtQuick
import "modal-previews/v7-gemini-precision" as V7

// Production PROGRAMS tab: program library (folders, sort, search, open in RUN).
FocusScope {
    id: root
    objectName: "programs-view"
    property var appState: null
    // main.qml switches to the RUN tab when this fires.
    signal openInRunRequested()
    focus: true

    V7.V7ProgramsLeftView {
        anchors.fill: parent
        appState: root.appState
        focus: true
        onOpenInRunRequested: root.openInRunRequested()
    }
}
