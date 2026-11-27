.pragma library

// LivePlacementJointMap.js
// Implements the deterministic logic in:
//
// Builds the live joint graph for a run frame: per-bend joints (SEGMENT/POINT,
// normalized visible side, parent identity, placement line/midpoint/live point),
// branch depths, visible completed root identities, and (optionally) contacts.
//
// Java functional-interface resolvers are passed as JS callbacks in `resolvers`:
//   placementLineResolver(bend)              -> {start:{x,y}, end:{x,y}} | null
//   sameAxisResolver(bend)                   -> bool
//   liveJointPointResolver(bend, panels)     -> {x,y} | null
//   parentIdentityResolver(bend)             -> string | null
//   visibleRootResolver()                    -> [string]    (visible completed roots)
//   contactBuilder(orthogonalPanels, joints) -> { contacts:[...], contactsByIdentity:{} }
//                                               (defaults to empty; port of LiveBranchContactMapBuilder)
//
// ExecutionSceneData shape expected (subset used here):
//   { currentBend:{id,sequenceHint,closestSide}, bends:[PreviewBend],
//     bendById:{id->PreviewBend},
//     topologySnapshot:{ branchesByExactIdentity:{ id->BranchNode } } | null }
// PreviewBend subset: { id, sequenceHint, closestSide, midXIn, midYIn, bendLineInstanceId }
// BranchNode subset: { exactIdentity, ownerBendId, ownerSequenceHint, bendClosestSide,
//                      parentExactIdentity, chainDepth }

function emptyGraph() {
    return {
        joints: [],
        visibleCompletedRootIdentities: [],
        branchDepthByExactIdentity: {},
        contacts: [],
        contactsByExactIdentity: {}
    };
}

function build(data, orthogonalPanels, resolvers) {
    resolvers = resolvers || {};
    if (!data || !data.currentBend || !data.bends) return emptyGraph();
    var joints = _buildJoints(data, orthogonalPanels, resolvers);
    var visibleRoots = resolvers.visibleRootResolver ? (resolvers.visibleRootResolver() || []) : [];
    var branchDepths = _resolveBranchDepths(data);
    var contactResult = resolvers.contactBuilder
        ? (resolvers.contactBuilder(orthogonalPanels, joints) || { contacts: [], contactsByIdentity: {} })
        : { contacts: [], contactsByIdentity: {} };
    return {
        joints: joints,
        visibleCompletedRootIdentities: visibleRoots,
        branchDepthByExactIdentity: branchDepths,
        contacts: contactResult.contacts || [],
        contactsByExactIdentity: contactResult.contactsByIdentity || {}
    };
}

// resolveVisibleCompletedRootIdentities: completed root branches on the side that
// becomes visible (opposite the current bend's closest side), excluding child branches.
function resolveVisibleCompletedRootIdentities(data, currentBend) {
    if (!data || !data.topologySnapshot || !currentBend || currentBend.sequenceHint <= 0) return [];
    var currentSide = _normalizeSide(currentBend.closestSide);
    var visibleSide = currentSide === "POS" ? "NEG" : (currentSide === "NEG" ? "POS" : null);
    if (visibleSide === null) return [];
    var roots = [];           // ordered, unique (LinkedHashMap.keySet)
    var seen = {};
    var branches = data.topologySnapshot.branchesByExactIdentity || {};
    for (var key in branches) {
        var node = branches[key];
        var ownerBend = (data.bendById && node) ? (data.bendById[node.ownerBendId] || null) : null;
        var ownerSequence = (ownerBend && ownerBend.sequenceHint > 0)
            ? ownerBend.sequenceHint
            : (node ? node.ownerSequenceHint : -1);
        var ownerSide = node ? node.bendClosestSide : (ownerBend ? ownerBend.closestSide : null);
        if (!node
            || _blankToNull(node.exactIdentity) === null
            || ownerSequence <= 0
            || ownerSequence >= currentBend.sequenceHint
            || _isTopologyChildBranch(node)
            || visibleSide !== _normalizeSide(ownerSide)) {
            continue;
        }
        if (!seen[node.exactIdentity]) { seen[node.exactIdentity] = true; roots.push(node.exactIdentity); }
    }
    return roots;
}

// ---- internals ----
function _buildJoints(data, orthogonalPanels, resolvers) {
    var joints = [];
    var bends = data.bends;
    var currentSeq = data.currentBend.sequenceHint;
    for (var i = 0; i < bends.length; i++) {
        var bend = bends[i];
        if (!bend || bend.sequenceHint <= 0 || bend.sequenceHint > currentSeq) continue;
        var placementLine = resolvers.placementLineResolver ? resolvers.placementLineResolver(bend) : null;
        var placementMid = placementLine
            ? _midpoint(placementLine.start, placementLine.end)
            : { x: bend.midXIn, y: bend.midYIn };
        var sameAxis = resolvers.sameAxisResolver ? !!resolvers.sameAxisResolver(bend) : false;
        var livePoint = resolvers.liveJointPointResolver ? resolvers.liveJointPointResolver(bend, orthogonalPanels) : null;
        var parentExactIdentity = resolvers.parentIdentityResolver ? resolvers.parentIdentityResolver(bend) : null;
        joints.push({
            bendId: bend.id,
            sequenceHint: bend.sequenceHint,
            projectionKind: sameAxis ? "SEGMENT" : "POINT",
            visibleSide: _normalizeSide(bend.closestSide),
            parentExactIdentity: parentExactIdentity,
            bendLineInstanceId: _blankToNull(bend.bendLineInstanceId),
            placementStart: placementLine ? placementLine.start : null,
            placementEnd: placementLine ? placementLine.end : null,
            placementMidpoint: placementMid,
            livePoint: livePoint
        });
    }
    return joints;
}

function _resolveBranchDepths(data) {
    if (!data || !data.topologySnapshot || !data.topologySnapshot.branchesByExactIdentity) return {};
    var depths = {};
    var branches = data.topologySnapshot.branchesByExactIdentity;
    for (var key in branches) {
        var node = branches[key];
        if (node && _blankToNull(node.exactIdentity) !== null) depths[node.exactIdentity] = node.chainDepth;
    }
    return depths;
}

function _midpoint(a, b) {
    if (!a || !b) return null;
    return { x: (a.x + b.x) / 2.0, y: (a.y + b.y) / 2.0 };
}
function _normalizeSide(side) {
    var v = _blankToNull(side);
    return v === null ? null : v.trim().toUpperCase();
}
function _isTopologyChildBranch(node) {
    return !!node && (_blankToNull(node.parentExactIdentity) !== null || node.chainDepth > 0);
}
function _blankToNull(value) {
    if (value === null || value === undefined) return null;
    var t = String(value).trim();
    return t.length === 0 ? null : t;
}
