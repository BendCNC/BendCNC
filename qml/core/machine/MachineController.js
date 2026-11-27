// MachineController.js — Phase 6.1/6.2: deterministic core of the press-machine
// state model + PressMachineStatus reducer + jog command construction).
//
// This is a PURE state-reduction layer: it does NOT own a serial port. A device
// (MockPressDevice by default; C++ SerialPressDevice when a machine is connected)
// feeds raw lines in via `ingestLine`; the controller decodes them with protocol.js
// and folds them into an immutable-ish status object. Outbound jog/abort commands
// are produced as strings for the device to transmit. The machine is NOT connected
// in this environment, so the mock device is the default wiring.
//
// Verified by test_MachineController.qml.

.pragma library
.import "protocol.js" as Protocol

// ---- PressMachineState (1:1 incl. alarm codes) ------------------------------
// Non-alarm states have alarmCode 0; alarm states carry the firmware alarm code.
var State = {
    STARTUP_HOMING_REQUIRED: { name: "STARTUP_HOMING_REQUIRED", alarmCode: 0 },
    HOMING: { name: "HOMING", alarmCode: 0 },
    HOMING_BUMP: { name: "HOMING_BUMP", alarmCode: 0 },
    SAFETY_JOG: { name: "SAFETY_JOG", alarmCode: 0 },
    SAFETY_JOG_HOLD: { name: "SAFETY_JOG_HOLD", alarmCode: 0 },
    CLAMP_JOG: { name: "CLAMP_JOG", alarmCode: 0 },
    CLAMP_JOG_HOLD: { name: "CLAMP_JOG_HOLD", alarmCode: 0 },
    BEND_JOG: { name: "BEND_JOG", alarmCode: 0 },
    BEND_DEPTH_REACHED: { name: "BEND_DEPTH_REACHED", alarmCode: 0 },
    BEND_JOG_HOLD: { name: "BEND_JOG_HOLD", alarmCode: 0 },
    RETRACT_JOG: { name: "RETRACT_JOG", alarmCode: 0 },
    RELEASE_LOAD_RETRACT: { name: "RELEASE_LOAD_RETRACT", alarmCode: 0 },
    IDLE: { name: "IDLE", alarmCode: 0 },
    PRIMING_MODE: { name: "PRIMING_MODE", alarmCode: 0 },
    UNKNOWN: { name: "UNKNOWN", alarmCode: 0 },
    ANTIBIND_TRIGGERED: { name: "ANTIBIND_TRIGGERED", alarmCode: 1 },
    ENCODER_SYNC_ERROR: { name: "ENCODER_SYNC_ERROR", alarmCode: 2 },
    Y1_TONNAGE_CALIB_FAIL: { name: "Y1_TONNAGE_CALIB_FAIL", alarmCode: 3 },
    Y2_TONNAGE_CALIB_FAIL: { name: "Y2_TONNAGE_CALIB_FAIL", alarmCode: 4 },
    Y1_Y2_TONNAGE_CALIB_FAIL: { name: "Y1_Y2_TONNAGE_CALIB_FAIL", alarmCode: 5 },
    Y1_NEG_TONN_FAIL: { name: "Y1_NEG_TONN_FAIL", alarmCode: 6 },
    Y2_NEG_TONN_FAIL: { name: "Y2_NEG_TONN_FAIL", alarmCode: 7 },
    Y1_Y2_NEG_TONN_FAIL: { name: "Y1_Y2_NEG_TONN_FAIL", alarmCode: 8 },
    STEADY_STATE_MOTION: { name: "STEADY_STATE_MOTION", alarmCode: 9 },
    MACHINE_TRACKING_ERROR: { name: "MACHINE_TRACKING_ERROR", alarmCode: 10 },
    MAX_TONNAGE_ERROR: { name: "MAX_TONNAGE_ERROR", alarmCode: 11 },
    STATIONARY_LOAD_TIMEOUT: { name: "STATIONARY_LOAD_TIMEOUT", alarmCode: 12 },
    HYDRAULIC_SHUTDOWN: { name: "HYDRAULIC_SHUTDOWN", alarmCode: 13 }
}

// PressMachineState.lookUp: upper-case, collapse [-/\s]+ -> "_", strip [.\s]+.
function lookUpState(description) {
    if (description === undefined || description === null) return State.UNKNOWN
    var s = String(description).toUpperCase().replace(/[-/\s]+/g, "_").replace(/[.\s]+/g, "")
    return State[s] !== undefined ? State[s] : State.UNKNOWN
}

function isAlarmState(state) { return !!state && state.alarmCode > 0 }
function stateLabel(state) { return state ? state.name.replace(/_/g, " ") : "UNKNOWN" }

