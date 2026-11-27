.pragma library

// CanonicalRuntimeGeometry.js
// Implements the deterministic logic in:
//
// This selects the VISIBLE panels for a live run frame and projects them into
// LiveProjectedBody records (exact identity, branch key, centroid, polygon, holes,
// mount/free edges). It is model-agnostic: callers pass already-parsed panel nodes
// (shape below) instead of a SheetMetalModel, so it works against the QML run
// renderer's preview JSON without porting the full graph/loop model first.
//
// PanelNode shape (plain object):
//   { panelId: "F1...", ownerBendId: "3",
//     outerLoop: [{x,y}, ...] (world points),
//     holeLoops: [ [{x,y}...], ... ],
//     mountEdge: [{x,y}, {x,y}], freeEdge: [{x,y}, {x,y}] }
//
// FrameContext shape (createFrameContext):
//   { currentBend:{id,sequenceHint}, bendsById:{id->{id,sequenceHint}},
//     bendFamiliesById:{id->Set<string>}, currentFamilies:Set<string>,
//     allFamilies:Set<string>, completedVisibleFamilyBendCount:int }

var ROOT_PANEL_ID = "ROOT";   // mirrors SheetMetalPreviewJsonAdapter.ROOT_PANEL_ID
var _FLANGE_PREFIX = /^(F\d+)/;
var _HIDDEN_FLANGE = /FLANGE:(\d+)/i;

// ---- public records as factories ----
function bendOwner(id, sequenceHint) {
    return { id: id | 0, sequenceHint: sequenceHint | 0 };
}

function createFrameContext(opts) {
    opts = opts || {};
    return {
        currentBend: opts.currentBend || null,
        bendsById: opts.bendsById || {},
        bendFamiliesById: opts.bendFamiliesById || {},
        currentFamilies: opts.currentFamilies || [],          // array of strings (acts as Set)
        allFamilies: opts.allFamilies || [],
        completedVisibleFamilyBendCount: opts.completedVisibleFamilyBendCount | 0
    };
}

// projectVisiblePanels(panelNodes, context) -> [LiveProjectedBody]
// panelNodes: array of PanelNode (order = iteration order of model.panelsById().values()).
function projectVisiblePanels(panelNodes, context) {
    if (!panelNodes || !context || !context.currentBend) return [];
    var bodies = [];
    var sourceIndex = 0;
    for (var i = 0; i < panelNodes.length; i++) {
        var panelNode = panelNodes[i];
        if (panelNode.panelId === ROOT_PANEL_ID) continue;
        var ownerBendId = _parseIntOrDefault(panelNode.ownerBendId, -1);
        var ownerBend = ownerBendId <= 0 ? null : (context.bendsById[ownerBendId] || null);
        if (!ownerBend || !isVisibleForFrame(context, ownerBend, panelNode)) continue;
        var body = projectPanel(panelNode, ownerBend, sourceIndex);
        if (body) { bodies.push(body); sourceIndex++; }
    }
    return bodies;
}

// projectPanel(panelNode, ownerBend, sourceIndex) -> LiveProjectedBody | null
function projectPanel(panelNode, ownerBend, sourceIndex) {
    if (!panelNode || !ownerBend) return null;
    var outerWorldPoints = _exportedWorldPoints(panelNode.outerLoop);
    var polygon = _toLivePoints(outerWorldPoints);
    if (polygon.length < 3) return null;
    var holeLoops = [];
    var holes = panelNode.holeLoops || [];
    for (var h = 0; h < holes.length; h++) {
        var liveHole = _toLivePoints(_exportedWorldPoints(holes[h]));
        if (liveHole.length >= 3) holeLoops.push(liveHole);
    }
    var exactIdentity = panelNode.panelId;
    var branchKey = branchKeyFromIdentifier(exactIdentity);
    var c = _centroid(outerWorldPoints);
    var bendIds = ownerBend.sequenceHint > 0 ? [ownerBend.sequenceHint] : [ownerBend.id];
    return {
        sourceIndex: sourceIndex,
        ownerBendId: ownerBend.id,
        bendIds: bendIds,
        exactIdentity: exactIdentity,
        branchKey: branchKey,
        rootIdentity: exactIdentity,
        groupIdentity: exactIdentity,
        centroid: c,
        polygon: polygon,
        holeLoops: holeLoops,
        mountEdge: _toLivePoints(panelNode.mountEdge),
        freeEdge: _toLivePoints(panelNode.freeEdge),
        provenance: {
            sourceIndex: sourceIndex,
            ownerBendId: ownerBend.id,
            exactIdentity: exactIdentity,
            branchKey: branchKey,
            rootIdentity: exactIdentity,
            groupIdentity: exactIdentity
        }
    };
}

