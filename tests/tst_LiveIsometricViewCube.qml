import QtQuick
import QtTest

Item {
    id: root
    width: 360
    height: 420

    TestCase {
        name: "LiveIsometricViewCubeTests"
        when: windowShown

        function createCube(properties) {
            let component = Qt.createComponent("../qml/LiveIsometricViewCube.qml")
            verify(component.status === Component.Ready, component.errorString())
            let cube = component.createObject(root, properties || {})
            verify(!!cube)
            wait(20)
            return cube
        }

        function test_defaultSizeAndMachineLabels() {
            let cube = createCube()
            compare(cube.orientation, "ISO_TOP_LEFT")
            compare(cube.implicitWidth, 132)
            compare(cube.implicitHeight, 120)
            // Cabinet projection: equal 45-degree recede at half the face size.
            compare(cube.recedeX, cube.recedeY)
            verify(Math.abs(Math.hypot(cube.recedeX, cube.recedeY) - cube.faceSize / 2) < 1)
            compare(cube.orientationLabel("ISO_TOP_LEFT"), "LEFT + TOP + BACK")
            compare(cube.orientationLabel("ISO_TOP_RIGHT"), "LEFT + TOP + FRONT")
            compare(cube.orientationLabel("ISO_LEFT"), "LEFT + BACK")
            compare(cube.orientationLabel("ISO_RIGHT"), "LEFT + FRONT")
            compare(cube.orientationLabel("ISO_FRONT"), "LEFT SIDE (FLAT)")
            compare(cube.orientationLabel("ISO_BACK"), "RIGHT SIDE (MIRRORED)")
            compare(findChild(cube, "orientationHomeButton"), null)
            cube.destroy()
        }

        function test_sideBandsFollowCanvasRecedeDirection() {
            let cube = createCube()
            compare(cube.sideFaces("ISO_TOP_LEFT"), ["TOP", "BACK"])
            compare(cube.sideFaces("ISO_TOP_RIGHT"), ["TOP", "FRONT"])
            compare(cube.sideFaces("ISO_BOTTOM_LEFT"), ["BOTTOM", "BACK"])
            compare(cube.sideFaces("ISO_BOTTOM_RIGHT"), ["BOTTOM", "FRONT"])
            compare(cube.sideFaces("ISO_TOP"), ["TOP"])
            compare(cube.sideFaces("ISO_BOTTOM"), ["BOTTOM"])
            compare(cube.sideFaces("ISO_LEFT"), ["BACK"])
            compare(cube.sideFaces("ISO_RIGHT"), ["FRONT"])
            compare(cube.sideFaces("ISO_FRONT"), [])
            compare(cube.sideFaces("ISO_BACK"), [])
            cube.destroy()
        }

        function test_chamferGridResolvesOnlyExistingViews() {
            let cube = createCube({ orientation: "ISO_TOP_LEFT" })
            compare(cube.targetModel.length, 9)
            for (let i = 0; i < cube.targetModel.length; i++) {
                let target = cube.targetModel[i]
                compare(cube.targetAt(target.x, target.y), target.value, target.value)
                verify(!!findChild(cube, "integratedTarget-" + target.value), target.value)
            }
            compare(cube.targetAt(57, 57), "ISO_FRONT")
            compare(cube.targetAt(32, 32), "ISO_TOP_LEFT")
            compare(cube.targetAt(57, 32), "ISO_TOP")
            compare(cube.targetAt(82, 32), "ISO_TOP_RIGHT")
            compare(cube.targetAt(32, 57), "ISO_LEFT")
            compare(cube.targetAt(82, 57), "ISO_RIGHT")
            compare(cube.targetAt(32, 82), "ISO_BOTTOM_LEFT")
            compare(cube.targetAt(57, 82), "ISO_BOTTOM")
            compare(cube.targetAt(82, 82), "ISO_BOTTOM_RIGHT")
            // Touch tolerance just outside the square still hits the corner.
            compare(cube.targetAt(91, 91), "ISO_BOTTOM_RIGHT")
            compare(cube.targetAt(120, 10), "")
            verify(!!findChild(cube, "integratedCubePointer"))
            cube.destroy()
        }

        function test_cornersAndEdgesWrapOntoVisibleSideFaces() {
            let cube = createCube({ orientation: "ISO_TOP_LEFT" })
            // The LEFT+TOP+BACK vertex shows on all three visible faces.
            compare(cube.targetPolygons("ISO_TOP_LEFT").length, 3)
            compare(cube.targetPolygons("ISO_TOP").length, 2)
            compare(cube.targetPolygons("ISO_LEFT").length, 2)
            compare(cube.targetPolygons("ISO_TOP_RIGHT").length, 2)
            compare(cube.targetPolygons("ISO_BOTTOM_LEFT").length, 2)
            compare(cube.targetPolygons("ISO_BOTTOM_RIGHT").length, 1)
            compare(cube.targetPolygons("ISO_FRONT").length, 1)
            // Corner pieces on the TOP and BACK faces select the same corner.
            compare(cube.targetAt(27, 22), "ISO_TOP_LEFT")
            compare(cube.targetAt(22, 28), "ISO_TOP_LEFT")
            compare(cube.targetAt(78, 22), "ISO_TOP_RIGHT")
            // Edge strips on the side faces select the shared edge.
            compare(cube.targetAt(52, 22), "ISO_TOP")
            compare(cube.targetAt(22, 53), "ISO_LEFT")
            // The rest of each side face is not a view of its own.
            compare(cube.targetAt(42, 11), "")
            compare(cube.targetAt(11, 42), "")
            cube.orientation = "ISO_BOTTOM_RIGHT"
            compare(cube.targetPolygons("ISO_BOTTOM_RIGHT").length, 3)
            compare(cube.targetPolygons("ISO_TOP_LEFT").length, 1)
            cube.destroy()
        }

        function test_mirroredRightSideOffersNoFalseEdges() {
            let cube = createCube({ orientation: "ISO_BACK" })
            compare(cube.targetAt(57, 57), "ISO_BACK")
            compare(cube.targetAt(32, 32), "")
            compare(cube.targetAt(82, 57), "")
            cube.destroy()
        }

        function test_clickingCornerAndEdgeEmitsStableIdentifiers() {
            let cube = createCube({ orientation: "ISO_FRONT" })
            let requested = ""
            cube.orientationRequested.connect(function(value) { requested = value })
            mouseClick(cube, 82, 82)
            compare(requested, "ISO_BOTTOM_RIGHT")
            mouseClick(cube, 57, 32)
            compare(requested, "ISO_TOP")
            requested = ""
            mouseClick(cube, 10, 40)
            compare(requested, "")
            cube.destroy()
        }

        function test_keyboardMovesOnGridAndMenuOpens() {
            let cube = createCube({ orientation: "ISO_TOP_LEFT" })
            let requested = ""
            cube.orientationRequested.connect(function(value) { requested = value })
            cube.forceActiveFocus()
            keyClick(Qt.Key_Right)
            compare(requested, "ISO_TOP")
            requested = ""
            keyClick(Qt.Key_Up)
            compare(requested, "")
            cube.orientation = "ISO_FRONT"
            keyClick(Qt.Key_Down)
            compare(requested, "ISO_BOTTOM")
            cube.orientation = "ISO_BACK"
            keyClick(Qt.Key_Left)
            compare(requested, "ISO_LEFT")
            let menuButton = findChild(cube, "orientationMenuButton")
            let menu = findChild(cube, "orientationMenu")
            verify(!!menuButton)
            verify(!!menu)
            mouseClick(menuButton)
            tryCompare(menu, "opened", true)
            menu.close()
            tryCompare(menu, "opened", false)
            cube.destroy()
        }
    }
}
