// protocol.js — Phase 6.1: Implements the press-machine serial protocol
//
// The firmware speaks a custom bracketed/braced GRBL-style line protocol:
//   - General status:   "<state|y1|y2|yError|vel|target|commJog|jogSpeed|sL|sR|pedal|distToGo|y1Ton|y2Ton|abState[|loop...]>"
//   - Temporary status:  "{TEMP:safetyRetract|manualEnable|maxTon|primingEnable}"
//   - EEPROM:            "{EEPROM:maxTon|defl|wdog|ramToTable|kp|ki|kd|kpAgg|kiAgg|kdAgg}"
//   - Welcome:           "[LS-BEND v<version>]"
//   - Echo:              "[RECEIVED STRING: <s>]"
//   - Fail/Error/Reset/Invalid/Unexpected/Operation: "[<type> FAIL]" etc.
//   - Pedal released:    "[PEDAL RELEASED]"   (exact)
//   - Limp mode:         "[LIMP MODE]"        (exact)
//   - Firmware ack:      "[XX_STATUS]"        (2-3 letter command + _STATUS)
//
// Outbound commands (operation.*):
//   - Jog/RepeatingJog:  "%.4f, %.4f, %s"  → "pos, speed, jogtype"  (jogtype lowercase)
//   - AbortJog:          abortType.toLowerCase()  ("forbidden"|"cancel"|"stop")
//
// This module is PURE (no IO). MockPressDevice/SerialPressDevice feed lines in,
// MachineController consumes the decoded message objects. Verified by
// test_protocol.qml.

.pragma library

// ---- enums (1:1 with PressMachineJogType / PressMachineAbortJogType) --------
var JogType = { SAFETY: "safety", RETRACT: "retract", CLAMP: "clamp", BEND: "bend", BUMP: "bump" }
var AbortJogType = { FORBIDDEN: "forbidden", CANCEL: "cancel", STOP: "stop" }

// Message kinds emitted by decode().
var MessageKind = {
    GENERAL_STATUS: "GENERAL_STATUS",
    TEMPORARY_STATUS: "TEMPORARY_STATUS",
    EEPROM: "EEPROM",
    WELCOME: "WELCOME",
    ECHO: "ECHO",
    FAIL: "FAIL",
    ERROR: "ERROR",
    RESET: "RESET",
    INVALID: "INVALID",
    UNEXPECTED_STATE: "UNEXPECTED_STATE",
    OPERATION_COMPLETED: "OPERATION_COMPLETED",
    PEDAL_RELEASED: "PEDAL_RELEASED",
    LIMP_MODE: "LIMP_MODE",
    FIRMWARE_ACK: "FIRMWARE_ACK",
    UNKNOWN: "UNKNOWN"
}

// ---- helpers ----------------------------------------------------------------
function _num(value) {
    if (value === undefined || value === null) return NaN
    var s = String(value).trim()
    if (s.toLowerCase() === "nan") return NaN
    var n = parseFloat(s)
    return isNaN(n) ? NaN : n
}

function _pad4(n) { return Number(n).toFixed(4) }
function _pad2(n) { return Number(n).toFixed(2) }

// ---- outbound encode (operation.*) ------------------------------------------
// MachineJogOperation template "%.4f, %.4f, %s" (RepeatingJog uses %f but the
// firmware accepts both; we mirror the primary jog operation's 4dp form).
function encodeJog(positionInch, speedInch, jogType) {
    return _pad4(positionInch) + ", " + _pad4(speedInch) + ", " + String(jogType)
}

// AbortJogOperation sends the abort type token, lowercased.
function encodeAbort(abortType) {
    return String(abortType).toLowerCase()
}

