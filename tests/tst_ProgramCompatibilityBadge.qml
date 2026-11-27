import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    width: 1024
    height: 768

    BendCNC.DataStore {
        id: store
    }

    BendCNC.AppState {
        id: state
        offlineSimulationEnabled: true
        virtualInputMode: "NEVER"
    }

    BendCNC.RunView {
        id: view
        anchors.fill: parent
        appState: state
        dataStore: store
    }

    TestCase {
        name: "ProgramCompatibilityBadgeTests"
        when: windowShown

        function cadJson(topology, revision) {
            let payload = { schemaVersion: "1.0", topologySchemaVersion: topology,
                            material: { tensile_psi: 58000, springBack_deg: 2 } }
            if (revision !== undefined)
                payload.generator = { id: "com.bendcnc.export", version: "1.1.0",
                                      revision: revision, topologySchemaVersion: topology }
            return JSON.stringify(payload)
        }

        // Display-only CAD bend: canonicalCadProgramBend rebuilds width from tonnage.
        function cadBend(id) {
            return { id: id, name: id, state: "CAD", angle: "90.0", thickness: "0.0600",
                     x: "1.0000", r: "0.0000", speed: "100.000", tonnage: "1.341", vdieValue: 0.5 }
        }

        // Bend saved after CAD generation lost its inputs (N1 programs on the press).
        function degradedBend(id) {
            return { id: id, name: id, state: "OVERBENT", desiredBendAngle: 90, angleCompensation: 0,
                     punchToMaterialClearance: 0.05, bendWidth: 0, width: "0.000", tonnage: "0.000",
                     materialThickness: 0.06 }
        }

        function loadPrograms() {
            const current = state.currentCadExporterRevision
            state.setProgramsFromStorage([
                { id: "p-current", name: "Current", bends: [cadBend("c1")], cadPreviewJson: cadJson("5.0", current) },
                { id: "p-old", name: "Old revision", bends: [cadBend("o1")],
                  cadPreviewJson: cadJson("5.0", "2026-08-03-cyclic-loop-graph-v4") },
                { id: "p-legacy", name: "Legacy", bends: [cadBend("l1")], cadPreviewJson: cadJson("4.0") },
                { id: "p-degraded", name: "Degraded", bends: [degradedBend("d1")],
                  cadPreviewJson: cadJson("5.0", current) },
                { id: "p-manual", name: "Manual", bends: [{ id: "m1", name: "m1", bendWidth: 4 }] },
                { id: "p-broken", name: "Broken", bends: [cadBend("b1")], cadPreviewJson: "{not json" }
            ], [], [], [], {})
        }

        function test_classification() {
            loadPrograms()
            const expected = [["current", "V5 OK"], ["old-revision", "OLD EXPORT"],
                              ["legacy", "LEGACY V4"], ["degraded", "REGENERATE"],
                              ["manual", "MANUAL"], ["invalid", "CAD ERROR"]]
            compare(state.programs.length, expected.length)
            for (let i = 0; i < expected.length; i++) {
                const info = state.programCompatibility(state.programs[i])
                compare(info.status, expected[i][0], state.programs[i].name)
                compare(info.label, expected[i][1], state.programs[i].name)
                verify(String(info.detail).length > 0)
            }
        }

        function test_validatorAcceptsSameRevisions() {
            compare(state.acceptedCadExporterRevisions[0], "2026-08-06-compound-operation-relations-v5")
            verify(state.acceptedCadExporterRevisions.indexOf("2026-08-03-cyclic-loop-graph-v4") >= 0)
        }

        function test_selectorShowsBadges() {
            loadPrograms()
            state.selectProgram(2)
            wait(0)
            const selected = findChild(view, "run-program-compatibility-selected")
            verify(selected)
            tryCompare(selected, "label", "LEGACY V4")
            verify(selected.visible)
            state.selectProgram(0)
            tryCompare(selected, "label", "V5 OK")
        }

        function test_comboTapTogglesMenu() {
            loadPrograms()
            const combo = findChild(view, "run-program-combo")
            verify(combo)
            verify(combo.visible)
            compare(combo.menuOpen, false)
            mouseClick(combo)
            tryCompare(combo, "menuOpen", true)
            mouseClick(combo)
            tryCompare(combo, "menuOpen", false)
            wait(100)
            compare(combo.menuOpen, false)
            mouseClick(combo)
            tryCompare(combo, "menuOpen", true)
            // A press elsewhere still closes it.
            mouseClick(view, 5, view.height - 5)
            tryCompare(combo, "menuOpen", false)
        }
    }
}
