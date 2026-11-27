// test_BackGauge.qml — Phase 6.3 self-test for BackGauge.js (GRBL command + status).
// Run: $env:QML_XHR_ALLOW_FILE_READ=1; & qml.exe test_BackGauge.qml ; expect RESULT N/N
import QtQuick 2.15
import "BackGauge.js" as BG

Item {
    width: 10; height: 10
    Component.onCompleted: {
        var pass = 0, total = 0
        function check(n, c) { total++; if (c) { pass++; console.log("PASS  " + n) } else console.log("FAIL  " + n) }
        function close(a, b) { return Math.abs(a - b) < 1e-6 }

        // ---- move-to ordering -----------------------------------------------
        // advancing (currentX 2.0 < targetX 5.0): X first, then Y
        var adv = BG.moveToCommands(BG.Unit.INCH, BG.CoordinateSystem.G54, 2.0, 5.0, 1.5, 30.0)
        check("advance two commands", adv.length === 2)
        check("advance X first", adv[0] === "G20 G90 G54 G1 X5.0000 F30.00")
        check("advance Y second", adv[1] === "G20 G90 G54 G1 Y1.5000 F30.00")
        // retracting (currentX 6.0 > targetX 1.0): Y first, then X
        var ret = BG.moveToCommands(BG.Unit.INCH, BG.CoordinateSystem.G55, 6.0, 1.0, 0.25, 20.0)
        check("retract Y first", ret[0] === "G20 G90 G55 G1 Y0.2500 F20.00")
        check("retract X second", ret[1] === "G20 G90 G55 G1 X1.0000 F20.00")
        // mm units
        var mm = BG.moveToCommands(BG.Unit.MILLIMETER, BG.CoordinateSystem.G56, 0, 10, 5, 100)
        check("mm unit word G21", mm[0].indexOf("G21") === 0)

        // ---- bump (incremental) ---------------------------------------------
        var bump = BG.bumpCommand(BG.Unit.INCH, BG.CoordinateSystem.G54, BG.Axis.X, 0.05, 10.0)
        check("bump command G91 incremental", bump === "G20 G91 G54 X 0.0500 F 10.00")
        var bumpNeg = BG.bumpCommand(BG.Unit.INCH, BG.CoordinateSystem.G59, BG.Axis.Y, -0.1, 5.0)
        check("bump neg axis Y", bumpNeg === "G20 G91 G59 Y -0.1000 F 5.00")

        // ---- homing ----------------------------------------------------------
        check("homing command", BG.homingCommand() === "$H")

        // ---- coordinate-system enum -----------------------------------------
        check("G54 altCode P1", BG.CoordinateSystem.G54.altCode === "P1")
        check("G59 altCode P6", BG.CoordinateSystem.G59.altCode === "P6")

        // ---- status decode: WPos form ---------------------------------------
        var st = BG.decodeStatus("<Idle|MPos:1.000,2.000,0.000|WPos:0.500,1.500,0.000|FS:0,0>")
        check("status state Idle", st.state === "Idle")
        check("status mpos x", close(st.mpos.x, 1.0))
        check("status wpos y", close(st.wpos.y, 1.5))

        // ---- status decode: MPos+WCO derives WPos ---------------------------
        var st2 = BG.decodeStatus("<Run|MPos:5.000,3.000,0.000|WCO:1.000,0.500,0.000>")
        check("derived wpos x", close(st2.wpos.x, 4.0))
        check("derived wpos y", close(st2.wpos.y, 2.5))
        check("status state Run", st2.state === "Run")

        // ---- non-status line -------------------------------------------------
        check("ok line not status", BG.decodeStatus("ok") === null)
        check("empty not status", BG.decodeStatus("") === null)

        // ---- display name ----------------------------------------------------
        var names = { list: { G54: "Front Edge", G55: "Center" } }
        check("display name resolved", BG.coordinateSystemDisplayName(names, BG.CoordinateSystem.G54) === "Front Edge")
        check("display name fallback", BG.coordinateSystemDisplayName(null, BG.CoordinateSystem.G57) === "G57")

        console.log("RESULT " + pass + "/" + total)
        Qt.quit()
    }
}