// branchKeyFromIdentifier("F1-...") -> "F1"; "FLANGE:3" -> "F3"; else null
function branchKeyFromIdentifier(value) {
    var normalized = _blankToNull(value);
    if (normalized === null) return null;
    var m = _FLANGE_PREFIX.exec(normalized.trim());
    if (m) return m[1];
    var hm = _HIDDEN_FLANGE.exec(normalized);
    if (hm) return "F" + hm[1];
    return null;
}

// ---- visibility decision (CanonicalSheetMetalRuntimeGeometry.isVisibleForFrame) ----
function isVisibleForFrame(context, ownerBend, panelNode) {
    if (!context || !context.currentBend || !ownerBend || !panelNode) return false;
    var currentBend = context.currentBend;
    // Earlier-in-sequence bends are always visible (already formed).
    if (ownerBend.sequenceHint > 0 && currentBend.sequenceHint > 0
        && ownerBend.sequenceHint < currentBend.sequenceHint) {
        return true;
    }
    var panelFamily = branchKeyFromIdentifier(panelNode.panelId);
    var currentFamilies = context.currentFamilies || [];
    if (ownerBend.id === currentBend.id || ownerBend.sequenceHint === currentBend.sequenceHint) {
        return panelFamily === null || currentFamilies.length === 0 || _has(currentFamilies, panelFamily);
    }
    return _isNextSameFamilyCompanionPanel(context, ownerBend, panelNode, panelFamily, currentFamilies);
}

function _isNextSameFamilyCompanionPanel(context, ownerBend, panelNode, panelFamily, currentFamilies) {
    var currentBend = context ? context.currentBend : null;
    if (!context || !currentBend || !ownerBend || !panelNode
        || currentBend.id !== currentBend.sequenceHint
        || ownerBend.id !== ownerBend.sequenceHint
        || ownerBend.sequenceHint !== currentBend.sequenceHint + 1) {
        return false;
    }
    if ((context.allFamilies || []).length !== 1 || (currentFamilies || []).length !== 1) return false;
    var family = currentFamilies[0];
    if (context.completedVisibleFamilyBendCount !== 2) return false;
    if (family !== panelFamily) return false;
    var ownerFamilies = context.bendFamiliesById[ownerBend.id] || [];
    return _has(ownerFamilies, family);
}

// ---- helpers ----
function _exportedWorldPoints(loop) {
    return (loop && loop.length > 0) ? loop : [];
}
function _toLivePoints(points) {
    if (!points || points.length === 0) return [];
    var out = [];
    for (var i = 0; i < points.length; i++) out.push({ x: points[i].x, y: points[i].y });
    return out;
}
function _centroid(points) {
    if (!points || points.length === 0) return { x: 0.0, y: 0.0 };
    var sx = 0.0, sy = 0.0;
    for (var i = 0; i < points.length; i++) { sx += points[i].x; sy += points[i].y; }
    return { x: sx / points.length, y: sy / points.length };
}
function _blankToNull(value) {
    return (value === null || value === undefined || String(value).trim().length === 0) ? null : String(value);
}
function _parseIntOrDefault(value, fallback) {
    if (value === null || value === undefined || String(value).trim().length === 0) return fallback;
    var n = parseInt(String(value).trim(), 10);
    return isNaN(n) ? fallback : n;
}
function _has(arrOrSet, key) {
    if (!arrOrSet) return false;
    if (arrOrSet.indexOf) return arrOrSet.indexOf(key) >= 0;
    return !!arrOrSet[key];
}
