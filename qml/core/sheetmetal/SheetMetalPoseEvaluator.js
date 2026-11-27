.pragma library

.import "RigidTransform3D.js" as Rigid
.import "SheetMetalPoseGraph.js" as Graph
.import "SheetMetalFoldSolver.js" as FoldSolver

// "radius": finite-radius strip kinematics (unfold port, default).
// "legacy": zero-radius rotation about the flat hinge line.
var foldSolverMode = "radius";
function setFoldSolverMode(mode) {
    foldSolverMode = String(mode) === "legacy" ? "legacy" : "radius";
    return foldSolverMode;
}

function point2(point) { return { x: Number(point && point.x_in || 0), y: Number(point && point.y_in || 0), z: 0 }; }
function point2Live(point) { return { x: point.x, r: point.y }; }

function fullFoldDegrees(edge) {
    return Number(edge.foldAngleDegrees !== undefined
                  ? edge.foldAngleDegrees
                  : (180 - Number(edge.bendAngleDegrees || 0)));
}

// amounts: optional map sourceBendId -> 0..1 (per-bend progress, allows
// partial pre-bends of several bends). Overrides the sequence rule.
function localAngle(edge, bendById, currentSequence, displayedAngleFn, amounts) {
    var sourceId = String(edge.sourceBendId || "");
    if (amounts) {
        // A per-relation amount (one span of a split hinge) wins over its CAD bend.
        var amount = Number(amounts[edge.bendId] !== undefined ? amounts[edge.bendId] : amounts[sourceId]);
        if (!(amount > 0))
            return 0;
        return FoldSolver.signedFoldRadians(edge, fullFoldDegrees(edge) * Math.min(1, amount));
    }
    var sourceBend = bendById ? bendById[sourceId] : null;
    var sourceSequence = edge.sequenceHint;
    if (sourceBend && sourceBend.sequenceHint !== undefined)
        sourceSequence = Number(sourceBend.sequenceHint);
    if (!(sourceSequence > 0) || sourceSequence > currentSequence)
        return 0;
    var angle = Number(edge.foldAngleDegrees !== undefined
                       ? edge.foldAngleDegrees
                       : (180 - Number(edge.bendAngleDegrees || 0)));
    if (displayedAngleFn && sourceBend && sourceSequence === currentSequence)
        angle = Number(displayedAngleFn(sourceBend));
    if (!isFinite(angle))
        angle = 0;
    return FoldSolver.signedFoldRadians(edge, angle);
}

function edgeTransform(edge, angle) {
    return foldSolverMode === "legacy"
        ? Rigid.rotateAroundLocalHinge(edge, angle)
        : FoldSolver.jointTransform(edge, angle);
}

function compileNormalized(model, bendById, currentSequence, displayedAngleFn, amounts) {
    if (!model)
        return null;
    var transforms = ({});
    var anglesByChildId = ({});
    transforms[model.rootPanelId] = Rigid.identity();
    var pending = [model.rootPanelId];
    var childrenByParent = ({});
    for (var edgeIndex = 0; edgeIndex < model.edges.length; edgeIndex++) {
        var edge = model.edges[edgeIndex];
        if (!childrenByParent[edge.parentPanelId])
            childrenByParent[edge.parentPanelId] = [];
        childrenByParent[edge.parentPanelId].push(edge);
    }
    while (pending.length > 0) {
        var parentId = pending.shift();
        var parentTransform = transforms[parentId];
        var children = childrenByParent[parentId] || [];
        children.sort(function(a, b) { return a.sequenceHint - b.sequenceHint || a.childPanelId.localeCompare(b.childPanelId); });
        for (var childIndex = 0; childIndex < children.length; childIndex++) {
            var childEdge = children[childIndex];
            var childAngle = localAngle(childEdge, bendById, currentSequence, displayedAngleFn, amounts);
            anglesByChildId[childEdge.childPanelId] = childAngle;
            transforms[childEdge.childPanelId] = Rigid.multiply(parentTransform, edgeTransform(childEdge, childAngle));
            pending.push(childEdge.childPanelId);
        }
    }
    return { model: model, transforms: transforms, anglesByChildId: anglesByChildId,
             currentSequence: currentSequence, foldSolver: foldSolverMode };
}

