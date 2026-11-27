.pragma library

// EntityEditingManager.js
// list of StorageEntity-like items (die / punch / material / program).
//
// property bindings are replaced with explicit state on a returned manager object
// plus an injected "bridge" that mirrors EntityBridge (live-edit buffer). The bridge is
// the only stateful collaborator; storage IO is separate (EntityStorage.js).
//
// Entity shape (minimum): { id, name, stock, ... }   (plain objects)
//
// Bridge contract (inject; a default in-memory bridge is provided by makeBridge):
//   bridge.bind(getSelected)          // selected-item supplier
//   bridge.commit()                   // copy live edits back into the selected item
//   bridge.reload()                   // discard edits, reload from selected item
//   bridge.copyValuesTo(target)       // copy live-edited values into target
//   bridge.setFromDefault()           // reset live item to factory defaults
//   bridge.isDifferent()              // live item differs from selected
//   bridge.liveItem                   // the live-edited entity object
//
// itemFactory()  -> new blank entity (plain object)

// ---- default in-memory bridge (mirrors EntityBridge semantics for the ported fields) ----
function makeBridge(itemFactory, trackedKeys) {
    trackedKeys = trackedKeys || ["name", "stock"];
    var live = itemFactory();
    var snapshot = {};          // last committed/loaded values of the selected item
    var getSelected = function () { return null; };

    function copyTracked(src, dst) {
        for (var i = 0; i < trackedKeys.length; i++) {
            var k = trackedKeys[i];
            dst[k] = src ? src[k] : undefined;
        }
    }

    return {
        liveItem: live,
        bind: function (selectedSupplier) {
            getSelected = selectedSupplier;
            this.reload();
        },
        reload: function () {
            var sel = getSelected();
            copyTracked(sel, live);
            snapshot = {};
            copyTracked(sel, snapshot);
        },
        commit: function () {
            var sel = getSelected();
            if (sel) {
                copyTracked(live, sel);
                snapshot = {};
                copyTracked(live, snapshot);
            }
        },
        copyValuesTo: function (target) { copyTracked(live, target); },
        setFromDefault: function () {
            var def = itemFactory();
            copyTracked(def, live);
        },
        isDifferent: function () {
            for (var i = 0; i < trackedKeys.length; i++) {
                var k = trackedKeys[i];
                if (live[k] !== snapshot[k]) return true;
            }
            return false;
        }
    };
}

// ---- editing manager ----
function create(items, itemFactory, bridge, options) {
    options = options || {};
    bridge = bridge || makeBridge(itemFactory, options.trackedKeys);

    var mgr = {
        items: items || [],          // ObservableList<T> -> plain array (mutate in place)
        selectedItem: null,
        previousItem: null,
        untitledName: options.untitledName || "UNTITLED",
        duplicateSuffix: options.duplicateSuffix || "DUPLICATE",
        bridge: bridge,
        itemFactory: itemFactory
    };

    function setSelected(item) {
        mgr.selectedItem = item;
        // initBindings: bridge.source bound to selectedItem; reload live edits
        bridge.bind(function () { return mgr.selectedItem; });
        // selectedItem listener: null while non-empty -> auto-select first
        if (mgr.selectedItem === null && mgr.items.length > 0) {
            mgr.selectedItem = mgr.items[0];
            bridge.bind(function () { return mgr.selectedItem; });
        }
    }

    // initAutoSelect: if items non-empty and nothing selected, select first
    if (mgr.items.length > 0 && mgr.selectedItem === null) {
        setSelected(mgr.items[0]);
    } else {
        bridge.bind(function () { return mgr.selectedItem; });
    }

    // creatingNew = selectedItem != null && !items.contains(selectedItem)
    mgr.isCreatingNew = function () {
        return mgr.selectedItem !== null && mgr.items.indexOf(mgr.selectedItem) < 0;
    };

    mgr.setSelectedItem = function (item) { setSelected(item); };
    mgr.getSelectedItem = function () { return mgr.selectedItem; };
    mgr.getLiveEditedItem = function () { return bridge.liveItem; };
    mgr.liveEditedItemChanged = function () { return bridge.isDifferent(); };

    mgr.addNew = function () {
        var newItem = itemFactory();
        newItem.name = nextUnusedName(mgr, mgr.untitledName);
        mgr.previousItem = mgr.selectedItem;
        setSelected(newItem);
    };

    mgr.save = function () {
        bridge.commit();
        if (mgr.isCreatingNew()) {
            mgr.items.unshift(mgr.selectedItem);   // items.add(0, selected)
            setSelected(mgr.items[0]);
        }
    };

    mgr.duplicate = function () {
        var newItem = itemFactory();
        bridge.copyValuesTo(newItem);
        newItem.name = nextDuplicateName(mgr, newItem.name);
        newItem.stock = false;
        mgr.previousItem = mgr.selectedItem;
        setSelected(newItem);
    };

    mgr.deleteSelected = function () {
        var idx = mgr.items.indexOf(mgr.selectedItem);
        if (idx >= 0) mgr.items.splice(idx, 1);
        selectPreviousItem(mgr, setSelected);
    };

    mgr.cancel = function () {
        if (mgr.isCreatingNew()) selectPreviousItem(mgr, setSelected);
        else bridge.reload();
    };

    mgr.setFromDefaults = function () {
        var name = bridge.liveItem.name;
        bridge.setFromDefault();
        bridge.liveItem.name = name;
    };

    mgr.isCurrentNameUsed = function () {
        for (var i = 0; i < mgr.items.length; i++) {
            var item = mgr.items[i];
            if (item !== mgr.selectedItem && item.name === bridge.liveItem.name) return true;
        }
        return false;
    };

    return mgr;
}

// ---- name helpers (1:1 with Java) ----
function selectPreviousItem(mgr, setSelected) {
    if (mgr.previousItem !== null && mgr.items.indexOf(mgr.previousItem) >= 0) {
        setSelected(mgr.previousItem);
        mgr.bridge.reload();
    } else if (mgr.items.length > 0) {
        setSelected(mgr.items[0]);
    } else {
        setSelected(null);
    }
}

function nextDuplicateName(mgr, name) {
    // Java: regex = "%s\\s\\d+$" with duplicateSuffix; strip trailing "SUFFIX 12" -> "SUFFIX"
    var suffix = mgr.duplicateSuffix;
    var regex = new RegExp(suffix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\s\\d+$");
    name = String(name).replace(regex, suffix);
    if (!name.endsWith(suffix)) name = name + " " + suffix;
    return nextUnusedName(mgr, name);
}

function nextUnusedName(mgr, nameBase) {
    var names = mgr.items.map(function (it) { return it.name; });
    if (names.indexOf(nameBase) < 0) return nameBase;
    for (var i = 1; i < 1000; i++) {
        var name = nameBase + " " + i;
        if (names.indexOf(name) < 0) return name;
    }
    throw new Error("Could not find unused name with index less then 1000");
}
