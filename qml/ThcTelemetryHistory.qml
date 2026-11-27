import QtQml

// Read-only telemetry observer. The clock ages data; it never manufactures samples.
QtObject {
    id: root
    property var backend: null
    property bool offline: false
    property bool monitoring: false
    property bool preferFine: false
    property string fineOwnerId: ""
    readonly property int windowMs: 60000
    readonly property int maximumSamples: 2048
    property double nowMs: Date.now()
    property var samples: []
    property string lastSequence: ""
    property string lastFineSequence: ""
    property string lastSourceIdentity: ""
    property bool gapOpen: true

    readonly property bool telemetryReady: backend !== null && !offline
        && backend.pressConnected === true && backend.pressTelemetryFresh === true
    readonly property var fineFrame: validFine(backend ? backend.thcFineLoad : null)
    readonly property bool fineAvailable: telemetryReady && fineFrame !== null
    readonly property string source: fineAvailable ? "TH_CTRL_FILTERED_PRE_DEADZONE" : "STATUS"
    readonly property bool loadY1Available: telemetryReady
        && (fineAvailable || (backend.independentRamTelemetryAvailable === true && finite(backend.ramLoadY1)))
    readonly property bool loadY2Available: telemetryReady
        && (fineAvailable || (backend.independentRamTelemetryAvailable === true && finite(backend.ramLoadY2)))
    readonly property bool loadAvailable: loadY1Available && loadY2Available
    readonly property var loadY1: loadY1Available ? (fineAvailable ? fineFrame.f1 : backend.ramLoadY1) : null
    readonly property var loadY2: loadY2Available ? (fineAvailable ? fineFrame.f2 : backend.ramLoadY2) : null
    readonly property var totalLoad: loadAvailable && finite(loadY1 + loadY2) ? loadY1 + loadY2 : null
    readonly property bool rpmAvailable: telemetryReady && backend.motorRpmAvailable === true
        && finite(backend.motorRpmY1) && finite(backend.motorRpmY2)
    readonly property var rpmY1: rpmAvailable ? backend.motorRpmY1 : null
    readonly property var rpmY2: rpmAvailable ? backend.motorRpmY2 : null
    readonly property var rpmDelta: rpmAvailable ? Math.abs(rpmY1 - rpmY2) : null
    readonly property bool fineOwnerActive: preferFine && fineOwnerId !== "" && backend !== null
        && String(backend.operationId) === fineOwnerId && backend.operationDevice === "press"
        && backend.operationName === "thc-contact-profile-v53"
        && backend.commandOperationActive === true && backend.thcContinuousActive === true
    // Expiry invalidates the current value, not previously measured values.
    // Keep one identified fine-source window through warm-up/fallback gaps.
    readonly property bool fineHistorySelected: fineOwnerActive && (fineAvailable
        || samples.some(sample => sample.source === "TH_CTRL_FILTERED_PRE_DEADZONE"
            && sample.ownerId === fineOwnerId))
    readonly property string historySource: fineHistorySelected ? "TH_CTRL_FILTERED_PRE_DEADZONE" : "STATUS"
    readonly property string selectionKey: historySource + ":" + (fineHistorySelected ? fineOwnerId : "")
    readonly property var selectedSamples: samples.filter(sample => sample.gap
        || ((sample.source || "STATUS") === historySource && (!fineHistorySelected
            || sample.ownerId === fineOwnerId)))
    readonly property var range: rangeOf(selectedSamples)
    readonly property var seriesSegments: segmentsOf(selectedSamples)

    function finite(value) {
        return typeof value === "number" && isFinite(value)
    }

    function sequence() {
        const value = backend ? backend.pressTelemetrySequence : undefined
        return Number.isSafeInteger(value) && value > 0 ? String(value) : ""
    }

    function validFine(value) {
        return preferFine && fineOwnerId !== "" && value
            && backend && String(backend.operationId) === fineOwnerId
            && backend.operationDevice === "press" && backend.operationName === "thc-contact-profile-v53"
            && backend.commandOperationActive === true && backend.thcContinuousActive === true
            && value.source === "TH_CTRL_FILTERED_PRE_DEADZONE"
            && value.ownerId === fineOwnerId && typeof value.generation === "string"
            && Number.isSafeInteger(value.sequence) && value.sequence > 0
            && finite(value.f1) && finite(value.f2) && finite(value.f1 + value.f2) ? value : null
    }

    function reset() {
        samples = []
        lastSequence = sequence()
        const fine = validFine(backend ? backend.thcFineLoad : null)
        lastFineSequence = fine ? String(fine.sequence) : ""
        lastSourceIdentity = ""
        gapOpen = true
        nowMs = Date.now()
    }

    function advance(at, deferNotify) {
        if (!finite(at)) return
        // Wall-clock rollback is an uncertainty boundary, not a negative duration.
        let changed = false
        if (at < nowMs) {
            samples.length = 0
            gapOpen = true
            changed = true
        }
        nowMs = at
        // Sorted arrival times make expiration a prefix trim. Do not replace
        // the data model at every axis tick when no samples have expired.
        let first = 0
        while (first < samples.length && samples[first].at < at - windowMs) ++first
        first = Math.max(first, samples.length - maximumSamples)
        if (first > 0) {
            samples.splice(0, first)
            changed = true
        }
        if (changed && !deferNotify) samplesChanged()
        return changed
    }

    function markGap(at, deferNotify) {
        let changed = advance(at, true)
        if (!gapOpen && samples.length > 0) {
            samples.push({ at: at, gap: true })
            if (samples.length > maximumSamples) samples.splice(0, samples.length - maximumSamples)
            changed = true
        }
        gapOpen = true
        if (changed && !deferNotify) samplesChanged()
        return changed
    }

    function observe(at) {
        if (!finite(at)) return false
        let changed = advance(at, true)
        const current = sequence()
        const previousStatusSequence = lastSequence
        if (current !== "") lastSequence = current
        // Capture one coherent native frame directly. Derived display bindings
        // may be notified in a different order by the shared telemetry signal.
        const fine = validFine(backend ? backend.thcFineLoad : null)
        const fineSequence = fine ? String(fine.sequence) : ""
        const y1 = fine ? fine.f1 : backend ? backend.ramLoadY1 : undefined
        const y2 = fine ? fine.f2 : backend ? backend.ramLoadY2 : undefined
        const ready = backend !== null && !offline && backend.pressConnected === true
            && backend.pressTelemetryFresh === true && (fine !== null || backend.independentRamTelemetryAvailable === true)
            && finite(y1) && finite(y2) && finite(y1 + y2)
        if (!monitoring || !ready) {
            // Consume unavailable/hidden frames too; a later module notification
            // must not assign a new arrival timestamp to an older press frame.
            if (fineSequence !== "") lastFineSequence = fineSequence
            changed = markGap(at, true) || changed
            if (changed) samplesChanged()
            return false
        }
        const selectedSequence = fine ? fineSequence : current
        const identity = fine ? fine.source + ":" + fine.ownerId + ":" + fine.generation : "STATUS"
        if (identity !== lastSourceIdentity) {
            changed = markGap(at, true) || changed
            lastSourceIdentity = identity
        }
        if (selectedSequence === "") {
            changed = markGap(at, true) || changed
            if (changed) samplesChanged()
            return false
        }
        const previous = fine ? lastFineSequence : previousStatusSequence
        if (selectedSequence === previous) {
            if (changed) samplesChanged()
            return false
        }
        // Reconnect/reset or missed telemetry frames must not be bridged.
        if ((previous !== "" && Number(selectedSequence) !== Number(previous) + 1)
                || (fine && fine.breakBefore === true))
            markGap(at, true)
        if (fine) lastFineSequence = fineSequence
        samples.push({ at: at, sequence: selectedSequence, source: fine ? fine.source : "STATUS",
            ownerId: fine ? fine.ownerId : "", generation: fine ? fine.generation : "",
            mcuMs: fine ? fine.mcuMs : null, mcuSequence: fine ? fine.mcuSequence : null, total: y1 + y2,
            y1: y1, y2: y2, breakBefore: gapOpen })
        if (samples.length > maximumSamples) samples.splice(0, samples.length - maximumSamples)
        gapOpen = false
        samplesChanged()
        return true
    }

    function rangeOf(values) {
        let minimum = null
        let maximum = null
        for (const sample of values) {
            if (sample.gap || !finite(sample.total)) continue
            minimum = minimum === null ? sample.total : Math.min(minimum, sample.total)
            maximum = maximum === null ? sample.total : Math.max(maximum, sample.total)
        }
        return { minimum: minimum, maximum: maximum }
    }

    function segmentsOf(values) {
        const result = []
        let segment = []
        let previous = null
        for (const sample of values) {
            // Filtered-out sources must never make two unrelated runs adjacent.
            if (sample.gap || sample.breakBefore || (previous &&
                    ((sample.source || "STATUS") !== (previous.source || "STATUS")
                    || sample.ownerId !== previous.ownerId || sample.generation !== previous.generation))) {
                if (segment.length > 0) result.push(segment)
                segment = []
            }
            if (!sample.gap) segment.push(sample)
            previous = sample.gap ? null : sample
        }
        if (segment.length > 0) result.push(segment)
        return result
    }

    onBackendChanged: reset()
    onMonitoringChanged: if (!monitoring) markGap(Date.now())
    onLoadAvailableChanged: if (!loadAvailable) markGap(Date.now())
    onPreferFineChanged: markGap(Date.now())
    onFineOwnerIdChanged: markGap(Date.now())
    Component.onCompleted: reset()

    property Connections telemetryConnections: Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onTelemetryChanged() { root.observe(Date.now()) }
        function onPressTelemetrySequenceChanged() { root.observe(Date.now()) }
        function onThcFineLoadChanged() { root.observe(Date.now()) }
        function onCommandLifecycleChanged() { root.observe(Date.now()) }
        function onThcContinuousActiveChanged() { root.observe(Date.now()) }
    }
    property Timer agingClock: Timer {
        interval: 250
        repeat: true
        running: root.monitoring
        onTriggered: root.advance(Date.now())
    }
}