function compile(graph, bendById, currentSequence, displayedAngleFn, amounts) {
    return compileNormalized(Graph.normalize(graph), bendById, currentSequence, displayedAngleFn, amounts);
}

// Radius-zone strip of an edge in world coordinates (empty for legacy/flat).
function worldBendStrip(compiled, edge, samples) {
    if (!compiled || !edge || compiled.foldSolver === "legacy")
        return null;
    var parentTransform = compiled.transforms[edge.parentPanelId];
    var angle = Number(compiled.anglesByChildId[edge.childPanelId] || 0);
    if (!parentTransform || Math.abs(angle) < 1e-9)
        return null;
    var strip = FoldSolver.bandPolyline(edge, angle, samples);
    var near = [], far = [];
    for (var i = 0; i < strip.near.length; i++) {
        near.push(Rigid.transformPoint(parentTransform, strip.near[i]));
        far.push(Rigid.transformPoint(parentTransform, strip.far[i]));
    }
    return { near: near, far: far, neutralLength: strip.neutralLength };
}

function poseLoop(points, transform) {
    var result = [];
    for (var i = 0; points && i < points.length; i++)
        result.push(point2Live(Rigid.transformPoint(transform, point2(points[i]))));
    return result;
}

function poseWorldLoop(points, transform) {
    var result = [];
    for (var i = 0; points && i < points.length; i++)
        result.push(Rigid.transformPoint(transform, point2(points[i])));
    return result;
}

function posePanelAttachmentEdges(compiled, panelId, transform) {
    var result = [];
    for (var edgeIndex = 0; compiled && compiled.model
            && edgeIndex < compiled.model.edges.length; edgeIndex++) {
        var edge = compiled.model.edges[edgeIndex];
        var role = "";
        if (edge.childPanelId === panelId)
            role = "parent";
        else if (edge.parentPanelId === panelId)
            role = "child";
        if (role.length === 0)
            continue;
        result.push({
            edgeId: edge.bendId,
            sourceBendId: edge.sourceBendId,
            sequenceHint: edge.sequenceHint,
            role: role,
            start: Rigid.transformPoint(transform, point2(edge.hingeStart)),
            end: Rigid.transformPoint(transform, point2(edge.hingeEnd))
        });
    }
    result.sort(function(a, b) {
        var aDistance = Math.abs(Number(a.sequenceHint) - Number(compiled.currentSequence));
        var bDistance = Math.abs(Number(b.sequenceHint) - Number(compiled.currentSequence));
        if (aDistance !== bDistance)
            return aDistance - bDistance;
        if (a.role !== b.role)
            return a.role === "parent" ? -1 : 1;
        return String(a.edgeId).localeCompare(String(b.edgeId));
    });
    return result;
}

