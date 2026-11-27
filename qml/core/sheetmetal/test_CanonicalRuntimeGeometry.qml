// test_CanonicalRuntimeGeometry.qml — self-test for the visible-panel selector port.
//
// Run:
//   C:\Qt\6.10.1\mingw_64\bin\qml.exe test_CanonicalRuntimeGeometry.qml

import QtQuick 2.15
import "CanonicalRuntimeGeometry.js" as CRG

Item {
    width: 100; height: 100

    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, cond) {
            total++;
            if (cond) { pass++; console.log("PASS  " + name); }
            else console.log("FAIL  " + name);
        }

        // --- branchKeyFromIdentifier ---
        check("F-prefix", CRG.branchKeyFromIdentifier("F1-panel-3") === "F1");
        check("F-prefix multi-digit", CRG.branchKeyFromIdentifier("F12.something") === "F12");
        check("FLANGE hidden", CRG.branchKeyFromIdentifier("HIDDEN-FLANGE:3-x") === "F3");
        check("FLANGE case-insensitive", CRG.branchKeyFromIdentifier("flange:7") === "F7");
        check("no match -> null", CRG.branchKeyFromIdentifier("ROOT") === null);
        check("blank -> null", CRG.branchKeyFromIdentifier("   ") === null);
        check("null -> null", CRG.branchKeyFromIdentifier(null) === null);

        // --- projectPanel: square outer loop, one triangular hole ---
        var square = [ {x:0,y:0}, {x:2,y:0}, {x:2,y:2}, {x:0,y:2} ];
        var hole = [ {x:0.5,y:0.5}, {x:1.5,y:0.5}, {x:1,y:1.5} ];
        var panel = {
            panelId: "F1-a", ownerBendId: "3", outerLoop: square,
            holeLoops: [ hole ], mountEdge: [ {x:0,y:0},{x:2,y:0} ], freeEdge: [ {x:0,y:2},{x:2,y:2} ]
        };
        var owner = CRG.bendOwner(3, 1);
        var body = CRG.projectPanel(panel, owner, 0);
        check("body created", body !== null);
        check("body identity", body.exactIdentity === "F1-a");
        check("body branchKey", body.branchKey === "F1");
        check("body polygon size", body.polygon.length === 4);
        check("body hole kept", body.holeLoops.length === 1);
        check("centroid x", Math.abs(body.centroid.x - 1.0) < 1e-9);
        check("centroid y", Math.abs(body.centroid.y - 1.0) < 1e-9);
        check("bendIds uses sequenceHint", body.bendIds.length === 1 && body.bendIds[0] === 1);
        check("mountEdge carried", body.mountEdge.length === 2);

        // degenerate polygon (<3 pts) -> null
        var bad = { panelId: "F2", ownerBendId: "1", outerLoop: [ {x:0,y:0},{x:1,y:1} ], holeLoops: [] };
        check("degenerate panel null", CRG.projectPanel(bad, CRG.bendOwner(1,1), 0) === null);
        // tiny hole (<3 pts) dropped
        var panel2 = { panelId: "F1", ownerBendId: "1", outerLoop: square, holeLoops: [ [ {x:0,y:0},{x:1,y:0} ] ] };
        var b2 = CRG.projectPanel(panel2, CRG.bendOwner(1,1), 0);
        check("tiny hole dropped", b2.holeLoops.length === 0);

        // --- isVisibleForFrame: earlier-sequence bend always visible ---
        var ctx1 = CRG.createFrameContext({
            currentBend: CRG.bendOwner(5, 3),
            bendsById: { 2: CRG.bendOwner(2, 1) },
            currentFamilies: ["F1"], allFamilies: ["F1","F2"]
        });
        check("earlier-seq visible", CRG.isVisibleForFrame(ctx1, CRG.bendOwner(2, 1), { panelId: "F2-x" }) === true);

        // same-bend, family in currentFamilies -> visible
        var ctx2 = CRG.createFrameContext({
            currentBend: CRG.bendOwner(5, 3),
            currentFamilies: ["F1"], allFamilies: ["F1"]
        });
        check("same-bend family match visible", CRG.isVisibleForFrame(ctx2, CRG.bendOwner(5, 3), { panelId: "F1-y" }) === true);
        check("same-bend family mismatch hidden", CRG.isVisibleForFrame(ctx2, CRG.bendOwner(5, 3), { panelId: "F9-z" }) === false);

        // unrelated future bend (not next-companion) -> hidden
        check("future unrelated hidden", CRG.isVisibleForFrame(ctx2, CRG.bendOwner(7, 6), { panelId: "F1-q" }) === false);

        // --- next-same-family companion case ---
        // current bend: id==seqHint==2; owner: id==seqHint==3 (==current+1);
        // single family, completedVisibleFamilyBendCount==2, panel family == that family.
        var ctxC = CRG.createFrameContext({
            currentBend: CRG.bendOwner(2, 2),
            bendsById: { 3: CRG.bendOwner(3, 3) },
            bendFamiliesById: { 3: ["F1"] },
            currentFamilies: ["F1"], allFamilies: ["F1"],
            completedVisibleFamilyBendCount: 2
        });
        check("next-companion visible", CRG.isVisibleForFrame(ctxC, CRG.bendOwner(3, 3), { panelId: "F1-comp" }) === true);
        // break a precondition (count != 2) -> hidden
        var ctxC2 = CRG.createFrameContext({
            currentBend: CRG.bendOwner(2, 2),
            bendFamiliesById: { 3: ["F1"] },
            currentFamilies: ["F1"], allFamilies: ["F1"],
            completedVisibleFamilyBendCount: 1
        });
        check("next-companion gated by count", CRG.isVisibleForFrame(ctxC2, CRG.bendOwner(3, 3), { panelId: "F1-comp" }) === false);

        // --- projectVisiblePanels: ROOT skipped, visible filtered, sourceIndex increments ---
        var panels = [
            { panelId: "ROOT", ownerBendId: "0", outerLoop: square, holeLoops: [] },
            { panelId: "F1-a", ownerBendId: "2", outerLoop: square, holeLoops: [] }, // earlier seq -> visible
            { panelId: "F9-b", ownerBendId: "5", outerLoop: square, holeLoops: [] }  // same as current bend? id 5 seq? -> check family
        ];
        var ctxP = CRG.createFrameContext({
            currentBend: CRG.bendOwner(5, 3),
            bendsById: { 2: CRG.bendOwner(2, 1), 5: CRG.bendOwner(5, 3) },
            currentFamilies: ["F1"], allFamilies: ["F1","F9"]
        });
        var visible = CRG.projectVisiblePanels(panels, ctxP);
        check("ROOT skipped + filtered", visible.length === 1);
        check("visible panel identity", visible[0].exactIdentity === "F1-a");
        check("sourceIndex starts 0", visible[0].sourceIndex === 0);

        console.log("======================================");
        console.log("CanonicalRuntimeGeometry parity: " + pass + "/" + total + " checks passed");
        console.log("======================================");
        Qt.callLater(Qt.quit);
    }
}
