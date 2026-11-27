// test_LiveJointContactIntegration.qml
// Verifies LivePlacementJointMap + LiveBranchContactMapBuilder compose end-to-end:
// the joint map's contactBuilder hook is wired to the contact builder and produces
// contacts indexed by branch identity in the returned graph.
//
// Run: C:\Qt\6.10.1\mingw_64\bin\qml.exe test_LiveJointContactIntegration.qml

import QtQuick 2.15
import "LivePlacementJointMap.js" as JM
import "LiveBranchContactMapBuilder.js" as CB

Item {
    width: 100; height: 100
    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, cond) {
            total++;
            if (cond) { pass++; console.log("PASS  " + name); }
            else console.log("FAIL  " + name);
        }

        // Scene: 2 completed bends, current = bend 2.
        var bend1 = { id: 1, sequenceHint: 1, closestSide: "NEG", midXIn: 2, midYIn: 0, bendLineInstanceId: "L1" };
        var bend2 = { id: 2, sequenceHint: 2, closestSide: "POS", midXIn: 2, midYIn: 2, bendLineInstanceId: "L2" };
        var data = {
            currentBend: bend2,
            bends: [bend1, bend2],
            bendById: { 1: bend1, 2: bend2 },
            topologySnapshot: { branchesByExactIdentity: {
                "BEND:1:FLANGE:1": { exactIdentity: "BEND:1:FLANGE:1", ownerBendId: 1, ownerSequenceHint: 1, bendClosestSide: "NEG", parentExactIdentity: null, chainDepth: 0 }
            } }
        };

        // One orthogonal flange panel for branch BEND:1:FLANGE:1.
        var polygon = [ { x: 0, y: 0 }, { x: 4, y: 0 }, { x: 4, y: 2 }, { x: 0, y: 2 } ];
        var panels = [ {
            polygon: polygon,
            anchor: { attachStart: { x: 0, y: 0 }, attachEnd: { x: 4, y: 0 } },
            label: "F1:B1",
            bendId: 1,
            labelPoint: { x: 2, y: 1 },
            rootAnchorId: "BEND:1:FLANGE:1"
        } ];

        var resolvers = {
            // joint 1 lives near the mount edge (owner), joint 2 near the free edge.
            placementLineResolver: function(b) { return null; },
            sameAxisResolver: function(b) { return false; },
            liveJointPointResolver: function(b, p) {
                return b.id === 1 ? { x: 2, y: 0.05 } : { x: 2, y: 1.95 };
            },
            parentIdentityResolver: function(b) {
                return b.id === 2 ? "BEND:1:FLANGE:1" : null;
            },
            visibleRootResolver: function() {
                return JM.resolveVisibleCompletedRootIdentities(data, data.currentBend);
            },
            contactBuilder: function(orthoPanels, joints) {
                var contacts = CB.build(orthoPanels, joints);
                return { contacts: contacts, contactsByIdentity: CB.indexByIdentity(contacts) };
            }
        };

        var graph = JM.build(data, panels, resolvers);

        check("joints built (2)", graph.joints.length === 2);
        check("visible root = BEND:1:FLANGE:1", graph.visibleCompletedRootIdentities.length === 1
              && graph.visibleCompletedRootIdentities[0] === "BEND:1:FLANGE:1");
        check("branch depth present", graph.branchDepthByExactIdentity["BEND:1:FLANGE:1"] === 0);

        check("contacts produced", graph.contacts.length === 2);
        check("contacts indexed by identity", !!graph.contactsByExactIdentity["BEND:1:FLANGE:1"]
              && graph.contactsByExactIdentity["BEND:1:FLANGE:1"].length === 2);

        var mount = null, free = null;
        for (var i = 0; i < graph.contacts.length; i++) {
            if (graph.contacts[i].edgeRole === "mount") mount = graph.contacts[i];
            if (graph.contacts[i].edgeRole === "free") free = graph.contacts[i];
        }
        check("mount contact -> owner joint (bend1)", mount && mount.jointBendId === 1 && mount.matchReason === "owner-mount");
        check("free contact -> child joint (bend2)", free && free.jointBendId === 2 && free.matchReason === "child-free");

        console.log("LiveJointContact integration: " + pass + "/" + total + " checks passed");
        Qt.callLater(Qt.quit);
    }
}