function poseCompiled(compiled, panelId) {
    if (!compiled || !compiled.model || !compiled.transforms[panelId])
        return null;
    var panel = compiled.model.panelsById[panelId];
    if (!panel)
        return null;
    var transform = compiled.transforms[panelId];
    var outer = poseLoop(panel.outerLoop, transform);
    var worldOuter = poseWorldLoop(panel.outerLoop, transform);
    var holes = [];
    var worldHoles = [];
    for (var holeIndex = 0; holeIndex < panel.holeLoops.length; holeIndex++)
        holes.push(poseLoop(panel.holeLoops[holeIndex], transform));
    for (var worldHoleIndex = 0; worldHoleIndex < panel.holeLoops.length; worldHoleIndex++)
        worldHoles.push(poseWorldLoop(panel.holeLoops[worldHoleIndex], transform));
    var edge = compiled.model.edgeByChildId[panelId] || null;
    var mountEdge = [];
    var worldMountEdge = [];
    if (edge) {
        worldMountEdge = [
            Rigid.transformPoint(transform, point2(edge.hingeStart)),
            Rigid.transformPoint(transform, point2(edge.hingeEnd))
        ];
        mountEdge = [
            point2Live(worldMountEdge[0]),
            point2Live(worldMountEdge[1])
        ];
    }
    var worldAttachmentEdges = posePanelAttachmentEdges(compiled, panelId, transform);
    return {
        panelId: panel.panelId,
        ownerBendId: panel.ownerBendId,
        polygon: outer,
        worldPolygon: worldOuter,
        holeLoops: holes,
        worldHoleLoops: worldHoles,
        mountEdge: mountEdge,
        worldMountEdge: worldMountEdge,
        worldAttachmentEdges: worldAttachmentEdges,
        edge: edge,
        transform: transform,
        geometryAuthority: panel.geometryAuthority,
        provenance: panel.provenance
    };
}

// Rendering-only variant. The caller supplies an already validated local
// contour (typically a bounded simplification) and receives only the world
// geometry required by LIVE display projection. The authoritative panel in
// compiled.model is never modified.
function poseCompiledRenderGeometry(compiled, panelId, renderGeometry) {
    if (!compiled || !compiled.model || !compiled.transforms[panelId]
            || !renderGeometry || !Array.isArray(renderGeometry.outerLoop)
            || renderGeometry.outerLoop.length < 3)
        return null;
    var panel = compiled.model.panelsById[panelId];
    if (!panel)
        return null;
    var transform = compiled.transforms[panelId];
    var worldHoles = [];
    for (var holeIndex = 0;
            renderGeometry.holeLoops && holeIndex < renderGeometry.holeLoops.length;
            holeIndex++) {
        worldHoles.push(poseWorldLoop(renderGeometry.holeLoops[holeIndex], transform));
    }
    return {
        panelId: panel.panelId,
        ownerBendId: panel.ownerBendId,
        worldPolygon: poseWorldLoop(renderGeometry.outerLoop, transform),
        worldHoleLoops: worldHoles,
        edge: compiled.model.edgeByChildId[panelId] || null,
        transform: transform,
        geometryAuthority: panel.geometryAuthority,
        provenance: panel.provenance,
        sourceOuterPointCount: renderGeometry.sourceOuterPointCount,
        renderOuterPointCount: renderGeometry.renderOuterPointCount
    };
}

function poseVisiblePanels(compiled, currentSequence) {
    var result = [];
    var ids = Graph.visiblePanelIds(compiled.model, currentSequence);
    for (var i = 0; i < ids.length; i++) {
        var posed = poseCompiled(compiled, ids[i]);
        if (posed)
            result.push(posed);
    }
    return result;
}

function poseAllPanels(compiled) {
    var result = [];
    for (var i = 0; compiled && compiled.model && i < compiled.model.panelOrder.length; i++) {
        var posed = poseCompiled(compiled, compiled.model.panelOrder[i]);
        if (posed)
            result.push(posed);
    }
    return result;
}

function worldHinge(compiled, edge) {
    if (!compiled || !edge)
        return null;
    var parentTransform = compiled.transforms[edge.parentPanelId];
    if (!parentTransform)
        return null;
    var start = Rigid.transformPoint(parentTransform, point2(edge.hingeStart));
    var end = Rigid.transformPoint(parentTransform, point2(edge.hingeEnd));
    if (Rigid.length(Rigid.sub(end, start)) <= 1e-9)
        return null;
    return { start: start, end: end, midpoint: Rigid.mul(Rigid.add(start, end), 0.5) };
}

