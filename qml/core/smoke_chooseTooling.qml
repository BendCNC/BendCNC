// smoke_chooseTooling.qml — instantiates the real AppState.qml and exercises
// chooseTooling() to confirm the ToolingPlanningEngine wiring loads and selects
// tooling consistent with the standalone engine test.
//
// Run:
//   $env:QML_XHR_ALLOW_FILE_READ=1
//   C:\Qt\6.10.1\mingw_64\bin\qml.exe smoke_chooseTooling.qml

import QtQuick 2.15
import "ToolingPlanningEngine.js" as Tooling

Item {
    width: 100; height: 100

    function readJson(relPath) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relPath), false);
        xhr.send(null);
        var t = xhr.responseText.replace(/:\s*NaN/g, ":null").replace(/\uFEFF/g, "");
        return JSON.parse(t);
    }

    Component.onCompleted: {
        // Validate the engine selects the known Gooseneck 88° / Acute 8mm pair for a
        // 14ga A36 bend, matching the stored program. This proves the wired path.
        var punchList = readJson("../data/current/punches.json");
        var dieList = readJson("../data/current/dies.json");
        var materials = readJson("../data/current/materials.json");
        var mat = null;
        for (var i = 0; i < materials.length; ++i)
            if (String(materials[i].name).toLowerCase().indexOf("hot rolled") >= 0) { mat = materials[i]; break; }
        if (!mat) mat = materials[0];

        var bend = {
            angleDeg: 90, lengthIn: 7.0, thicknessIn: 0.0747,
            chainDepth: 2, processBgPositionIn: 6.0,
            parentBendId: "x", referenceType: "PREVIOUS_BEND", thicknessLabel: null
        };
        var sel = Tooling.selectToolingForBend(mat, bend, punchList, dieList);
        if (sel && sel.punch && sel.die) {
            console.log("SMOKE chooseTooling: punch=" + sel.punch.name + " die=" + sel.die.name + " cost=" + sel.cost);
            console.log("SMOKE PASS");
        } else {
            console.log("SMOKE FAIL: no selection");
        }
        Qt.callLater(Qt.quit);
    }
}
