// test_protocol.qml — Phase 6.1 self-test for protocol.js (encode + decode).
// Run: $env:QML_XHR_ALLOW_FILE_READ=1; & qml.exe test_protocol.qml ; expect RESULT N/N
import QtQuick 2.15
import "protocol.js" as P

Item {
    width: 10; height: 10
    Component.onCompleted: {
        var pass = 0, total = 0
        function check(n, c) { total++; if (c) { pass++; console.log("PASS  " + n) } else console.log("FAIL  " + n) }
        function close(a, b) { return Math.abs(a - b) < 1e-9 }

        // ---- encode ---------------------------------------------------------
        check("encodeJog bend", P.encodeJog(-1.2345, 5.0, P.JogType.BEND) === "-1.2345, 5.0000, bend")
        check("encodeJog safety", P.encodeJog(0.05, 100.0, P.JogType.SAFETY) === "0.0500, 100.0000, safety")
        check("encodeAbort cancel", P.encodeAbort(P.AbortJogType.CANCEL) === "cancel")
        check("encodeAbort stop upper-in", P.encodeAbort("STOP") === "stop")

        // ---- general status -------------------------------------------------
        var g = P.decode("<RUN|-1.000|-1.002|0.002|3.5|-1.0|-0.5|5.0|0|1|1|0.25|2.4|2.4|1>")
        check("general kind", g.kind === P.MessageKind.GENERAL_STATUS)
        check("general state", g.state === "RUN")
        check("general y1Pos", close(g.y1Pos, -1.0))
        check("general safetyJogL true when 0", g.safetyJogL === true)
        check("general safetyJogR false when 1", g.safetyJogR === false)
        check("general pedal true when 1", g.bendJogPedal === true)
        check("general abState true when 1", g.abState === true)
        check("general distToGo", close(g.distToGo, 0.25))
        // < 15 fields -> unknown
        check("general too few fields -> unknown", P.decode("<RUN|1|2>").kind === P.MessageKind.UNKNOWN)
        // optional loop field
        var gLoop = P.decode("<RUN|-1|-1|0|0|-1|-1|5|0|0|0|0|0|0|0|7>")
        check("general loop parsed", gLoop.loop === 7)
        // nan tolerant
        var gNan = P.decode("<RUN|nan|-1|0|0|-1|-1|5|0|0|0|0|0|0|0>")
        check("general nan -> NaN", isNaN(gNan.y1Pos))

        // ---- temporary status ----------------------------------------------
        var t = P.decode("{TEMP:0.5|1|12.5|0}")
        check("temp kind", t.kind === P.MessageKind.TEMPORARY_STATUS)
        check("temp safetyRetract", close(t.bendSafetyRetract, 0.5))
        check("temp manualEnable true", t.manualModeEnable === true)
        check("temp maxTon", close(t.manualModeMaxTonnagePerRam, 12.5))
        check("temp priming false", t.primingModeEnable === false)
        check("temp malformed -> unknown", P.decode("{TEMP:x|y}").kind === P.MessageKind.UNKNOWN)

        // ---- eeprom ---------------------------------------------------------
        var e = P.decode("{EEPROM:25.0|1|0|8.25|1.1|2.2|3.3|4.4|5.5|6.6}")
        check("eeprom kind", e.kind === P.MessageKind.EEPROM)
        check("eeprom maxTon", close(e.maxTonnageThreshold, 25.0))
        check("eeprom defl enable >0", e.deflectionCompEnable === true)
        check("eeprom wdog 0 -> false", e.watchDogEnable === false)
        check("eeprom ramToTable", close(e.ramToTableOpening, 8.25))
        check("eeprom kpAgg", close(e.kpAgg, 4.4))

        // ---- text messages --------------------------------------------------
        check("pedal released", P.decode("[PEDAL RELEASED]").kind === P.MessageKind.PEDAL_RELEASED)
        check("limp mode", P.decode("[LIMP MODE]").kind === P.MessageKind.LIMP_MODE)
        var w = P.decode("[LS-BEND v1.2a]")
        check("welcome kind+version", w.kind === P.MessageKind.WELCOME && w.version === "1.2a")
        var echo = P.decode("[RECEIVED STRING: hello world]")
        check("echo string", echo.kind === P.MessageKind.ECHO && echo.string === "hello world")
        var fail = P.decode("[HOMING FAIL]")
        check("fail type", fail.kind === P.MessageKind.FAIL && fail.failType === "HOMING")
        var err = P.decode("[RETRACT ERROR]")
        check("error type", err.kind === P.MessageKind.ERROR && err.errorType === "RETRACT")
        var rst = P.decode("[SOFT RESET]")
        check("reset type", rst.kind === P.MessageKind.RESET && rst.resetType === "SOFT")
        var comp = P.decode("[JOG COMPLETED]")
        check("completed op", comp.kind === P.MessageKind.OPERATION_COMPLETED && comp.operation === "JOG")
        var unexp = P.decode("[MACHINE NOT IDLE]")
        check("unexpected state", unexp.kind === P.MessageKind.UNEXPECTED_STATE && unexp.state === "IDLE")
        var inv = P.decode("[INVALID JOG TYPE]")
        check("invalid type", inv.kind === P.MessageKind.INVALID && inv.type === "JOG TYPE")
        var ack = P.decode("[SS_OK]")
        check("firmware ack", ack.kind === P.MessageKind.FIRMWARE_ACK && ack.command === "SS" && ack.status === "OK")

        // ---- specificity: FAIL beats ack ------------------------------------
        check("FAIL beats ack pattern", P.decode("[HOMING FAIL]").kind === P.MessageKind.FAIL)

        // ---- junk -----------------------------------------------------------
        check("empty -> unknown", P.decode("").kind === P.MessageKind.UNKNOWN)
        check("null -> unknown", P.decode(null).kind === P.MessageKind.UNKNOWN)
        check("garbage -> unknown", P.decode("hello").kind === P.MessageKind.UNKNOWN)

        console.log("RESULT " + pass + "/" + total)
        Qt.quit()
    }
}
