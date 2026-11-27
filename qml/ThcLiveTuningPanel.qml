pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Popup {
    id: root
    objectName: "thc-live-tuning-panel"
    property var backend: null
    property bool offline: false
    property bool intendedVisible: true
    property var draft: ({})
    property bool draftDirty: false
    property bool confirmationVisible: false
    property string actionError: ""
    property string ownerId: ""
    property var ownerBackend: null
    property bool leaseIntended: false
    property bool cancelRequested: false
    property bool starting: false
    property string previousOwnerId: ""
    property var startBackend: null
    property bool reloadDraft: false
    // Auto THC free approach uses the current Bend speed (0 = firmware default).
    property real approachSpeed: 0

    readonly property color ink: "#232323"
    readonly property color paper: "#F5F5F5"
    readonly property color charcoal: "#2B2C2B"
    readonly property color teal: "#1B7A5A"
    readonly property color red: "#A82011"
    readonly property color blue: "#2D83B2"
    readonly property var hostWindow: contentItem.Window.window
    readonly property bool surfaceActive: opened && visible && intendedVisible
        && hostWindow !== null && hostWindow.visible && hostWindow.active
    readonly property bool apiAvailable: backend !== null
        && typeof backend.pressSafetyStopUnconfirmed === "boolean"
        && typeof backend.queryThcLiveTuning === "function"
        && typeof backend.applyThcLiveTuning === "function"
        && typeof backend.startContinuousThcContactProfile === "function"
        && typeof backend.heartbeatThcCommissioning === "function"
        && typeof backend.releaseThcCommissioning === "function"
        && typeof backend.cancelThcCommissioning === "function"
    readonly property bool supported: apiAvailable && backend.thcLiveTuningSupported === true
    readonly property bool extendedRanges: supported && backend.thcLiveTuningExtended === true
    // Six fixed decimals, nine integer digits, bounded 128-byte firmware frame.
    readonly property real technicalMaximum: 999999999.999999
    readonly property bool pending: apiAvailable && backend.thcLiveTuningPending === true
    readonly property string tuningError: apiAvailable ? String(backend.thcLiveTuningError || "") : ""
    readonly property string commissioningState: backend ? String(backend.thcCommissioningState || "") : ""
    readonly property bool stopUnconfirmed: backend !== null
        && backend.pressSafetyStopUnconfirmed !== false
    readonly property bool transportReady: apiAvailable && !offline
        && backend.pressTransportAvailable === true && backend.pressConnected === true
        && backend.pressReady === true && backend.pressConnectionState === "READY"
    readonly property bool controllerSafe: transportReady && backend.pressHomed === true
        && backend.pressTelemetryFresh === true && !stopUnconfirmed
        && backend.physicalPedalAvailable === true && backend.physicalPedal === false
        && backend.bendPedal === false && backend.antiBind === false
        && backend.primingModeEnabled === false
        && backend.primingLatchY1 === false && backend.primingLatchY2 === false
    readonly property bool ownerMatches: backend !== null && backend === ownerBackend
        && ownerId !== "" && String(backend.operationId) === ownerId
        && backend.operationDevice === "press" && backend.operationName === "thc-contact-profile-v53"
    readonly property bool ownsOperation: ownerMatches
        && backend.commandOperationActive === true && backend.thcContinuousActive === true
    readonly property bool idle: controllerSafe && backend.pressMachineState === "IDLE"
        && backend.commandOperationActive === false && backend.pressOperationActive === false
    readonly property bool holding: controllerSafe && ownsOperation && commissioningState === "HOLDING"
    readonly property bool canQuery: surfaceActive && (idle || holding) && !pending && !starting
    readonly property bool canTune: canQuery && supported && tuningError === ""
    readonly property bool draftValid: validValues(draft)
    readonly property bool canApply: canTune && draftValid && draftDirty && !confirmationVisible
    readonly property bool canResetDraft: canTune && !confirmationVisible
    readonly property bool canStart: surfaceActive && idle && supported && !pending
        && tuningError === "" && !starting && !draftDirty
    readonly property bool renewing: surfaceActive && !offline && ownsOperation && leaseIntended
        && commissioningState !== "CANCELLING"
        && commissioningState !== "FAILED_STOP_UNCONFIRMED" && commissioningState !== "DONE"
    readonly property var requested: supported ? (backend.thcLiveTuning || ({})) : ({})
    readonly property var diagnostics: backend && backend.pressTelemetryFresh === true
        && ownsOperation ? (backend.thcLiveDiagnostics || ({})) : ({})
    readonly property var effective: diagnostics.effective || ({})
    // Shipped V53 v1 factory snapshot (compiled source 162e5088), not queried
    // controller settings or a promise of physical stability. See panel docs.
    readonly property var legacyFactoryDefaults: Object.freeze({
        kp: 0.15, ki: 0.02, kd: 0.03, rate: 0.010, cq: 0.010, fs: 0.050
    })
    // V2 default: remote HOLD sweep 2026-10-31 winner (set B), also the
    // firmware desired default of env v53_hold_force_filter. Kp 0.45 exceeds
    // the v1 range, so v1/unconfirmed firmware keeps the legacy snapshot.
    readonly property var sweepDefaults: Object.freeze({
        kp: 0.45, ki: 0.02, kd: 0.06, rate: 0.003, cq: 0.010, fs: 0.050
    })
    readonly property var factoryDefaults: extendedRanges ? sweepDefaults : legacyFactoryDefaults
    readonly property var fields: [
        { key: "kp", title: qsTr("Kp"), minimum: 0, maximum: 3000, step: 10, digits: 3 },
        { key: "ki", title: qsTr("Ki"), minimum: 0, maximum: 400, step: 1, digits: 4 },
        { key: "kd", title: qsTr("Kd"), minimum: 0, maximum: 600, step: 5, digits: 4 },
        { key: "rate", title: qsTr("Rate"), minimum: 20, maximum: 100, step: 1, digits: 4 },
        { key: "cq", title: qsTr("CQ"), minimum: 50, maximum: 200, step: 10, digits: 3 },
        { key: "fs", title: qsTr("FS"), minimum: 200, maximum: 1000, step: 10, digits: 3 }
    ]

    parent: Overlay.overlay
    width: Math.max(0, Math.min(950, parent ? parent.width - 24 : 950))
    height: Math.max(0, Math.min(600, parent ? parent.height - 24 : 600))
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    padding: 14
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    enter: Transition { }
    exit: Transition { }
    background: Rectangle { color: "#0F141C"; radius: 12; border.color: "#222D3D"; border.width: 1.5 }
    Overlay.modal: Rectangle { color: "#A6000000" }

    function validValues(values) {
        if (!values) return false
        for (let index = 0; index < fields.length; ++index) {
            const field = fields[index]
            const value = values[field.key]
            if (typeof value !== "number" || !isFinite(value)
                    || value < (extendedRanges ? 0 : field.minimum / 10000)
                    || value > (extendedRanges ? technicalMaximum : field.maximum / 10000))
                return false
        }
        return values.fs > values.cq && (!extendedRanges
            || (values.fs >= 0.000001 && Number(values.fs.toFixed(6)) > Number(values.cq.toFixed(6))))
    }

    function outsideOriginalRange(field) {
        const value = draft[field.key]
        return typeof value === "number" && isFinite(value)
            && (value < field.minimum / 10000 || value > field.maximum / 10000)
    }

    function setDraftText(key, text) {
        // Invalid/incomplete input invalidates the draft rather than retaining
        // a hidden old value that APPLY could send. No exponent or silent clamp.
        const value = /^[0-9]{1,9}(\.[0-9]{0,6})?$/.test(text) ? Number(text) : NaN
        setDraftValue(key, value)
    }

    function stepDraft(field, direction) {
        const value = draft[field.key]
        if (typeof value !== "number" || !isFinite(value)) return
        const next = Math.max(0, Math.min(technicalMaximum, value + direction * field.step / 10000))
        setDraftValue(field.key, Number(next.toFixed(6)))
    }

    function numericText(values, key, digits) {
        const value = values ? values[key] : undefined
        return typeof value === "number" && isFinite(value) ? value.toFixed(digits) : qsTr("—")
    }

    function setDraftValue(key, value) {
        if (!canTune || confirmationVisible) return
        const next = Object.assign({}, draft)
        next[key] = value
        draft = next
        draftDirty = true
    }

    function resetDraftField(key) {
        if (!canResetDraft) return false
        for (let index = 0; index < fields.length; ++index) {
            if (fields[index].key === key) {
                setDraftValue(key, factoryDefaults[key])
                return true
            }
        }
        return false
    }

    function resetDraftDefaults() {
        if (!canResetDraft) return false
        draft = Object.assign({}, factoryDefaults)
        draftDirty = true
        return true
    }

    function loadConfirmedDraft() {
        if (!supported || pending || !validValues(backend.thcLiveTuning)) return
        if (reloadDraft || !draftDirty) {
            const next = {}
            for (let index = 0; index < fields.length; ++index)
                next[fields[index].key] = backend.thcLiveTuning[fields[index].key]
            draft = next
            draftDirty = false
            reloadDraft = false
        }
    }

    function queryCapability() {
        if (!canQuery) return false
        actionError = ""
        reloadDraft = true
        const accepted = backend.queryThcLiveTuning()
        if (!accepted) actionError = qsTr("Query refused. Inspect controller status; no retry was queued.")
        loadConfirmedDraft()
        return accepted
    }

    function applyDraft() {
        if (!canApply) return false
        // Exactly six numeric fields. Revision belongs to the backend; no
        // motion method, history reset, lease renewal or retry accompanies Apply.
        const settings = { kp: draft.kp, ki: draft.ki, kd: draft.kd,
            rate: draft.rate, cq: draft.cq, fs: draft.fs }
        actionError = ""
        const accepted = backend.applyThcLiveTuning(settings)
        if (accepted) draftDirty = false
        else actionError = qsTr("Apply refused. Inspect the error; no retry was queued.")
        return accepted
    }

    function requestStart() {
        if (!canStart) return false
        confirmationVisible = true
        return true
    }

    function captureStartedOwner() {
        if (!starting || ownerId !== "" || backend !== startBackend || backend === null) return
        // The backend increments once on admission. A synchronous subscriber
        // may already have replaced that operation before our signal handler.
        const previous = Number(previousOwnerId)
        if (!Number.isSafeInteger(previous) || !Number.isSafeInteger(previous + 1)) return
        if (String(backend.operationId) === String(previous + 1)
                && backend.operationDevice === "press"
                && backend.operationName === "thc-contact-profile-v53"
                && backend.commandOperationActive === true && backend.thcContinuousActive === true) {
            ownerBackend = backend
            ownerId = String(backend.operationId)
            if (!surfaceActive) cancelOwned()
        }
    }

    function confirmStart() {
        if (!confirmationVisible || !canStart) return false
        if (!Number.isSafeInteger(Number(backend.operationId))
                || !Number.isSafeInteger(Number(backend.operationId) + 1)) {
            confirmationVisible = false
            actionError = qsTr("Owner identifier cannot be represented safely. Start was not sent.")
            return false
        }
        confirmationVisible = false
        actionError = ""
        ownerId = ""
        ownerBackend = null
        cancelRequested = false
        previousOwnerId = String(backend.operationId)
        startBackend = backend
        leaseIntended = true
        starting = true
        if (typeof startBackend.setThcApproachSpeed === "function")
            startBackend.setThcApproachSpeed(approachSpeed)
        const accepted = startBackend.startContinuousThcContactProfile()
        captureStartedOwner()
        starting = false
        startBackend = null
        // Direct backend callbacks may hide/destroy this surface or install a
        // different owner. Never renew or cancel that later operation.
        if (!accepted) {
            actionError = qsTr("Start refused. Inspect controller status; no Home or retry was queued.")
            cancelOwned()
            return false
        }
        if (!surfaceActive || !ownsOperation) {
            cancelOwned()
            return false
        }
        renewLease()
        return ownsOperation && leaseIntended
    }

    function renewLease() {
        if (!surfaceActive) { cancelOwned(); return false }
        if (!renewing) return false
        const accepted = ownerBackend.heartbeatThcCommissioning()
        if (!surfaceActive || !accepted) cancelOwned()
        return accepted && ownsOperation && leaseIntended
    }

    function releaseOwned() {
        if (!ownsOperation || !surfaceActive) return false
        const accepted = ownerBackend.releaseThcCommissioning()
        if (!accepted) actionError = qsTr("RELEASE refused by controller. STOP / CANCEL remains available.")
        return accepted
    }

    function cancelOwned() {
        leaseIntended = false
        confirmationVisible = false
        if (!ownsOperation || cancelRequested) return false
        cancelRequested = true
        return ownerBackend.cancelThcCommissioning()
    }

    onSurfaceActiveChanged: if (!surfaceActive) cancelOwned()
    onOfflineChanged: if (offline) cancelOwned()
    onOwnsOperationChanged: if (!ownsOperation && ownerId !== "") leaseIntended = false
    onCanStartChanged: if (!canStart) confirmationVisible = false
    onBackendChanged: {
        // Backend replacement must not redirect a cancel to a different device.
        leaseIntended = false
        const previousBackend = ownerBackend
        if (!cancelRequested && previousBackend && ownerId !== "" && String(previousBackend.operationId) === ownerId
            && previousBackend.operationDevice === "press"
            && previousBackend.operationName === "thc-contact-profile-v53"
            && previousBackend.commandOperationActive === true && previousBackend.thcContinuousActive === true) {
            cancelRequested = true
            previousBackend.cancelThcCommissioning()
        }
        ownerId = ""
        ownerBackend = null
        draft = ({})
        draftDirty = false
        confirmationVisible = false
    }
    onOpened: {
        loadConfirmedDraft()
        queryCapability()
    }
    onAboutToHide: cancelOwned()
    Component.onDestruction: cancelOwned()

    Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onThcLiveTuningChanged() { root.loadConfirmedDraft() }
        function onCommandLifecycleChanged() { root.captureStartedOwner() }
        function onThcContinuousActiveChanged() { root.captureStartedOwner() }
    }

    Timer {
        objectName: "thc-live-operator-lease"
        interval: 350
        repeat: true
        running: root.renewing
        onTriggered: root.renewLease()
    }

    ThcTelemetryHistory {
        id: telemetryHistory
        objectName: "thc-live-telemetry-history"
        backend: root.backend
        offline: root.offline
        monitoring: root.surfaceActive
        preferFine: root.ownsOperation
        fineOwnerId: root.ownsOperation ? root.ownerId : ""
    }
    contentItem: ThcLiveTuningView {
        controller: root
        history: telemetryHistory
    }
}