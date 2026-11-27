import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    width: 864
    height: 638.4

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
    }

    BendCNC.CreateBendView {
        id: view
        anchors.fill: parent
        appState: state
    }

    BendCNC.OnScreenKeyboard {
        anchors.fill: parent
        appState: state
    }

    TestCase {
        name: "CreateBendReferenceEdgeStopTests"
        when: windowShown

        function init() {
            state.closeOnScreenKeyboardState()
            view.cancelEditing()
            state.virtualInputMode = "ALWAYS"
            state.backGaugeCoordinateNames = ({
                G54: "LOWER FINGER",
                G55: "UPPER FINGER"
            })
            wait(0)
        }

        function test_textFieldsOpenFullKeyboardAndCommit() {
            const nameField = findChild(view, "create-bend-name-field")
            const xNotes = findChild(view, "create-bend-x-axis-notes")
            const rNotes = findChild(view, "create-bend-r-axis-notes")
            const generalNotes = findChild(view, "create-bend-general-notes")
            verify(nameField && xNotes && rNotes && generalNotes)

            view.beginEdit(false)
            view.editingName = true
            nameField.openKeyboard()
            compare(state.onScreenKeyboardKind, "text")
            state.clearOnScreenKeyboard()
            state.insertOnScreenKeyboardText("TOUCH BEND")
            verify(state.commitOnScreenKeyboard())
            compare(view.currentBend.name, "TOUCH BEND")

            const noteCases = [
                { field: xNotes, value: "X TOUCH NOTE", property: "xAxisNotes" },
                { field: rNotes, value: "R TOUCH NOTE", property: "rAxisNotes" },
                { field: generalNotes, value: "GENERAL TOUCH NOTE", property: "notes" }
            ]
            for (let index = 0; index < noteCases.length; index++) {
                noteCases[index].field.openKeyboard()
                compare(state.onScreenKeyboardKind, "text")
                compare(state.onScreenKeyboardTarget, noteCases[index].field.textInput)
                state.clearOnScreenKeyboard()
                state.insertOnScreenKeyboardText(noteCases[index].value)
                verify(state.commitOnScreenKeyboard())
                compare(view.currentBend[noteCases[index].property], noteCases[index].value)
            }
        }

        function test_nameEditActionOpensFullKeyboard() {
            view.editingName = false
            const nameField = findChild(view, "create-bend-name-field")
            verify(nameField)
            view.beginNameEdit(nameField)
            tryCompare(state, "onScreenKeyboardVisible", true)
            compare(state.onScreenKeyboardKind, "text")
            compare(state.onScreenKeyboardTarget, nameField)
        }

        function test_editableMeasurementFieldsOpenNumericKeyboard() {
            const cases = [
                { name: "highlighted-text-field", property: "desiredBendAngle", value: "88.5", expected: 88.5 },
                { name: "create-bend-compensation-field", property: "angleCompensation", value: "1.2", expected: 1.2 },
                { name: "create-bend-clearance-field", property: "punchToMaterialClearance", value: "0.045", expected: 0.045 },
                { name: "create-bend-retract-field", property: "additionalRetractAfterBend", value: "0.125", expected: 0.125 },
                { name: "create-bend-thickness-field", property: "materialThickness", value: "0.063", expected: 0.063 },
                { name: "create-bend-width-field", property: "bendWidth", value: "12.5", expected: 12.5 },
                { name: "create-bend-backgauge-x-field", property: "backGaugeXPosition", value: "2.5", expected: 2.5 },
                { name: "create-bend-backgauge-r-field", property: "backGaugeRPosition", value: "-0.5", expected: -0.5 },
                { name: "create-bend-backgauge-speed-field", property: "backGaugeJogSpeed", value: "75", expected: 75 }
            ]
            view.beginEdit(false)
            view.setBendValue("overrideFinalBendPositionEnabled", false)
            view.setBendValue("backGaugeRefEdgeStopEnabled", true)
            for (let index = 0; index < cases.length; index++) {
                const field = view.editableMeasurementFields[index]
                verify(field, "Missing field: " + cases[index].name)
                field.openKeyboard()
                compare(state.onScreenKeyboardKind, "numeric")
                state.insertOnScreenKeyboardText(cases[index].value)
                verify(state.commitOnScreenKeyboard())
                compare(view.currentBend[cases[index].property], cases[index].expected)
            }

            view.setBendValue("overrideFinalBendPositionEnabled", true)
            view.setBendValue("overriddenFinalBendPosition", -2.0)
            wait(0)
            const overrideField = findChild(view, "create-bend-overridden-final-position-field")
            verify(overrideField)
            overrideField.openKeyboard()
            compare(state.onScreenKeyboardKind, "numeric")
            state.clearOnScreenKeyboard()
            state.insertOnScreenKeyboardText("-2.250")
            verify(state.commitOnScreenKeyboard())
            compare(view.currentBend.overriddenFinalBendPosition, -2.25)
        }

        function test_usesSharedBackGaugeProfileNames() {
            const selector = findChild(view, "reference-edge-stop-combo")
            verify(selector)
            compare(selector.model.length, 6)
            compare(selector.model[0], "LOWER FINGER")
            compare(selector.model[1], "UPPER FINGER")

            state.backGaugeCoordinateSystem = "G54"
            verify(state.renameBackGaugeCoordinateSystem("LOWER FINGER CALIBRATED"))
            wait(0)
            compare(selector.model[0], "LOWER FINGER CALIBRATED")
        }

        function test_selectionKeepsCanonicalCoordinateId() {
            const selector = findChild(view, "reference-edge-stop-combo")
            verify(selector)
            verify(view.currentBend !== null)
            selector.activated(1)
            compare(view.currentBend.backGaugeRefEdgeStop, "G55")
            compare(selector.model[1], "UPPER FINGER")
        }

        function test_transactionalCancelRestoresOriginal() {
            const original = view.currentBend.desiredBendAngle
            view.beginEdit(false)
            view.setBendValue("desiredBendAngle", 123.4)
            compare(view.currentBend.desiredBendAngle, 123.4)
            verify(view.hasUnsavedChanges)
            view.cancelEditing()
            compare(view.currentBend.desiredBendAngle, original)
            verify(!view.editing)
        }

        function test_newBendUsesJavaDefaultsAndStartsWithoutTooling() {
            view.createNew()
            verify(view.creatingNew)
            verify(isNaN(view.currentBend.materialThickness))
            verify(isNaN(view.currentBend.desiredBendAngle))
            compare(view.currentBend.punchId, "")
            compare(view.currentBend.dieId, "")
            compare(view.currentBend.materialId, "")
            compare(view.currentBend.punchToMaterialClearance, 0.05)
            compare(view.currentBend.backGaugeRPosition, state.defaultBackGaugeRPositionInch)
            verify(!view.canSave)
        }

        function test_angleDirectionAndOverrideAreFunctional() {
            view.beginEdit(false)
            view.setBendValue("angleCompensationReversed", false)
            const direction = findChild(view, "create-bend-compensation-direction")
            verify(direction)
            compare(direction.text, "OVERBENT")
            direction.clicked()
            compare(direction.text, "UNDERBENT")

            const overrideToggle = findChild(view, "create-bend-override-toggle")
            verify(overrideToggle)
            view.setBendValue("overrideFinalBendPositionEnabled", false)
            overrideToggle.clicked()
            verify(view.overrideEnabled)
            verify(isFinite(view.currentBend.overriddenFinalBendPosition))
            verify(findChild(view, "create-bend-overridden-final-position-field"))
        }

        function test_verticalDiagramUsesJavaImagePopup() {
            view.showVerticalDiagram()
            compare(state.popupKind, "info")
            compare(state.popupTitle, "VERTICAL POSITIONS DIAGRAM")
            compare(state.popupImageSource, "images/info/create_bend/vertical_diagram.png")
            verify(state.popupBody.indexOf("FINAL BEND POSITION") >= 0)
        }
    }
}