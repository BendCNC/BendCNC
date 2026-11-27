.pragma library

// LiveBranchContactMapBuilder.js
// LiveJointSideViewResolver. Pure, qmlscene-compatible.
//
// Shapes (plain objects):
//   Point      = { x, y }
//   Segment    = { a:Point, b:Point }
//   FlangePanel = {
//       polygon: [Point],           // CCW/CW loop, >= 3 pts
//       anchor:  { attachStart:Point, attachEnd:Point } | null,
//       label:   string | null,
//       bendId:  int,
//       labelPoint: Point | null,
//       rootAnchorId: string | null
//   }
//   LivePlacementJoint = { bendId, sequenceHint, parentExactIdentity, livePoint:Point|null, ... }
//
// build(panels, joints)  -> [LiveJointContact]
// indexByIdentity(contacts) -> { exactIdentity: [LiveJointContact] }
//
// LiveJointContact = {
//   exactIdentity, label, panelBendId, jointBendId, jointLabel, edgeRole,
//   distanceIn, sideSign, edgeStart, edgeEnd, contactPoint, matchReason
// }

// ---------------- public API ----------------

function build(panels, joints) {
    if (!panels || panels.length === 0 || !joints || joints.length === 0) return [];
    var contacts = [];
    for (var i = 0; i < panels.length; i++) {
        var panel = panels[i];
        if (!panel || !panel.polygon || panel.polygon.length < 3) continue;
        var exactIdentity = _exactBranchIdentityForPanel(panel);
        if (exactIdentity === null) continue;

        var anchor = panel.anchor || null;
        var mountEdge = _resolveVisiblePanelMountEdge(panel.polygon, anchor);
        var freeEdge = _resolveVisiblePanelFreeEdge(panel.polygon, anchor);
        if (mountEdge === null && anchor && anchor.attachStart && anchor.attachEnd) {
            mountEdge = { a: anchor.attachStart, b: anchor.attachEnd };
        }
        _addContact(contacts, panel, exactIdentity, "mount", mountEdge, joints);
        _addContact(contacts, panel, exactIdentity, "free", freeEdge, joints);
    }
    return contacts;
}

function indexByIdentity(contacts) {
    if (!contacts || contacts.length === 0) return {};
    var indexed = {};
    for (var i = 0; i < contacts.length; i++) {
        var c = contacts[i];
        if (!c || _blankToNull(c.exactIdentity) === null) continue;
        if (!indexed[c.exactIdentity]) indexed[c.exactIdentity] = [];
        indexed[c.exactIdentity].push(c);
    }
    return indexed;
}

// Public wrappers used by the Run live-overlay skeleton drawing (Phase 3.3).
// Mirror RunExecutionPreviewRenderer.resolve(Diagnostic)VisiblePanelMountEdge /
// resolveVisiblePanelFreeEdge / closestPointOnSegment. Return {a:Point, b:Point} | null.
function resolveVisiblePanelMountEdge(polygon, anchor) {
    var edge = _resolveVisiblePanelMountEdge(polygon, anchor);
    if (edge === null && anchor && anchor.attachStart && anchor.attachEnd) {
        edge = { a: anchor.attachStart, b: anchor.attachEnd };
    }
    return edge;
}

function resolveVisiblePanelFreeEdge(polygon, anchor) {
    return _resolveVisiblePanelFreeEdge(polygon, anchor);
}

function closestPointOnSegment(p, a, b) {
    return _closestPointOnSegment(p, a, b);
}

function midpoint(a, b) {
    return _midpoint(a, b);
}

// ---------------- contact scoring ----------------

var MAX_OWNER_MOUNT_DISTANCE_IN = 0.12;
var MAX_CHILD_FREE_DISTANCE_IN = 0.18;
var MAX_RELATED_EDGE_DISTANCE_IN = 0.25;

function _candidateDistanceLimit(edgeRole, ownerJoint, branchFeedsJoint, samePanelBend) {
    if (edgeRole === "mount" && ownerJoint) return MAX_OWNER_MOUNT_DISTANCE_IN;
    if (edgeRole === "free" && branchFeedsJoint) return MAX_CHILD_FREE_DISTANCE_IN;
    if (branchFeedsJoint || samePanelBend || ownerJoint) return MAX_RELATED_EDGE_DISTANCE_IN;
    return -1.0;
}

