// test_BendCalculator.qml — qmlscene golden-file parity harness.
// Loads real data/current/*.json, resolves each bend, runs BendCalculator.js,
// and compares against golden_reference.json (produced by golden_reference.py).
//
// Run:
//   C:\Qt\6.10.1\mingw_64\bin\qmlscene.exe test_BendCalculator.qml
// Prints PASS/FAIL per bend and an overall summary, then quits.

import QtQuick 2.15
import "BendCalculator.js" as BendCalculator

Item {
    id: root
    width: 200; height: 100

    function readJson(relPath) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relPath), false);
        xhr.send(null);
        if (xhr.status !== 200 && xhr.status !== 0)
            throw new Error("Failed to read " + relPath + " status=" + xhr.status);
        var text = xhr.responseText;
        // The Java app serializes NaN literally (e.g. "segmentCount16In":NaN), which is
        // invalid JSON. Replace bare NaN tokens with null so JSON.parse succeeds.
        text = text.replace(/:\s*NaN/g, ":null").replace(/\uFEFF/g, "");
        return JSON.parse(text);
    }

    function byId(arr) {
        var m = {};
        for (var i = 0; i < arr.length; ++i) m[arr[i].id] = arr[i];
        return m;
    }

    function approxEq(a, b, tol) {
        if (typeof a === "boolean" || typeof b === "boolean") return a === b;
        if (a === null || b === null) return a === b;
        if (!isFinite(a) && !isFinite(b)) return true; // NaN/Inf parity
        return Math.abs(a - b) <= tol;
    }

    Component.onCompleted: {
        var TOL = 1e-9;
        var bends = readJson("../data/current/bends.json");
        var punches = byId(readJson("../data/current/punches.json"));
        var dies = byId(readJson("../data/current/dies.json"));
        var materials = byId(readJson("../data/current/materials.json"));
        var golden = readJson("golden_reference.json");
        var goldenById = {};
        for (var g = 0; g < golden.length; ++g) goldenById[golden[g].id] = golden[g].result;

        var checkedKeys = [
            "startSafetyClearance", "clampPosition", "totalBendStroke",
            "calculatedFinalBendPosition", "inUseFinalBendPosition", "retractAfterBend",
            "bendTonnage", "predictedInsideBendRadius",
            "finalBendPositionMin", "finalBendPositionMax",
            "punchToMaterialClearanceWarning", "tonnageWarning", "tonnageError",
            "upperLimitExceededError", "lowerLimitExceededError",
            "finalBendPositionOutLimit", "errorCount"
        ];

        var total = 0, passed = 0;
        for (var i = 0; i < bends.length; ++i) {
            var b = bends[i];
            var ref = goldenById[b.id];
            if (!ref) { console.log("SKIP (no golden): " + b.name); continue; }
            var r = BendCalculator.computeBend({
                bend: b,
                punch: punches[b.punchId],
                die: dies[b.dieId],
                material: materials[b.materialId]
            });
            total++;
            var ok = true;
            var diffs = [];
            for (var k = 0; k < checkedKeys.length; ++k) {
                var key = checkedKeys[k];
                if (!approxEq(r[key], ref[key], TOL)) {
                    ok = false;
                    diffs.push(key + " got=" + r[key] + " exp=" + ref[key]);
                }
            }
            if (ok) { passed++; console.log("PASS  " + b.name); }
            else    { console.log("FAIL  " + b.name + "  ->  " + diffs.join("; ")); }
        }
        console.log("======================================");
        console.log("BendCalculator parity: " + passed + "/" + total + " bends matched golden reference");
        console.log("======================================");
        Qt.callLater(Qt.quit);
    }
}
