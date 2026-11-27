import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick3D
import QtQuick3D.Helpers
import Unfold3DViewer

ApplicationWindow {
    id: root
    width: 1366
    height: 768
    visible: true
    title: "Unfold 3D viewer · " + scene.status

    property string planPath
    property string capturePath
    property real captureTime: 0
    property real benchSeconds: 0
    property bool playing: benchSeconds > 0
    property real speed: 1

    // Bench counters (frames shown while playing).
    property int benchFrames: 0
    property real benchElapsed: 0
    property real benchWorst: 0
    property real benchUpdateMs: 0

    SceneFrames {
        id: scene
        Component.onCompleted: {
            planPath = root.planPath
            if (root.capturePath.length > 0)
                time = root.captureTime
        }
    }

    FrameAnimation {
        running: root.playing
        onTriggered: {
            scene.time = scene.time + frameTime * root.speed
            if (scene.time >= scene.durationSeconds && root.benchSeconds <= 0)
                root.playing = false
            if (root.benchSeconds > 0) {
                root.benchFrames++
                root.benchElapsed += frameTime
                root.benchWorst = Math.max(root.benchWorst, frameTime)
                root.benchUpdateMs += scene.updateMs
                if (scene.time >= scene.durationSeconds)
                    scene.time = 0
                if (root.benchElapsed >= root.benchSeconds) {
                    console.log("BENCH-3D fps=" + (root.benchFrames / root.benchElapsed).toFixed(1)
                                + " worstMs=" + (root.benchWorst * 1000).toFixed(1)
                                + " meshUpdateMs=" + (root.benchUpdateMs / root.benchFrames).toFixed(2)
                                + " triangles=" + scene.triangleCount
                                + " renderFps=" + view.renderStats.fps)
                    Qt.quit()
                }
            }
        }
    }

    Timer {
        // Headless capture: wait a few frames after positioning the scene.
        running: root.capturePath.length > 0
        interval: 1500
        onTriggered: canvas.grabToImage(function(result) {
            console.log("CAPTURE-3D " + result.saveToFile(root.capturePath) + " " + root.capturePath)
            Qt.quit()
        })
    }

    Item {
    id: canvas
    anchors.fill: parent

    View3D {
        id: view
        anchors.fill: parent
        environment: SceneEnvironment {
            clearColor: "#1e2228"
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
        }

        Node {
            id: orbitOrigin
            position: Qt.vector3d(0, 40, 0)
            eulerRotation: Qt.vector3d(-18, -28, 0)
            PerspectiveCamera {
                id: camera
                position: Qt.vector3d(0, 0, 620)
                clipNear: 5
                clipFar: 20000
                fieldOfView: 40
            }
        }

        DirectionalLight { eulerRotation: Qt.vector3d(-40, -30, 0); brightness: 1.1 }
        DirectionalLight { eulerRotation: Qt.vector3d(-20, 150, 0); brightness: 0.45 }
        DirectionalLight { eulerRotation: Qt.vector3d(70, 0, 0); brightness: 0.2 }

        Repeater3D {
            model: scene.geometries
            Model {
                required property var modelData
                required property int index
                geometry: modelData
                materials: PrincipledMaterial {
                    // part, punch, die, riser, table, finger
                    baseColor: ["#c9d3dc", "#5d6875", "#4a535e", "#6b5f52", "#3a3f46", "#e08a2c"][index]
                    metalness: index === 0 ? 0.55 : 0.3
                    roughness: index === 0 ? 0.35 : 0.6
                    cullMode: Material.NoCulling
                    opacity: index === 4 ? 0.85 : 1
                }
            }
        }
    }

    OrbitCameraController {
        anchors.fill: view
        origin: orbitOrigin
        camera: camera
    }

    Rectangle {
        anchors { left: parent.left; top: parent.top; margins: 12 }
        width: info.implicitWidth + 24
        height: info.implicitHeight + 16
        radius: 6
        color: "#cc111418"
        ColumnLayout {
            id: info
            anchors.centerIn: parent
            spacing: 2
            Label { text: scene.stageText; color: "white"; font.pixelSize: 20; font.bold: true }
            Label { text: scene.phaseText; color: "#9fc6ff"; font.pixelSize: 16 }
            Label {
                color: "#b8c0c8"
                font.pixelSize: 13
                text: "FPS " + view.renderStats.fps + " · render " + view.renderStats.renderTime.toFixed(1)
                      + " ms · malla " + scene.updateMs.toFixed(2) + " ms · " + scene.triangleCount + " triángulos"
            }
            Label { text: scene.status; color: "#7f8891"; font.pixelSize: 12 }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: controls.implicitHeight + 16
        color: "#cc111418"
        RowLayout {
            id: controls
            anchors { fill: parent; margins: 8 }
            spacing: 8
            Button {
                text: root.playing ? "Pausa" : "Reproducir"
                onClicked: {
                    if (!root.playing && scene.time >= scene.durationSeconds)
                        scene.time = 0
                    root.playing = !root.playing
                }
            }
            Repeater {
                model: scene.stageCount
                Button {
                    required property int index
                    text: String(index + 1)
                    implicitWidth: 44
                    onClicked: scene.time = scene.stageStartTime(index)
                }
            }
            Slider {
                Layout.fillWidth: true
                from: 0
                to: Math.max(0.001, scene.durationSeconds)
                value: scene.time
                onMoved: scene.time = value
            }
            ComboBox {
                model: ["0.5x", "1x", "2x", "4x"]
                currentIndex: 1
                onActivated: root.speed = [0.5, 1, 2, 4][currentIndex]
            }
            Label {
                color: "white"
                text: scene.time.toFixed(1) + " / " + scene.durationSeconds.toFixed(0) + " s"
            }
        }
    }
    }
}
