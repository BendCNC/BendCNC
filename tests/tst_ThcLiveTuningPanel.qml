import QtQuick
import QtTest
import "../qml" as BendCNC

Item {
    id: testSurface
    width: 1280
    height: 800

    BendCNC.Theme { id: testTheme }

    Component {
        id: backendComponent
        QtObject {
            property bool pressTransportAvailable: true
            property bool pressConnected: true
            property bool pressReady: true
            property bool pressHomed: true
            property bool pressTelemetryFresh: true
            property bool independentRamTelemetryAvailable: true
            property double pressTelemetrySequence: 100
            property var ramLoadY1: 0.4
            property var ramLoadY2: 0.6
            property bool motorRpmAvailable: true
            property var motorRpmY1: 1420
            property var motorRpmY2: 1418
            property string pressConnectionState: "READY"
            property string pressMachineState: "IDLE"
            property string pressFirmwareVersion: "1.3"
            property bool pressOperationActive: false
            property bool physicalPedalAvailable: true
            property bool physicalPedal: false
            property bool bendPedal: false
            property bool antiBind: false
            property bool primingModeEnabled: false
            property bool primingLatchY1: false
            property bool primingLatchY2: false
            property bool pressSafetyStopUnconfirmed: false
            property var thcLiveTuning: ({ kp: 0.1, ki: 0.01, kd: 0.005,
                rate: 0.005, cq: 0.01, fs: 0.04, revision: 7 })
            property bool thcLiveTuningSupported: false
            property bool thcLiveTuningExtended: false
            property bool thcLiveTuningPending: false
            property string thcLiveTuningError: ""
            property bool thcContinuousActive: false
            property var thcLiveDiagnostics: ({})
            property string thcCommissioningState: "IDLE"
            property int operationId: 41
            property string operationDevice: "press"
            property string operationName: ""
            property string operationState: "IDLE"
            property string operationError: ""
            property bool commandOperationActive: false
            property bool capabilityPresent: true
            property int queryCalls: 0
            property int applyCalls: 0
            property int startCalls: 0
            property int heartbeatCalls: 0
            property int releaseCalls: 0
            property int cancelCalls: 0
            property int homeCalls: 0
            property var applied: ({})
            property bool deferApplyAck: false
            property var startHook: null
            property var heartbeatHook: null
            signal commandLifecycleChanged()

            function queryThcLiveTuning() {
                ++queryCalls
                thcLiveTuningSupported = capabilityPresent
                if (!capabilityPresent) thcLiveTuningError = "V53_QUERY_REQUIRED"
                return capabilityPresent
            }
            function applyThcLiveTuning(settings) {
                ++applyCalls
                applied = settings
                if (deferApplyAck) thcLiveTuningPending = true
                else thcLiveTuning = Object.assign({}, settings, { revision: thcLiveTuning.revision + 1 })
                return true
            }
            function startContinuousThcContactProfile() {
                ++startCalls
                ++operationId
                operationName = "thc-contact-profile-v53"
                operationState = "ACKNOWLEDGED"
                commandOperationActive = true
                pressOperationActive = true
                thcContinuousActive = true
                thcCommissioningState = "CONTACT_PROFILE_V53_RUNNING"
                commandLifecycleChanged()
                if (startHook) startHook()
                return true
            }
            function heartbeatThcCommissioning() {
                ++heartbeatCalls
                if (heartbeatHook) return heartbeatHook()
                return true
            }
            function releaseThcCommissioning() {
                ++releaseCalls
                thcCommissioningState = "RELEASE_PENDING"
                thcLiveTuningSupported = false
                thcLiveTuningError = "V53_RELEASE_PENDING"
                return true
            }
            function cancelThcCommissioning() {
                ++cancelCalls
                thcCommissioningState = "CANCELLING"
                pressSafetyStopUnconfirmed = true
                return true
            }
            function replaceWithHome() {
                ++homeCalls
                ++operationId
                operationName = "home"
                operationState = "SENT"
                commandOperationActive = true
                pressOperationActive = true
                pressHomed = false
                thcContinuousActive = false
                // Native Home does not rewrite the earlier THC terminal state.
                commandLifecycleChanged()
            }
        }
    }
    Component { id: panelComponent; BendCNC.ThcLiveTuningPanel { font.family: testTheme.appFontFamily } }
    Component {
        id: navigationComponent
        Loader {
            id: navigationLoader
            property var testBackend: null
            active: true
            sourceComponent: Component {
                BendCNC.ThcLiveTuningPanel {
                    backend: navigationLoader.testBackend
                    intendedVisible: navigationLoader.active && navigationLoader.visible
                    Component.onCompleted: open()
                }
            }
        }
    }
    Component { id: manualComponent; BendCNC.ManualModeView { width: 864; height: 638 } }
    Component { id: stateComponent; BendCNC.AppState { offlineSimulationEnabled: true } }
    Component { id: viewportComponent; Item {} }

    TestCase {
        id: testCase
        name: "ThcLiveTuningPanelTests"
        when: windowShown
        property var mock: null
        property var panel: null

        function init() {
            mock = createTemporaryObject(backendComponent, testSurface)
            verify(!!mock, "Object exists")
            panel = createTemporaryObject(panelComponent, testSurface, { backend: mock })
            verify(!!panel, "Component exists")
            panel.open()
            tryCompare(panel, "opened", true)
            panel.hostWindow.requestActivate()
            tryCompare(panel, "surfaceActive", true)
            // Activation may happen after opened on headless platforms. The
            // query button is the same explicit recovery path used by operators.
            if (mock.queryCalls === 0) panel.queryCapability()
            tryCompare(panel, "supported", true)
        }

        function cleanup() {
            if (panel) {
                panel.close()
                panel.destroy()
            }
            panel = null
            mock = null
        }

        function control(name) {
            const item = findChild(panel.contentItem, name)
            verify(!!item, "Object exists")
            return item
        }

        function clickScrolledControl(name) {
            const button = control(name)
            const flick = control("thc-live-body-scroll").contentItem
            verify(waitForItemPolished(panel.contentItem))
            // Nested responsive grids finish their first layout on rendering;
            // measuring earlier sees the temporary single-column positions.
            // Request a frame even for a reset already at its default/scroll.
            panel.contentItem.update()
            verify(waitForRendering(panel.contentItem))
            const position = button.mapToItem(flick, 0, 0)
            flick.contentY = Math.max(0, Math.min(flick.contentY + position.y - 8,
                flick.contentHeight - flick.height))
            verify(waitForItemPolished(panel.contentItem))
            panel.contentItem.update()
            verify(waitForRendering(panel.contentItem))
            const visiblePosition = button.mapToItem(flick, 0, 0)
            verify(visiblePosition.y >= 0 && visiblePosition.y + button.height <= flick.height,
                name + " is inside the scroll viewport: " + visiblePosition.y
                    + "; before=" + position.y + "; scroll=" + flick.contentY
                    + "; origin=" + flick.originY + "; viewport=" + flick.height
                    + "; content=" + flick.contentHeight)
            mouseClick(button)
        }

        function resetSideEffectsSnapshot() {
            return JSON.stringify({ query: mock.queryCalls, apply: mock.applyCalls,
                start: mock.startCalls, heartbeat: mock.heartbeatCalls,
                release: mock.releaseCalls, cancel: mock.cancelCalls, home: mock.homeCalls,
                operationId: mock.operationId, operationName: mock.operationName,
                requested: mock.thcLiveTuning, diagnostics: mock.thcLiveDiagnostics,
                ownerId: panel.ownerId, leaseIntended: panel.leaseIntended,
                reloadDraft: panel.reloadDraft, actionError: panel.actionError,
                history: findChild(panel, "thc-live-telemetry-history").samples })
        }

        function startOwned() {
            mouseClick(control("thc-live-start"))
            tryCompare(panel, "confirmationVisible", true)
            compare(mock.startCalls, 0)
            mouseClick(control("thc-live-confirm-start"))
            tryCompare(mock, "startCalls", 1)
            tryCompare(panel, "ownsOperation", true)
        }

        function test_capabilityAbsentAndVersionIsNotProof() {
            mock.capabilityPresent = false
            verify(!panel.queryCapability())
            compare(mock.pressFirmwareVersion, "1.3")
            compare(panel.supported, false)
            compare(panel.canStart, false)
            compare(panel.canApply, false)
            compare(mock.startCalls, 0)
        }

        function test_nullAndOfflineHaveNoProductionMock() {
            panel.offline = true
            compare(panel.canQuery, false)
            compare(panel.canStart, false)
            compare(panel.canTune, false)
            panel.offline = false
            panel.backend = null
            compare(panel.apiAvailable, false)
            compare(panel.canStart, false)
            compare(panel.canQuery, false)
            compare(panel.ownsOperation, false)
        }

        function test_sixExactNumbersAndAtomicApply() {
            panel.setDraftValue("kp", 0.101)
            verify(panel.canApply)
            mouseClick(control("thc-live-apply"))
            tryCompare(mock, "applyCalls", 1)
            compare(Object.keys(mock.applied).sort().join(","), "cq,fs,kd,ki,kp,rate")
            for (const key of Object.keys(mock.applied)) compare(typeof mock.applied[key], "number")
            compare(mock.applied.kp, 0.101)
            compare(mock.startCalls, 0)
            compare(mock.heartbeatCalls, 0)
            compare(mock.cancelCalls, 0)
            compare(mock.operationId, 41)
        }

        function test_factorySnapshotExactAndBounded() {
            const expected = { kp: 0.15, ki: 0.02, kd: 0.03,
                rate: 0.010, cq: 0.010, fs: 0.050 }
            compare(Object.keys(panel.factoryDefaults).sort().join(","), "cq,fs,kd,ki,kp,rate")
            for (const key of Object.keys(expected)) compare(panel.factoryDefaults[key], expected[key])
            verify(Object.isFrozen(panel.factoryDefaults))
            verify(panel.validValues(panel.factoryDefaults))
            verify(control("thc-live-default-note").text.indexOf("not firmware") >= 0)
            verify(control("thc-live-range-warning").text.indexOf("requires firmware v2") >= 0)
        }

        function test_v2DefaultsAreSweepWinner() {
            const expected = { kp: 0.45, ki: 0.02, kd: 0.06,
                rate: 0.003, cq: 0.010, fs: 0.050 }
            mock.thcLiveTuningExtended = true
            compare(panel.extendedRanges, true)
            compare(panel.factoryDefaults, panel.sweepDefaults)
            for (const key of Object.keys(expected)) compare(panel.factoryDefaults[key], expected[key])
            verify(Object.isFrozen(panel.sweepDefaults))
            verify(panel.validValues(panel.factoryDefaults))
            verify(control("thc-live-default-note").text.indexOf("set B") >= 0)
            verify(control("thc-live-default-note").text.indexOf("not firmware") >= 0)
            mock.thcLiveTuningExtended = false
            compare(panel.factoryDefaults, panel.legacyFactoryDefaults)
        }

        function test_resetEachFieldDraftOnly_data() {
            return [{ tag: "kp", key: "kp", expected: 0.15 },
                { tag: "ki", key: "ki", expected: 0.02 },
                { tag: "kd", key: "kd", expected: 0.03 },
                { tag: "rate", key: "rate", expected: 0.010 },
                { tag: "cq", key: "cq", expected: 0.010 },
                { tag: "fs", key: "fs", expected: 0.050 }]
        }

        function test_resetEachFieldDraftOnly(data) {
            panel.setDraftValue("ki", 0.0123) // Existing dirty edits survive other resets.
            panel.setDraftValue("cq", 0.015) // Every tested field differs from factory.
            const original = Object.assign({}, panel.draft)
            const untouched = resetSideEffectsSnapshot()
            const button = control("thc-live-default-" + data.key)
            verify(button.enabled)
            verify(button.width >= 38 && button.height >= 38)
            clickScrolledControl(button.objectName)
            for (const key of Object.keys(original))
                compare(panel.draft[key], key === data.key ? data.expected : original[key])
            compare(panel.draftDirty, true)
            compare(panel.canStart, false)
            compare(panel.canApply, true)
            compare(resetSideEffectsSnapshot(), untouched)
            panel.loadConfirmedDraft()
            compare(panel.draft[data.key], data.expected)
        }

        function test_resetAllRepairsInvalidDraftAndRequiresExplicitAtomicApply() {
            panel.setDraftValue("cq", 0.02)
            panel.setDraftValue("fs", 0.02)
            compare(panel.draftValid, false)
            const original = panel.draft
            const confirmed = JSON.stringify(mock.thcLiveTuning)
            const untouched = resetSideEffectsSnapshot()
            clickScrolledControl("thc-live-default-all")
            compare(panel.draftDirty, true)
            verify(panel.draft !== original && panel.draft !== panel.factoryDefaults)
            compare(Object.keys(panel.draft).sort().join(","), "cq,fs,kd,ki,kp,rate")
            for (const key of Object.keys(panel.factoryDefaults))
                compare(panel.draft[key], panel.factoryDefaults[key])
            verify(panel.draftValid)
            verify(panel.canApply)
            compare(panel.canStart, false)
            compare(resetSideEffectsSnapshot(), untouched)
            verify(waitForRendering(panel.contentItem))
            grabImage(testSurface).save("thc-defaults-draft-" + Qt.platform.pluginName + ".png")

            mock.deferApplyAck = true
            mouseClick(control("thc-live-apply"))
            compare(mock.applyCalls, 1)
            compare(JSON.stringify(mock.applied), JSON.stringify(panel.factoryDefaults))
            compare(JSON.stringify(mock.thcLiveTuning), confirmed) // Not ACKed yet.
            compare(panel.pending, true)
            compare(panel.canApply, false)
            compare(panel.canStart, false)
            compare(panel.canResetDraft, false)
            const pendingDraft = JSON.stringify(panel.draft)
            verify(!panel.resetDraftDefaults())
            verify(!panel.resetDraftField("kp"))
            compare(JSON.stringify(panel.draft), pendingDraft)
            compare(mock.applyCalls, 1)
            mock.thcLiveTuningPending = false
            mock.thcLiveTuning = Object.assign({}, mock.applied, { revision: 8 })
            compare(panel.requested.revision, 8)
            compare(panel.draftDirty, false)
            compare(mock.startCalls, 0)
            compare(mock.homeCalls, 0)
            compare(mock.heartbeatCalls, 0)
            compare(mock.cancelCalls, 0)
        }

        function test_matchingDefaultsStillNeedApplyAndUnknownKeyIsNoOp() {
            mock.thcLiveTuning = Object.assign({}, panel.factoryDefaults, { revision: 8 })
            compare(panel.draftDirty, false)
            const initialDraft = JSON.stringify(panel.draft)
            verify(!panel.resetDraftField("revision"))
            compare(JSON.stringify(panel.draft), initialDraft)
            compare(panel.draftDirty, false)
            verify(panel.resetDraftField("kp"))
            compare(panel.draftDirty, true)
            compare(panel.canStart, false)
            verify(panel.canApply)
            panel.draftDirty = false
            verify(panel.resetDraftDefaults())
            compare(panel.draftDirty, true)
            verify(panel.canApply)
            compare(mock.applyCalls, 0)
        }

        function test_defaultsTouchControlsRemainReachable_data() {
            return [{ tag: "nominal", w: 950, h: 600 },
                { tag: "manual", w: 840, h: 600 },
                { tag: "compact", w: 616, h: 456 }]
        }

        function test_defaultsTouchControlsRemainReachable(data) {
            panel.width = data.w
            panel.height = data.h
            const untouched = resetSideEffectsSnapshot()
            clickScrolledControl("thc-live-default-all")
            for (const field of panel.fields) {
                const button = control("thc-live-default-" + field.key)
                verify(button.width >= 38 && button.height >= 38)
                clickScrolledControl(button.objectName)
                compare(panel.draft[field.key], panel.factoryDefaults[field.key])
            }
            verify(panel.canApply)
            compare(resetSideEffectsSnapshot(), untouched)
            const stop = control("thc-live-stop")
            const position = stop.mapToItem(panel.contentItem, 0, 0)
            verify(position.y + stop.height <= panel.contentItem.height)
            compare(panel.contentItem.scale, 1)
        }

        function test_resetRepairsFsCqRelationship_data() {
            return [{ tag: "cq", key: "cq", expected: 0.010 },
                { tag: "fs", key: "fs", expected: 0.050 }]
        }

        function test_resetRepairsFsCqRelationship(data) {
            panel.setDraftValue("cq", 0.02)
            panel.setDraftValue("fs", 0.02)
            compare(panel.draftValid, false)
            verify(panel.resetDraftField(data.key))
            compare(panel.draft[data.key], data.expected)
            verify(panel.draft.fs > panel.draft.cq)
            verify(panel.canApply)
            compare(mock.applyCalls, 0)
        }

        function test_resetGuards_data() {
            return ["pending", "confirmation", "offline", "unsupported", "error",
                "not-homed", "stale", "other-owner", "hidden", "stop-unconfirmed"]
                .map(function(tag) { return { tag: tag } })
        }

        function test_resetGuards(data) {
            if (data.tag === "pending") mock.thcLiveTuningPending = true
            else if (data.tag === "confirmation") verify(panel.requestStart())
            else if (data.tag === "offline") panel.offline = true
            else if (data.tag === "unsupported") mock.thcLiveTuningSupported = false
            else if (data.tag === "error") mock.thcLiveTuningError = "V53_ACK_MISMATCH"
            else if (data.tag === "not-homed") mock.pressHomed = false
            else if (data.tag === "stale") mock.pressTelemetryFresh = false
            else if (data.tag === "other-owner") mock.startContinuousThcContactProfile()
            else if (data.tag === "hidden") panel.intendedVisible = false
            else if (data.tag === "stop-unconfirmed") mock.pressSafetyStopUnconfirmed = true
            compare(panel.canResetDraft, false)
            compare(control("thc-live-default-all").enabled, false)
            const draft = JSON.stringify(panel.draft)
            const dirty = panel.draftDirty
            const untouched = resetSideEffectsSnapshot()
            verify(!panel.resetDraftDefaults())
            for (const field of panel.fields) {
                compare(control("thc-live-default-" + field.key).enabled, false)
                verify(!panel.resetDraftField(field.key))
            }
            compare(JSON.stringify(panel.draft), draft)
            compare(panel.draftDirty, dirty)
            compare(resetSideEffectsSnapshot(), untouched)
        }

        function test_resetOwnedHoldPreservesOwnerLeaseAckEffectiveAndHistory() {
            startOwned()
            verify(!panel.canResetDraft) // Acquisition is not HOLD.
            verify(!panel.resetDraftDefaults())
            mock.thcCommissioningState = "HOLDING"
            mock.thcLiveDiagnostics = { effective: { kp: 0.09, ki: 0.008, kd: 0.004,
                rate: 0.004, cq: 0.006, fs: 0.03, revision: 7 } }
            mock.pressTelemetrySequence++
            const ownerBackend = panel.ownerBackend
            const untouched = resetSideEffectsSnapshot()
            verify(panel.resetDraftDefaults())
            verify(panel.resetDraftField("fs"))
            compare(resetSideEffectsSnapshot(), untouched)
            compare(panel.ownerBackend, ownerBackend)
            verify(panel.ownsOperation)
            verify(panel.renewing)
            compare(panel.requested.kp, 0.1)
            compare(panel.effective.kp, 0.09)
            compare(panel.draft.kp, 0.15)
            mock.thcCommissioningState = "RELEASING"
            verify(!panel.resetDraftField("kp"))
            verify(!panel.resetDraftDefaults())
            verify(control("thc-live-stop").enabled)
        }

        function test_extendedRangesRequireNegotiationAndExplicitApply() {
            compare(panel.extendedRanges, false)
            panel.setDraftValue("kp", 3)
            compare(panel.draftValid, false)
            mock.thcLiveTuningExtended = true
            compare(panel.extendedRanges, true)
            compare(panel.draftValid, true)
            verify(panel.outsideOriginalRange(panel.fields[0]))
            compare(control("thc-live-kp").visible, false)
            compare(control("thc-live-extended-kp").visible, true)
            panel.setDraftText("ki", "2.500000")
            panel.setDraftText("kd", "1.200000")
            panel.setDraftText("rate", "0.000000")
            panel.setDraftText("cq", "0.000000")
            panel.setDraftText("fs", "0.000001")
            verify(panel.canApply)
            compare(mock.applyCalls, 0)
            verify(panel.applyDraft())
            compare(mock.applyCalls, 1)
            compare(mock.applied.kp, 3)
            compare(mock.applied.rate, 0)
            compare(mock.applied.fs, 0.000001)
            compare(mock.startCalls, 0)
            compare(mock.heartbeatCalls, 0)
            compare(mock.homeCalls, 0)
            mock.thcLiveTuningSupported = false
            compare(panel.extendedRanges, false)
            compare(panel.canApply, false)
        }

        function test_extendedInvalidText_data() {
            return ["", "-1", "NaN", "Infinity", "1e9", "1000000000", "0.0000001", "1,2"]
                .map(function(value) { return { tag: value || "empty", value: value } })
        }

        function test_extendedInvalidText(data) {
            mock.thcLiveTuningExtended = true
            panel.setDraftText("kp", data.value)
            compare(panel.canApply, false)
            compare(panel.draftDirty, true)
            verify(!panel.applyDraft())
            compare(mock.applyCalls, 0)
            verify(panel.resetDraftField("kp"))
            verify(panel.canApply)
        }

        function test_extendedPrecisionAndTechnicalBoundary() {
            mock.thcLiveTuningExtended = true
            panel.setDraftText("kp", "999999999.999999")
            verify(panel.canApply)
            panel.stepDraft(panel.fields[0], 1)
            compare(panel.draft.kp, panel.technicalMaximum)
            panel.setDraftValue("cq", 0.0000011)
            panel.setDraftValue("fs", 0.0000012)
            compare(panel.draftValid, false)
            panel.setDraftText("cq", "0.000000")
            panel.setDraftText("fs", "0.000001")
            verify(panel.canApply)
            panel.setDraftText("kp", "0")
            panel.stepDraft(panel.fields[0], -1)
            compare(panel.draft.kp, 0)
            verify(panel.canApply)
        }

        function test_extendedEditorRejectsIncompleteInputImmediately() {
            mock.thcLiveTuningExtended = true
            clickScrolledControl("thc-live-extended-kp")
            const input = control("thc-live-extended-kp")
            input.forceActiveFocus()
            keyClick(Qt.Key_A, Qt.ControlModifier)
            keyClick(Qt.Key_Backspace)
            compare(panel.draftValid, false)
            keyClick(Qt.Key_2)
            compare(panel.draft.kp, 2)
            verify(panel.canApply)
            verify(panel.outsideOriginalRange(panel.fields[0]))
            compare(mock.applyCalls, 0)
        }

        function test_extendedFocusKeepsVisibleValueAndTouchEntryWorks() {
            mock.thcLiveTuningExtended = true
            panel.setDraftValue("kp", 2.5)
            const input = control("thc-live-extended-kp")
            tryCompare(input, "text", "2.500000")
            input.forceActiveFocus()
            compare(input.text, "2.500000")
            compare(Number(input.text), panel.draft.kp)
            clickScrolledControl("thc-live-keypad-kp")
            for (const key of ["1", "2", ".", "3", "4", "5", "6", "7", "8"])
                clickScrolledControl("thc-live-key-kp-" + key)
            compare(input.text, "12.345678")
            compare(panel.draft.kp, 12.345678)
            compare(mock.applyCalls, 0)
            verify(waitForRendering(panel.contentItem))
            grabImage(testSurface).save("thc-extended-keypad-" + Qt.platform.pluginName + ".png")
            clickScrolledControl("thc-live-keypad-kp")
            verify(panel.canApply)
            verify(panel.applyDraft())
            compare(mock.applied.kp, 12.345678)
            compare(mock.startCalls, 0)
            compare(mock.heartbeatCalls, 0)
        }

        function test_boundsAndSteps_data() {
            return [
                { tag: "kp", key: "kp", min: 0, max: 3000, step: 10 },
                { tag: "ki", key: "ki", min: 0, max: 400, step: 1 },
                { tag: "kd", key: "kd", min: 0, max: 600, step: 5 },
                { tag: "rate", key: "rate", min: 20, max: 100, step: 1 },
                { tag: "cq", key: "cq", min: 50, max: 200, step: 10 },
                { tag: "fs", key: "fs", min: 200, max: 1000, step: 10 }
            ]
        }

        function test_boundsAndSteps(data) {
            const spin = control("thc-live-" + data.key)
            compare(spin.from, data.min)
            compare(spin.to, data.max)
            compare(spin.stepSize, data.step)
            verify(spin.up.indicator.width >= 38)
            verify(spin.down.indicator.width >= 38)
            const original = panel.draft[data.key]
            spin.forceActiveFocus()
            keyClick(Qt.Key_Up)
            fuzzyCompare(panel.draft[data.key], original + data.step / 10000, 0.0000001)
            keyClick(Qt.Key_Down)
            fuzzyCompare(panel.draft[data.key], original, 0.0000001)
            const invalid = Object.assign({}, panel.draft)
            invalid[data.key] = data.min / 10000
            panel.draft = Object.assign({}, invalid)
            compare(panel.draftValid, true)
            invalid[data.key] = data.max / 10000
            panel.draft = Object.assign({}, invalid)
            compare(panel.draftValid, true)
            invalid[data.key] = data.min / 10000 - 0.0001
            panel.draft = Object.assign({}, invalid)
            compare(panel.draftValid, false)
            compare(panel.canApply, false)
            invalid[data.key] = data.max / 10000 + 0.0001
            panel.draft = Object.assign({}, invalid)
            compare(panel.draftValid, false)
            compare(panel.canApply, false)
            invalid[data.key] = "0.01"
            panel.draft = Object.assign({}, invalid)
            compare(panel.draftValid, false)
        }

        function test_fsStrictlyGreaterThanCqAndDraftRemainsRepairable() {
            panel.setDraftValue("cq", 0.02)
            panel.setDraftValue("fs", 0.02)
            compare(panel.draftValid, false)
            compare(panel.canApply, false)
            verify(control("thc-live-fs").enabled)
            control("thc-live-fs").forceActiveFocus()
            keyClick(Qt.Key_Up)
            compare(panel.draft.fs, 0.021)
            compare(panel.draftValid, true)
            compare(panel.canApply, true)
        }

        function test_pendingAndErrorBlockTuningNotOwnerStop() {
            startOwned()
            mock.thcCommissioningState = "HOLDING"
            panel.setDraftValue("ki", 0.0101)
            mock.thcLiveTuningPending = true
            compare(panel.canApply, false)
            compare(control("thc-live-kp").enabled, false)
            verify(control("thc-live-release").enabled)
            verify(control("thc-live-stop").enabled)
            mock.thcLiveTuningPending = false
            mock.thcLiveTuningError = "V53_ACK_MISMATCH"
            compare(panel.canTune, false)
            verify(control("thc-live-stop").enabled)
            mouseClick(control("thc-live-stop"))
            tryCompare(mock, "cancelCalls", 1)
            tryCompare(panel, "renewing", false)
            verify(control("thc-live-status").text.indexOf("STOP UNCONFIRMED") >= 0)
        }

        function test_confirmedStartAndIdleHoldAcquisitionGuards() {
            compare(panel.canTune, true)
            mock.pressHomed = false
            compare(panel.canTune, false)
            compare(panel.canStart, false)
            mock.pressHomed = true
            mouseClick(control("thc-live-start"))
            tryCompare(panel, "confirmationVisible", true)
            mouseClick(control("thc-live-confirm-back"))
            tryCompare(panel, "confirmationVisible", false)
            compare(mock.startCalls, 0)
            startOwned()
            compare(panel.canTune, false)
            mock.thcCommissioningState = "CONTACT"
            compare(panel.canTune, false)
            mock.thcCommissioningState = "HOLDING"
            compare(panel.canTune, true)
            mock.pressTelemetryFresh = false
            compare(panel.canTune, false)
            mock.pressTelemetryFresh = true
            mock.thcCommissioningState = "RELEASING"
            compare(panel.canTune, false)
            verify(control("thc-live-stop").enabled)
        }

        function test_confirmationCannotBypassChangedAdmission() {
            verify(panel.requestStart())
            mock.antiBind = true
            compare(panel.confirmationVisible, false)
            verify(!panel.confirmStart())
            compare(mock.startCalls, 0)
            mock.antiBind = false
            mock.operationName = "home"
            mock.commandOperationActive = true
            mock.pressOperationActive = true
            compare(panel.canStart, false)
            compare(panel.canTune, false)
            panel.close()
            compare(mock.cancelCalls, 0)
        }

        function test_desiredAndEffectiveNotConflatedOrInvented() {
            startOwned()
            mock.thcCommissioningState = "HOLDING"
            mock.thcLiveDiagnostics = { force: 0.999, request: 0.0021, velocity: 0.003,
                p: 0.001, i: 0.0002, d: 0, ha: 0.0035,
                effective: { revision: 8, effectiveRevision: 7, rampMs: 500, hold: 1,
                    kp: 0.099, ki: 0.009, kd: 0.004, rate: 0.005, cq: 0.01, fs: 0.04 } }
            compare(panel.requested.revision, 7)
            compare(panel.effective.revision, 8)
            compare(panel.effective.effectiveRevision, 7)
            compare(panel.effective.rampMs, 500)
            compare(panel.numericText(panel.effective, "kp", 3), "0.099")
            const label = control("thc-live-diagnostics")
            verify(label.text.indexOf("0.999 T") >= 0)
            verify(label.text.indexOf("commanded velocity 0.0030 IPM") >= 0)
            verify(label.text.indexOf("NOT bootstrap") >= 0)
            verify(label.text.indexOf("NOT measured speed") >= 0)
            mock.pressTelemetryFresh = false
            compare(panel.numericText(panel.diagnostics, "force", 3), "—")
            compare(panel.numericText(panel.effective, "kp", 3), "—")
        }

        function test_activeSurfaceRenewsAndHiddenCancels() {
            startOwned()
            const calls = mock.heartbeatCalls
            tryVerify(function() { return mock.heartbeatCalls > calls }, 1000)
            panel.intendedVisible = false
            tryVerify(function() { return mock.cancelCalls > 0 })
            compare(panel.renewing, false)
            const stoppedCalls = mock.heartbeatCalls
            wait(450)
            compare(mock.heartbeatCalls, stoppedCalls)
        }

        function test_windowForegroundLossCancelsAndNeverResumes() {
            if (Qt.platform.pluginName === "offscreen")
                skip("Offscreen platform has no exclusive foreground; run the windows surface CTest.")
            startOwned()
            const window = panel.hostWindow
            // A second same-app window is blocked by the modal. Minimize the
            // actual host to exercise its real active notification instead.
            window.showMinimized()
            tryCompare(panel, "surfaceActive", false)
            tryVerify(function() { return mock.cancelCalls > 0 })
            window.showNormal()
            window.requestActivate()
            tryCompare(panel, "surfaceActive", true)
            compare(panel.renewing, false)
        }

        function test_closeAndEscapeCancel_data() {
            return [{ tag: "close", escape: false }, { tag: "escape", escape: true }]
        }

        function test_closeAndEscapeCancel(data) {
            startOwned()
            if (data.escape) {
                control("thc-live-stop").forceActiveFocus()
                keyClick(Qt.Key_Escape)
            } else mouseClick(control("thc-live-close"))
            tryCompare(panel, "opened", false)
            tryVerify(function() { return mock.cancelCalls > 0 })
            compare(panel.renewing, false)
        }

        function test_destroyCancelsExactOwner() {
            startOwned()
            panel.destroy()
            panel = null
            tryVerify(function() { return mock.cancelCalls > 0 })
        }

        function test_navigationUnloadsAndCancelsExactOwner() {
            panel.close()
            const loader = createTemporaryObject(navigationComponent, testSurface, { testBackend: mock })
            verify(!!loader, "Component exists")
            tryCompare(loader, "status", Loader.Ready)
            panel = loader.item
            tryCompare(panel, "surfaceActive", true)
            if (!panel.supported) panel.queryCapability()
            startOwned()
            loader.active = false
            panel = null
            tryCompare(loader, "item", null)
            tryVerify(function() { return mock.cancelCalls > 0 })
        }

        function test_laterHomeAndOrdinaryAutoUntouched_data() {
            return [{ tag: "home", name: "home" },
                { tag: "ordinary-auto", name: "automatic-thc-contact-profile" },
                { tag: "later-v53", name: "thc-contact-profile-v53" }]
        }

        function test_laterHomeAndOrdinaryAutoUntouched(data) {
            startOwned()
            ++mock.operationId
            mock.operationName = data.name
            mock.thcContinuousActive = data.tag === "later-v53"
            mock.commandLifecycleChanged()
            compare(panel.ownsOperation, false)
            compare(panel.renewing, false)
            panel.intendedVisible = false
            panel.close()
            compare(mock.cancelCalls, 0)
            compare(mock.releaseCalls, 0)
            compare(mock.operationName, data.name)
        }

        function test_synchronousStartHideCancelsOriginalOnly() {
            mock.startHook = function() { panel.intendedVisible = false }
            verify(panel.requestStart())
            verify(!panel.confirmStart())
            verify(mock.cancelCalls > 0)
            compare(panel.renewing, false)
        }

        function test_synchronousStartReplacementCannotCaptureOrCancelHome() {
            mock.startHook = function() { mock.replaceWithHome(); panel.intendedVisible = false }
            verify(panel.requestStart())
            verify(!panel.confirmStart())
            compare(panel.ownsOperation, false)
            compare(mock.cancelCalls, 0)
            compare(mock.operationName, "home")
        }

        function test_reentrantLaterV53CannotBeAdopted() {
            mock.startHook = function() {
                ++mock.operationId
                mock.operationName = "thc-contact-profile-v53"
                mock.thcContinuousActive = true
                mock.commandLifecycleChanged()
            }
            verify(panel.requestStart())
            verify(!panel.confirmStart())
            compare(panel.ownsOperation, false)
            compare(mock.cancelCalls, 0)
            compare(mock.heartbeatCalls, 0)
        }

        function test_newPanelNeverAdoptsAnExistingV53Owner() {
            panel.close()
            mock.startContinuousThcContactProfile()
            panel.open()
            tryCompare(panel, "opened", true)
            compare(panel.ownsOperation, false)
            compare(panel.renewing, false)
            compare(control("thc-live-stop").enabled, false)
            panel.close()
            compare(mock.cancelCalls, 0)
            compare(mock.heartbeatCalls, 0)
        }

        function test_stopUnconfirmedPersistsAfterTerminalOwner() {
            startOwned()
            panel.cancelOwned()
            mock.commandOperationActive = false
            mock.thcContinuousActive = false
            mock.thcCommissioningState = "FAILED_STOP_UNCONFIRMED"
            mock.operationError = "THC_V53_CANCEL_CONFIRMATION_TIMEOUT"
            verify(panel.stopUnconfirmed)
            verify(control("thc-live-status").text.indexOf("STOP UNCONFIRMED") >= 0)
            compare(panel.canStart, false)
            compare(panel.canTune, false)
            compare(panel.renewing, false)
        }

        function test_authoritativeLatchOverridesOnlyHistoricalPresentation_data() {
            return [{ tag: "terminal-unconfirmed", state: "FAILED_STOP_UNCONFIRMED" },
                { tag: "cancelling-history", state: "CANCELLING" }]
        }

        function test_authoritativeLatchOverridesOnlyHistoricalPresentation(data) {
            mock.thcCommissioningState = data.state
            mock.pressSafetyStopUnconfirmed = true
            compare(panel.stopUnconfirmed, true)
            compare(panel.canQuery, false)
            compare(panel.canTune, false)
            compare(panel.canStart, false)
            mock.pressSafetyStopUnconfirmed = false
            compare(mock.thcCommissioningState, data.state)
            compare(panel.stopUnconfirmed, false)
            compare(panel.canQuery, true)
            const queries = mock.queryCalls
            verify(panel.queryCapability())
            compare(mock.queryCalls, queries + 1)
            compare(mock.cancelCalls, 0)
            compare(mock.homeCalls, 0)
        }

        function test_missingLatchApiFailsClosed() {
            const legacy = Object.assign({}, mock, { pressSafetyStopUnconfirmed: undefined })
            panel.backend = legacy
            compare(panel.apiAvailable, false)
            compare(panel.stopUnconfirmed, true)
            compare(panel.canQuery, false)
            compare(panel.canTune, false)
            compare(panel.canStart, false)
            verify(!panel.queryCapability())
            compare(mock.cancelCalls, 0)
            compare(mock.homeCalls, 0)
        }

        function test_unconfirmedStopHomeRecoveryAndNavigationNeverRecancel() {
            startOwned()
            verify(panel.cancelOwned())
            compare(mock.cancelCalls, 1)
            verify(!panel.cancelOwned())
            mock.commandOperationActive = false
            mock.pressOperationActive = false
            mock.thcContinuousActive = false
            mock.operationState = "FAILED"
            mock.thcCommissioningState = "FAILED_STOP_UNCONFIRMED"
            compare(panel.canQuery, false)
            mock.replaceWithHome() // Explicit user Home, not a panel method.
            compare(mock.pressSafetyStopUnconfirmed, true)
            compare(panel.ownsOperation, false)
            compare(panel.renewing, false)
            compare(panel.canQuery, false)
            panel.intendedVisible = false
            panel.close()
            compare(mock.cancelCalls, 1)
            compare(mock.homeCalls, 1)
            compare(mock.operationName, "home")
            mock.pressMachineState = "HOMING"
            compare(mock.pressSafetyStopUnconfirmed, true)
            mock.pressMachineState = "IDLE"
            mock.pressHomed = true
            mock.commandOperationActive = false
            mock.pressOperationActive = false
            mock.operationState = "COMPLETED"
            mock.pressSafetyStopUnconfirmed = false // Only after scripted Home progress + fresh IDLE.
            compare(mock.thcCommissioningState, "FAILED_STOP_UNCONFIRMED")
            compare(panel.stopUnconfirmed, false)
            panel.intendedVisible = true
            panel.open()
            tryCompare(panel, "surfaceActive", true)
            compare(panel.canQuery, true)
            verify(panel.queryCapability())
            compare(mock.cancelCalls, 1)
            compare(mock.homeCalls, 1)
        }

        function test_multipleCleanupCallbacksCancelExactOwnerOnlyOnce() {
            startOwned()
            panel.intendedVisible = false
            panel.close()
            panel.cancelOwned()
            panel.destroy()
            panel = null
            tryCompare(mock, "cancelCalls", 1)
            compare(mock.homeCalls, 0)
        }

        function test_synchronousHeartbeatReplacementCannotCancelHome() {
            startOwned()
            mock.heartbeatHook = function() { mock.replaceWithHome(); return false }
            verify(!panel.renewLease())
            compare(mock.cancelCalls, 0)
            compare(mock.operationName, "home")
            compare(panel.renewing, false)
        }

        function test_releaseDoesNotResetOrRestartAndStopRemainsAvailable() {
            startOwned()
            mock.thcCommissioningState = "HOLDING"
            const id = mock.operationId
            mouseClick(control("thc-live-release"))
            tryCompare(mock, "releaseCalls", 1)
            compare(mock.operationId, id)
            compare(mock.startCalls, 1)
            compare(mock.applyCalls, 0)
            compare(panel.canTune, false)
            verify(control("thc-live-stop").enabled)
        }

        function test_backendReplacementCancelsOldV53NeverNewHome() {
            startOwned()
            const replacement = createTemporaryObject(backendComponent, testSurface)
            verify(!!replacement, "Object exists")
            replacement.replaceWithHome()
            panel.backend = replacement
            verify(mock.cancelCalls > 0)
            compare(replacement.cancelCalls, 0)
            compare(replacement.operationName, "home")
            compare(panel.ownsOperation, false)
        }

        function test_manualEntryLazyAndOrdinaryUiPreserved() {
            panel.close()
            const state = createTemporaryObject(stateComponent, testSurface)
            verify(!!state, "Object exists")
            const view = createTemporaryObject(manualComponent, testSurface, { appState: state })
            verify(!!view, "Component exists")
            const loader = findChild(view, "manual-thc-live-loader")
            verify(!!loader, "Object exists")
            compare(loader.active, false)
            compare(loader.item, null)
            const autoButton = findChild(view, "button-automatic-tonnage-hold")
            const pedalButton = findChild(view, "button-tonnage-hold button-tonnage-hold-active")
            verify(!!autoButton, "Object exists")
            verify(!!pedalButton, "Object exists")
            compare(autoButton.label, "AUTO")
            compare(pedalButton.label, "PEDAL")
            const entry = findChild(view, "button-thc-live-fine-tune")
            verify(!!entry, "Object exists")
            verify(entry.height >= 48)
            waitForRendering(view)
            mouseClick(entry)
            tryCompare(loader, "active", true)
            tryCompare(loader, "status", Loader.Ready)
            compare(loader.item.backend, null)
            compare(loader.item.offline, true)
            compare(loader.item.canStart, false)
            view.visible = false
            tryCompare(loader, "active", false)
            tryCompare(loader, "item", null)
            compare(state.contactProfileActive, false)
            compare(state.tonnageHoldActive, false)
        }

        function test_touchActionsFitAndRemainVisible_data() {
            return [{ tag: "requested-screen", w: 1280, h: 800 },
                { tag: "actual-app", w: 1366, h: 768 },
                { tag: "manual-viewport", w: 864, h: 638 },
                { tag: "compact", w: 640, h: 480 }]
        }

        function test_touchActionsFitAndRemainVisible(data) {
            panel.width = data.w
            panel.height = data.h
            waitForRendering(panel.contentItem)
            for (const name of ["thc-live-close", "thc-live-query", "thc-live-apply",
                    "thc-live-start", "thc-live-release", "thc-live-stop"]) {
                const button = control(name)
                verify(button.width >= 38)
                verify(button.height >= 38)
                const position = button.mapToItem(panel.contentItem, 0, 0)
                verify(position.x >= 0)
                verify(position.y >= 0)
                verify(position.x + button.width <= panel.contentItem.width + 1)
                verify(position.y + button.height <= panel.contentItem.height + 1)
            }
            verify(panel.requestStart())
            for (const name of ["thc-live-confirm-back", "thc-live-confirm-start"]) {
                const button = control(name)
                verify(button.height >= 48)
                const position = button.mapToItem(panel.contentItem, 0, 0)
                verify(position.y + button.height <= panel.contentItem.height + 1)
            }
        }

        function test_centeredModalAdaptsWithoutScalingTouchTargets_data() {
            return [{ tag: "app", w: 1366, h: 768, modalW: 950, modalH: 600 },
                { tag: "manual", w: 864, h: 638, modalW: 840, modalH: 600 },
                { tag: "compact", w: 640, h: 480, modalW: 616, modalH: 456 }]
        }

        function test_centeredModalAdaptsWithoutScalingTouchTargets(data) {
            const viewport = createTemporaryObject(viewportComponent, testSurface, { width: data.w, height: data.h })
            verify(!!viewport, "Object exists")
            panel.parent = viewport
            verify(waitForItemPolished(panel.contentItem))
            compare(panel.modal, true)
            compare(panel.width, data.modalW)
            compare(panel.height, data.modalH)
            fuzzyCompare(panel.x, (data.w - data.modalW) / 2, 0.01)
            fuzzyCompare(panel.y, (data.h - data.modalH) / 2, 0.01)
            compare(panel.contentItem.scale, 1)
            verify(control("thc-live-stop").height >= 38)
            verify(control("thc-live-kp").up.indicator.width >= 38)
        }

        function test_realTelemetryAndUnavailableValuesNeverUseDiagnosticsAsRpm() {
            const history = findChild(panel, "thc-live-telemetry-history")
            verify(!!history, "Object exists")
            compare(history.samples.length, 0)
            mock.pressTelemetrySequence++
            compare(history.samples.length, 1)
            compare(history.totalLoad, 1)
            verify(control("thc-live-load-total").text.indexOf("LIVE 1.000 T") >= 0)
            verify(control("thc-live-load-channels").text.indexOf("Y1 LOAD 0.400 T") >= 0)
            compare(control("thc-live-rpm-y1").text, "1420 RPM")
            compare(control("thc-live-rpm-y2").text, "1418 RPM")
            verify(control("thc-live-motor-unavailable-y1").text.indexOf("Target — · Temp — · Torque —") >= 0)
            verify(control("thc-live-motor-unavailable-y2").text.indexOf("Not available from controller") >= 0)
            mock.thcLiveDiagnostics = { velocity: 1234, force: 5 }
            mock.motorRpmAvailable = false
            compare(control("thc-live-rpm-y1").text, "— RPM")
            compare(history.totalLoad, 1)
            mock.pressTelemetryFresh = false
            compare(history.totalLoad, null)
            verify(control("thc-live-load-total").text.indexOf("LIVE — T") >= 0)
            compare(history.samples[history.samples.length - 1].gap, true)
            mock.pressTelemetryFresh = true
            mock.pressTelemetrySequence++
            compare(history.seriesSegments.length, 2)
            mock.independentRamTelemetryAvailable = false
            compare(history.loadY1, null)
            compare(history.totalLoad, null)
            panel.offline = true
            compare(history.rpmY1, null)
            panel.backend = null
            compare(history.samples.length, 0)
        }

        function test_visualEvidenceFixtures_data() {
            return [{ tag: "populated", compact: false, gap: false, confirmation: false },
                { tag: "gap-stale", compact: false, gap: true, confirmation: false },
                { tag: "confirmation", compact: false, gap: false, confirmation: true },
                { tag: "compact", compact: true, gap: false, confirmation: false }]
        }

        function test_visualEvidenceFixtures(data) {
            const history = findChild(panel, "thc-live-telemetry-history")
            verify(!!history, "Object exists")
            const at = Date.now()
            const values = []
            for (let i = 0; i < 59; ++i) {
                if (data.gap && i >= 24 && i <= 33) {
                    if (i === 24) values.push({ at: at - (58 - i) * 1000, gap: true })
                    continue
                }
                values.push({ at: at - (58 - i) * 1000,
                    total: 1 + 0.08 * Math.sin(i / 4), breakBefore: i === 0 || (data.gap && i === 34) })
            }
            history.samples = values
            history.nowMs = at
            if (data.gap) mock.pressTelemetryFresh = false
            compare(history.seriesSegments.length, data.gap ? 2 : 1)
            if (data.confirmation) verify(panel.requestStart())
            if (data.compact) {
                panel.width = 616
                panel.height = 456
            } else {
                compare(panel.width, 950)
                compare(panel.height, 600)
            }
            verify(waitForItemPolished(panel.contentItem))
            verify(waitForRendering(panel.contentItem))
            compare(mock.startCalls, 0)
            compare(mock.homeCalls, 0)
            compare(mock.cancelCalls, 0)
            compare(panel.contentItem.scale, 1)
            for (const name of ["thc-live-close", "thc-live-query", "thc-live-apply",
                    "thc-live-start", "thc-live-release", "thc-live-stop"]) {
                const button = control(name)
                verify(button.height >= 38)
                const position = button.mapToItem(panel.contentItem, 0, 0)
                verify(position.y + button.height <= panel.contentItem.height + 1)
            }
            // Relative output follows the runner's working directory, never
            // the source tree. Separate Windows/offscreen evidence is retained.
            const output = "thc-modal-mock-" + Qt.platform.pluginName + "-" + data.tag + ".png"
            const image = grabImage(testSurface)
            verify(image.width > 0 && image.height > 0, "Nonempty rendered viewport")
            // QtTest's image.save() returns void; artifact existence/decoding
            // is checked by the evidence review, not a fabricated bool result.
            image.save(output)
        }

        function test_confirmationDisablesUnderlyingKeyboardAndPreservesHistory() {
            const history = findChild(panel, "thc-live-telemetry-history")
            verify(!!history, "Object exists")
            mock.pressTelemetrySequence++
            compare(history.samples.length, 1)
            verify(panel.requestStart())
            compare(control("thc-live-kp").enabled, false)
            compare(control("thc-live-apply").enabled, false)
            const draft = panel.draft.kp
            panel.setDraftValue("kp", 0.2)
            compare(panel.draft.kp, draft)
            compare(mock.startCalls, 0)
            mouseClick(control("thc-live-confirm-back"))
            tryCompare(panel, "confirmationVisible", false)
            compare(history.samples.length, 1)
            panel.setDraftValue("kp", 0.101)
            verify(panel.applyDraft())
            compare(history.samples.length, 1)
            compare(mock.startCalls, 0)
        }
    }
}