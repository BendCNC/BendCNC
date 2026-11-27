.pragma library

.import "SheetMetalPoseEvaluator.js" as Evaluator

var DEFAULT_AREA_TOLERANCE = 1.0e-8
var DEFAULT_PLANE_TOLERANCE = 1.0e-7

function finiteNumber(value) {
    return value !== null && value !== undefined && isFinite(Number(value))
}

function pointIsFinite(point) {
    return !!point && finiteNumber(point.x) && finiteNumber(point.r)
}

function worldPointIsFinite(point) {
    return !!point && finiteNumber(point.x) && finiteNumber(point.y)
        && finiteNumber(point.z)
}

function dot3(a, b) {
    return Number(a.x) * Number(b.x) + Number(a.y) * Number(b.y)
        + Number(a.z) * Number(b.z)
}

function subtract3(a, b) {
    return {
        x: Number(a.x) - Number(b.x),
        y: Number(a.y) - Number(b.y),
        z: Number(a.z) - Number(b.z)
    }
}

function sectionSignedDistance(point, sectionFrame) {
    if (!worldPointIsFinite(point) || !sectionFrame
            || !worldPointIsFinite(sectionFrame.origin)
            || !worldPointIsFinite(sectionFrame.viewAxis))
        return NaN
    return dot3(subtract3(point, sectionFrame.origin), sectionFrame.viewAxis)
}

function interpolateWorldPoint(start, end, parameter) {
    return {
        x: Number(start.x) + (Number(end.x) - Number(start.x)) * parameter,
        y: Number(start.y) + (Number(end.y) - Number(start.y)) * parameter,
        z: Number(start.z) + (Number(end.z) - Number(start.z)) * parameter
    }
}

function worldDistance(a, b) {
    var delta = subtract3(a, b)
    return Math.sqrt(dot3(delta, delta))
}

function pushUniqueWorldPoint(points, point, tolerance) {
    for (var index = 0; index < points.length; index++) {
        if (worldDistance(points[index], point) <= tolerance)
            return
    }
    points.push(point)
}

// Returns only the part of a world-space segment that physically intersects the
// section plane. This deliberately does not orthographically project off-plane
// segments into the section.
function intersectWorldSegmentWithSectionPlane(start, end, sectionFrame, planeTolerance) {
    var tolerance = finiteNumber(planeTolerance)
        ? Math.max(0, Number(planeTolerance)) : DEFAULT_PLANE_TOLERANCE
    var startDistance = sectionSignedDistance(start, sectionFrame)
    var endDistance = sectionSignedDistance(end, sectionFrame)
    if (!isFinite(startDistance) || !isFinite(endDistance))
        return { ok: false, kind: "invalid", points: [] }
    var startOnPlane = Math.abs(startDistance) <= tolerance
    var endOnPlane = Math.abs(endDistance) <= tolerance
    if (startOnPlane && endOnPlane)
        return { ok: true, kind: "coplanar", points: [start, end] }
    if (startOnPlane)
        return { ok: true, kind: "point", points: [start] }
    if (endOnPlane)
        return { ok: true, kind: "point", points: [end] }
    if ((startDistance < 0 && endDistance < 0)
            || (startDistance > 0 && endDistance > 0))
        return { ok: true, kind: "off-section", points: [] }
    var denominator = startDistance - endDistance
    if (Math.abs(denominator) <= 1.0e-15)
        return { ok: true, kind: "off-section", points: [] }
    var parameter = startDistance / denominator
    if (parameter < -tolerance || parameter > 1 + tolerance)
        return { ok: true, kind: "off-section", points: [] }
    return {
        ok: true,
        kind: "point",
        points: [interpolateWorldPoint(start, end, Math.max(0, Math.min(1, parameter)))]
    }
}

