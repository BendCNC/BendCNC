import QtQuick
import "modal-previews/v7-gemini-precision" as V6

// Production BACK GAUGE tab: renders the promoted V5 precision panel and keeps
// (now maintained in v6-gemini-precision) and keeps the production safety lifecycle (jog release on focus loss/destruction and
// offline continuous-jog stepping).
FocusScope {
    id: root
    objectName: "backgauge-control-view"
    property var appState: null
    property bool openProfilePopupOnCompleted: false
    focus: true

    function releaseActiveJog() {
        if (appState && appState.backGaugeActiveDirection.length === 2) {
            const direction = appState.backGaugeActiveDirection
            appState.releaseBackGaugeJog(direction.charAt(0), direction.charAt(1) === "+" ? 1 : -1)
        }
    }

    onActiveFocusChanged: if (!activeFocus) releaseActiveJog()
    Component.onDestruction: releaseActiveJog()

    Timer {
        interval: 120
        repeat: true
        running: root.appState && root.appState.offlineSimulationEnabled
                 && root.appState.backGaugeContinuousJog
                 && root.appState.backGaugeActiveDirection.length > 0
        onTriggered: root.appState.continueBackGaugeJog()
    }

    DataStore { id: bgDataStore }

    V6.V6BackGaugeLeftView {
        id: panel
        dataStore: bgDataStore
        objectName: "backgauge-left-panel-v5"
        anchors.fill: parent
        appState: root.appState
        designerInteractive: false
        focus: true
    }
}