function worldPanelCentroid(compiled, panelId) {
    if (!compiled || !compiled.model || !compiled.transforms[panelId])
        return null;
    var panel = compiled.model.panelsById[panelId];
    if (!panel || !Array.isArray(panel.outerLoop) || panel.outerLoop.length === 0)
        return null;
    var centroid = Rigid.v(0, 0, 0);
    for (var pointIndex = 0; pointIndex < panel.outerLoop.length; pointIndex++) {
        centroid = Rigid.add(centroid, Rigid.transformPoint(
            compiled.transforms[panelId], point2(panel.outerLoop[pointIndex])));
    }
    return Rigid.mul(centroid, 1 / panel.outerLoop.length);
}

function hingeSectionFrame(compiled, edge) {
    var hinge = worldHinge(compiled, edge);
    if (!hinge)
        return null;
    var parentTransform = compiled.transforms[edge.parentPanelId];
    var childTransform = compiled.transforms[edge.childPanelId];
    if (!parentTransform || !childTransform)
        return null;
    var localStart = point2(edge.hingeStart);
    var localEnd = point2(edge.hingeEnd);
    var localHinge = Rigid.normalize(Rigid.sub(localEnd, localStart));
    var childSide = Number(edge.childSideSign || 1) < 0 ? -1 : 1;
    var localChildOutward = Rigid.v(-localHinge.y * childSide, localHinge.x * childSide, 0);
    var parentOutward = Rigid.mul(Rigid.normalize(Rigid.transformVector(parentTransform, localChildOutward)), -1);
    var childOutward = Rigid.normalize(Rigid.transformVector(childTransform, localChildOutward));
    var horizontal = Rigid.normalize(Rigid.sub(childOutward, parentOutward));
    // The backgauge is rendered on negative display X. Keep the parent body on
    // positive X so the active child flange approaches the finger instead of
    // letting the completed sheet cover it. Hinge endpoint order is arbitrary,
    // so use the actual parent-panel topology to choose the display-side sign.
    var parentCentroid = worldPanelCentroid(compiled, edge.parentPanelId);
    if (parentCentroid) {
        var parentSide = Rigid.sub(parentCentroid, hinge.midpoint);
        if (Rigid.dot(parentSide, horizontal) < 0)
            horizontal = Rigid.mul(horizontal, -1);
    }
    var naturalVertical = Rigid.normalize(Rigid.add(childOutward, parentOutward));
    if (Rigid.length(naturalVertical) <= 1e-9) {
        var angleSign = String(edge.direction || "UP").toUpperCase() === "DOWN" ? -1 : 1;
        angleSign *= childSide;
        var flatChildOutward = Rigid.normalize(Rigid.transformVector(parentTransform, localChildOutward));
        naturalVertical = Rigid.normalize(Rigid.mul(Rigid.cross(Rigid.normalize(Rigid.sub(hinge.end, hinge.start)), flatChildOutward), angleSign));
    }
    // localAngle() already applies direction and child-side sign to the rigid
    // fold. The operation camera must use the resulting parent/child angle
    // bisector directly so both active legs rise from the die as a V. Applying
    // DOWN a second time reflects that V below the tooling.
    var vertical = naturalVertical;
    if (Rigid.length(horizontal) <= 1e-9 || Rigid.length(vertical) <= 1e-9)
        return null;
    return {
        origin: hinge.midpoint,
        hingeStart: hinge.start,
        hingeEnd: hinge.end,
        viewAxis: Rigid.normalize(Rigid.sub(hinge.end, hinge.start)),
        horizontal: horizontal,
        vertical: vertical,
        parentOutward: parentOutward,
        childOutward: childOutward,
        angleRadians: Number(compiled.anglesByChildId[edge.childPanelId] || 0)
    };
}

function projectWorldPointToSection(point, frame, centerX, centerR) {
    if (!point || !frame)
        return null;
    var relative = Rigid.sub(point, frame.origin);
    return {
        x: Number(centerX || 0) + Rigid.dot(relative, frame.horizontal),
        r: Number(centerR || 0) + Rigid.dot(relative, frame.vertical)
    };
}
