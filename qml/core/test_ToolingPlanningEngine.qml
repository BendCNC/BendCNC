// test_ToolingPlanningEngine.qml — qmlscene/qml parity harness.
// Runs ToolingPlanningEngine.js selectToolingForBend against the golden
// reference produced by golden_reference.py (the "tooling" field per bend).
//
// Run:
//   $env:QML_XHR_ALLOW_FILE_READ=1
//   C:\Qt\6.10.1\mingw_64\bin\qml.exe test_ToolingPlanningEngine.qml

import QtQuick 2.15
import "ToolingPlanningEngine.js" as Tooling

Item {
    width: 200; height: 100

    function readJson(relPath) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relPath), false);
        xhr.send(null);
        var t = xhr.responseText.replace(/:\s*NaN/g, ":null").replace(/\uFEFF/g, "");
        return JSON.parse(t);
    }
    function byId(arr) { var m = {}; for (var i = 0; i < arr.length; ++i) m[arr[i].id] = arr[i]; return m; }

    Component.onCompleted: {
        var bends = readJson("../data/current/bends.json");
        var punchList = readJson("../data/current/punches.json");
        var dieList = readJson("../data/current/dies.json");
        var materials = byId(readJson("../data/current/materials.json"));
        var golden = readJson("golden_reference.json");
        var goldenById = {};
        for (var g = 0; g < golden.length; ++g) goldenById[golden[g].id] = golden[g].tooling;

        var total = 0, passed = 0;
        for (var i = 0; i < bends.length; ++i) {
            var b = bends[i];
            var ref = goldenById[b.id];
            if (!ref) { continue; }
            var mat = materials[b.materialId];
            if (!mat) { continue; }
            var tb = {
                angleDeg: Number(b.desiredBendAngle),
                lengthIn: Number(b.bendWidth),
                thicknessIn: Number(b.materialThickness),
                chainDepth: 0,
                processBgPositionIn: b.backGaugeXPosition !== undefined && b.backGaugeXPosition !== null
                    ? Math.abs(Number(b.backGaugeXPosition)) : 0.0,
                parentBendId: null,
                referenceType: null,
                thicknessLabel: null
            };
            var sel = Tooling.selectToolingForBend(mat, tb, punchList, dieList);
            total++;
            if (sel && sel.punch.id === ref.punchId && sel.die.id === ref.dieId && sel.cost === ref.cost) {
                passed++;
                console.log("PASS  " + b.name);
            } else {
                console.log("FAIL  " + b.name + "  got=" + (sel ? (sel.punch.id + "/" + sel.die.id + " cost=" + sel.cost) : "null")
                    + "  exp=" + ref.punchId + "/" + ref.dieId + " cost=" + ref.cost);
            }
        }
        console.log("======================================");
        console.log("ToolingPlanningEngine parity: " + passed + "/" + total + " bends matched golden selection");
        console.log("======================================");
        Qt.callLater(Qt.quit);
    }
}