// ---- inbound decode ---------------------------------------------------------
// Returns a plain object { kind, ...fields } or { kind: UNKNOWN, raw }.
function decode(line) {
    if (line === undefined || line === null) return { kind: MessageKind.UNKNOWN, raw: line }
    var msg = String(line).trim()
    if (msg.length === 0) return { kind: MessageKind.UNKNOWN, raw: line }

    // ---- braced reports ({...}) --------------------------------------------
    if (msg.charAt(0) === "{" && msg.charAt(msg.length - 1) === "}") {
        var braced = msg.substring(1, msg.length - 1)
        if (braced.indexOf("TEMP:") === 0)
            return _decodeTemporary(braced)
        if (braced.indexOf("EEPROM:") === 0)
            return _decodeEeprom(braced)
        return { kind: MessageKind.UNKNOWN, raw: line }
    }

    // ---- angle-bracket general status (<...>) ------------------------------
    if (msg.charAt(0) === "<" && msg.charAt(msg.length - 1) === ">")
        return _decodeGeneral(msg.substring(1, msg.length - 1))

    // ---- square-bracket text messages ([...]) ------------------------------
    if (msg.charAt(0) === "[" && msg.charAt(msg.length - 1) === "]") {
        if (msg === "[PEDAL RELEASED]") return { kind: MessageKind.PEDAL_RELEASED }
        if (msg === "[LIMP MODE]") return { kind: MessageKind.LIMP_MODE }

        var mWelcome = msg.match(/^\[(?:BENDCNC|LS-BEND) v(\d+(?:\.\d+)?(?:[a-zA-Z]+)?)\]$/)
        if (mWelcome) return { kind: MessageKind.WELCOME, version: mWelcome[1] }

        var mEcho = msg.match(/^\[RECEIVED STRING: (.+)\]$/)
        if (mEcho) return { kind: MessageKind.ECHO, string: mEcho[1] }

        var mUnexpected = msg.match(/^\[MACHINE NOT (.*)\]$/)
        if (mUnexpected) return { kind: MessageKind.UNEXPECTED_STATE, state: mUnexpected[1] }

        var mInvalid = msg.match(/^\[INVALID (.*)\]$/)
        if (mInvalid) return { kind: MessageKind.INVALID, type: mInvalid[1] }

        var mFail = msg.match(/^\[(.*) FAIL\]$/)
        if (mFail) return { kind: MessageKind.FAIL, failType: mFail[1] }

        var mError = msg.match(/^\[(.*) ERROR\]$/)
        if (mError) return { kind: MessageKind.ERROR, errorType: mError[1] }

        var mReset = msg.match(/^\[(.*) RESET\]$/)
        if (mReset) return { kind: MessageKind.RESET, resetType: mReset[1] }

        var mCompleted = msg.match(/^\[(.*) COMPLETED\]$/)
        if (mCompleted) return { kind: MessageKind.OPERATION_COMPLETED, operation: mCompleted[1] }

        // Firmware ack [XX_STATUS] (2-3 letter command prefix). Checked last so
        // the more specific FAIL/ERROR/RESET/COMPLETED patterns win first.
        var mAck = msg.match(/^\[([A-Z]{2,3})_([A-Z]+)\]$/)
        if (mAck) return { kind: MessageKind.FIRMWARE_ACK, command: mAck[1], status: mAck[2] }

        return { kind: MessageKind.UNKNOWN, raw: line }
    }

    return { kind: MessageKind.UNKNOWN, raw: line }
}

// General status report: split on '|'. Requires >= 15 fields (MachineStatusMessageParser).
function _decodeGeneral(report) {
    var f = report.split("|")
    if (f.length < 15) return { kind: MessageKind.UNKNOWN, raw: report }
    var out = {
        kind: MessageKind.GENERAL_STATUS,
        state: f[0],
        y1Pos: _num(f[1]), y2Pos: _num(f[2]), yError: _num(f[3]),
        velocity: _num(f[4]), targetPos: _num(f[5]), commJogPos: _num(f[6]),
        jogSpeed: _num(f[7]),
        // safetyJogL/R: builder stores (field == "0") — i.e. true when "0".
        safetyJogL: f[8] === "0", safetyJogR: f[9] === "0",
        bendJogPedal: f[10] === "1",
        distToGo: _num(f[11]), y1Ton: _num(f[12]), y2Ton: _num(f[13]),
        abState: f[14] === "1"
    }
    if (f.length > 15) out.loop = parseInt(f[15], 10)
    if (f.length > 22) {
        out.y1MotorHz = _num(f[19]); out.y1MotorDir = parseInt(f[20], 10)
        out.y2MotorHz = _num(f[21]); out.y2MotorDir = parseInt(f[22], 10)
    }
    return out
}

// Temporary status: "TEMP:safetyRetract|manualEnable|maxTon|primingEnable".
function _decodeTemporary(report) {
    var m = report.match(/^TEMP:(-?\d+(?:\.\d+)?)\|([01])\|(-?\d+(?:\.\d+)?)\|([01])$/)
    if (!m) return { kind: MessageKind.UNKNOWN, raw: report }
    return {
        kind: MessageKind.TEMPORARY_STATUS,
        bendSafetyRetract: _num(m[1]),
        manualModeEnable: m[2] === "1",
        manualModeMaxTonnagePerRam: _num(m[3]),
        primingModeEnable: m[4] === "1"
    }
}

// EEPROM: "EEPROM:maxTon|defl|wdog|ramToTable|kp|ki|kd|kpAgg|kiAgg|kdAgg".
function _decodeEeprom(report) {
    var m = report.match(/^EEPROM:(\d+(?:\.\d+)?)\|(\d)\|(\d)\|(\d+(?:\.\d+)?)\|(\d+(?:\.\d+)?)\|(\d+(?:\.\d+)?)\|(\d+(?:\.\d+)?)\|(\d+(?:\.\d+)?)\|(\d+(?:\.\d+)?)\|(\d+(?:\.\d+)?)$/)
    if (!m) return { kind: MessageKind.UNKNOWN, raw: report }
    return {
        kind: MessageKind.EEPROM,
        maxTonnageThreshold: _num(m[1]),
        deflectionCompEnable: _num(m[2]) > 0,
        watchDogEnable: _num(m[3]) > 0,
        ramToTableOpening: _num(m[4]),
        kp: _num(m[5]), ki: _num(m[6]), kd: _num(m[7]),
        kpAgg: _num(m[8]), kiAgg: _num(m[9]), kdAgg: _num(m[10])
    }
}
