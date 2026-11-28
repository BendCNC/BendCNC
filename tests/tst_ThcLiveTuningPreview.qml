import QtQuick
import QtTest
import "../qml" as Production
import "../qml/modal-previews/v5" as Preview

Item {
    id: testSurface
    width: 1366
    height: 768
    Production.Theme { id: theme }
    Component { id: candidate; Preview.ThcLiveTuningPreview {} }
    Component {
        id: designerScene
        Preview.PreviewScene { selectedPreview: "THC_LIVE_TUNING" }
    }
    SignalSpy { id: closed; signalName: "closeRequested" }

    TestCase {
        name: "ThcLiveTuningPreviewTests"
        when: windowShown
        property var panel: null

        function init() {
            panel = createTemporaryObject(candidate, testSurface)
            verify(!!panel)
            verify(waitForItemPolished(panel))
            closed.target = panel
            closed.clear()
        }

        function cleanup() {
            closed.target = null
            panel = null
        }

        function control(name) {
            const item = findChild(panel, "designer-thc-" + name)
            verify(!!item, name)
            return item
        }

        function test_visualOnlyAndAllFieldsPresent() {
            compare(panel.previewOnly, true)
            compare(panel.width, 950)
            compare(panel.height, 600)
            compare(panel.backend, undefined)
            compare(panel.appState, undefined)
            verify(control("safety-label").text.indexOf("No machine commands") >= 0)
            compare(panel.fields.length, 6)
            for (const field of panel.fields) {
                compare(control(field.key).from, field.minimum)
                compare(control(field.key).to, field.maximum)
                compare(control(field.key).stepSize, field.step)
            }
        }

        function test_editAndApplyAreLocalSamples() {
            const spin = control("kp")
            mouseClick(spin.up.indicator)
            tryCompare(panel, "draftDirty", true)
            compare(panel.draft.kp, 0.101)
            mouseClick(control("apply"))
            compare(panel.sampleValues.kp, 0.101)
            compare(panel.sampleRevision, 8)
            compare(panel.draftDirty, false)
            compare(panel.previewState, "IDLE")
        }

        function test_invalidSampleCannotApply() {
            panel.editSample("cq", 0.02)
            panel.editSample("fs", 0.02)
            compare(panel.draftValid, false)
            compare(control("apply").enabled, false)
            compare(panel.applySample(), false)
            compare(panel.sampleRevision, 7)
            mouseClick(control("query"))
            compare(panel.draftValid, true)
            compare(panel.draftDirty, false)
        }

        function test_confirmationAndLifecycleOnlyChangeAppearance() {
            mouseClick(control("start"))
            compare(panel.confirmationVisible, true)
            compare(control("apply").enabled, false)
            mouseClick(control("confirm"))
            compare(panel.previewState, "HOLD")
            compare(panel.confirmationVisible, false)
            mouseClick(control("release"))
            compare(panel.previewState, "IDLE")
            panel.previewState = "HOLD"
            mouseClick(control("stop"))
            compare(panel.previewState, "STOP")
            compare(control("start").enabled, false)
            compare(control("kp").enabled, false)
        }

        function test_offlineAndStopDisableSampleActions_data() {
            return [{ tag: "offline", state: "OFFLINE" }, { tag: "stop", state: "STOP" }]
        }

        function test_offlineAndStopDisableSampleActions(data) {
            panel.previewState = data.state
            for (const name of ["query", "apply", "start", "release", "stop", "kp"])
                compare(control(name).enabled, false, name)
            panel.editSample("kp", 0.2)
            compare(panel.draft.kp, 0.1)
        }

        function test_closeAndFreshInstanceResetSamples() {
            panel.editSample("kp", 0.2)
            verify(panel.applySample())
            mouseClick(control("close"))
            compare(closed.count, 1)
            const fresh = createTemporaryObject(candidate, testSurface)
            verify(!!fresh)
            compare(fresh.sampleRevision, 7)
            compare(fresh.draft.kp, 0.1)
        }

        function test_redesignedTelemetryDynamicsStayLocalAndBounded() {
            compare(panel.tonnageHistory.length, 60)
            panel.previewState = "HOLD"
            panel.stepDynamics()
            compare(panel.tonnageHistory.length, 60)
            verify(panel.motorRpmY1 > 0)
            verify(panel.motorRpmY2 > 0)
            compare(panel.backend, undefined)
            compare(panel.previewOnly, true)
            panel.previewState = "OFFLINE"
            panel.stepDynamics()
            compare(panel.motorRpmY1, 0) // Candidate samples only; production shows unavailable.
            compare(panel.tonnageHistory.length, 60)
        }

        function test_designerSelectionUnloadsAndReopensCandidate() {
            panel.visible = false
            const scene = createTemporaryObject(designerScene, testSurface)
            verify(!!scene)
            const loader = findChild(scene, "designer-thc-loader")
            verify(!!loader)
            tryCompare(loader, "status", Loader.Ready)
            const sample = findChild(loader.item, "designer-thc-live-tuning")
            verify(!!sample)
            compare(sample.previewOnly, true)
            sample.editSample("kp", 0.2)
            verify(sample.applySample())
            mouseClick(findChild(sample, "designer-thc-close"))
            compare(scene.selectedPreview, "LEFT_4")
            tryCompare(loader, "active", false)
            tryCompare(loader, "item", null)
            scene.selectedPreview = "THC_LIVE_TUNING"
            tryCompare(loader, "status", Loader.Ready)
            const reopened = findChild(loader.item, "designer-thc-live-tuning")
            verify(!!reopened)
            compare(reopened.draft.kp, 0.1)
            scene.visible = false
            tryCompare(loader, "item", null)
        }
    }
}