function _addContact(contacts, panel, exactIdentity, edgeRole, edge, joints) {
    if (!contacts || !panel || !exactIdentity || !edgeRole || !edge || !joints) return;
    if (!edge.a || !edge.b) return;

    var bestJoint = null;
    var bestCandidate = null;
    var bestScore = Number.NEGATIVE_INFINITY;
    for (var j = 0; j < joints.length; j++) {
        var joint = joints[j];
        if (!joint || !joint.livePoint) continue;
        var candidate = _scoreCandidate(panel, exactIdentity, edgeRole, edge, joint);
        if (candidate === null) continue;
        if (candidate.score > bestScore) {
            bestScore = candidate.score;
            bestCandidate = candidate;
            bestJoint = joint;
        }
    }
    if (bestJoint === null || bestCandidate === null) return;

    var sideSign = _resolvePanelSideSign(panel, edge);
    contacts.push({
        exactIdentity: exactIdentity,
        label: _blankToNull(panel.label),
        panelBendId: panel.bendId,
        jointBendId: bestJoint.bendId,
        jointLabel: "J" + bestJoint.sequenceHint,
        edgeRole: edgeRole,
        distanceIn: bestCandidate.distanceIn,
        distanceLimitIn: bestCandidate.distanceLimitIn,
        sideSign: sideSign,
        edgeStart: edge.a,
        edgeEnd: edge.b,
        contactPoint: bestCandidate.contactPoint,
        matchReason: bestCandidate.matchReason
    });
}

function _scoreCandidate(panel, exactIdentity, edgeRole, edge, joint) {
    if (!panel || !exactIdentity || !edgeRole || !edge || !joint || !joint.livePoint) return null;
    var contactPoint = _closestPointOnSegment(joint.livePoint, edge.a, edge.b);
    if (contactPoint === null) return null;
    var physicalDistance = _distanceBetween(contactPoint, joint.livePoint);
    if (!isFinite(physicalDistance)) return null;

    var ownerSequence = _branchBendSequenceFromIdentifier(exactIdentity);
    var ownerJoint = ownerSequence === joint.sequenceHint;
    var branchFeedsJoint = exactIdentity === _blankToNull(joint.parentExactIdentity);
    var samePanelBend = panel.bendId === joint.bendId;
    var mountEdge = edgeRole === "mount";
    var freeEdge = edgeRole === "free";
    var distanceLimit = _candidateDistanceLimit(edgeRole, ownerJoint, branchFeedsJoint, samePanelBend);
    if (!(distanceLimit >= 0.0) || physicalDistance > distanceLimit) return null;
    var edgeLength = _distanceBetween(edge.a, edge.b);
    var endpointDistance = Math.min(_distanceBetween(edge.a, joint.livePoint),
                                    _distanceBetween(edge.b, joint.livePoint));

    var score = -physicalDistance * 1000.0;
    var reason = "nearest-edge";
    if (mountEdge && ownerJoint) { score += 20000.0; reason = "owner-mount"; }
    if (freeEdge && branchFeedsJoint) { score += 18000.0; reason = "child-free"; }
    else if (branchFeedsJoint) { score += 9000.0; reason = "child-edge"; }
    if (samePanelBend) {
        score += 1500.0;
        if (reason === "nearest-edge") reason = "panel-bend";
    }
    if (ownerJoint) {
        score += 800.0;
        if (reason === "nearest-edge") reason = "owner";
    }
    if (isFinite(endpointDistance)) score -= endpointDistance * 0.10;
    if (isFinite(edgeLength)) score += Math.min(edgeLength, 24.0) * 0.01;

    return { score: score, distanceIn: physicalDistance, distanceLimitIn: distanceLimit, contactPoint: contactPoint, matchReason: reason };
}

// ---------------- edge resolution ----------------

