// test_DwellAndBailOut.qml — self-test for the ported DwellTimerModel countdown
// reducer and BailOutReason/BailOutModel debounce logic.
//
// Run:
//   C:\Qt\6.10.1\mingw_64\bin\qml.exe test_DwellAndBailOut.qml

import QtQuick 2.15
import "DwellAndBailOut.js" as DB

Item {
    width: 100; height: 100

    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, cond) {
            total++;
            if (cond) { pass++; console.log("PASS  " + name); }
            else console.log("FAIL  " + name);
        }
        function approx(a, b) { return Math.abs(a - b) <= 1e-9; }

        // Dwell timer: 0.3s = 3 ticks of 100ms, pedal held -> FINISHED after countdown.
        var t = DB.createDwellTimer(0.3);
        check("initial FINISHED", t.lastState === DB.DwellTimerState.FINISHED);
        check("start -> RUNNING", DB.startDwellTimer(t) === true && DB.isDwellRunning(t));
        check("remaining = duration", approx(t.remainingSec, 0.3));
        // start again returns false (already running)
        check("double-start no-op", DB.startDwellTimer(t) === false);
        DB.tickDwellTimer(t, true); check("tick1 remaining .2", approx(t.remainingSec, 0.2));
        DB.tickDwellTimer(t, true); check("tick2 remaining .1", approx(t.remainingSec, 0.1));
        DB.tickDwellTimer(t, true); check("tick3 remaining 0", approx(t.remainingSec, 0.0) && DB.isDwellRunning(t));
        DB.tickDwellTimer(t, true); check("tick4 FINISHED", t.lastState === DB.DwellTimerState.FINISHED);
        check("finishedGracefully", DB.isDwellFinishedGracefully(t));

        // Pedal release mid-countdown -> CANCELLED
        var t2 = DB.createDwellTimer(0.5);
        DB.startDwellTimer(t2);
        DB.tickDwellTimer(t2, true);
        DB.tickDwellTimer(t2, false);
        check("pedal release cancels", t2.lastState === DB.DwellTimerState.CANCELLED);

        // BailOutReason enum + ordinals
        check("PedalReleased ordinal 0", DB.bailOutOrdinal(DB.BailOutReason.PedalReleased) === 0);
        check("DwellCancelled not alarm", DB.bailOutIsMachineAlarm(DB.BailOutReason.DwellCancelled) === false);
        check("AntibindTriggered is alarm", DB.bailOutIsMachineAlarm(DB.BailOutReason.AntibindTriggered) === true);
        check("MaxTonnageError is alarm", DB.bailOutIsMachineAlarm(DB.BailOutReason.MaxTonnageError) === true);
        check("fromOrdinal roundtrip", DB.bailOutFromOrdinal(9) === DB.BailOutReason.DwellCancelled);
        var threw = false;
        try { DB.bailOutFromOrdinal(999); } catch (e) { threw = true; }
        check("fromOrdinal OOB throws", threw);

        // BailOut debounce: two fires within 100ms -> second suppressed
        var m = DB.createBailOut();
        check("first fire", DB.onBailOut(m, DB.BailOutReason.PedalReleased, 1000) === true);
        check("reason stored", m.lastBailOutReason === DB.BailOutReason.PedalReleased);
        check("debounced fire", DB.onBailOut(m, DB.BailOutReason.MachineNotIdle, 1050) === false);
        check("reason unchanged", m.lastBailOutReason === DB.BailOutReason.PedalReleased);
        check("fire after latency", DB.onBailOut(m, DB.BailOutReason.MachineNotIdle, 1100) === true);
        check("reason updated", m.lastBailOutReason === DB.BailOutReason.MachineNotIdle);
        DB.setIncludeBackGaugeBailOut(m, false);
        check("includeBG toggle", m.includeBackGaugeBailOut === false);

        console.log("======================================");
        console.log("DwellAndBailOut parity: " + pass + "/" + total + " checks passed");
        console.log("======================================");
        Qt.callLater(Qt.quit);
    }
}
