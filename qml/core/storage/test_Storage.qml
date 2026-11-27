// test_Storage.qml — self-test for EntityEditingManager.js + EntityStorage.js
// Run: $env:QML_XHR_ALLOW_FILE_READ=1; C:\Qt\6.10.1\mingw_64\bin\qml.exe test_Storage.qml
//
// File IO is exercised only against a temp sandbox URL so NO production data is touched.

import QtQuick 2.15
import "EntityEditingManager.js" as EM
import "EntityStorage.js" as ST

Item {
    width: 100; height: 100
    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, cond) {
            total++;
            if (cond) { pass++; console.log("PASS  " + name); }
            else console.log("FAIL  " + name);
        }

        var seq = 0;
        function factory() { return { id: "id-" + (++seq), name: "", stock: false }; }

        // ---------- EntityEditingManager ----------
        var items = [ { id: "a", name: "Alpha", stock: true }, { id: "b", name: "Beta", stock: true } ];
        var mgr = EM.create(items, factory);

        check("auto-selects first", mgr.getSelectedItem() === items[0]);
        check("not creatingNew on existing", mgr.isCreatingNew() === false);

        // addNew -> UNTITLED, creatingNew, not yet in list
        mgr.addNew();
        check("addNew name UNTITLED", mgr.getSelectedItem().name === "UNTITLED");
        check("addNew creatingNew", mgr.isCreatingNew() === true);
        check("addNew not in list yet", items.indexOf(mgr.getSelectedItem()) < 0);

        // edit the live item name then save -> committed + inserted at index 0
        mgr.getLiveEditedItem().name = "Gamma";
        mgr.save();
        check("save inserts at 0", items[0].name === "Gamma");
        check("save selects new", mgr.getSelectedItem() === items[0]);
        check("save clears creatingNew", mgr.isCreatingNew() === false);
        check("list length 3", items.length === 3);

        // addNew twice -> UNTITLED, then UNTITLED 1 (after first saved as UNTITLED)
        mgr.addNew(); mgr.getLiveEditedItem().name = "UNTITLED"; mgr.save();
        mgr.addNew();
        check("second untitled increments", mgr.getSelectedItem().name === "UNTITLED 1");
        mgr.cancel(); // discard the second new

        // duplicate selected (Gamma) -> "Gamma DUPLICATE", stock false, creatingNew
        mgr.setSelectedItem(items[items.length - 1]); // Beta
        mgr.duplicate();
        check("duplicate name suffix", /DUPLICATE$/.test(mgr.getSelectedItem().name));
        check("duplicate stock false", mgr.getSelectedItem().stock === false);
        check("duplicate creatingNew", mgr.isCreatingNew() === true);
        mgr.save();
        check("duplicate saved into list", items.indexOf(mgr.getSelectedItem()) >= 0);

        // duplicate again -> name "... DUPLICATE 1" (nextUnusedName)
        mgr.duplicate(); mgr.save();
        var dupNames = items.map(function (i) { return i.name; }).filter(function (n) { return /DUPLICATE/.test(n); });
        check("two duplicates uniquely named", dupNames.length === 2 && dupNames[0] !== dupNames[1]);

        // isCurrentNameUsed: live name equals another item's name
        mgr.setSelectedItem(items[0]);
        mgr.getLiveEditedItem().name = items[1].name;
        check("isCurrentNameUsed true", mgr.isCurrentNameUsed() === true);
        mgr.getLiveEditedItem().name = "UniqueXYZ";
        check("isCurrentNameUsed false", mgr.isCurrentNameUsed() === false);

        // delete selected -> removed, selects previous/first
        var beforeLen = items.length;
        mgr.setSelectedItem(items[1]);
        mgr.deleteSelected();
        check("delete removes item", items.length === beforeLen - 1);
        check("delete reselects", mgr.getSelectedItem() !== null);

        // cancel during create -> reselect previous
        var prev = mgr.getSelectedItem();
        mgr.addNew();
        mgr.cancel();
        check("cancel-create reselects previous", mgr.getSelectedItem() === prev);

        // ---------- EntityStorage (pure helpers) ----------
        check("parseEntities tolerates NaN", (function () {
            var arr = ST.parseEntities('[{"id":"x","v":NaN}]');
            return arr && arr.length === 1 && arr[0].v === null;
        })());
        check("parseEntities strips BOM", (function () {
            var arr = ST.parseEntities('\uFEFF[{"id":"x"}]');
            return arr && arr.length === 1;
        })());
        check("parseEntities bad -> null", ST.parseEntities("not json") === null);
        check("stringify NaN -> null", ST.stringifyEntities([{ v: NaN }]).indexOf("null") >= 0);
        check("findById hit", ST.findById([{ id: "a" }, { id: "b" }], "b").id === "b");
        check("findById miss", ST.findById([{ id: "a" }], "z") === null);

        // ---------- EntityStorage with an in-memory fake IO backend ----------
        // (Real file:// writes can't create new files in pure QML XHR; the packaged app
        //  injects a C++ FileIO. Here we inject a fake to verify the backup-guard logic.)
        var fs = {};   // url -> text
        var fakeIo = {
            read: function (url) { return Object.prototype.hasOwnProperty.call(fs, url) ? fs[url] : null; },
            write: function (url, text) { fs[url] = text; return true; },
            exists: function (url) { return Object.prototype.hasOwnProperty.call(fs, url); }
        };
        var prod = "file:///prod/dies.json";
        var payload = [ { id: "s1", name: "Sample", stock: false } ];

        // first write (no existing -> no backup)
        var r1 = ST.save(prod, payload, { io: fakeIo, backup: true });
        check("first write ok", r1.ok === true);
        check("first write no backup (file absent)", r1.backupUrl === null);
        var roundTrip = ST.load(prod, null, fakeIo);
        check("round-trip", roundTrip.length === 1 && roundTrip[0].name === "Sample");

        // backup-guarded overwrite: existing present -> .bak created with OLD content
        var r2 = ST.save(prod, [ { id: "s1", name: "Changed", stock: true } ], { io: fakeIo, backup: true });
        check("backup-guarded write ok", r2.ok === true);
        check("backup url returned", r2.backupUrl === prod + ".bak");
        check("backup holds OLD content", ST.load(prod + ".bak", null, fakeIo)[0].name === "Sample");
        check("file holds NEW content", ST.load(prod, null, fakeIo)[0].name === "Changed");

        // refuse overwrite if backup write fails (safety-first)
        var failIo = {
            read: function (url) { return fakeIo.read(url); },
            write: function (url, text) { return url.indexOf(".bak") >= 0 ? false : (fs[url] = text, true); },
            exists: fakeIo.exists
        };
        var r2b = ST.save(prod, [ { id: "s1", name: "ShouldNotApply" } ], { io: failIo, backup: true });
        check("refuses overwrite when backup fails", r2b.ok === false && r2b.reason === "backup-write-failed");
        check("file unchanged after refused write", ST.load(prod, null, fakeIo)[0].name === "Changed");

        // restoreFromBackup rolls back
        check("restore from backup", ST.restoreFromBackup(prod, ".bak", fakeIo) === true);
        check("restored to OLD", ST.load(prod, null, fakeIo)[0].name === "Sample");

        // sandbox mode never writes the production fileUrl (redirects to sandboxUrl)
        var sbUrl = "file:///sandbox/dies.json";
        var r3 = ST.save("file:///prod/never.json", payload, { io: fakeIo, sandbox: true, sandboxUrl: sbUrl });
        check("sandbox-redirect target", r3.ok === true && r3.targetUrl === sbUrl);
        check("production never.json untouched", fakeIo.exists("file:///prod/never.json") === false);
        check("sandbox file written", fakeIo.exists(sbUrl) === true);

        console.log("Storage parity: " + pass + "/" + total + " checks passed");
        Qt.callLater(Qt.quit);
    }
}
