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

    TestCase {
        name: "CreateBendLifecycleTests"
        when: windowShown

        property var files: ({})
        property bool writesSucceed: true
        property var fakeIo: ({
            read: function(url) {
                return Object.prototype.hasOwnProperty.call(files, url) ? files[url] : null
            },
            write: function(url, text) {
                if (!writesSucceed)
                    return false
                files[url] = text
                return true
            },
            exists: function(url) {
                return Object.prototype.hasOwnProperty.call(files, url)
            }
        })
        property var originalPrograms: []
        property int originalSelectedProgramIndex: 0

        function initTestCase() {
            originalPrograms = view.cloneValue(state.programs)
            originalSelectedProgramIndex = state.selectedProgramIndex
        }

        function init() {
            state.programs = view.cloneValue(originalPrograms)
            state.selectedProgramIndex = originalSelectedProgramIndex
            state.selectedRunBend = state.programs.length > 0
                && state.programs[state.selectedProgramIndex].bends.length > 0 ? 0 : -1
            state.syncActiveProgramState()
            writesSucceed = true
            state.storageIoOverride = fakeIo
            view.cancelEditing()
            view.syncWorkingBends()
            state.hidePopup()
            state.clearAlarm()
            wait(0)
        }

        function test_selectedProgramSequenceIsCreateBendSource() {
            compare(view.workingBends.length, state.programBends.length)
            verify(view.workingBends.length > 0)
            compare(view.workingBends[0].name, state.programBends[0].name)
            if (view.punchItems.length === 0 || view.dieItems.length === 0 || view.materialItems.length === 0)
                skip("requires a populated tooling/material catalog (not bundled)")

            state.setActiveProgram("CREATE BEND SOURCE REGRESSION", [{
                id: "selected-program-bend",
                name: "SELECTED PROGRAM BEND",
                punchId: view.punchItems[0].id,
                dieId: view.dieItems[0].id,
                materialId: view.materialItems[0].id,
                materialThickness: 0.0625,
                desiredBendAngle: 90,
                angleCompensation: 0,
                punchToMaterialClearance: 0.05,
                additionalRetractAfterBend: 0,
                bendWidth: 1,
                overriddenFinalBendPosition: -2
            }], "test", "")
            wait(0)
            compare(view.workingBends.length, 1)
            compare(view.currentBend.name, "SELECTED PROGRAM BEND")
        }

        function completeValidDraft(name) {
            if (view.punchItems.length === 0 || view.dieItems.length === 0 || view.materialItems.length === 0)
                skip("requires a populated tooling/material catalog (not bundled)")
            view.setBendValue("name", name)
            view.setBendValue("punchId", view.punchItems[0].id)
            view.setBendValue("dieId", view.dieItems[0].id)
            view.setBendValue("materialId", view.materialItems[0].id)
            view.syncSelectedToolIndexes()
            view.setBendValue("materialThickness", 0.0625)
            view.setBendValue("desiredBendAngle", 90)
            view.setBendValue("angleCompensation", 0)
            view.setBendValue("punchToMaterialClearance", 0.053125)
            view.setBendValue("additionalRetractAfterBend", 0)
            view.setBendValue("bendWidth", 8)
            view.setBendValue("overriddenFinalBendPosition", -2)
            view.setBendValue("notes", "Lifecycle note")
        }

        function test_serializerPreservesEditableSourceFields() {
            const source = Object.assign({}, view.currentBend, {
                id: "serializer-source-bend",
                notes: "PRESERVED",
                xAxisNotes: "X NOTE",
                rAxisNotes: "R NOTE",
                backGaugeRefEdgeStopEnabled: true,
                backGaugeRefEdgeStop: "G55",
                backGaugeXPosition: 2.5,
                backGaugeRPosition: -0.25,
                overrideFinalBendPositionEnabled: true,
                overriddenFinalBendPosition: -2.125
            })
            const serialized = state.bendFromCreateDraft(source.name, source,
                view.currentPunch, view.currentDie, view.currentMaterial, -2.125, 4)
            compare(serialized.id, source.id)
            compare(serialized.notes, "PRESERVED")
            compare(serialized.xAxisNotes, "X NOTE")
            compare(serialized.rAxisNotes, "R NOTE")
            compare(serialized.backGaugeRefEdgeStop, "G55")
            compare(serialized.backGaugeRefEdgeStopEnabled, true)
            compare(serialized.backGaugeXPosition, 2.5)
            compare(serialized.backGaugeRPosition, -0.25)
            compare(serialized.overrideFinalBendPositionEnabled, true)
            compare(serialized.overriddenFinalBendPosition, -2.125)
        }

        function test_newSaveAndDuplicateLifecycle() {
            const initialCount = view.workingBends.length
            view.createNew()
            completeValidDraft("LIFECYCLE BEND")
            verify(view.canSave)
            verify(view.saveEditing())
            compare(view.workingBends.length, initialCount + 1)
            compare(view.currentBend.name, "LIFECYCLE BEND")
            compare(view.currentBend.notes, "Lifecycle note")

            view.duplicateCurrent()
            verify(view.creatingNew)
            verify(view.currentBend.name.indexOf("COPY") >= 0)
            verify(view.currentBend.id !== view.workingBends[view.selectedBendIndex].id)
            verify(view.canSave)
            verify(view.saveEditing())
            compare(view.workingBends.length, initialCount + 2)
        }

        function test_deleteRequiresConfirmationAndRemovesRecord() {
            const initialCount = view.workingBends.length
            view.requestDelete()
            verify(state.popupVisible)
            compare(state.popupAction, "confirmation")
            compare(view.workingBends.length, initialCount)
            state.performPopupPrimaryAction()
            compare(view.workingBends.length, initialCount - 1)
        }

        function test_loadIntoProgramUsesCalculatedAndSourceFields() {
            const initialProgramCount = state.programBends.length
            view.beginEdit(false)
            view.setBendValue("overrideFinalBendPositionEnabled", true)
            view.setBendValue("overriddenFinalBendPosition", -2)
            const source = view.cloneValue(view.currentBend)
            const result = state.createBendAction("load", source.name,
                source, view.currentPunch, view.currentDie, view.currentMaterial,
                view.calculation.inUseFinalBendPosition, view.calculation.bendTonnage)
            verify(result.ok)
            compare(state.programBends.length, initialProgramCount + 1)
            const loaded = state.programBends[state.programBends.length - 1]
            compare(loaded.id, result.bend.id)
            compare(loaded.punchId, result.bend.punchId)
            compare(loaded.dieId, result.bend.dieId)
            compare(loaded.materialId, result.bend.materialId)
            verify(isFinite(Number(loaded.finalPosition)))
            verify(isFinite(Number(loaded.tonnage)))
        }

        function test_programValidationUsesMachineTravelRange() {
            compare(state.validateProgramBend({ tonnage: 1, finalPosition: -4.0, x: 0 }).length, 0)
            compare(state.validateProgramBend({ tonnage: 1, finalPosition: -0.05, x: 0 }).length, 0)
            verify(state.validateProgramBend({ tonnage: 1, finalPosition: -4.01, x: 0 })[0].indexOf("FINAL_BEND_POS_OUT_RANGE") >= 0)
            verify(state.validateProgramBend({ tonnage: 1, finalPosition: -0.04, x: 0 })[0].indexOf("FINAL_BEND_POS_OUT_RANGE") >= 0)
        }

        function test_programMutationRollsBackWhenPersistenceFails() {
            const before = view.cloneValue(state.programBends)
            const beforeSelection = state.selectedRunBend
            writesSucceed = false

            view.beginEdit(false)
            completeValidDraft(view.currentBend.name)
            view.setBendValue("notes", "MUST NOT PUBLISH")
            verify(view.canSave)
            verify(!view.saveEditing())
            compare(JSON.stringify(state.programBends), JSON.stringify(before))
            compare(state.selectedRunBend, beforeSelection)
            compare(view.editing, true)
        }
    }
}
