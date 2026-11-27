.pragma library

// DwellAndBailOut.js
// Implements the deterministic state in:
//   - model/execution/DwellTimerModel (countdown state machine, 100ms tick, pedal-gated)
//   - core/entity/BailOutReason (enum + isMachineAlarm + fromOrdinal)
//   - model/execution/BailOutModel core (lastBailOutReason, 100ms-debounced onBailOut,
//     includeBackGaugeBailOut)
//
// The Java DwellTimerModel uses a ScheduledExecutorService; here the countdown is
// driven by explicit `tick()` calls (QML Timer or test loop) so it is deterministic
// and runtime-agnostic. Event subscriptions to hardware models (pedal/back-gauge/
// alarms) are Phase 6 — this module exposes the pure reducer `onBailOut(reason)` plus
// the timer reducer.

// ---- DwellTimerState ----
var DwellTimerState = { FINISHED: "FINISHED", RUNNING: "RUNNING", CANCELLED: "CANCELLED" };
var DWELL_TICK_MS = 100;

// Create a dwell timer state. durationSec mirrors userSettings.autoClampBendDwellSec.
function createDwellTimer(durationSec) {
    return {
        durationSec: (typeof durationSec === "number" && isFinite(durationSec)) ? durationSec : 0.0,
        remainingSec: 0.0,
        lastState: DwellTimerState.FINISHED
    };
}

function isDwellRunning(t) { return t.lastState === DwellTimerState.RUNNING; }
function isDwellFinishedGracefully(t) { return t.lastState === DwellTimerState.FINISHED; }

// startDwellTimer — RUNNING + reset remaining to duration. No-op if already running.
function startDwellTimer(t) {
    if (t.lastState === DwellTimerState.RUNNING) return false;  // "Dwell already running"
    t.lastState = DwellTimerState.RUNNING;
    t.remainingSec = t.durationSec;
    return true;
}

// cancel — CANCELLED, stop.
function cancelDwellTimer(t) { t.lastState = DwellTimerState.CANCELLED; }

// tick(t, pedalPressed) — advance one 100ms tick (DwellCountdownTimerTask.run):
//   if remaining > 0: if pedal NOT pressed -> CANCELLED; then remaining -= 0.1 (clamped 0).
//   else: FINISHED.
// Returns the new state.
function tickDwellTimer(t, pedalPressed) {
    if (t.lastState !== DwellTimerState.RUNNING) return t.lastState;
    if (t.remainingSec > 0.0) {
        if (!pedalPressed) {
            t.lastState = DwellTimerState.CANCELLED;
            return t.lastState;
        }
        // Java: max((remaining*1000 - 100)/1000, 0)
        t.remainingSec = Math.max((t.remainingSec * 1000.0 - DWELL_TICK_MS) / 1000.0, 0.0);
    } else {
        t.lastState = DwellTimerState.FINISHED;
    }
    return t.lastState;
}

// Order preserved (ordinals matter for fromOrdinal + alarm mapping). [isMachineAlarm]
var BAIL_OUT_REASONS = [
    "PedalReleased", "BendReachFail", "RetractPlaneError", "MachineConnectionProblem",
    "MachineHydraulicShutdown", "MachineDisconnectedDuringOperation",
    "BackGaugeStoppingOrResetting", "MachineHomingRequired", "UserRequestedMachineAbort",
    "DwellCancelled", "JogHoldTimeout", "CancelledDuringWaitSwitchRelease",
    "InvalidJogType", "InvalidCommand", "MachineNotIdle", "BackGaugeNotReady",
    "BackGaugeAlarm", "BackGaugeOnHold",
    // machine-alarm reasons:
    "AntibindTriggered", "EncoderSyncError", "Y1TonnageCalibFail", "Y2TonnageCalibFail",
    "Y1Y2TonnageCalibFail", "Y1NegTonnFail", "Y2NegTonnFail", "Y1Y2NegTonnFail",
    "SteadyStateMotion", "MachineTrackingError", "MaxTonnageError",
    "StationaryLoadTimeout", "UserHydraulicShutdown"
];
var _FIRST_ALARM_INDEX = 18; // AntibindTriggered onward are machine alarms

var BailOutReason = {};
(function () {
    for (var i = 0; i < BAIL_OUT_REASONS.length; i++) BailOutReason[BAIL_OUT_REASONS[i]] = BAIL_OUT_REASONS[i];
})();
function bailOutOrdinal(reason) { return BAIL_OUT_REASONS.indexOf(reason); }
function bailOutFromOrdinal(ordinal) {
    if (ordinal < 0 || ordinal >= BAIL_OUT_REASONS.length)
        throw new Error("Invalid ordinal: " + ordinal);
    return BAIL_OUT_REASONS[ordinal];
}
function bailOutIsMachineAlarm(reason) {
    var i = bailOutOrdinal(reason);
    return i >= _FIRST_ALARM_INDEX;
}

// ---- BailOutModel core ----
var BAIL_OUT_LATENCY_MS = 100;

function createBailOut() {
    return {
        lastBailOutReason: null,
        lastFiredMillis: 0,
        includeBackGaugeBailOut: true
    };
}

// onBailOut(model, reason, nowMs) — debounced by 100ms (Java getAndSet latency gate).
// Returns true if the bail-out fired (state updated), false if suppressed by debounce.
// nowMs lets tests/QML inject Date.now().
function onBailOut(model, reason, nowMs) {
    var now = (typeof nowMs === "number") ? nowMs : Date.now();
    if (now - model.lastFiredMillis >= BAIL_OUT_LATENCY_MS) {
        model.lastFiredMillis = now;
        model.lastBailOutReason = reason;
        return true;
    }
    return false;
}

function setIncludeBackGaugeBailOut(model, value) { model.includeBackGaugeBailOut = !!value; }