function _resolveVisiblePanelMountEdge(polygon, anchor) {
    if (!anchor || !anchor.attachStart || !anchor.attachEnd || !polygon || polygon.length < 3) return null;
    var mountDir = _normalizeVector(_vector(anchor.attachStart, anchor.attachEnd));
    if (mountDir === null) return null;
    var anchorMid = _midpoint(anchor.attachStart, anchor.attachEnd);

    var best = null;
    var bestDistance = Number.POSITIVE_INFINITY;
    var bestLength = Number.NEGATIVE_INFINITY;
    for (var i = 0; i < polygon.length; i++) {
        var a = polygon[i];
        var b = polygon[(i + 1) % polygon.length];
        var edgeDir = _normalizeVector(_vector(a, b));
        if (edgeDir === null) continue;
        var parallel = Math.abs(edgeDir.x * mountDir.x + edgeDir.y * mountDir.y);
        if (parallel < 0.92) continue;

        var start = a, end = b;
        if (edgeDir.x * mountDir.x + edgeDir.y * mountDir.y < 0.0) { start = b; end = a; }
        var edgeMid = _midpoint(start, end);
        var distance = (edgeMid === null || anchorMid === null)
            ? Number.POSITIVE_INFINITY
            : Math.abs((edgeMid.x - anchorMid.x) * (-mountDir.y) + (edgeMid.y - anchorMid.y) * mountDir.x);
        var length = _distanceBetween(start, end);
        if (distance < bestDistance - 1e-6 || (Math.abs(distance - bestDistance) <= 1e-6 && length > bestLength)) {
            bestDistance = distance;
            bestLength = length;
            best = { a: start, b: end };
        }
    }
    return best;
}

function _resolveVisiblePanelFreeEdge(polygon, anchor) {
    if (!anchor || !anchor.attachStart || !anchor.attachEnd || !polygon || polygon.length < 3) return null;
    var mountDir = _normalizeVector(_vector(anchor.attachStart, anchor.attachEnd));
    if (mountDir === null) return null;
    var mountMid = _midpoint(anchor.attachStart, anchor.attachEnd);
    var centroid = _loopRepresentativePoint(polygon);
    var normalA = { x: -mountDir.y, y: mountDir.x };
    var normalB = { x: mountDir.y, y: -mountDir.x };
    var preferredNormal;
    if (centroid === null) {
        preferredNormal = normalA;
    } else {
        var toCentroid = { x: centroid.x - mountMid.x, y: centroid.y - mountMid.y };
        var dotA = normalA.x * toCentroid.x + normalA.y * toCentroid.y;
        var dotB = normalB.x * toCentroid.x + normalB.y * toCentroid.y;
        preferredNormal = dotA >= dotB ? normalA : normalB;
    }

    var maxSignedOffset = Number.NEGATIVE_INFINITY;
    for (var i = 0; i < polygon.length; i++) {
        var a = polygon[i];
        var b = polygon[(i + 1) % polygon.length];
        var edgeDir = _normalizeVector(_vector(a, b));
        if (edgeDir === null) continue;
        var parallel = Math.abs(edgeDir.x * mountDir.x + edgeDir.y * mountDir.y);
        if (parallel < 0.92) continue;
        var mid = _midpoint(a, b);
        var offset = { x: mid.x - mountMid.x, y: mid.y - mountMid.y };
        var signedOffset = preferredNormal.x * offset.x + preferredNormal.y * offset.y;
        maxSignedOffset = Math.max(maxSignedOffset, signedOffset);
    }
    if (maxSignedOffset < 0.05) return null;
    var offsetTolerance = Math.max(0.08, maxSignedOffset * 0.12);

    var best = null;
    var bestLength = Number.NEGATIVE_INFINITY;
    var bestOffset = Number.NEGATIVE_INFINITY;
    for (var k = 0; k < polygon.length; k++) {
        var pa = polygon[k];
        var pb = polygon[(k + 1) % polygon.length];
        var pdir = _normalizeVector(_vector(pa, pb));
        if (pdir === null) continue;
        var pparallel = Math.abs(pdir.x * mountDir.x + pdir.y * mountDir.y);
        if (pparallel < 0.92) continue;
        var pmid = _midpoint(pa, pb);
        var poffset = { x: pmid.x - mountMid.x, y: pmid.y - mountMid.y };
        var psignedOffset = preferredNormal.x * poffset.x + preferredNormal.y * poffset.y;
        if (psignedOffset < maxSignedOffset - offsetTolerance) continue;

        var pstart = pa, pend = pb;
        if (pdir.x * mountDir.x + pdir.y * mountDir.y < 0.0) { pstart = pb; pend = pa; }
        var plength = _distanceBetween(pstart, pend);
        if (plength > bestLength + 1e-6 || (Math.abs(plength - bestLength) <= 1e-6 && psignedOffset > bestOffset)) {
            best = { a: pstart, b: pend };
            bestLength = plength;
            bestOffset = psignedOffset;
        }
    }
    return best;
}

