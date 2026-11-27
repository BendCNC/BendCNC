// test_MachineController.qml — Phase 6.1/6.2 self-test: MachineController + MockPressDevice.
// Drives the mock firmware through the controller end-to-end (connect, jog,
// motion ticks, COMPLETED, abort, alarm) with no real serial port.
// Run: $env:QML_XHR_ALLOW_FILE_READ=1; & qml.exe test_MachineController.qml ; expect RESULT N/N
import QtQuick 2.15
import "MachineController.js" as MC
import "MockPressDevice.js" as Mock

Item {
    width: 10; height: 10
    Component.onCompleted: {
        var pass = 0, total = 0
        function check(n, c) { total++; if (c) { pass++; console.log("PASS  " + n) } else console.log("FAIL  " + n) }
        function close(a, b) { return Math.abs(a - b) < 1e-6 }

        // ---- state lookup + alarm ------------------------------------------
        check("lookUp IDLE", MC.lookUpState("IDLE") === MC.State.IDLE)
        check("lookUp normalizes spaces/slashes", MC.lookUpState("Y1/Y2 NEG TONN FAIL") === MC.State.Y1_Y2_NEG_TONN_FAIL)
        check("lookUp unknown", MC.lookUpState("totally bogus").name === "UNKNOWN")
        check("alarm code MAX_TONNAGE", MC.State.MAX_TONNAGE_ERROR.alarmCode === 11)
        check("isAlarm true for alarm state", MC.isAlarmState(MC.State.ANTIBIND_TRIGGERED) === true)
        check("isAlarm false for IDLE", MC.isAlarmState(MC.State.IDLE) === false)
        check("stateLabel spaces", MC.stateLabel(MC.State.SAFETY_JOG) === "SAFETY JOG")

        // ---- controller event capture --------------------------------------
        var events = { status: 0, completed: [], alarms: [], eeprom: 0, welcome: null, pedal: 0 }
        var ctrl = MC.createController({
            onStatus: function (s) { events.status++ },
            onCompleted: function (op) { events.completed.push(op) },
            onAlarm: function (st) { events.alarms.push(st.name) },
            onEeprom: function (e) { events.eeprom++ },
            onWelcome: function (v) { events.welcome = v },
            onPedalReleased: function () { events.pedal++ }
        })

        var dev = Mock.createMockDevice({ stepInch: 0.05 })
        function pump() { var lines = dev.drain(); for (var i = 0; i < lines.length; i++) ctrl.ingestLine(lines[i]) }

        // connect -> welcome + eeprom + temp + status
        dev.connect(); pump()
        check("welcome captured", events.welcome === "1.0")
        check("eeprom captured", events.eeprom === 1)
        check("controller connected", ctrl.isConnected() === true)
        check("eeprom ramToTable bound", close(ctrl.getEeprom().ramToTableOpening, 0.0))
        check("eeprom maxTon", close(ctrl.getEeprom().maxTonnageThreshold, 25.0))

        // ---- jog to -1.0 inch via SAFETY -----------------------------------
        var cmd = ctrl.jogCommand(-1.0, 5.0, "safety")
        check("jog command format", cmd === "-1.0000, 5.0000, safety")
        dev.send(cmd); pump()
        check("device busy after jog", dev.isBusy() === true)
        check("state SAFETY JOG", ctrl.getStatus().state === MC.State.SAFETY_JOG)

        // tick until COMPLETED (target -1.0, step 0.05 => 20 ticks)
        var guard = 0
        while (dev.isBusy() && guard < 200) { dev.tick(); pump(); guard++ }
        check("device reached target", close(dev.ramPosition(), -1.0))
        check("device idle after complete", dev.isBusy() === false)
        check("completed event fired safety", events.completed.indexOf("SAFETY") >= 0)
        check("status state IDLE after complete", ctrl.getStatus().state === MC.State.IDLE)
        check("commandedJogPos reflects target", close(ctrl.getStatus().commandedJogPos, -1.0))

        // ---- abort -----------------------------------------------------------
        dev.send(ctrl.jogCommand(-2.0, 5.0, "bend")); pump()
        check("busy after bend jog", dev.isBusy() === true)
        var abort = ctrl.abortCommand("CANCEL")
        check("abort token lowercased", abort === "cancel")
        dev.send(abort); pump()
        check("device idle after abort", dev.isBusy() === false)

        // ---- alarm injection -------------------------------------------------
        ctrl.ingestLine("<MAX TONNAGE ERROR|-1|-1|0|0|-1|-1|5|0|0|0|0|0|0|0>")
        check("alarm state detected", ctrl.isAlarm() === true)
        check("alarm callback fired", events.alarms.indexOf("MAX_TONNAGE_ERROR") >= 0)

        // ---- pedal released --------------------------------------------------
        ctrl.ingestLine("[PEDAL RELEASED]")
        check("pedal released callback", events.pedal === 1)

        // ---- temporary status reducer ---------------------------------------
        ctrl.ingestLine("{TEMP:0.5|1|12.5|1}")
        check("temp status folded", ctrl.getStatus().temporaryStatus !== null
            && ctrl.getStatus().temporaryStatus.primingEnabled === true
            && close(ctrl.getStatus().temporaryStatus.manualModeMaxTonnage, 12.5))

        console.log("RESULT " + pass + "/" + total)
        Qt.quit()
    }
}
