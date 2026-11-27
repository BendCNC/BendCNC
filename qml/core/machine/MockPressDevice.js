// MockPressDevice.js — Phase 6.1: deterministic firmware simulator used as the
// DEFAULT press device (the real machine is NOT connected in this environment).
//
// It mimics the LS-BEND firmware closely enough for the run/manual UI to drive
// against: it accepts encoded jog commands (from MachineController.jogCommand),
// advances a virtual ram toward the commanded position in fixed-size steps per
// `tick()`, and emits the same line protocol the real device would (general
// status frames "<...>", a temporary status, EEPROM dump, welcome banner, and a
// "[<JOGTYPE> COMPLETED]" line when a move finishes). All output is produced as
// strings; a host loop feeds them into MachineController.ingestLine.
//
// PURE + deterministic (no timers, no IO). The caller decides cadence by calling
// tick(); each tick advances motion by `stepInch` (default 0.05"). Verified by
// test_MockPressDevice.qml.

.pragma library

// Default disconnected-machine constants (match limits.json / settings defaults).
var DEFAULTS = {
    ramToTableOpening: 0.0,
    maxTonnageThreshold: 25.0,
    manualModeMaxTonnage: 12.5,
    stepInch: 0.05,          // ram travel per tick
    jogSpeedInch: 5.0,
    safetyRetractInch: 0.5
}

// Create a mock device. opts may override DEFAULTS. The device starts in
// STARTUP_HOMING_REQUIRED and emits a welcome banner on connect().
function createMockDevice(opts) {
    var cfg = {}
    for (var k in DEFAULTS) cfg[k] = DEFAULTS[k]
    if (opts) for (var o in opts) if (opts.hasOwnProperty(o)) cfg[o] = opts[o]

    var ram = 0.0                 // current ram (Y) position, inches
    var target = 0.0              // commanded target
    var stateName = "STARTUP_HOMING_REQUIRED"
    var activeJogType = null      // "safety"|"retract"|"clamp"|"bend"|"bump"|null
    var pedalPressed = false
    var connected = false
    var outbox = []               // queued lines for the host to read

    // Map jog type -> the firmware run-state it drives while moving.
    function stateForJog(jogType) {
        switch (jogType) {
        case "safety": return "SAFETY JOG"
        case "clamp": return "CLAMP JOG"
        case "bend": return "BEND JOG"
        case "retract": return "RETRACT JOG"
        case "bump": return "HOMING BUMP"
        default: return "IDLE"
        }
    }

    function pad(n) { return Number(n).toFixed(3) }

    // Build a general-status frame mirroring the firmware's 15+ field layout.
    function statusFrame() {
        var distToGo = Math.abs(target - ram)
        var y1Ton = activeJogType === "bend" ? 2.4 : 0.0
        var velocity = activeJogType ? cfg.jogSpeedInch : 0.0
        var fields = [
            stateName,
            pad(ram), pad(ram),          // y1Pos, y2Pos (locked together in mock)
            "0.000",                     // yError
            pad(velocity),               // velocity
            pad(target),                 // targetPos
            pad(target),                 // commJogPos
            pad(cfg.jogSpeedInch),       // jogSpeed
            "0", "0",                    // safetyJogL, safetyJogR (0 => sensor open)
            pedalPressed ? "1" : "0",    // bendJogPedal
            pad(distToGo),               // distToGo
            pad(y1Ton), pad(y1Ton),      // y1Ton, y2Ton
            activeJogType ? "1" : "0"    // abState (active/busy)
        ]
        return "<" + fields.join("|") + ">"
    }

    function temporaryFrame() {
        return "{TEMP:" + pad(cfg.safetyRetractInch) + "|0|" + pad(cfg.manualModeMaxTonnage) + "|0}"
    }

    function eepromFrame() {
        return "{EEPROM:" + pad(cfg.maxTonnageThreshold) + "|0|1|" + pad(cfg.ramToTableOpening)
            + "|1.0|0.1|0.01|2.0|0.2|0.02}"
    }

    function emit(line) { outbox.push(line) }

    return {
        // connect(): emit welcome + initial EEPROM + first status. Idempotent.
        connect: function () {
            if (connected) return
            connected = true
            stateName = "STARTUP HOMING REQUIRED"
            emit("[LS-BEND v1.0]")
            emit(eepromFrame())
            emit(temporaryFrame())
            emit(statusFrame())
        },

        // Accept an encoded command string (jog "pos, speed, type" or an abort token).
        send: function (command) {
            var s = String(command).trim()
            // abort tokens are single lowercase words
            if (s === "forbidden" || s === "cancel" || s === "stop") {
                activeJogType = null
                stateName = "IDLE"
                emit(statusFrame())
                return
            }
            var parts = s.split(",")
            if (parts.length >= 3) {
                target = parseFloat(parts[0])
                cfg.jogSpeedInch = parseFloat(parts[1]) || cfg.jogSpeedInch
                activeJogType = parts[2].trim()
                stateName = stateForJog(activeJogType)
                emit(statusFrame())
            }
        },

        // tick(): advance motion by stepInch toward target; emit a status frame
        // and, when the target is reached, a COMPLETED line + return to IDLE.
        tick: function () {
            if (!connected || activeJogType === null) {
                emit(statusFrame())
                return
            }
            var remaining = target - ram
            var step = cfg.stepInch
            if (Math.abs(remaining) <= step) {
                ram = target
                var finishedType = activeJogType
                activeJogType = null
                stateName = "IDLE"
                emit(statusFrame())
                emit("[" + finishedType.toUpperCase() + " COMPLETED]")
            } else {
                ram += (remaining > 0 ? step : -step)
                emit(statusFrame())
            }
        },

        setPedal: function (pressed) { pedalPressed = pressed === true },

        // Drain queued output lines (the host feeds these into the controller).
        drain: function () { var out = outbox.slice(0); outbox = []; return out; },

        // Inspection helpers for tests.
        ramPosition: function () { return ram; },
        isBusy: function () { return activeJogType !== null; },
        currentState: function () { return stateName; }
    }
}
