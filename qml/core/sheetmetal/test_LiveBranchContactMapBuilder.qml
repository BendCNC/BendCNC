import QtQuick
import "LiveBranchContactMapBuilder.js" as CB

QtObject {
    property int passed: 0
    property int total: 0
    function chk(name, cond) {
        total++;
        if (cond) { passed++; console.log("PASS  " + name); }
        else console.log("FAIL  " + name);
    }
    function approx(a, b, eps) { return Math.abs(a - b) <= (eps === undefined ? 1e-6 : eps); }

    Component.onCompleted: {
        // ---- empty inputs ----
        chk("null panels -> empty", CB.build(null, [{}]).length === 0);
        chk("empty joints -> empty", CB.build([{}], []).length === 0);

        // ---- scenario: rectangular flange panel ----
        // Mount edge along the bottom (y=0), free edge along the top (y=2).
        // Polygon CCW: (0,0)->(4,0)->(4,2)->(0,2)
        var polygon = [
            { x: 0, y: 0 }, { x: 4, y: 0 }, { x: 4, y: 2 }, { x: 0, y: 2 }
        ];
        var panel = {
            polygon: polygon,
            anchor: { attachStart: { x: 0, y: 0 }, attachEnd: { x: 4, y: 0 } },
            label: "F1:B1",
            bendId: 1,
            labelPoint: { x: 2, y: 1 },      // interior, picks free-edge side
            rootAnchorId: "BEND:1:FLANGE:1"
        };

        // Joint near the mount edge midpoint -> mount contact for owner (seq 1)
        var jointMount = { bendId: 1, sequenceHint: 1, parentExactIdentity: null, livePoint: { x: 2, y: 0.05 } };
        // Joint near the free (top) edge, child of this branch -> free contact
        var jointChild = { bendId: 2, sequenceHint: 2, parentExactIdentity: "BEND:1:FLANGE:1", livePoint: { x: 2, y: 1.95 } };

        var contacts = CB.build([panel], [jointMount, jointChild]);
        chk("two contacts (mount+free)", contacts.length === 2);

        var mount = null, free = null;
        for (var i = 0; i < contacts.length; i++) {
            if (contacts[i].edgeRole === "mount") mount = contacts[i];
            if (contacts[i].edgeRole === "free") free = contacts[i];
        }
        chk("mount contact present", mount !== null);
        chk("free contact present", free !== null);

        if (mount) {
            chk("mount identity", mount.exactIdentity === "BEND:1:FLANGE:1");
            chk("mount joint = owner seq1", mount.jointBendId === 1);
            chk("mount reason owner-mount", mount.matchReason === "owner-mount");
            chk("mount edge along y=0", approx(mount.edgeStart.y, 0) && approx(mount.edgeEnd.y, 0));
            chk("mount distance small", mount.distanceIn < 0.1);
            chk("mount contactPoint x~2", approx(mount.contactPoint.x, 2, 1e-6));
        }
        if (free) {
            chk("free identity", free.exactIdentity === "BEND:1:FLANGE:1");
            chk("free joint = child seq2", free.jointBendId === 2);
            chk("free reason child-free", free.matchReason === "child-free");
            chk("free edge along y=2", approx(free.edgeStart.y, 2) && approx(free.edgeEnd.y, 2));
            chk("free distance small", free.distanceIn < 0.1);
        }

        // sideSign: labelPoint (2,1) relative to mount edge (y=0) normal -> nonzero
        if (mount) chk("mount sideSign nonzero", mount.sideSign !== 0);

        // ---- indexByIdentity ----
        var idx = CB.indexByIdentity(contacts);
        chk("index has identity key", !!idx["BEND:1:FLANGE:1"]);
        chk("index groups both contacts", idx["BEND:1:FLANGE:1"] && idx["BEND:1:FLANGE:1"].length === 2);
        chk("index empty for empty", Object.keys(CB.indexByIdentity([])).length === 0);

        // ---- panel without identity is skipped ----
        var noIdPanel = { polygon: polygon, anchor: panel.anchor, label: "junk", bendId: 9, labelPoint: { x: 2, y: 1 }, rootAnchorId: "nope" };
        chk("no-identity panel skipped", CB.build([noIdPanel], [jointMount]).length === 0);

        // ---- panel with < 3 polygon pts skipped ----
        var thinPanel = { polygon: [{x:0,y:0},{x:1,y:0}], anchor: panel.anchor, label: "F2:B2", bendId: 3, labelPoint: {x:0,y:0}, rootAnchorId: "F2:B2" };
        chk("thin polygon skipped", CB.build([thinPanel], [jointMount]).length === 0);

        // ---- joints without livePoint produce no contacts ----
        chk("no livePoint -> no contacts", CB.build([panel], [{ bendId: 1, sequenceHint: 1, livePoint: null }]).length === 0);

        console.log("LiveBranchContactMapBuilder parity: " + passed + "/" + total + " checks passed");
        Qt.callLater(Qt.quit);
    }
}