function loopSectionHits(points, sectionFrame, planeTolerance) {
    var hits = []
    if (!Array.isArray(points) || points.length < 2)
        return hits
    var uniqueTolerance = Math.max(DEFAULT_PLANE_TOLERANCE,
                                   Number(planeTolerance || DEFAULT_PLANE_TOLERANCE) * 2)
    for (var index = 0; index < points.length; index++) {
        var intersection = intersectWorldSegmentWithSectionPlane(
            points[index], points[(index + 1) % points.length],
            sectionFrame, planeTolerance)
        if (!intersection.ok)
            return null
        for (var pointIndex = 0; pointIndex < intersection.points.length; pointIndex++)
            pushUniqueWorldPoint(hits, intersection.points[pointIndex], uniqueTolerance)
    }
    return hits
}

function projectedLineBasis(points) {
    if (!Array.isArray(points) || points.length < 2)
        return null
    var bestStart = null
    var bestEnd = null
    var bestDistance = 0
    for (var first = 0; first < points.length; first++) {
        for (var second = first + 1; second < points.length; second++) {
            var dx = Number(points[second].x) - Number(points[first].x)
            var dr = Number(points[second].r) - Number(points[first].r)
            var distance = Math.hypot(dx, dr)
            if (distance > bestDistance) {
                bestDistance = distance
                bestStart = points[first]
                bestEnd = points[second]
            }
        }
    }
    if (!(bestDistance > 1.0e-8))
        return null
    return {
        origin: { x: Number(bestStart.x), r: Number(bestStart.r) },
        direction: {
            x: (Number(bestEnd.x) - Number(bestStart.x)) / bestDistance,
            r: (Number(bestEnd.r) - Number(bestStart.r)) / bestDistance
        }
    }
}

function lineParameter(point, basis) {
    return (Number(point.x) - basis.origin.x) * basis.direction.x
        + (Number(point.r) - basis.origin.r) * basis.direction.r
}

function loopIntervals(points, sectionFrame, centerX, centerR, basis,
                       planeTolerance, intervalTolerance) {
    var hits = loopSectionHits(points, sectionFrame, planeTolerance)
    if (hits === null)
        return null
    var projectedHits = projectWorldLoop(hits, sectionFrame, centerX, centerR)
    if (!projectedHits)
        return null
    var parameters = []
    for (var index = 0; index < projectedHits.length; index++)
        parameters.push(lineParameter(projectedHits[index], basis))
    parameters.sort(function(a, b) { return a - b })
    var unique = []
    for (var parameterIndex = 0; parameterIndex < parameters.length; parameterIndex++) {
        if (unique.length === 0
                || Math.abs(parameters[parameterIndex] - unique[unique.length - 1]) > intervalTolerance)
            unique.push(parameters[parameterIndex])
    }
    var intervals = []
    for (var pairIndex = 0; pairIndex + 1 < unique.length; pairIndex += 2) {
        if (unique[pairIndex + 1] - unique[pairIndex] > intervalTolerance)
            intervals.push({ start: unique[pairIndex], end: unique[pairIndex + 1] })
    }
    return intervals
}

function subtractIntervals(source, removed, tolerance) {
    var result = source.slice(0)
    for (var removedIndex = 0; removedIndex < removed.length; removedIndex++) {
        var next = []
        var cut = removed[removedIndex]
        for (var sourceIndex = 0; sourceIndex < result.length; sourceIndex++) {
            var interval = result[sourceIndex]
            if (cut.end <= interval.start + tolerance
                    || cut.start >= interval.end - tolerance) {
                next.push(interval)
                continue
            }
            if (cut.start > interval.start + tolerance)
                next.push({ start: interval.start, end: Math.min(interval.end, cut.start) })
            if (cut.end < interval.end - tolerance)
                next.push({ start: Math.max(interval.start, cut.end), end: interval.end })
        }
        result = next
    }
    return result
}

function pointOnBasis(basis, parameter) {
    return {
        x: basis.origin.x + basis.direction.x * parameter,
        r: basis.origin.r + basis.direction.r * parameter
    }
}

function projectWorldLoop(points, sectionFrame, centerX, centerR) {
    if (!Array.isArray(points) || !sectionFrame)
        return null
    var result = []
    for (var index = 0; index < points.length; index++) {
        var projected = Evaluator.projectWorldPointToSection(
            points[index], sectionFrame, Number(centerX || 0), Number(centerR || 0))
        if (!pointIsFinite(projected))
            return null
        result.push({ x: Number(projected.x), r: Number(projected.r) })
    }
    return result
}

