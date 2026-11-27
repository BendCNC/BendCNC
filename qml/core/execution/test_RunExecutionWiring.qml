// test_RunExecutionWiring.qml — validates the execution-phase progression contract
// that AppState.advanceExecutionPhase()/completeCurrentBendExecution() implement,
// driving ExecutionStateModel + DwellAndBailOut exactly as AppState does (without
// instantiating the full AppState graph, which needs Settings/DataStore).
//
// Run:
//   C:\Qt\6.10.1\mingw_64\bin\qml.exe test_RunExecutionWiring.qml

import QtQuick 2.15
import "ExecutionStateModel.js" as ExecutionModel
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

        // --- Mini AppState mirror (same logic as AppState.qml run wiring) ---
        var app = {
            bendMode: "PROGRAM_BEND_MODE",
            activeProgram: "P",
            programBends: [ { name: "b1" }, { name: "b2" } ],
            selectedRunBend: 0,
            runActive: false,
            autoClampEnabled: false,
            dwellPedalHeld: true,
            executionPhaseIndex: 0,
            executionPhase: "STARTING",
            dwellTimerState: null,
            bailOutState: null,
            lastBailOutReason: "",
            dwellStartedForBend: false,
            finished: false,
            bailedOut: false
        };
        function progMode() { return app.bendMode === "PROGRAM_BEND_MODE" || app.bendMode === "PROGRAM_BEND_LOOP"; }
        function repeatable() { return app.bendMode === "SINGLE_BEND_REPEAT" || app.bendMode === "PROGRAM_BEND_LOOP"; }
        function runPhaseSequence() {
            var P = ExecutionModel.BendPhase;
            return [ P.STARTING.name, P.BACK_GAUGE_MOVE.name, P.SAFETY_CLEARANCE_POSITION_MOVE.name,
                     P.CLAMP_MATERIAL_MOVE.name, P.BACK_GAUGE_BUMP_MOVE.name, P.DWELL_TIMER_WAIT.name,
                     P.BEND_MOVE.name, P.BACK_GAUGE_AND_RAM_RETRACT_MOVE.name ];
        }
        function execStateFor(index) {
            var s = ExecutionModel.createExecution();
            s.mode = ExecutionModel.BendMode[app.bendMode] || ExecutionModel.BendMode.PROGRAM_BEND_MODE;
            ExecutionModel.setSelectedProgram(s, { name: app.activeProgram, bends: app.programBends });
            s.selectedBendIndex = Math.max(0, index);
            return s;
        }
        function begin() {
            app.runActive = true;
            app.executionPhaseIndex = 0;
            app.executionPhase = ExecutionModel.BendPhase.STARTING.name;
            app.dwellTimerState = DB.createDwellTimer(0.2);
            app.bailOutState = DB.createBailOut();
            app.dwellStartedForBend = false;
            app.finished = false; app.bailedOut = false; app.lastBailOutReason = "";
        }
        function bailOut(reason) {
            DB.onBailOut(app.bailOutState, reason, Date.now());
            app.lastBailOutReason = reason; app.runActive = false; app.bailedOut = true;
        }
        function completeBend() {
            var s = execStateFor(app.selectedRunBend);
            var hasNext = ExecutionModel.nextBend(s);
            if (hasNext && progMode()) {
                app.selectedRunBend = s.selectedBendIndex;
                app.executionPhaseIndex = 0;
                app.executionPhase = ExecutionModel.BendPhase.STARTING.name;
                app.dwellTimerState = DB.createDwellTimer(0.2);
                app.dwellStartedForBend = false;
            } else if (repeatable()) {
                if (progMode()) app.selectedRunBend = 0;
                app.executionPhaseIndex = 0;
                app.executionPhase = ExecutionModel.BendPhase.STARTING.name;
                app.dwellTimerState = DB.createDwellTimer(0.2);
                app.dwellStartedForBend = false;
            } else {
                app.runActive = false; app.finished = true;
            }
        }
        function advance() {
            if (!app.runActive) return app.executionPhase;
            var seq = runPhaseSequence();
            var cur = (app.executionPhaseIndex < seq.length) ? seq[app.executionPhaseIndex] : null;
            if (cur === ExecutionModel.BendPhase.DWELL_TIMER_WAIT.name && app.autoClampEnabled && app.dwellTimerState) {
                if (!app.dwellStartedForBend) { DB.startDwellTimer(app.dwellTimerState); app.dwellStartedForBend = true; }
                if (DB.isDwellRunning(app.dwellTimerState)) {
                    var st = DB.tickDwellTimer(app.dwellTimerState, app.dwellPedalHeld);
                    app.executionPhase = ExecutionModel.BendPhase.DWELL_TIMER_WAIT.name;
                    if (st === DB.DwellTimerState.CANCELLED) { bailOut(DB.BailOutReason.DwellCancelled); return app.executionPhase; }
                    if (st !== DB.DwellTimerState.FINISHED) return app.executionPhase;
                }
            }
            app.executionPhaseIndex += 1;
            if (app.executionPhaseIndex >= seq.length) { completeBend(); return app.executionPhase; }
            app.executionPhase = seq[app.executionPhaseIndex];
            return app.executionPhase;
        }

        // --- Test 1: program mode, auto-clamp OFF, 2 bends -> finishes ---
        begin();
        var guard = 0, phases = [];
        while (app.runActive && guard++ < 100) { advance(); phases.push(app.executionPhase); }
        check("program run finishes", app.finished === true);
        check("ended on last bend index", app.selectedRunBend === 1);
        // sequence has 6 phases per bend; first phase after STARTING is BACK_GAUGE_MOVE
        check("walked back_gauge_move", phases.indexOf("BACK_GAUGE_MOVE") >= 0);
        check("walked bend_move", phases.indexOf("BEND_MOVE") >= 0);

        // --- Test 2: dwell gating with auto-clamp ON, pedal held -> completes ---
        app.bendMode = "SINGLE_BEND_MODE"; app.programBends = [ { name: "b1" } ]; app.selectedRunBend = 0;
        app.autoClampEnabled = true; app.dwellPedalHeld = true;
        begin();
        var dwellHoldTicks = 0; guard = 0;
        while (app.runActive && guard++ < 100) {
            var wasDwell = (app.executionPhaseIndex < runPhaseSequence().length)
                            && runPhaseSequence()[app.executionPhaseIndex] === "DWELL_TIMER_WAIT";
            var idxBefore = app.executionPhaseIndex;
            advance();
            // counted as a hold tick when the phase index did NOT advance while on dwell
            if (wasDwell && app.executionPhaseIndex === idxBefore) dwellHoldTicks++;
        }
        check("single-bend dwell run finishes", app.finished === true);
        check("dwell held >=1 tick", dwellHoldTicks >= 1);

        // --- Test 3: dwell cancel on pedal release -> bail out DwellCancelled ---
        app.bendMode = "SINGLE_BEND_MODE"; app.programBends = [ { name: "b1" } ]; app.selectedRunBend = 0;
        app.autoClampEnabled = true; app.dwellPedalHeld = true;
        begin();
        guard = 0;
        // advance until DWELL becomes the current phase index (not yet ticked)
        while (app.runActive && guard++ < 100) {
            var seqNow = runPhaseSequence();
            if (app.executionPhaseIndex < seqNow.length && seqNow[app.executionPhaseIndex] === "DWELL_TIMER_WAIT")
                break;
            advance();
        }
        var atDwell = (app.executionPhaseIndex < runPhaseSequence().length)
                       && runPhaseSequence()[app.executionPhaseIndex] === "DWELL_TIMER_WAIT";
        check("reached dwell phase", atDwell === true);
        // first dwell tick starts + ticks the timer (pedal held)
        advance();
        // release pedal; next tick must cancel -> bail out
        app.dwellPedalHeld = false;
        advance();
        check("pedal release bails out", app.bailedOut === true);
        check("bail reason DwellCancelled", app.lastBailOutReason === DB.BailOutReason.DwellCancelled);
        check("run no longer active", app.runActive === false);

        // --- Test 4: program LOOP mode repeats (does not 'finish') ---
        app.bendMode = "PROGRAM_BEND_LOOP"; app.programBends = [ { name: "b1" }, { name: "b2" } ]; app.selectedRunBend = 0;
        app.autoClampEnabled = false;
        begin();
        guard = 0;
        while (app.runActive && guard++ < 50) advance();
        check("loop mode never finishes", app.finished === false && app.runActive === true);

        console.log("======================================");
        console.log("RunExecutionWiring parity: " + pass + "/" + total + " checks passed");
        console.log("======================================");
        Qt.callLater(Qt.quit);
    }
}
