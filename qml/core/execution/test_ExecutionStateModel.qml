// test_ExecutionStateModel.qml — self-test for the ported execution state machine.
// Validates BendMode/BendPhase tables, ExecutionModel navigation, and
// BendProgramModel.executingBends slicing against the Java semantics.
//
// Run:
//   C:\Qt\6.10.1\mingw_64\bin\qml.exe test_ExecutionStateModel.qml

import QtQuick 2.15
import "ExecutionStateModel.js" as Exec

Item {
    width: 100; height: 100

    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, cond) {
            total++;
            if (cond) { pass++; console.log("PASS  " + name); }
            else console.log("FAIL  " + name);
        }

        // BendMode flags
        check("PROGRAM_BEND_MODE programMode", Exec.BendMode.PROGRAM_BEND_MODE.programMode === true);
        check("PROGRAM_BEND_MODE not repeat", Exec.BendMode.PROGRAM_BEND_MODE.repeatable === false);
        check("PROGRAM_BEND_LOOP repeat", Exec.BendMode.PROGRAM_BEND_LOOP.repeatable === true);
        check("SINGLE_BEND_MODE not program", Exec.BendMode.SINGLE_BEND_MODE.programMode === false);
        check("SINGLE_BEND_REPEAT repeat", Exec.BendMode.SINGLE_BEND_REPEAT.repeatable === true);
        check("fromString roundtrip", Exec.bendModeFromString("PROGRAM BEND LOOP") === Exec.BendMode.PROGRAM_BEND_LOOP);

        // BendPhase
        check("phase seq length 6", Exec.BEND_PHASE_SEQUENCE.length === 6);
        check("BACK_GAUGE_MOVE haveBG", Exec.BendPhase.BACK_GAUGE_MOVE.haveBackgaugeMove === true);
        check("BEND_MOVE noBG", Exec.BendPhase.BEND_MOVE.haveBackgaugeMove === false);
        check("phase[0]=BACK_GAUGE_MOVE", Exec.BEND_PHASE_SEQUENCE[0] === Exec.BendPhase.BACK_GAUGE_MOVE);
        check("phase[4]=BEND_MOVE", Exec.BEND_PHASE_SEQUENCE[4] === Exec.BendPhase.BEND_MOVE);

        // Build a fake program of 4 bends
        var prog = { name: "P", bends: [{ id: 1 }, { id: 2 }, { id: 3 }, { id: 4 }] };
        var st = Exec.createExecution();
        Exec.setSelectedProgram(st, prog);
        check("index reset on program set", st.selectedBendIndex === 0);
        check("selectedBend id 1", Exec.selectedBend(st).id === 1);

        // Program mode (not repeatable): executingBends = bends[index..end]
        st.mode = Exec.BendMode.PROGRAM_BEND_MODE;
        st.selectedBendIndex = 2;
        var eb = Exec.executingBends(st);
        check("program-mode slice from index", eb.length === 2 && eb[0].id === 3 && eb[1].id === 4);

        // Program loop (repeatable): all bends
        st.mode = Exec.BendMode.PROGRAM_BEND_LOOP;
        check("program-loop all bends", Exec.executingBends(st).length === 4);

        // Single-bend mode: just the selected bend
        st.mode = Exec.BendMode.SINGLE_BEND_MODE;
        st.selectedBendIndex = 1;
        var sb = Exec.executingBends(st);
        check("single-bend mode one bend", sb.length === 1 && sb[0].id === 2);

        // nextBend in program mode advances until last
        st.mode = Exec.BendMode.PROGRAM_BEND_MODE;
        st.selectedBendIndex = 0;
        check("nextBend 0->1", Exec.nextBend(st) === true && st.selectedBendIndex === 1);
        st.selectedBendIndex = 3;
        check("nextBend at last false", Exec.nextBend(st) === false && st.selectedBendIndex === 3);

        // saved index
        st.selectedBendIndex = 2;
        Exec.saveBendIndex(st);
        st.selectedBendIndex = 0;
        Exec.toSavedIndex(st);
        check("toSavedIndex restores", st.selectedBendIndex === 2);

        // backGaugeEnabledInProgram
        st.mode = Exec.BendMode.PROGRAM_BEND_LOOP;
        var anyBG = Exec.backGaugeEnabledInProgram(st, function (b) { return b.id === 3; });
        check("backGaugeEnabledInProgram true", anyBG === true);
        var noBG = Exec.backGaugeEnabledInProgram(st, function (b) { return false; });
        check("backGaugeEnabledInProgram false", noBG === false);

        // problematic classification: undefined die/material/punch buckets
        var problems = Exec.problematicExecutingBends(st, function (b) {
            return { punch: null, die: null, material: null };
        });
        check("all undefined die", problems.undefinedDie.length === 4);
        check("all undefined punch", problems.undefinedPunch.length === 4);
        check("not valid when problems", Exec.executingBendsValid(problems) === false);

        var clean = { exceedingTonnage: [], exceedingUpperTravelLimit: [], exceedingLowerTravelLimit: [],
                      undefinedDie: [], undefinedMaterial: [], undefinedPunch: [], notInRangeFinalBendPos: [] };
        check("valid when clean", Exec.executingBendsValid(clean) === true);

        console.log("======================================");
        console.log("ExecutionStateModel parity: " + pass + "/" + total + " checks passed");
        console.log("======================================");
        Qt.callLater(Qt.quit);
    }
}