function _resolvePanelSideSign(panel, edge) {
    if (!panel || !panel.labelPoint || !edge || !edge.a || !edge.b) return 0.0;
    var edgeDir = _normalizeVector(_vector(edge.a, edge.b));
    var edgeMid = _midpoint(edge.a, edge.b);
    if (edgeDir === null || edgeMid === null) return 0.0;
    var normal = { x: -edgeDir.y, y: edgeDir.x };
    return Math.sign((panel.labelPoint.x - edgeMid.x) * normal.x + (panel.labelPoint.y - edgeMid.y) * normal.y);
}

// ---------------- geometry helpers ----------------

function _closestPointOnSegment(p, a, b) {
    if (!p || !a || !b) return null;
    var dx = b.x - a.x;
    var dy = b.y - a.y;
    var len2 = dx * dx + dy * dy;
    if (len2 < 1e-12) return a;
    var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2;
    t = Math.max(0.0, Math.min(1.0, t));
    return { x: a.x + dx * t, y: a.y + dy * t };
}

function _loopRepresentativePoint(points) {
    if (!points || points.length === 0) return null;
    var sumX = 0.0, sumY = 0.0, count = 0;
    for (var i = 0; i < points.length; i++) {
        var point = points[i];
        if (!point) continue;
        sumX += point.x; sumY += point.y; count++;
    }
    return count === 0 ? null : { x: sumX / count, y: sumY / count };
}

function _midpoint(a, b) {
    if (!a || !b) return null;
    return { x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5 };
}

function _vector(a, b) {
    if (!a || !b) return null;
    return { x: b.x - a.x, y: b.y - a.y };
}

function _normalizeVector(v) {
    if (!v) return null;
    var length = Math.sqrt(v.x * v.x + v.y * v.y);
    if (length < 1e-9) return null;
    return { x: v.x / length, y: v.y / length };
}

function _distanceBetween(a, b) {
    if (!a || !b) return Number.POSITIVE_INFINITY;
    var dx = a.x - b.x, dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy);
}

// ---------------- identity parsing ----------------

function _branchBendSequenceFromIdentifier(value) {
    var normalized = _blankToNull(value);
    if (normalized === null) return -1;
    var hidden = /^BEND:(\d+):FLANGE:\d+$/i.exec(normalized.trim());
    if (hidden) {
        var n1 = parseInt(hidden[1], 10);
        return isNaN(n1) ? -1 : n1;
    }
    var visible = /^F\d+:B(\d+)$/.exec(normalized.trim());
    if (visible) {
        var n2 = parseInt(visible[1], 10);
        return isNaN(n2) ? -1 : n2;
    }
    return -1;
}

// from LiveJointSideViewResolver.exactBranchIdentityForPanel
function _exactBranchIdentityForPanel(panel) {
    if (!panel) return null;
    var anchor = _exactBranchIdentityFromIdentifier(panel.rootAnchorId);
    if (anchor !== null) return anchor;
    return _exactBranchIdentityFromIdentifier(panel.label);
}

function _exactBranchIdentityFromIdentifier(value) {
    var normalized = _blankToNull(value);
    if (normalized === null) return null;
    if (/^F\d+:B\d+$/.test(normalized)) return normalized;
    if (/^BEND:\d+:FLANGE:\d+$/.test(normalized)) return normalized;
    return null;
}

function _blankToNull(value) {
    if (value === null || value === undefined) return null;
    var trimmed = String(value).trim();
    return trimmed.length === 0 ? null : trimmed;
}