// Display projection is intentionally separate from the exact section-plane
// projection above. LIVE must show every posed panel body, including material
// that is in front of or behind the active bend section. A small oblique depth
// contribution keeps orthogonal flanges visible without changing the rigid 3D
// pose or the section geometry used by tooling/collision calculations.
function projectWorldLoopForDisplay(points, sectionFrame, centerX, centerR,
                                    depthHorizontal, depthVertical) {
    if (!Array.isArray(points) || !sectionFrame
            || !worldPointIsFinite(sectionFrame.origin)
            || !worldPointIsFinite(sectionFrame.viewAxis))
        return null
    var horizontalDepth = finiteNumber(depthHorizontal) ? Number(depthHorizontal) : 0.32
    var verticalDepth = finiteNumber(depthVertical) ? Number(depthVertical) : -0.18
    var result = []
    for (var index = 0; index < points.length; index++) {
        if (!worldPointIsFinite(points[index]))
            return null
        var projected = Evaluator.projectWorldPointToSection(
            points[index], sectionFrame, Number(centerX || 0), Number(centerR || 0))
        var depth = sectionSignedDistance(points[index], sectionFrame)
        if (!pointIsFinite(projected) || !isFinite(depth))
            return null
        result.push({
            x: Number(projected.x) + depth * horizontalDepth,
            r: Number(projected.r) + depth * verticalDepth,
            viewDepth: depth
        })
    }
    return result
}

function projectedDepthBounds(points) {
    var result = { min: Infinity, max: -Infinity, centroid: 0, count: 0 }
    for (var index = 0; Array.isArray(points) && index < points.length; index++) {
        var depth = Number(points[index] ? points[index].viewDepth : NaN)
        if (!isFinite(depth))
            continue
        result.min = Math.min(result.min, depth)
        result.max = Math.max(result.max, depth)
        result.centroid += depth
        result.count++
    }
    if (result.count === 0)
        return null
    result.centroid /= result.count
    return result
}

function signedArea(points) {
    var area = 0
    for (var index = 0; Array.isArray(points) && index < points.length; index++) {
        var next = points[(index + 1) % points.length]
        area += Number(points[index].x) * Number(next.r)
            - Number(next.x) * Number(points[index].r)
    }
    return area * 0.5
}

function centroid(points) {
    var result = { x: 0, r: 0 }
    if (!Array.isArray(points) || points.length === 0)
        return result
    for (var index = 0; index < points.length; index++) {
        result.x += Number(points[index].x)
        result.r += Number(points[index].r)
    }
    result.x /= points.length
    result.r /= points.length
    return result
}

