// test_LivePlacementJointMap.qml — self-test for LivePlacementJointMap.js
//
// Run: C:\Qt\6.10.1\mingw_64\bin\qml.exe test_LivePlacementJointMap.qml

import QtQuick 2.15
import "LivePlacementJointMap.js" as JM

Item {
    width: 100; height: 100
    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, cond) {
            total++;
            if (cond) { pass++; console.log("PASS  " + name); }
            else console.log("FAIL  " + name);
        }

        // --- empty / guard cases ---
        check("null data -> empty", JM.build(null, [], {}).joints.length === 0);
        check("no currentBend -> empty", JM.build({ bends: [] }, [], {}).joints.length === 0);

        // --- buildJoints: sequence filter + SEGMENT/POINT + side normalize + parent + mid ---
        var data = {
            currentBend: { id: 3, sequenceHint: 2, closestSide: "pos" },
            bends: [
                { id: 1, sequenceHint: 1, closestSide: "neg", midXIn: 4, midYIn: 6, bendLineInstanceId: " " },
                { id: 3, sequenceHint: 2, closestSide: "POS", midXIn: 0, midYIn: 0, bendLineInstanceId: "bl-3" },
                { id: 9, sequenceHint: 5, closestSide: "neg", midXIn: 1, midYIn: 1 }, // future -> excluded
                { id: 0, sequenceHint: 0, closestSide: "neg" }                         // seq 0 -> excluded
            ],
            bendById: {},
            topologySnapshot: null
        };
        var resolvers = {
            placementLineResolver: function (b) {
                return b.id === 1 ? { start: { x: 0, y: 0 }, end: { x: 10, y: 4 } } : null;
            },
            sameAxisResolver: function (b) { return b.id === 1; },
            parentIdentityResolver: function (b) { return b.id === 3 ? "F1-root" : null; }
        };
        var g = JM.build(data, [], resolvers);
        check("joints count (seq filter)", g.joints.length === 2);

        var j1 = g.joints[0], j3 = g.joints[1];
        check("bend1 SEGMENT", j1.projectionKind === "SEGMENT");
        check("bend3 POINT", j3.projectionKind === "POINT");
        check("side normalized upper", j1.visibleSide === "NEG" && j3.visibleSide === "POS");
        check("placement midpoint from line", Math.abs(j1.placementMidpoint.x - 5) < 1e-9 && Math.abs(j1.placementMidpoint.y - 2) < 1e-9);
        check("no line -> mid from bend midXY", j3.placementMidpoint.x === 0 && j3.placementMidpoint.y === 0);
        check("parent identity carried", j3.parentExactIdentity === "F1-root");
        check("blank bendLineInstanceId -> null", j1.bendLineInstanceId === null);
        check("bendLineInstanceId kept", j3.bendLineInstanceId === "bl-3");

        // --- branch depths ---
        var data2 = {
            currentBend: { id: 2, sequenceHint: 3, closestSide: "POS" },
            bends: [],
            bendById: {},
            topologySnapshot: {
                branchesByExactIdentity: {
                    "F1": { exactIdentity: "F1", chainDepth: 0, ownerBendId: 1, ownerSequenceHint: 1, bendClosestSide: "NEG", parentExactIdentity: null },
                    "F2": { exactIdentity: "F2", chainDepth: 2, ownerBendId: 2, ownerSequenceHint: 2, bendClosestSide: "POS", parentExactIdentity: "F1" },
                    "blank": { exactIdentity: "   ", chainDepth: 5 }
                }
            }
        };
        var g2 = JM.build(data2, [], {});
        check("branch depth F1", g2.branchDepthByExactIdentity["F1"] === 0);
        check("branch depth F2", g2.branchDepthByExactIdentity["F2"] === 2);
        check("blank-identity branch skipped in depths", g2.branchDepthByExactIdentity["   "] === undefined);

        // --- resolveVisibleCompletedRootIdentities ---
        // current side POS -> visible side NEG. Completed (seq<current=3), non-child, side NEG.
        var roots = JM.resolveVisibleCompletedRootIdentities(data2, data2.currentBend);
        check("visible root = F1 (NEG side, completed, root)", roots.length === 1 && roots[0] === "F1");
        // F2 excluded: child branch (parent set / depth>0) AND wrong side.

        // no side -> empty
        check("unknown side -> empty roots",
            JM.resolveVisibleCompletedRootIdentities(data2, { sequenceHint: 3, closestSide: "?" }).length === 0);

        // --- contactBuilder callback wired ---
        var g3 = JM.build(data, [], {
            contactBuilder: function () { return { contacts: [{ exactIdentity: "X" }], contactsByIdentity: { X: [{}] } }; }
        });
        check("contactBuilder wired", g3.contacts.length === 1 && g3.contactsByExactIdentity["X"].length === 1);
        check("default no contacts", g.contacts.length === 0);

        console.log("======================================");
        console.log("LivePlacementJointMap parity: " + pass + "/" + total + " checks passed");
        console.log("======================================");
        Qt.callLater(Qt.quit);
    }
}
