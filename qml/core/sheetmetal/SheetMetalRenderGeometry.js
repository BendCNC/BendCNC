.pragma library

function finitePoint(point) {
    return !!point && isFinite(Number(point.x_in)) && isFinite(Number(point.y_in))
}

function signedArea(points) {
    var area = 0
    for (var index = 0; points && index < points.length; index++) {
        var next = points[(index + 1) % points.length]
        area += Number(points[index].x_in) * Number(next.y_in)
            - Number(next.x_in) * Number(points[index].y_in)
    }
    return area * 0.5
}

function pointSegmentDistance(point, start, end) {
    var dx = Number(end.x_in) - Number(start.x_in)
    var dy = Number(end.y_in) - Number(start.y_in)
    var lengthSquared = dx * dx + dy * dy
    if (lengthSquared <= 1.0e-20)
        return Math.hypot(Number(point.x_in) - Number(start.x_in),
                          Number(point.y_in) - Number(start.y_in))
    var parameter = ((Number(point.x_in) - Number(start.x_in)) * dx
        + (Number(point.y_in) - Number(start.y_in)) * dy) / lengthSquared
    parameter = Math.max(0, Math.min(1, parameter))
    return Math.hypot(Number(point.x_in) - (Number(start.x_in) + dx * parameter),
                      Number(point.y_in) - (Number(start.y_in) + dy * parameter))
}

function simplifyOpen(points, tolerance) {
    if (points.length <= 2)
        return points.slice(0)
    var maximumDistance = 0
    var splitIndex = -1
    for (var index = 1; index < points.length - 1; index++) {
        var distance = pointSegmentDistance(
            points[index], points[0], points[points.length - 1])
        if (distance > maximumDistance) {
            maximumDistance = distance
            splitIndex = index
        }
    }
    if (splitIndex < 0 || maximumDistance <= tolerance)
        return [points[0], points[points.length - 1]]
    var left = simplifyOpen(points.slice(0, splitIndex + 1), tolerance)
    var right = simplifyOpen(points.slice(splitIndex), tolerance)
    return left.slice(0, left.length - 1).concat(right)
}

function segmentOrientation(a, b, c) {
    return (Number(b.x_in) - Number(a.x_in)) * (Number(c.y_in) - Number(a.y_in))
        - (Number(b.y_in) - Number(a.y_in)) * (Number(c.x_in) - Number(a.x_in))
}

function segmentsProperlyIntersect(a, b, c, d) {
    var abC = segmentOrientation(a, b, c)
    var abD = segmentOrientation(a, b, d)
    var cdA = segmentOrientation(c, d, a)
    var cdB = segmentOrientation(c, d, b)
    return ((abC > 1.0e-12 && abD < -1.0e-12)
            || (abC < -1.0e-12 && abD > 1.0e-12))
        && ((cdA > 1.0e-12 && cdB < -1.0e-12)
            || (cdA < -1.0e-12 && cdB > 1.0e-12))
}

function selfIntersects(points) {
    for (var first = 0; first < points.length; first++) {
        var firstNext = (first + 1) % points.length
        for (var second = first + 1; second < points.length; second++) {
            var secondNext = (second + 1) % points.length
            if (first === second || firstNext === second
                    || secondNext === first)
                continue
            if (segmentsProperlyIntersect(
                    points[first], points[firstNext],
                    points[second], points[secondNext]))
                return true
        }
    }
    return false
}

// Produces a rendering-only loop from already validated authoritative geometry.
// Returned vertices are references to original points, so no feature is moved;
// the tolerance only bounds the omitted samples' distance from retained chords.
function simplifyClosedLoop(points, tolerance) {
    if (!Array.isArray(points) || points.length < 4)
        return points || []
    var limit = Math.max(0, Number(tolerance || 0))
    if (!(limit > 0))
        return points
    for (var finiteIndex = 0; finiteIndex < points.length; finiteIndex++) {
        if (!finitePoint(points[finiteIndex]))
            return points
    }
    var firstAnchor = 0
    var secondAnchor = 1
    var maximumDistanceSquared = -1
    for (var first = 0; first < points.length; first++) {
        for (var second = first + 1; second < points.length; second++) {
            var dx = Number(points[first].x_in) - Number(points[second].x_in)
            var dy = Number(points[first].y_in) - Number(points[second].y_in)
            var distanceSquared = dx * dx + dy * dy
            if (distanceSquared > maximumDistanceSquared) {
                maximumDistanceSquared = distanceSquared
                firstAnchor = first
                secondAnchor = second
            }
        }
    }
    var firstArc = []
    for (var firstIndex = firstAnchor;; firstIndex = (firstIndex + 1) % points.length) {
        firstArc.push(points[firstIndex])
        if (firstIndex === secondAnchor)
            break
    }
    var secondArc = []
    for (var secondIndex = secondAnchor;; secondIndex = (secondIndex + 1) % points.length) {
        secondArc.push(points[secondIndex])
        if (secondIndex === firstAnchor)
            break
    }
    var firstSimplified = simplifyOpen(firstArc, limit)
    var secondSimplified = simplifyOpen(secondArc, limit)
    var candidate = firstSimplified.slice(0, firstSimplified.length - 1)
        .concat(secondSimplified.slice(0, secondSimplified.length - 1))
    if (candidate.length < 3 || candidate.length >= points.length)
        return points
    var sourceArea = signedArea(points)
    var candidateArea = signedArea(candidate)
    if (!isFinite(sourceArea) || !isFinite(candidateArea)
            || Math.abs(sourceArea) <= 1.0e-12
            || sourceArea * candidateArea <= 0)
        return points
    var relativeAreaError = Math.abs(candidateArea - sourceArea)
        / Math.abs(sourceArea)
    if (relativeAreaError > 0.001 || selfIntersects(candidate))
        return points
    return candidate
}

function preparePanel(panel, tolerance) {
    if (!panel)
        return null
    var outer = simplifyClosedLoop(panel.outerLoop, tolerance)
    var holes = []
    var sourceHoles = panel.holeLoops || []
    for (var holeIndex = 0; holeIndex < sourceHoles.length; holeIndex++)
        holes.push(simplifyClosedLoop(sourceHoles[holeIndex], tolerance))
    return {
        outerLoop: outer,
        holeLoops: holes,
        sourceOuterPointCount: panel.outerLoop ? panel.outerLoop.length : 0,
        renderOuterPointCount: outer.length
    }
}