function projectPosedPanelForDisplay(posedPanel, sectionFrame, centerX, centerR,
                                     halfThickness, areaTolerance,
                                     depthHorizontal, depthVertical) {
    if (!posedPanel || !Array.isArray(posedPanel.worldPolygon)
            || posedPanel.worldPolygon.length < 3)
        return { ok: false, reason: "world-polygon-missing" }
    var horizontalDepth = finiteNumber(depthHorizontal) ? Number(depthHorizontal) : 0.32
    var verticalDepth = finiteNumber(depthVertical) ? Number(depthVertical) : -0.18
    var polygon = projectWorldLoopForDisplay(
        posedPanel.worldPolygon, sectionFrame, centerX, centerR,
        horizontalDepth, verticalDepth)
    if (!polygon || polygon.length !== posedPanel.worldPolygon.length)
        return { ok: false, reason: "world-polygon-display-projection-failed" }
    var holes = []
    var sourceHoles = posedPanel.worldHoleLoops || []
    if (!Array.isArray(sourceHoles))
        return { ok: false, reason: "world-holes-invalid" }
    for (var holeIndex = 0; holeIndex < sourceHoles.length; holeIndex++) {
        var hole = projectWorldLoopForDisplay(
            sourceHoles[holeIndex], sectionFrame, centerX, centerR,
            horizontalDepth, verticalDepth)
        if (!hole || hole.length !== sourceHoles[holeIndex].length || hole.length < 3)
            return { ok: false, reason: "world-hole-display-projection-failed:" + holeIndex }
        holes.push(hole)
    }
    var tolerance = finiteNumber(areaTolerance)
        ? Math.max(0, Number(areaTolerance)) : DEFAULT_AREA_TOLERANCE
    var projectedArea = Math.abs(signedArea(polygon))
    var depthBounds = projectedDepthBounds(polygon)
    if (!depthBounds)
        return { ok: false, reason: "world-polygon-display-depth-failed" }
    var obliqueDisplay = Math.abs(horizontalDepth) > 1.0e-12
        || Math.abs(verticalDepth) > 1.0e-12
    if (projectedArea <= tolerance && !obliqueDisplay) {
        var edgeOnSegment = principalExtentSegment(polygon, halfThickness)
        if (!edgeOnSegment)
            return { ok: false, reason: "display-projection-collapsed" }
        return {
            ok: true,
            visible: true,
            reason: "display-edge-on-thickness-band",
            polygon: [],
            holeLoops: [],
            projectedArea: 0,
            sectionSegment: edgeOnSegment,
            sectionSegments: [edgeOnSegment],
            viewDepthMin: depthBounds.min,
            viewDepthMax: depthBounds.max,
            viewDepthCentroid: depthBounds.centroid,
            labelPoint: {
                x: (edgeOnSegment.start.x + edgeOnSegment.end.x) * 0.5,
                r: (edgeOnSegment.start.r + edgeOnSegment.end.r) * 0.5
            }
        }
    }
    if (projectedArea <= tolerance) {
        // In an oblique/isometric view the posed polygon is authoritative even
        // when it is mathematically edge-on. Replacing it with the SIDE-only
        // section band discards the panel's longitudinal camera depth and makes
        // the workpiece look flat while tooling remains visibly extruded.
        return {
            ok: true,
            visible: true,
            reason: "full-body-oblique-edge-on-display",
            polygon: polygon,
            holeLoops: holes,
            projectedArea: projectedArea,
            sectionSegment: null,
            sectionSegments: [],
            viewDepthMin: depthBounds.min,
            viewDepthMax: depthBounds.max,
            viewDepthCentroid: depthBounds.centroid,
            labelPoint: centroid(polygon)
        }
    }
    return {
        ok: true,
        visible: true,
        reason: Math.abs(horizontalDepth) <= 1.0e-12
                    && Math.abs(verticalDepth) <= 1.0e-12
                ? "orthographic-side-display" : "full-body-oblique-display",
        polygon: polygon,
        holeLoops: holes,
        projectedArea: projectedArea,
        sectionSegment: null,
        sectionSegments: [],
        viewDepthMin: depthBounds.min,
        viewDepthMax: depthBounds.max,
        viewDepthCentroid: depthBounds.centroid,
        labelPoint: centroid(polygon)
    }
}

function principalExtentSegment(points, halfThickness) {
    if (!Array.isArray(points) || points.length < 2)
        return null
    var center = centroid(points)
    var covarianceXX = 0
    var covarianceXR = 0
    var covarianceRR = 0
    for (var index = 0; index < points.length; index++) {
        if (!pointIsFinite(points[index]))
            return null
        var dx = Number(points[index].x) - center.x
        var dr = Number(points[index].r) - center.r
        covarianceXX += dx * dx
        covarianceXR += dx * dr
        covarianceRR += dr * dr
    }
    if (covarianceXX + covarianceRR <= 1.0e-12)
        return null
    var angle = 0.5 * Math.atan2(2 * covarianceXR, covarianceXX - covarianceRR)
    var directionX = Math.cos(angle)
    var directionR = Math.sin(angle)
    var minParameter = Infinity
    var maxParameter = -Infinity
    for (var parameterIndex = 0; parameterIndex < points.length; parameterIndex++) {
        var parameter = (Number(points[parameterIndex].x) - center.x) * directionX
            + (Number(points[parameterIndex].r) - center.r) * directionR
        minParameter = Math.min(minParameter, parameter)
        maxParameter = Math.max(maxParameter, parameter)
    }
    if (!(maxParameter - minParameter > 1.0e-6))
        return null
    return {
        start: {
            x: center.x + directionX * minParameter,
            r: center.r + directionR * minParameter
        },
        end: {
            x: center.x + directionX * maxParameter,
            r: center.r + directionR * maxParameter
        },
        halfThickness: Math.max(0.0005, Number(halfThickness || 0.018)),
        source: "edge-on-face-principal-extent"
    }
}

