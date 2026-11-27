import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    id: root
    width: 864
    height: 668

    BendCNC.ToolsView {
        id: view
        anchors.fill: parent
    }

    TestCase {
        name: "ToolsViewTests"
        when: windowShown

        function test_threeModulesFillTheViewWithoutOverlap() {
            var punch = findChild(view, "punch-view")
            var die = findChild(view, "die-view")
            var material = findChild(view, "material-view")
            verify(punch !== null)
            verify(die !== null)
            verify(material !== null)
            fuzzyCompare(punch.width, die.width, 0.01)
            fuzzyCompare(die.width, material.width, 0.01)
            compare(punch.pageX, 7)
            compare(die.pageX - (punch.pageX + punch.width), 7)
            compare(material.pageX - (die.pageX + die.width), 7)
            compare(material.pageX + material.width, view.width - 7)
            compare(punch.parent.y, 7)
            compare(punch.parent.y + punch.height, view.height - 7)
        }

        function test_sectionsAndFootersStayInsideModules() {
            var moduleNames = ["punch-view", "die-view", "material-view"]
            for (let index = 0; index < moduleNames.length; index++) {
                const module = findChild(view, moduleNames[index])
                const body = findChild(module, "body")
                const stack = findChild(module, "tool-section-stack")
                const footer = findChild(module, "tool-footer")
                const selector = findChild(module, "tool-selector")
                verify(body !== null)
                verify(stack !== null)
                verify(footer !== null)
                verify(selector !== null)
                verify(selector.x >= 0)
                verify(selector.x + selector.width <= body.width + 0.01)
                verify(stack.x >= 0)
                verify(stack.x + stack.width <= body.width + 0.01)
                verify(stack.y + stack.height < footer.y)
                verify(footer.y + footer.height <= body.height + 0.01)
            }
        }

        function test_controlsExposeReadableGeometry() {
            var material = findChild(view, "material-view")
            var moduleNames = ["punch-view", "die-view", "material-view"]
            for (let index = 0; index < moduleNames.length; index++) {
                const module = findChild(view, moduleNames[index])
                const selector = findChild(module, "tool-selector")
                verify(selector !== null)
                verify(selector.height >= 35)
                verify(selector.width >= 190)
            }
                verify(material !== null)
                compare(view.formatPreferredToolName("Acute 30° Punch [BC-9302]", "punch"),
                    "Acute 30°\n[BC-9302]")
                compare(view.formatPreferredToolName("Acute 26mm 30° Die [BC-9355]", "die"),
                    "Acute 26mm 30°\n[BC-9355]")
                const preferredPunch = findChild(material, "preferred-punch-combo")
                const preferredDie = findChild(material, "preferred-die-combo")
                verify(preferredPunch !== null)
                verify(preferredDie !== null)
                verify(preferredPunch.twoLineItems)
                verify(preferredDie.twoLineItems)
                if (preferredPunch.count === 0 || preferredDie.count === 0)
                    skip("requires a populated tooling catalog (not bundled)")
                verify(preferredPunch.displayText.indexOf("\n") > 0)
                verify(preferredDie.displayText.indexOf("\n") > 0)
                verify(preferredPunch.displayText.indexOf("[BC-") > 0)
                verify(preferredDie.displayText.indexOf("[BC-") > 0)
        }
    }
}