// ---- status reducer (ports PressMachineStatus.updateFrom) -------------------
function emptyStatus() {
    return {
        state: State.UNKNOWN,
        y1Pos: NaN, y2Pos: NaN, yError: NaN, velocity: NaN, targetPos: NaN,
        commandedJogPos: NaN, jogSpeed: NaN,
        safetyJogR: false, safetyJogL: false, bendJogPedal: false, abState: false,
        distToGo: NaN, y1Ton: NaN, y2Ton: NaN,
        y1MotorHz: NaN, y1MotorDir: 0, y2MotorHz: NaN, y2MotorDir: 0,
        temporaryStatus: null,
        connected: false
    }
}

// Fold a decoded general-status message into the status (immutable copy).
function applyGeneral(status, msg) {
    var next = _clone(status || emptyStatus())
    next.state = lookUpState(msg.state)
    next.y1Pos = msg.y1Pos; next.y2Pos = msg.y2Pos; next.yError = msg.yError
    next.velocity = msg.velocity; next.targetPos = msg.targetPos
    next.commandedJogPos = msg.commJogPos; next.jogSpeed = msg.jogSpeed
    next.safetyJogL = msg.safetyJogL; next.safetyJogR = msg.safetyJogR
    next.bendJogPedal = msg.bendJogPedal; next.abState = msg.abState
    next.distToGo = msg.distToGo; next.y1Ton = msg.y1Ton; next.y2Ton = msg.y2Ton
    if (msg.y1MotorHz !== undefined) {
        next.y1MotorHz = msg.y1MotorHz; next.y1MotorDir = msg.y1MotorDir
        next.y2MotorHz = msg.y2MotorHz; next.y2MotorDir = msg.y2MotorDir
    }
    if (msg.loop !== undefined) next.loop = msg.loop
    next.connected = true
    return next
}

// Fold a decoded temporary-status message (priming/manual/maxTon/safetyRetract).
function applyTemporary(status, msg) {
    var next = _clone(status || emptyStatus())
    next.temporaryStatus = {
        bendSafetyRetract: msg.bendSafetyRetract,
        manualModeEnable: msg.manualModeEnable,
        manualModeMaxTonnage: msg.manualModeMaxTonnagePerRam,
        primingEnabled: msg.primingModeEnable
    }
    next.connected = true
    return next
}

function _clone(o) {
    var c = {}
    for (var k in o) if (o.hasOwnProperty(k)) c[k] = o[k]
    return c
}

// ---- controller object ------------------------------------------------------
// Stateful wrapper: holds the current status + last EEPROM + last events. The
// `handlers` object may provide onStatus/onAlarm/onPedalReleased/onCompleted/
// onEeprom/onWelcome/onLimp callbacks (all optional). Pure JS — no Qt types.
function createController(handlers) {
    var h = handlers || {}
    var status = emptyStatus()
    var eeprom = null
    var lastEvent = null

    function ingestDecoded(m) {
        lastEvent = m
        switch (m.kind) {
        case Protocol.MessageKind.GENERAL_STATUS:
            status = applyGeneral(status, m)
            if (h.onStatus) h.onStatus(status)
            if (isAlarmState(status.state) && h.onAlarm) h.onAlarm(status.state)
            break
        case Protocol.MessageKind.TEMPORARY_STATUS:
            status = applyTemporary(status, m)
            if (h.onStatus) h.onStatus(status)
            break
        case Protocol.MessageKind.EEPROM:
            eeprom = m
            if (h.onEeprom) h.onEeprom(m)
            break
        case Protocol.MessageKind.WELCOME:
            status = _clone(status); status.connected = true
            if (h.onWelcome) h.onWelcome(m.version)
            break
        case Protocol.MessageKind.PEDAL_RELEASED:
            if (h.onPedalReleased) h.onPedalReleased()
            break
        case Protocol.MessageKind.OPERATION_COMPLETED:
            if (h.onCompleted) h.onCompleted(m.operation)
            break
        case Protocol.MessageKind.LIMP_MODE:
            if (h.onLimp) h.onLimp()
            break
        case Protocol.MessageKind.FAIL:
        case Protocol.MessageKind.ERROR:
            if (h.onFault) h.onFault(m)
            break
        default:
            break
        }
        return m
    }

    return {
        ingestLine: function (line) { return ingestDecoded(Protocol.decode(line)); },
        ingestDecoded: ingestDecoded,
        getStatus: function () { return status; },
        getEeprom: function () { return eeprom; },
        getLastEvent: function () { return lastEvent; },
        isAlarm: function () { return isAlarmState(status.state); },
        isConnected: function () { return status.connected === true; },
        // outbound command builders (delegate to protocol.js encode)
        jogCommand: function (positionInch, speedInch, jogType) { return Protocol.encodeJog(positionInch, speedInch, jogType); },
        abortCommand: function (abortType) { return Protocol.encodeAbort(abortType); }
    }
}