function closestPointOnWorldSegment(point, start, end) {
    var axis = subtract3(end, start)
    var lengthSquared = dot3(axis, axis)
    if (!(lengthSquared > 1.0e-15))
        return null
    var parameter = dot3(subtract3(point, start), axis) / lengthSquared
    return interpolateWorldPoint(start, end, Math.max(0, Math.min(1, parameter)))
}

function representativeMountEdge(posedPanel) {
    if (posedPanel && Array.isArray(posedPanel.worldMountEdge)
            && posedPanel.worldMountEdge.length === 2
            && worldPointIsFinite(posedPanel.worldMountEdge[0])
            && worldPointIsFinite(posedPanel.worldMountEdge[1]))
        return posedPanel.worldMountEdge
    var attachments = posedPanel ? posedPanel.worldAttachmentEdges : null
    if (!Array.isArray(attachments))
        return null
    for (var index = 0; index < attachments.length; index++) {
        var attachment = attachments[index]
        if (attachment && worldPointIsFinite(attachment.start)
                && worldPointIsFinite(attachment.end))
            return [attachment.start, attachment.end]
    }
    return null
}

function representativeHingeBand(posedPanel, polygon, sectionFrame,
                                 centerX, centerR, halfThickness) {
    var mountEdge = representativeMountEdge(posedPanel)
    if (!mountEdge || worldDistance(mountEdge[0], mountEdge[1]) <= 1.0e-9)
        return null
    var projectedMount = projectWorldLoop(mountEdge, sectionFrame, centerX, centerR)
    if (!projectedMount || projectedMount.length !== 2)
        return null
    var best = null
    for (var vertexIndex = 0; vertexIndex < posedPanel.worldPolygon.length; vertexIndex++) {
        var worldVertex = posedPanel.worldPolygon[vertexIndex]
        var worldAnchor = closestPointOnWorldSegment(worldVertex, mountEdge[0], mountEdge[1])
        if (!worldAnchor)
            continue
        var physicalLength = worldDistance(worldVertex, worldAnchor)
        if (!(physicalLength > 1.0e-7))
            continue
        var projectedAnchorLoop = projectWorldLoop([worldAnchor], sectionFrame, centerX, centerR)
        if (!projectedAnchorLoop || projectedAnchorLoop.length !== 1)
            continue
        var projectedAnchor = projectedAnchorLoop[0]
        var projectedVertex = polygon[vertexIndex]
        var projectedLength = Math.hypot(projectedVertex.x - projectedAnchor.x,
                                         projectedVertex.r - projectedAnchor.r)
        if (!best || projectedLength > best.projectedLength + 1.0e-9
                || (Math.abs(projectedLength - best.projectedLength) <= 1.0e-9
                    && physicalLength > best.physicalLength)) {
            best = {
                start: projectedAnchor,
                end: projectedVertex,
                physicalLength: physicalLength,
                projectedLength: projectedLength
            }
        }
    }
    var materialHalfThickness = Math.max(0.0005, Number(halfThickness || 0.018))
    if (best && best.projectedLength > 1.0e-6) {
        return {
            start: best.start,
            end: best.end,
            mountAnchor: best.start,
            projectedMountEdge: projectedMount,
            physicalLength: best.physicalLength,
            projectedLength: best.projectedLength,
            halfThickness: materialHalfThickness,
            source: "hinge-anchored-face-extent"
        }
    }
    var mountLength = Math.hypot(projectedMount[1].x - projectedMount[0].x,
                                 projectedMount[1].r - projectedMount[0].r)
    if (mountLength > 1.0e-6) {
        return {
            start: projectedMount[0],
            end: projectedMount[1],
            mountAnchor: projectedMount[0],
            projectedMountEdge: projectedMount,
            physicalLength: worldDistance(mountEdge[0], mountEdge[1]),
            projectedLength: mountLength,
            halfThickness: materialHalfThickness,
            source: "hinge-anchored-edge-on"
        }
    }
    var extent = principalExtentSegment(polygon, materialHalfThickness)
    if (!extent)
        return null
    var anchor = projectedMount[0]
    var startDistance = Math.hypot(extent.start.x - anchor.x, extent.start.r - anchor.r)
    var endDistance = Math.hypot(extent.end.x - anchor.x, extent.end.r - anchor.r)
    return {
        start: anchor,
        end: startDistance >= endDistance ? extent.start : extent.end,
        mountAnchor: anchor,
        projectedMountEdge: projectedMount,
        physicalLength: best ? best.physicalLength : 0,
        projectedLength: Math.max(startDistance, endDistance),
        halfThickness: materialHalfThickness,
        source: "hinge-anchored-collapsed-mount"
    }
}

function representativePanelProjection(posedPanel, polygon, halfThickness,
                                       sectionFrame, centerX, centerR) {
    var segment = representativeHingeBand(
        posedPanel, polygon, sectionFrame, centerX, centerR, halfThickness)
    if (!segment || Math.hypot(segment.end.x - segment.start.x,
                               segment.end.r - segment.start.r) <= 1.0e-6) {
        return {
            ok: false,
            visible: false,
            reason: "representative-hinge-anchor-missing",
            polygon: [],
            holeLoops: [],
            projectedArea: 0,
            sectionSegment: null,
            sectionSegments: [],
            labelPoint: null
        }
    }
    return {
        ok: true,
        visible: true,
        reason: "representative-hinge-band",
        polygon: [],
        holeLoops: [],
        projectedArea: 0,
        sectionSegment: segment,
        sectionSegments: [segment],
        labelPoint: {
            x: (segment.start.x + segment.end.x) * 0.5,
            r: (segment.start.r + segment.end.r) * 0.5
        }
    }
}

function projectPosedPanel(posedPanel, sectionFrame, centerX, centerR, halfThickness, areaTolerance) {
    if (!posedPanel || !Array.isArray(posedPanel.worldPolygon)
            || posedPanel.worldPolygon.length < 3)
        return { ok: false, reason: "world-polygon-missing" }
    var polygon = projectWorldLoop(posedPanel.worldPolygon, sectionFrame, centerX, centerR)
    if (!polygon || polygon.length !== posedPanel.worldPolygon.length)
        return { ok: false, reason: "world-polygon-projection-failed" }
    var tolerance = finiteNumber(areaTolerance)
        ? Math.max(0, Number(areaTolerance)) : DEFAULT_AREA_TOLERANCE
    var projectedArea = Math.abs(signedArea(polygon))
    var holes = []
    var sourceHoles = posedPanel.worldHoleLoops || []
    if (!Array.isArray(sourceHoles))
        return { ok: false, reason: "world-holes-invalid" }
    var coordinateScale = 1
    var minDistance = Infinity
    var maxDistance = -Infinity
    for (var distanceIndex = 0; distanceIndex < posedPanel.worldPolygon.length; distanceIndex++) {
        var worldPoint = posedPanel.worldPolygon[distanceIndex]
        if (!worldPointIsFinite(worldPoint))
            return { ok: false, reason: "world-polygon-invalid" }
        coordinateScale = Math.max(coordinateScale, Math.abs(Number(worldPoint.x)),
                                   Math.abs(Number(worldPoint.y)), Math.abs(Number(worldPoint.z)))
        var distance = sectionSignedDistance(worldPoint, sectionFrame)
        if (!isFinite(distance))
            return { ok: false, reason: "section-frame-invalid" }
        minDistance = Math.min(minDistance, distance)
        maxDistance = Math.max(maxDistance, distance)
    }
    var planeTolerance = Math.max(DEFAULT_PLANE_TOLERANCE, coordinateScale * 1.0e-9)
    var coplanar = Math.abs(minDistance) <= planeTolerance
        && Math.abs(maxDistance) <= planeTolerance
    if (coplanar) {
        for (var holeIndex = 0; holeIndex < sourceHoles.length; holeIndex++) {
            var hole = projectWorldLoop(sourceHoles[holeIndex], sectionFrame, centerX, centerR)
            if (!hole || hole.length !== sourceHoles[holeIndex].length
                    || hole.length < 3 || Math.abs(signedArea(hole)) <= tolerance)
                return { ok: false, reason: "world-hole-projection-failed:" + holeIndex }
            holes.push(hole)
        }
        return {
            ok: true,
            visible: true,
            reason: "coplanar-section",
            polygon: polygon,
            holeLoops: holes,
            projectedArea: projectedArea,
            sectionSegment: null,
            sectionSegments: [],
            labelPoint: centroid(polygon)
        }
    }

    var outerHits = loopSectionHits(posedPanel.worldPolygon, sectionFrame, planeTolerance)
    if (outerHits === null)
        return { ok: false, reason: "section-intersection-failed" }
    var projectedOuterHits = projectWorldLoop(outerHits, sectionFrame, centerX, centerR)
    var basis = projectedLineBasis(projectedOuterHits)
    if (!basis) {
        return representativePanelProjection(
            posedPanel, polygon, halfThickness, sectionFrame, centerX, centerR)
    }
    var intervalTolerance = Math.max(1.0e-7, coordinateScale * 1.0e-9)
    var materialIntervals = loopIntervals(
        posedPanel.worldPolygon, sectionFrame, centerX, centerR, basis,
        planeTolerance, intervalTolerance)
    if (materialIntervals === null)
        return { ok: false, reason: "outer-section-intervals-failed" }
    for (var sectionHoleIndex = 0; sectionHoleIndex < sourceHoles.length; sectionHoleIndex++) {
        var holeIntervals = loopIntervals(
            sourceHoles[sectionHoleIndex], sectionFrame, centerX, centerR, basis,
            planeTolerance, intervalTolerance)
        if (holeIntervals === null)
            return { ok: false, reason: "hole-section-intervals-failed:" + sectionHoleIndex }
        materialIntervals = subtractIntervals(materialIntervals, holeIntervals, intervalTolerance)
    }
    var sectionSegments = []
    var materialHalfThickness = Math.max(0.0005, Number(halfThickness || 0.018))
    var longestSegment = null
    var longestLength = 0
    for (var intervalIndex = 0; intervalIndex < materialIntervals.length; intervalIndex++) {
        var interval = materialIntervals[intervalIndex]
        var segment = {
            start: pointOnBasis(basis, interval.start),
            end: pointOnBasis(basis, interval.end),
            halfThickness: materialHalfThickness,
            source: "face-plane-intersection"
        }
        var segmentLength = Math.hypot(segment.end.x - segment.start.x,
                                       segment.end.r - segment.start.r)
        if (segmentLength <= intervalTolerance)
            continue
        sectionSegments.push(segment)
        if (segmentLength > longestLength) {
            longestLength = segmentLength
            longestSegment = segment
        }
    }
    if (sectionSegments.length === 0) {
        return representativePanelProjection(
            posedPanel, polygon, halfThickness, sectionFrame, centerX, centerR)
    }
    return {
        ok: true,
        visible: true,
        reason: "section-intersection",
        polygon: polygon,
        holeLoops: [],
        projectedArea: 0,
        sectionSegment: sectionSegments.length === 1 ? sectionSegments[0] : null,
        sectionSegments: sectionSegments,
        labelPoint: {
            x: (longestSegment.start.x + longestSegment.end.x) / 2,
            r: (longestSegment.start.r + longestSegment.end.r) / 2
        }
    }
}