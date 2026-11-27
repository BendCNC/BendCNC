.pragma library

var TOPOLOGY_TOLERANCE = 1.0e-6

function hasOwn(object, name) {
    return !!object && Object.prototype.hasOwnProperty.call(object, name)
}

function finiteValue(value) {
    return value !== null && value !== undefined && isFinite(Number(value))
}

function pointIsFinite(point) {
    return !!point && hasOwn(point, "x_in") && hasOwn(point, "y_in")
        && finiteValue(point.x_in) && finiteValue(point.y_in)
}

function pointDistanceSquared(a, b) {
    var dx = Number(a.x_in) - Number(b.x_in)
    var dy = Number(a.y_in) - Number(b.y_in)
    return dx * dx + dy * dy
}

function loopArea(points) {
    var area = 0
    for (var i = 0; i < points.length; i++) {
        var next = points[(i + 1) % points.length]
        area += Number(points[i].x_in) * Number(next.y_in)
            - Number(next.x_in) * Number(points[i].y_in)
    }
    return area * 0.5
}

function orientation(a, b, c) {
    return (Number(b.x_in) - Number(a.x_in)) * (Number(c.y_in) - Number(a.y_in))
        - (Number(b.y_in) - Number(a.y_in)) * (Number(c.x_in) - Number(a.x_in))
}

function pointOnSegment(point, start, end) {
    var pointX = Number(point.x_in)
    var pointY = Number(point.y_in)
    var startX = Number(start.x_in)
    var startY = Number(start.y_in)
    var endX = Number(end.x_in)
    var endY = Number(end.y_in)
    if (pointX < Math.min(startX, endX) - TOPOLOGY_TOLERANCE
            || pointX > Math.max(startX, endX) + TOPOLOGY_TOLERANCE
            || pointY < Math.min(startY, endY) - TOPOLOGY_TOLERANCE
            || pointY > Math.max(startY, endY) + TOPOLOGY_TOLERANCE)
        return false
    if (Math.abs(orientation(start, end, point)) > TOPOLOGY_TOLERANCE)
        return false
    return true
}

function segmentBoundsOverlap(a, b, c, d) {
    return Math.max(Number(a.x_in), Number(b.x_in)) + TOPOLOGY_TOLERANCE
            >= Math.min(Number(c.x_in), Number(d.x_in))
        && Math.max(Number(c.x_in), Number(d.x_in)) + TOPOLOGY_TOLERANCE
            >= Math.min(Number(a.x_in), Number(b.x_in))
        && Math.max(Number(a.y_in), Number(b.y_in)) + TOPOLOGY_TOLERANCE
            >= Math.min(Number(c.y_in), Number(d.y_in))
        && Math.max(Number(c.y_in), Number(d.y_in)) + TOPOLOGY_TOLERANCE
            >= Math.min(Number(a.y_in), Number(b.y_in))
}

function segmentsIntersect(a, b, c, d) {
    if (!segmentBoundsOverlap(a, b, c, d))
        return false
    var abC = orientation(a, b, c)
    var abD = orientation(a, b, d)
    var cdA = orientation(c, d, a)
    var cdB = orientation(c, d, b)
    if (((abC > TOPOLOGY_TOLERANCE && abD < -TOPOLOGY_TOLERANCE)
            || (abC < -TOPOLOGY_TOLERANCE && abD > TOPOLOGY_TOLERANCE))
            && ((cdA > TOPOLOGY_TOLERANCE && cdB < -TOPOLOGY_TOLERANCE)
            || (cdA < -TOPOLOGY_TOLERANCE && cdB > TOPOLOGY_TOLERANCE)))
        return true
    return (Math.abs(abC) <= TOPOLOGY_TOLERANCE && pointOnSegment(c, a, b))
        || (Math.abs(abD) <= TOPOLOGY_TOLERANCE && pointOnSegment(d, a, b))
        || (Math.abs(cdA) <= TOPOLOGY_TOLERANCE && pointOnSegment(a, c, d))
        || (Math.abs(cdB) <= TOPOLOGY_TOLERANCE && pointOnSegment(b, c, d))
}

function loopSelfIntersects(points) {
    var edges = []
    for (var edgeIndex = 0; edgeIndex < points.length; edgeIndex++) {
        var edgeEndIndex = (edgeIndex + 1) % points.length
        var edgeStart = points[edgeIndex]
        var edgeEnd = points[edgeEndIndex]
        edges.push({
            index: edgeIndex,
            endIndex: edgeEndIndex,
            start: edgeStart,
            end: edgeEnd,
            minX: Math.min(Number(edgeStart.x_in), Number(edgeEnd.x_in)),
            maxX: Math.max(Number(edgeStart.x_in), Number(edgeEnd.x_in)),
            minY: Math.min(Number(edgeStart.y_in), Number(edgeEnd.y_in)),
            maxY: Math.max(Number(edgeStart.y_in), Number(edgeEnd.y_in))
        })
    }
    edges.sort(function(left, right) { return left.minX - right.minX })
    for (var i = 0; i < edges.length; i++) {
        var left = edges[i]
        for (var j = i + 1; j < edges.length; j++) {
            var right = edges[j]
            if (right.minX > left.maxX + TOPOLOGY_TOLERANCE)
                break
            if (left.maxY + TOPOLOGY_TOLERANCE < right.minY
                    || right.maxY + TOPOLOGY_TOLERANCE < left.minY)
                continue
            if (left.index === right.index || left.endIndex === right.index
                    || right.endIndex === left.index)
                continue
            if (segmentsIntersect(left.start, left.end, right.start, right.end))
                return true
        }
    }
    return false
}

// Each check uses immutable input contours. Index only for the lifetime of
// this validation, so edits made before another check are always observed.
var validationRows = null

function edgesInYRange(loop, low, high) {
    if (!validationRows || loop.length < 12)
        return null
    var index = validationRows.get(loop)
    if (index === undefined) {
        var minY = Infinity, maxY = -Infinity
        for (var i = 0; i < loop.length; i++) {
            var y = Number(loop[i].y_in)
            minY = Math.min(minY, y)
            maxY = Math.max(maxY, y)
        }
        var n = Math.min(64, Math.ceil(Math.sqrt(loop.length)))
        var scale = n / (maxY - minY)
        index = null
        if (isFinite(scale) && scale > 0) {
            var rows = []
            for (i = 0; i < n; i++)
                rows.push([])
            var added = 0
            for (i = 0; i < loop.length; i++) {
                var a = Number(loop[i].y_in), b = Number(loop[(i + 1) % loop.length].y_in)
                // Keep near-boundary edges for both the inclusive contact
                // test and the half-open horizontal ray crossing test.
                var first = Math.min(n - 1, Math.max(0, Math.floor((Math.min(a, b) - 2 * TOPOLOGY_TOLERANCE - minY) * scale)))
                var last = Math.max(0, Math.min(n - 1, Math.floor((Math.max(a, b) + 2 * TOPOLOGY_TOLERANCE - minY) * scale)))
                added += last - first + 1
                if (added > loop.length * 8)
                    break
                for (var row = first; row <= last; row++)
                    rows[row].push(i)
            }
            if (i === loop.length)
                index = { minY: minY, maxY: maxY, scale: scale, rows: rows }
        }
        validationRows.set(loop, index)
    }
    if (!index)
        return null
    if (high < index.minY - 2 * TOPOLOGY_TOLERANCE || low > index.maxY + 2 * TOPOLOGY_TOLERANCE)
        return []
    var end = index.rows.length - 1
    var firstRow = Math.max(0, Math.min(end, Math.floor((low - index.minY) * index.scale)))
    var lastRow = Math.max(0, Math.min(end, Math.floor((high - index.minY) * index.scale)))
    return firstRow === lastRow ? index.rows[firstRow] : null
}

function pointInLoop(point, points, boundaryAlreadyChecked) {
    var inside = false
    var edges = edgesInYRange(points, Number(point.y_in), Number(point.y_in))
    for (var pos = 0, count = edges ? edges.length : points.length; pos < count; pos++) {
        var i = edges ? edges[pos] : pos
        var a = points[i]
        var b = points[(i + 1) % points.length]
        if (boundaryAlreadyChecked !== true && pointOnSegment(point, a, b))
            return true
        if ((Number(a.y_in) > Number(point.y_in)) === (Number(b.y_in) > Number(point.y_in)))
            continue
        var intersectionX = Number(a.x_in)
            + (Number(point.y_in) - Number(a.y_in)) * (Number(b.x_in) - Number(a.x_in))
            / (Number(b.y_in) - Number(a.y_in))
        if (intersectionX > Number(point.x_in))
            inside = !inside
    }
    return inside
}

function pointOnLoopBoundary(point, loop) {
    var edges = edgesInYRange(loop, Number(point.y_in), Number(point.y_in))
    for (var pos = 0, count = edges ? edges.length : loop.length; pos < count; pos++) {
        var index = edges ? edges[pos] : pos
        if (pointOnSegment(point, loop[index], loop[(index + 1) % loop.length]))
            return true
    }
    return false
}

function pointInMaterial(point, outer, holes, allowBoundary) {
    var onOuterBoundary = pointOnLoopBoundary(point, outer)
    if (!onOuterBoundary && !pointInLoop(point, outer, true))
        return false
    if (onOuterBoundary && !allowBoundary)
        return false
    for (var holeIndex = 0; holeIndex < holes.length; holeIndex++) {
        var onHoleBoundary = pointOnLoopBoundary(point, holes[holeIndex])
        if ((!onHoleBoundary && pointInLoop(point, holes[holeIndex], true))
                || (onHoleBoundary && !allowBoundary))
            return false
    }
    return true
}

function loopIsValid(points, label) {
    if (!Array.isArray(points) || points.length < 3)
        return label + ":requires-at-least-three-points"
    var repeatedPointBuckets = ({})
    var bucketSize = TOPOLOGY_TOLERANCE
    for (var i = 0; i < points.length; i++) {
        if (!pointIsFinite(points[i]))
            return label + ":non-finite-point"
        if (pointDistanceSquared(points[i], points[(i + 1) % points.length]) <= TOPOLOGY_TOLERANCE * TOPOLOGY_TOLERANCE)
            return label + ":degenerate-edge"
        var bucketX = Math.floor(Number(points[i].x_in) / bucketSize)
        var bucketY = Math.floor(Number(points[i].y_in) / bucketSize)
        for (var bucketDx = -1; bucketDx <= 1; bucketDx++) {
            for (var bucketDy = -1; bucketDy <= 1; bucketDy++) {
                var priorPoints = repeatedPointBuckets[String(bucketX + bucketDx) + ":" + String(bucketY + bucketDy)] || []
                for (var priorIndex = 0; priorIndex < priorPoints.length; priorIndex++) {
                    if (pointDistanceSquared(points[i], priorPoints[priorIndex])
                            <= TOPOLOGY_TOLERANCE * TOPOLOGY_TOLERANCE)
                        return label + ":repeated-point"
                }
            }
        }
        var bucketKey = String(bucketX) + ":" + String(bucketY)
        if (!repeatedPointBuckets[bucketKey])
            repeatedPointBuckets[bucketKey] = []
        repeatedPointBuckets[bucketKey].push(points[i])
    }
    if (Math.abs(loopArea(points)) <= TOPOLOGY_TOLERANCE)
        return label + ":zero-area"
    if (loopSelfIntersects(points))
        return label + ":self-intersecting"
    return ""
}

function previewLoopRing(points) {
    if (!Array.isArray(points))
        return []
    var result = points.slice(0)
    if (result.length > 1 && pointIsFinite(result[0]) && pointIsFinite(result[result.length - 1])
            && pointDistanceSquared(result[0], result[result.length - 1])
                <= TOPOLOGY_TOLERANCE * TOPOLOGY_TOLERANCE)
        result.pop()
    return result
}

function holeIsValid(hole, outer, label) {
    var error = loopIsValid(hole, label)
    if (error.length > 0)
        return error
    for (var i = 0; i < hole.length; i++) {
        if (!pointInLoop(hole[i], outer))
            return label + ":outside-panel"
    }
    if (loopsHaveBoundaryIntersection(hole, outer))
        return label + ":touches-panel-boundary"
    return ""
}

function loopsHaveBoundaryIntersection(left, right) {
    for (var leftEdge = 0; leftEdge < left.length; leftEdge++) {
        var leftEnd = (leftEdge + 1) % left.length
        var a = Number(left[leftEdge].y_in), b = Number(left[leftEnd].y_in)
        var edges = edgesInYRange(right, Math.min(a, b), Math.max(a, b))
        for (var pos = 0, count = edges ? edges.length : right.length; pos < count; pos++) {
            var rightEdge = edges ? edges[pos] : pos
            var rightEnd = (rightEdge + 1) % right.length
            if (segmentsIntersect(left[leftEdge], left[leftEnd], right[rightEdge], right[rightEnd]))
                return true
        }
    }
    return false
}

function segmentProperlyCrossesLoop(start, end, loop) {
    var aY = Number(start.y_in), bY = Number(end.y_in)
    var edges = edgesInYRange(loop, Math.min(aY, bY), Math.max(aY, bY))
    for (var pos = 0, count = edges ? edges.length : loop.length; pos < count; pos++) {
        var index = edges ? edges[pos] : pos
        var loopStart = loop[index]
        var loopEnd = loop[(index + 1) % loop.length]
        if (!segmentBoundsOverlap(start, end, loopStart, loopEnd))
            continue
        var abC = orientation(start, end, loopStart)
        var abD = orientation(start, end, loopEnd)
        var cdA = orientation(loopStart, loopEnd, start)
        var cdB = orientation(loopStart, loopEnd, end)
        if (((abC > TOPOLOGY_TOLERANCE && abD < -TOPOLOGY_TOLERANCE)
                || (abC < -TOPOLOGY_TOLERANCE && abD > TOPOLOGY_TOLERANCE))
                && ((cdA > TOPOLOGY_TOLERANCE && cdB < -TOPOLOGY_TOLERANCE)
                || (cdA < -TOPOLOGY_TOLERANCE && cdB > TOPOLOGY_TOLERANCE)))
            return true
    }
    return false
}

function loopsEquivalent(left, right) {
    if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length)
        return false
    for (var offset = 0; offset < right.length; offset++) {
        if (pointDistanceSquared(left[0], right[offset])
                > TOPOLOGY_TOLERANCE * TOPOLOGY_TOLERANCE)
            continue
        var forward = true
        var reverse = true
        for (var index = 0; index < left.length; index++) {
            if (pointDistanceSquared(left[index], right[(index + offset) % right.length])
                    > TOPOLOGY_TOLERANCE * TOPOLOGY_TOLERANCE)
                forward = false
            var reverseIndex = (offset - index) % right.length
            if (reverseIndex < 0)
                reverseIndex += right.length
            if (pointDistanceSquared(left[index], right[reverseIndex])
                    > TOPOLOGY_TOLERANCE * TOPOLOGY_TOLERANCE)
                reverse = false
            if (!forward && !reverse)
                break
        }
        if (forward || reverse)
            return true
    }
    return false
}

function interiorSample(points) {
    if (!Array.isArray(points) || points.length < 3)
        return null
    var orientationSign = loopArea(points) >= 0 ? 1 : -1
    for (var index = 0; index < points.length; index++) {
        var start = points[index]
        var end = points[(index + 1) % points.length]
        var dx = Number(end.x_in) - Number(start.x_in)
        var dy = Number(end.y_in) - Number(start.y_in)
        var length = Math.sqrt(dx * dx + dy * dy)
        if (length <= TOPOLOGY_TOLERANCE)
            continue
        var distance = Math.max(TOPOLOGY_TOLERANCE * 8, length * 1.0e-7)
        var sample = {
            x_in: (Number(start.x_in) + Number(end.x_in)) * 0.5 - dy / length * orientationSign * distance,
            y_in: (Number(start.y_in) + Number(end.y_in)) * 0.5 + dx / length * orientationSign * distance
        }
        if (pointInLoop(sample, points) && !pointOnSegment(sample, start, end))
            return sample
    }
    return null
}

function holesOverlapOrNest(left, right) {
    if (loopsHaveBoundaryIntersection(left, right))
        return true
    var leftSample = interiorSample(left)
    var rightSample = interiorSample(right)
    return (leftSample && pointInLoop(leftSample, right))
        || (rightSample && pointInLoop(rightSample, left))
}

function segmentParameter(point, start, dx, dy, lengthSquared) {
    return ((Number(point.x_in) - Number(start.x_in)) * dx
        + (Number(point.y_in) - Number(start.y_in)) * dy) / lengthSquared
}

function segmentCoveredByLoopBoundary(start, end, loop) {
    var dx = Number(end.x_in) - Number(start.x_in)
    var dy = Number(end.y_in) - Number(start.y_in)
    var lengthSquared = dx * dx + dy * dy
    var length = Math.sqrt(lengthSquared)
    if (!(length > TOPOLOGY_TOLERANCE))
        return false
    var intervals = []
    for (var edgeIndex = 0; edgeIndex < loop.length; edgeIndex++) {
        var edgeStart = loop[edgeIndex]
        var edgeEnd = loop[(edgeIndex + 1) % loop.length]
        if (Math.abs(orientation(start, end, edgeStart)) / length > TOPOLOGY_TOLERANCE
                || Math.abs(orientation(start, end, edgeEnd)) / length > TOPOLOGY_TOLERANCE)
            continue
        var first = segmentParameter(edgeStart, start, dx, dy, lengthSquared)
        var second = segmentParameter(edgeEnd, start, dx, dy, lengthSquared)
        var intervalStart = Math.max(0, Math.min(first, second))
        var intervalEnd = Math.min(1, Math.max(first, second))
        if (intervalEnd >= intervalStart - TOPOLOGY_TOLERANCE)
            intervals.push([intervalStart, intervalEnd])
    }
    intervals.sort(function(a, b) { return a[0] - b[0] })
    var covered = 0
    for (var intervalIndex = 0; intervalIndex < intervals.length; intervalIndex++) {
        var interval = intervals[intervalIndex]
        if (interval[0] > covered + TOPOLOGY_TOLERANCE)
            return false
        covered = Math.max(covered, interval[1])
    }
    return covered >= 1 - TOPOLOGY_TOLERANCE
}

function segmentCoveredByPanelBoundary(start, end, outer, holes) {
    if (segmentCoveredByLoopBoundary(start, end, outer))
        return true
    for (var index = 0; holes && index < holes.length; index++) {
        if (segmentCoveredByLoopBoundary(start, end, holes[index]))
            return true
    }
    return false
}

function loopInsideOrOnLoop(inner, outer) {
    for (var index = 0; index < inner.length; index++) {
        var point = inner[index]
        if (!pointInLoop(point, outer)
                && !outer.some(function(start, edge) { return pointOnSegment(point, start, outer[(edge + 1) % outer.length]) }))
            return false
    }
    var sample = interiorSample(inner)
    return !!sample && pointInLoop(sample, outer)
}

function loopInsideAnyHole(loop, holes) {
    for (var index = 0; holes && index < holes.length; index++) {
        if (loopInsideOrOnLoop(loop, holes[index]))
            return true
    }
    return false
}

function pointInsideAnyPanelOuter(point, panels) {
    for (var index = 0; index < panels.length; index++) {
        var outer = panels[index] && panels[index].outerLoop
        if (Array.isArray(outer) && outer.length >= 3 && pointInLoop(point, outer))
            return true
    }
    return false
}

function islandHoleContainsPanel(hole, panels) {
    for (var index = 0; index < panels.length; index++) {
        var outer = panels[index] && panels[index].outerLoop
        if (Array.isArray(outer) && outer.length >= 3 && loopInsideOrOnLoop(outer, hole))
            return true
    }
    return false
}

function panelInteriorsOverlap(left, right) {
    for (var leftEdge = 0; leftEdge < left.length; leftEdge++) {
        var leftStart = left[leftEdge]
        var leftEnd = left[(leftEdge + 1) % left.length]
        for (var rightEdge = 0; rightEdge < right.length; rightEdge++) {
            var rightStart = right[rightEdge]
            var rightEnd = right[(rightEdge + 1) % right.length]
            if (!segmentBoundsOverlap(leftStart, leftEnd, rightStart, rightEnd))
                continue
            var abC = orientation(leftStart, leftEnd, rightStart)
            var abD = orientation(leftStart, leftEnd, rightEnd)
            var cdA = orientation(rightStart, rightEnd, leftStart)
            var cdB = orientation(rightStart, rightEnd, leftEnd)
            if (((abC > TOPOLOGY_TOLERANCE && abD < -TOPOLOGY_TOLERANCE)
                    || (abC < -TOPOLOGY_TOLERANCE && abD > TOPOLOGY_TOLERANCE))
                    && ((cdA > TOPOLOGY_TOLERANCE && cdB < -TOPOLOGY_TOLERANCE)
                    || (cdA < -TOPOLOGY_TOLERANCE && cdB > TOPOLOGY_TOLERANCE)))
                return true
        }
    }
    for (var leftPoint = 0; leftPoint < left.length; leftPoint++) {
        if (pointInLoop(left[leftPoint], right)
                && !right.some(function(start, index) { return pointOnSegment(left[leftPoint], start, right[(index + 1) % right.length]) }))
            return true
    }
    for (var rightPoint = 0; rightPoint < right.length; rightPoint++) {
        if (pointInLoop(right[rightPoint], left)
                && !left.some(function(start, index) { return pointOnSegment(right[rightPoint], start, left[(index + 1) % left.length]) }))
            return true
    }
    var leftSample = interiorSample(left)
    var rightSample = interiorSample(right)
    return (leftSample && pointInLoop(leftSample, right))
        || (rightSample && pointInLoop(rightSample, left))
}

function edgePointIsValid(point, label) {
    return pointIsFinite(point) ? "" : label + ":non-finite-point"
}

function hingeGapIsVoidOrSibling(edge, start, ux, uy, gapStart, gapEnd, materialBoundary, siblingEdges) {
    if (!materialBoundary)
        return false
    var pieces = [[gapStart, gapEnd]]
    for (var s = 0; s < (siblingEdges || []).length; s++) {
        var sibling = siblingEdges[s]
        if (sibling === edge || String(sibling.sourceBendId) !== String(edge.sourceBendId))
            continue
        var segments = sibling.hingeSegments || []
        for (var k = 0; k < segments.length; k++) {
            var p0 = (Number(segments[k][0].x_in) - Number(start.x_in)) * ux + (Number(segments[k][0].y_in) - Number(start.y_in)) * uy
            var p1 = (Number(segments[k][1].x_in) - Number(start.x_in)) * ux + (Number(segments[k][1].y_in) - Number(start.y_in)) * uy
            var lo = Math.min(p0, p1), hi = Math.max(p0, p1)
            var next = []
            for (var q = 0; q < pieces.length; q++) {
                var piece = pieces[q]
                if (hi <= piece[0] + TOPOLOGY_TOLERANCE || lo >= piece[1] - TOPOLOGY_TOLERANCE) {
                    next.push(piece)
                    continue
                }
                if (lo > piece[0] + TOPOLOGY_TOLERANCE)
                    next.push([piece[0], lo])
                if (hi < piece[1] - TOPOLOGY_TOLERANCE)
                    next.push([hi, piece[1]])
            }
            pieces = next
        }
    }
    for (var r = 0; r < pieces.length; r++) {
        var mid = (pieces[r][0] + pieces[r][1]) / 2
        var point = { x_in: Number(start.x_in) + ux * mid, y_in: Number(start.y_in) + uy * mid }
        if (pointInMaterial(point, materialBoundary.outerLoop, materialBoundary.holeLoops || [], false))
            return false
    }
    return true
}

function hingeSegmentsError(edge, edgeId, materialBoundary, siblingEdges) {
    var start = edge.hingeStart
    var end = edge.hingeEnd
    var dx = Number(end.x_in) - Number(start.x_in)
    var dy = Number(end.y_in) - Number(start.y_in)
    var length = Math.sqrt(dx * dx + dy * dy)
    var ux = dx / length
    var uy = dy / length
    var intervals = []
    for (var index = 0; index < edge.hingeSegments.length; index++) {
        var segment = edge.hingeSegments[index]
        var first = segment[0]
        var second = segment[1]
        if (Math.abs(orientation(start, end, first)) / length > TOPOLOGY_TOLERANCE
                || Math.abs(orientation(start, end, second)) / length > TOPOLOGY_TOLERANCE)
            return "edge-hinge-segment-not-collinear:" + edgeId + ":" + index
        var firstDx = Number(first.x_in) - Number(start.x_in)
        var firstDy = Number(first.y_in) - Number(start.y_in)
        var secondDx = Number(second.x_in) - Number(start.x_in)
        var secondDy = Number(second.y_in) - Number(start.y_in)
        var firstParameter = firstDx * ux + firstDy * uy
        var secondParameter = secondDx * ux + secondDy * uy
        if (firstParameter < -TOPOLOGY_TOLERANCE || firstParameter > length + TOPOLOGY_TOLERANCE
                || secondParameter < -TOPOLOGY_TOLERANCE || secondParameter > length + TOPOLOGY_TOLERANCE)
            return "edge-hinge-segment-outside:" + edgeId + ":" + index
        intervals.push([Math.min(firstParameter, secondParameter),
                        Math.max(firstParameter, secondParameter)])
    }
    intervals.sort(function(a, b) { return a[0] - b[0] })
    var covered = 0
    for (var intervalIndex = 0; intervalIndex < intervals.length; intervalIndex++) {
        var interval = intervals[intervalIndex]
        if (interval[0] < covered - TOPOLOGY_TOLERANCE)
            return "edge-hinge-segments-overlap:" + edgeId
        if (interval[0] > covered + TOPOLOGY_TOLERANCE) {
            // A slot/cutout crossing the bend splits the hinge: the gap must be void
            // or carried by another relation of the same source bend (e.g. a tab).
            if (!hingeGapIsVoidOrSibling(edge, start, ux, uy, covered, interval[0],
                                         materialBoundary, siblingEdges))
                return "edge-hinge-segments-gap:" + edgeId
        }
        covered = Math.max(covered, interval[1])
    }
    return covered >= length - TOPOLOGY_TOLERANCE
        ? ""
        : "edge-hinge-segments-incomplete:" + edgeId
}

function validateGraph(graph, timing) {
    var previous = validationRows
    validationRows = new WeakMap()
    try {
        return validateGraphContours(graph, timing)
    } finally {
        validationRows = previous
    }
}

function validateGraphContours(graph, timing) {
    var validateStarted = timing ? Date.now() : 0
    var diagnostics = graph && graph.diagnostics ? graph.diagnostics : null
    if (!graph)
        return "graph-missing"
    if (!finiteValue(graph.schemaVersion) || Number(graph.schemaVersion) < 5)
        return "schema-version-not-v5"
    if (!diagnostics || String(diagnostics.status || "") !== "qualified")
        return "diagnostics-not-qualified"
    if (diagnostics.rootSelectionAmbiguous !== false)
        return "root-selection-not-proven-unambiguous"
    if (String(graph.geometryAuthority || "").indexOf("planar-subdivision-v5") < 0)
        return "geometry-authority-not-v5"
    var materialBoundary = graph.materialBoundary
    if (!materialBoundary || typeof materialBoundary !== "object")
        return "material-boundary-missing"
    var materialOuterError = loopIsValid(materialBoundary.outerLoop, "material-outer-loop")
    if (materialOuterError.length > 0)
        return materialOuterError
    var materialHoles = materialBoundary.holeLoops
    if (!Array.isArray(materialHoles))
        return "material-holes-not-array"
    for (var materialHoleIndex = 0; materialHoleIndex < materialHoles.length; materialHoleIndex++) {
        var materialHoleError = holeIsValid(
            materialHoles[materialHoleIndex], materialBoundary.outerLoop,
            "material-hole-loop:" + materialHoleIndex)
        if (materialHoleError.length > 0)
            return materialHoleError
        for (var previousMaterialHole = 0; previousMaterialHole < materialHoleIndex; previousMaterialHole++) {
            if (holesOverlapOrNest(materialHoles[previousMaterialHole], materialHoles[materialHoleIndex]))
                return "material-holes-overlap-or-nest:" + previousMaterialHole + ":" + materialHoleIndex
        }
    }
    var materialAt = timing ? Date.now() : 0
    if (!Array.isArray(graph.panels) || graph.panels.length === 0)
        return "panels-missing"
    if (!Array.isArray(graph.bendEdges))
        return "bend-edges-missing"

    var rootId = String(graph.rootPanelId || "")
    if (rootId.length === 0)
        return "root-panel-id-missing"
    var panelIds = ({})
    var panelLoops = ({})
    var panelNetAreas = ({})
    var panelHoleLoops = ({})
    var allPanelHoles = []
    var computedPartitionArea = 0
    for (var panelIndex = 0; panelIndex < graph.panels.length; panelIndex++) {
        var panel = graph.panels[panelIndex]
        if (!panel || String(panel.panelId || "").length === 0)
            return "panel-id-missing:" + panelIndex
        var panelId = String(panel.panelId)
        if (panelIds[panelId])
            return "duplicate-panel-id:" + panelId
        panelIds[panelId] = true
        var outerError = loopIsValid(panel.outerLoop, "panel-outer-loop:" + panelId)
        if (outerError.length > 0)
            return outerError
        for (var materialEdgeIndex = 0; materialEdgeIndex < panel.outerLoop.length; materialEdgeIndex++) {
            var materialEdgeStart = panel.outerLoop[materialEdgeIndex]
            var materialEdgeEnd = panel.outerLoop[(materialEdgeIndex + 1) % panel.outerLoop.length]
            if (!pointInMaterial(materialEdgeStart, materialBoundary.outerLoop, materialHoles, true))
                return "panel-vertex-outside-material:" + panelId + ":" + materialEdgeIndex
            var materialMidpoint = {
                x_in: (Number(materialEdgeStart.x_in) + Number(materialEdgeEnd.x_in)) * 0.5,
                y_in: (Number(materialEdgeStart.y_in) + Number(materialEdgeEnd.y_in)) * 0.5
            }
            if (!pointInMaterial(materialMidpoint, materialBoundary.outerLoop, materialHoles, true)
                    || segmentProperlyCrossesLoop(materialEdgeStart, materialEdgeEnd, materialBoundary.outerLoop))
                return "panel-edge-outside-material:" + panelId + ":" + materialEdgeIndex
            for (var crossingHoleIndex = 0; crossingHoleIndex < materialHoles.length; crossingHoleIndex++) {
                if (segmentProperlyCrossesLoop(materialEdgeStart, materialEdgeEnd, materialHoles[crossingHoleIndex]))
                    return "panel-edge-outside-material:" + panelId + ":" + materialEdgeIndex
            }
        }
        if (String(panel.geometryAuthority || "").indexOf("planar-subdivision") < 0)
            return "panel-geometry-authority-not-planar:" + panelId
        var holes = panel.holeLoops === undefined || panel.holeLoops === null ? [] : panel.holeLoops
        if (!Array.isArray(holes))
            return "panel-holes-not-array:" + panelId
        for (var holeIndex = 0; holeIndex < holes.length; holeIndex++) {
            var holeError = holeIsValid(holes[holeIndex], panel.outerLoop,
                                        "panel-hole-loop:" + panelId + ":" + holeIndex)
            if (holeError.length > 0)
                return holeError
            for (var previousHole = 0; previousHole < holeIndex; previousHole++) {
                if (holesOverlapOrNest(holes[previousHole], holes[holeIndex]))
                    return "panel-holes-overlap-or-nest:" + panelId + ":" + previousHole + ":" + holeIndex
            }
            allPanelHoles.push(holes[holeIndex])
        }
        var netArea = Math.abs(loopArea(panel.outerLoop))
        for (var areaHoleIndex = 0; areaHoleIndex < holes.length; areaHoleIndex++)
            netArea -= Math.abs(loopArea(holes[areaHoleIndex]))
        if (!(netArea > TOPOLOGY_TOLERANCE))
            return "panel-net-area-invalid:" + panelId
        panelLoops[panelId] = panel.outerLoop
        panelHoleLoops[panelId] = holes
        panelNetAreas[panelId] = netArea
        computedPartitionArea += netArea
    }
    var panelsAt = timing ? Date.now() : 0
    var assignedPanelHoles = []
    for (var panelHoleSeed = 0; panelHoleSeed < allPanelHoles.length; panelHoleSeed++)
        assignedPanelHoles.push(false)
    for (var expectedHoleIndex = 0; expectedHoleIndex < materialHoles.length; expectedHoleIndex++) {
        var matchingHoleCount = 0
        var matchingPanelHoleIndex = -1
        for (var candidateHoleIndex = 0; candidateHoleIndex < allPanelHoles.length; candidateHoleIndex++) {
            if (loopsEquivalent(materialHoles[expectedHoleIndex], allPanelHoles[candidateHoleIndex])) {
                matchingHoleCount++
                matchingPanelHoleIndex = candidateHoleIndex
            }
        }
        if (matchingHoleCount === 0) {
            // A relief slot around an island tab is covered by the island cutout.
            var nestedSample = interiorSample(materialHoles[expectedHoleIndex])
            var islandOwners = 0
            for (var islandHoleIndex = 0; islandHoleIndex < allPanelHoles.length; islandHoleIndex++) {
                if (nestedSample && pointInLoop(nestedSample, allPanelHoles[islandHoleIndex])
                        && islandHoleContainsPanel(allPanelHoles[islandHoleIndex], graph.panels))
                    islandOwners++
            }
            if (islandOwners === 1)
                continue
            // A hole crossed by a bend (split hinge) is carved out of the adjacent
            // panels' outer loops, so it lies outside every panel.
            if (nestedSample && !pointInsideAnyPanelOuter(nestedSample, graph.panels))
                continue
        }
        if (matchingHoleCount !== 1)
            return "material-hole-panel-assignment-invalid:" + expectedHoleIndex + ":" + matchingHoleCount
        assignedPanelHoles[matchingPanelHoleIndex] = true
    }
    for (var unexpectedHoleIndex = 0; unexpectedHoleIndex < assignedPanelHoles.length; unexpectedHoleIndex++) {
        if (!assignedPanelHoles[unexpectedHoleIndex]
                && !islandHoleContainsPanel(allPanelHoles[unexpectedHoleIndex], graph.panels))
            return "unexpected-panel-hole:" + unexpectedHoleIndex
    }
    var holeAssignmentAt = timing ? Date.now() : 0
    for (var leftPanelIndex = 0; leftPanelIndex < graph.panels.length; leftPanelIndex++) {
        var leftPanelId = String(graph.panels[leftPanelIndex].panelId)
        for (var rightPanelIndex = leftPanelIndex + 1; rightPanelIndex < graph.panels.length; rightPanelIndex++) {
            var rightPanelId = String(graph.panels[rightPanelIndex].panelId)
            if (panelInteriorsOverlap(panelLoops[leftPanelId], panelLoops[rightPanelId])
                    && !loopInsideAnyHole(panelLoops[rightPanelId], panelHoleLoops[leftPanelId])
                    && !loopInsideAnyHole(panelLoops[leftPanelId], panelHoleLoops[rightPanelId]))
                return "panel-interiors-overlap:" + leftPanelId + ":" + rightPanelId
        }
    }
    var overlapAt = timing ? Date.now() : 0
    var expectedArea = Number(diagnostics.expectedMaterialArea_in2)
    var declaredPartitionArea = Number(diagnostics.partitionArea_in2)
    var declaredAreaError = Number(diagnostics.partitionAreaError_in2)
    if (!finiteValue(expectedArea) || !(expectedArea > 0)
            || !finiteValue(declaredPartitionArea) || !(declaredPartitionArea > 0)
            || !finiteValue(declaredAreaError) || declaredAreaError < 0)
        return "partition-area-proof-missing"
    var areaTolerance = Math.max(0.001, expectedArea * 0.0005)
    var computedMaterialArea = Math.abs(loopArea(materialBoundary.outerLoop))
    for (var materialAreaHoleIndex = 0; materialAreaHoleIndex < materialHoles.length; materialAreaHoleIndex++)
        computedMaterialArea -= Math.abs(loopArea(materialHoles[materialAreaHoleIndex]))
    if (Math.abs(computedMaterialArea - expectedArea) > areaTolerance
            || Math.abs(computedPartitionArea - declaredPartitionArea) > areaTolerance
            || Math.abs(computedPartitionArea - expectedArea) > areaTolerance
            || Math.abs(Math.abs(expectedArea - declaredPartitionArea) - declaredAreaError) > areaTolerance)
        return "partition-area-proof-mismatch"
    if (!panelIds[rootId])
        return "root-panel-does-not-exist:" + rootId

    var rootPanel = null
    for (var rootIndex = 0; rootIndex < graph.panels.length; rootIndex++) {
        if (String(graph.panels[rootIndex].panelId) === rootId) {
            rootPanel = graph.panels[rootIndex]
            break
        }
    }
    if (rootPanel.parentPanelId !== null && rootPanel.parentPanelId !== undefined
            && String(rootPanel.parentPanelId).length > 0)
        return "root-panel-has-parent:" + rootId
    for (var parentIndex = 0; parentIndex < graph.panels.length; parentIndex++) {
        var candidatePanel = graph.panels[parentIndex]
        var candidateId = String(candidatePanel.panelId)
        if (candidateId === rootId)
            continue
        if (candidatePanel.parentPanelId === null || candidatePanel.parentPanelId === undefined
                || String(candidatePanel.parentPanelId).length === 0)
            return "non-root-panel-missing-parent:" + candidateId
        if (!panelIds[String(candidatePanel.parentPanelId)])
            return "panel-parent-does-not-exist:" + candidateId
        if (String(candidatePanel.parentPanelId) === candidateId)
            return "panel-self-parent:" + candidateId
        if (candidatePanel.ownerBendId === null || candidatePanel.ownerBendId === undefined
                || String(candidatePanel.ownerBendId).length === 0)
            return "non-root-panel-missing-owner-bend:" + candidateId
    }
    var areaAndRelationsAt = timing ? Date.now() : 0

    if (graph.bendEdges.length !== graph.panels.length - 1)
        return "edge-count-does-not-form-tree"
    var edgeIds = ({})
    var sourceBendRelations = ({})
    var incoming = ({})
    var outgoing = ({})
    for (var edgeIndex = 0; edgeIndex < graph.bendEdges.length; edgeIndex++) {
        var edge = graph.bendEdges[edgeIndex]
        if (!edge)
            return "edge-missing:" + edgeIndex
        var edgeId = String(edge.bendId || "")
        if (edgeId.length === 0)
            return "edge-id-missing:" + edgeIndex
        if (edgeIds[edgeId])
            return "duplicate-edge-id:" + edgeId
        edgeIds[edgeId] = true
        var parentId = String(edge.parentPanelId || "")
        var childId = String(edge.childPanelId || "")
        if (!panelIds[parentId])
            return "edge-parent-does-not-exist:" + edgeId
        if (!panelIds[childId])
            return "edge-child-does-not-exist:" + edgeId
        if (parentId === childId)
            return "edge-self-reference:" + edgeId
        if (childId === rootId)
            return "root-panel-has-incoming-edge:" + edgeId
        if (incoming[childId])
            return "child-has-multiple-parent-edges:" + childId
        incoming[childId] = edgeId
        if (!outgoing[parentId])
            outgoing[parentId] = []
        outgoing[parentId].push(edge)
        var sourceBendId = String(edge.sourceBendId || "")
        if (sourceBendId.length === 0)
            return "edge-source-bend-id-missing:" + edgeId
        var relationCount = Number(edge.operationRelationCount === undefined
                                   ? 1 : edge.operationRelationCount)
        var relationIndex = Number(edge.operationRelationIndex === undefined
                                   ? 0 : edge.operationRelationIndex)
        if (!Number.isInteger(relationCount) || relationCount < 1
                || !Number.isInteger(relationIndex) || relationIndex < 0
                || relationIndex >= relationCount)
            return "edge-operation-relation-invalid:" + edgeId
        if (!sourceBendRelations[sourceBendId])
            sourceBendRelations[sourceBendId] = ({
                count: relationCount,
                indices: ({}),
                sequenceHint: Number(edge.sequenceHint),
                bendAngleDegrees: Number(edge.bendAngleDegrees),
                direction: String(edge.direction || "").toUpperCase()
            })
        var relationSet = sourceBendRelations[sourceBendId]
        if (relationSet.count !== relationCount)
            return "edge-operation-relation-count-mismatch:" + sourceBendId
        if (relationSet.indices[relationIndex])
            return "edge-operation-relation-duplicate:" + sourceBendId + ":" + relationIndex
        relationSet.indices[relationIndex] = true
        var startError = edgePointIsValid(edge.hingeStart, "edge-hinge-start:" + edgeId)
        var endError = edgePointIsValid(edge.hingeEnd, "edge-hinge-end:" + edgeId)
        if (startError.length > 0)
            return startError
        if (endError.length > 0)
            return endError
        if (pointDistanceSquared(edge.hingeStart, edge.hingeEnd) <= TOPOLOGY_TOLERANCE * TOPOLOGY_TOLERANCE)
            return "edge-hinge-degenerate:" + edgeId
        if (!finiteValue(edge.sequenceHint) || Number(edge.sequenceHint) <= 0)
            return "edge-sequence-invalid:" + edgeId
        if (!finiteValue(edge.bendAngleDegrees) || Number(edge.bendAngleDegrees) <= 0
                || Number(edge.bendAngleDegrees) > 180)
            return "edge-bend-angle-invalid:" + edgeId
        if (!finiteValue(edge.foldAngleDegrees) || Number(edge.foldAngleDegrees) < 0
                || Number(edge.foldAngleDegrees) > 180)
            return "edge-fold-angle-invalid:" + edgeId
        if (!finiteValue(edge.insideRadius_in) || Number(edge.insideRadius_in) < 0
                || !finiteValue(edge.thickness_in) || Number(edge.thickness_in) <= 0
                || !finiteValue(edge.kFactor) || Number(edge.kFactor) < 0
                || Number(edge.kFactor) > 1)
            return "edge-material-invalid:" + edgeId
        var sideSign = Number(edge.childSideSign)
        if (!finiteValue(edge.childSideSign) || (sideSign !== -1 && sideSign !== 1))
            return "edge-child-side-invalid:" + edgeId
        var direction = String(edge.direction || "").toUpperCase()
        if (direction !== "UP" && direction !== "DOWN")
            return "edge-direction-invalid:" + edgeId
        if (relationSet.sequenceHint !== Number(edge.sequenceHint)
                || Math.abs(relationSet.bendAngleDegrees
                            - Number(edge.bendAngleDegrees)) > TOPOLOGY_TOLERANCE
                || relationSet.direction !== direction)
            return "edge-operation-relation-metadata-mismatch:" + sourceBendId
        if (!Array.isArray(edge.hingeSegments) || edge.hingeSegments.length === 0)
            return "edge-hinge-segments-missing:" + edgeId
        for (var segmentIndex = 0; segmentIndex < edge.hingeSegments.length; segmentIndex++) {
            var hingeSegment = edge.hingeSegments[segmentIndex]
            if (!Array.isArray(hingeSegment) || hingeSegment.length !== 2)
                return "edge-hinge-segment-invalid:" + edgeId + ":" + segmentIndex
            if (!pointIsFinite(hingeSegment[0]) || !pointIsFinite(hingeSegment[1]))
                return "edge-hinge-segment-non-finite:" + edgeId + ":" + segmentIndex
            if (pointDistanceSquared(hingeSegment[0], hingeSegment[1]) <= TOPOLOGY_TOLERANCE * TOPOLOGY_TOLERANCE)
                return "edge-hinge-segment-degenerate:" + edgeId + ":" + segmentIndex
            if (!segmentCoveredByPanelBoundary(hingeSegment[0], hingeSegment[1], panelLoops[parentId], panelHoleLoops[parentId])
                    || !segmentCoveredByPanelBoundary(hingeSegment[0], hingeSegment[1], panelLoops[childId], panelHoleLoops[childId]))
                return "edge-hinge-not-shared-panel-boundary:" + edgeId + ":" + segmentIndex
        }
        var hingeError = hingeSegmentsError(edge, edgeId, graph.materialBoundary, graph.bendEdges)
        if (hingeError.length > 0)
            return hingeError
        var childPanel = null
        for (var childPanelIndex = 0; childPanelIndex < graph.panels.length; childPanelIndex++) {
            if (String(graph.panels[childPanelIndex].panelId) === childId) {
                childPanel = graph.panels[childPanelIndex]
                break
            }
        }
        if (!childPanel || String(childPanel.parentPanelId) !== parentId
                || String(childPanel.ownerBendId || "") !== sourceBendId)
            return "edge-panel-relation-inconsistent:" + edgeId
    }
    var edgesAt = timing ? Date.now() : 0
    for (var nonRootId in panelIds) {
        if (nonRootId !== rootId && !incoming[nonRootId])
            return "panel-missing-incoming-edge:" + nonRootId
    }
    for (var operationId in sourceBendRelations) {
        var operation = sourceBendRelations[operationId]
        for (var operationIndex = 0; operationIndex < operation.count; operationIndex++) {
            if (!operation.indices[operationIndex])
                return "edge-operation-relation-missing:" + operationId + ":" + operationIndex
        }
    }

    var visited = ({})
    var visiting = ({})
    function visit(panelId) {
        if (visiting[panelId])
            return "cycle-at-panel:" + panelId
        if (visited[panelId])
            return ""
        visiting[panelId] = true
        var children = outgoing[panelId] || []
        for (var childIndex = 0; childIndex < children.length; childIndex++) {
            var childError = visit(String(children[childIndex].childPanelId))
            if (childError.length > 0)
                return childError
        }
        delete visiting[panelId]
        visited[panelId] = true
        return ""
    }
    var visitError = visit(rootId)
    if (visitError.length > 0)
        return visitError
    for (var visitedId in panelIds) {
        if (!visited[visitedId]) {
            var disconnectedError = visit(visitedId)
            if (disconnectedError.length > 0)
                return disconnectedError
            return "unreachable-panel:" + visitedId
        }
    }
    if (timing) {
        var finishedAt = Date.now()
        timing.materialMs = materialAt - validateStarted
        timing.panelsMs = panelsAt - materialAt
        timing.holeAssignmentMs = holeAssignmentAt - panelsAt
        timing.overlapMs = overlapAt - holeAssignmentAt
        timing.areaAndRelationsMs = areaAndRelationsAt - overlapAt
        timing.edgesMs = edgesAt - areaAndRelationsAt
        timing.treeMs = finishedAt - edgesAt
    }
    return ""
}

function graphIsQualified(graph) {
    return validateGraph(graph).length === 0
}

// The same CAD geometry is validated by the importer and by every canvas that
// draws it, usually through fresh JSON copies. Results are keyed by the
// validated content itself, so a copy reuses the verdict and any change in
// geometry, provenance or flat pattern validates again.
var validationVerdicts = []
var VALIDATION_VERDICT_LIMIT = 4

function validationKey(preview, expectedGeneratorId, expectedGeneratorVersion,
                       expectedGeneratorRevision) {
    return JSON.stringify([preview.sheetMetalGraph, preview.generator, preview.flatPattern,
                           expectedGeneratorId, expectedGeneratorVersion,
                           expectedGeneratorRevision])
}

// Stores a verdict computed by the identical code in a worker thread.
function rememberValidation(preview, expectedGeneratorId, expectedGeneratorVersion,
                            expectedGeneratorRevision, error) {
    if (!preview || typeof preview !== "object")
        return
    var key = validationKey(preview, expectedGeneratorId, expectedGeneratorVersion,
                            expectedGeneratorRevision)
    validationVerdicts.unshift({ key: key, error: String(error || "") })
    if (validationVerdicts.length > VALIDATION_VERDICT_LIMIT)
        validationVerdicts.length = VALIDATION_VERDICT_LIMIT
}

// Returns the remembered verdict, or null when this content was never validated.
function cachedValidationError(preview, expectedGeneratorId, expectedGeneratorVersion,
                               expectedGeneratorRevision) {
    if (!preview || typeof preview !== "object")
        return "preview-missing"
    var key = validationKey(preview, expectedGeneratorId, expectedGeneratorVersion,
                            expectedGeneratorRevision)
    for (var i = 0; i < validationVerdicts.length; i++)
        if (validationVerdicts[i].key === key)
            return validationVerdicts[i].error
    return null
}

function validateAuthoritativePreview(preview, expectedGeneratorId, expectedGeneratorVersion,
                                      expectedGeneratorRevision, timing) {
    if (!preview || typeof preview !== "object")
        return "preview-missing"
    var key = validationKey(preview, expectedGeneratorId, expectedGeneratorVersion,
                            expectedGeneratorRevision)
    for (var verdictIndex = 0; verdictIndex < validationVerdicts.length; verdictIndex++) {
        if (validationVerdicts[verdictIndex].key === key) {
            if (timing)
                timing.cached = true
            return validationVerdicts[verdictIndex].error
        }
    }
    var error = validateAuthoritativePreviewUncached(preview, expectedGeneratorId,
                                                     expectedGeneratorVersion,
                                                     expectedGeneratorRevision, timing)
    validationVerdicts.unshift({ key: key, error: error })
    if (validationVerdicts.length > VALIDATION_VERDICT_LIMIT)
        validationVerdicts.length = VALIDATION_VERDICT_LIMIT
    return error
}

// Exporter ids before and after the brand rename identify the same exporter.
function canonicalGeneratorId(id) {
    var value = String(id || "")
    return /^com\.(?:[a-z0-9_]+\.)*?bend(?:control|cnc)\.export$/i.test(value) ? "bend.export" : value
}

function generatorIdMatches(actual, expected) {
    return canonicalGeneratorId(actual) === canonicalGeneratorId(expected)
}

function validateAuthoritativePreviewUncached(preview, expectedGeneratorId, expectedGeneratorVersion,
                                              expectedGeneratorRevision, timing) {
    var graph = preview.sheetMetalGraph
    var graphStarted = timing ? Date.now() : 0
    var graphTiming = timing ? ({}) : null
    var graphError = validateGraph(graph, graphTiming)
    if (timing)
        timing.graphMs = Date.now() - graphStarted
    if (timing)
        timing.graph = graphTiming
    if (graphError.length > 0)
        return graphError
    var authorityStarted = timing ? Date.now() : 0
    var generator = preview.generator
    var acceptedRevisions = Array.isArray(expectedGeneratorRevision)
        ? expectedGeneratorRevision.map(function(value) { return String(value || "") })
        : [String(expectedGeneratorRevision || "")]
    if (!generator || !generatorIdMatches(generator.id, expectedGeneratorId)
            || String(generator.version || "") !== String(expectedGeneratorVersion || "")
            || acceptedRevisions.indexOf(String(generator.revision || "")) < 0
            || Number(generator.topologySchemaVersion) !== 5)
        return "generator-provenance-not-current"
    var flatPattern = preview.flatPattern
    var preview2d = flatPattern && flatPattern.preview2d
    if (!preview2d || String(preview2d.surfaceType || "").toLowerCase() !== "plane")
        return "flat-pattern-profile-surface-not-planar"
    var sourceLoops = preview2d.loops
    var integrity = preview2d.loopIntegrity
    if (!Array.isArray(sourceLoops) || sourceLoops.length === 0
            || !Array.isArray(integrity) || integrity.length !== sourceLoops.length)
        return "flat-pattern-loop-integrity-missing"
    var integrityByIndex = ({})
    for (var integrityIndex = 0; integrityIndex < integrity.length; integrityIndex++) {
        var integrityItem = integrity[integrityIndex]
        var loopIndex = Number(integrityItem && integrityItem.loopIndex)
        if (!integrityItem || !Number.isInteger(loopIndex) || loopIndex < 0
                || loopIndex >= sourceLoops.length || hasOwn(integrityByIndex, String(loopIndex)))
            return "flat-pattern-loop-integrity-invalid:" + String(loopIndex)
        integrityByIndex[String(loopIndex)] = integrityItem
    }
    var previewOuter = null
    var previewHoles = []
    for (var sourceIndex = 0; sourceIndex < sourceLoops.length; sourceIndex++) {
        var sourceLoop = sourceLoops[sourceIndex]
        var points = previewLoopRing(sourceLoop && sourceLoop.points)
        var itemError = loopIsValid(points, "flat-pattern-loop:" + sourceIndex)
        var sourceIntegrity = integrityByIndex[String(sourceIndex)]
        if (itemError.length > 0 || !sourceIntegrity
                || Number(sourceIntegrity.discontinuityCount) !== 0
                || !finiteValue(sourceIntegrity.closureGap_in)
                || Number(sourceIntegrity.closureGap_in) < 0
                || Number(sourceIntegrity.closureGap_in) > 0.0002)
            return "flat-pattern-loop-integrity-invalid:" + sourceIndex
        if (sourceLoop.outer === true) {
            if (previewOuter !== null)
                return "flat-pattern-material-outer-count-invalid"
            previewOuter = points
        } else {
            previewHoles.push(points)
        }
    }
    if (previewOuter === null)
        return "flat-pattern-material-outer-count-invalid"
    var boundary = graph.materialBoundary
    if (!loopsEquivalent(previewOuter, boundary.outerLoop))
        return "material-boundary-preview-outer-mismatch"
    var unmatchedBoundaryHoles = boundary.holeLoops.slice(0)
    for (var previewHoleIndex = 0; previewHoleIndex < previewHoles.length; previewHoleIndex++) {
        var matchedIndex = -1
        for (var boundaryHoleIndex = 0; boundaryHoleIndex < unmatchedBoundaryHoles.length; boundaryHoleIndex++) {
            if (!loopsEquivalent(previewHoles[previewHoleIndex], unmatchedBoundaryHoles[boundaryHoleIndex]))
                continue
            if (matchedIndex >= 0)
                return "material-boundary-preview-hole-ambiguous:" + previewHoleIndex
            matchedIndex = boundaryHoleIndex
        }
        if (matchedIndex < 0)
            return "material-boundary-preview-hole-mismatch:" + previewHoleIndex
        unmatchedBoundaryHoles.splice(matchedIndex, 1)
    }
    var result = unmatchedBoundaryHoles.length === 0
        ? "" : "material-boundary-unexpected-holes:" + unmatchedBoundaryHoles.length
    if (timing)
        timing.authorityMs = Date.now() - authorityStarted
    return result
}

function point2(point) {
    return { x: Number(point.x_in), y: Number(point.y_in), z: 0 };
}

function edgeSequence(edge, fallback) {
    var value = Number(edge && (edge.sequenceHint !== undefined ? edge.sequenceHint : edge.sequence_hint));
    return isFinite(value) && value > 0 ? value : fallback;
}

function normalize(graph) {
    if (validateGraph(graph).length > 0)
        return null;
    return normalizeValidated(graph);
}

function normalizeValidated(graph) {
    if (!graph || !Array.isArray(graph.panels) || !Array.isArray(graph.bendEdges))
        return null;
    var panelsById = ({});
    var panelOrder = [];
    for (var i = 0; i < graph.panels.length; i++) {
        var panel = graph.panels[i];
        var normalizedPanel = {
            panelId: String(panel.panelId),
            parentPanelId: panel.parentPanelId === null || panel.parentPanelId === undefined ? null : String(panel.parentPanelId),
            ownerBendId: panel.ownerBendId === null || panel.ownerBendId === undefined ? null : String(panel.ownerBendId),
            outerLoop: panel.outerLoop.slice(0),
            holeLoops: (panel.holeLoops || []).slice(0),
            geometryAuthority: String(panel.geometryAuthority || "planar-subdivision"),
            provenance: String(panel.provenance || "")
        };
        panelsById[normalizedPanel.panelId] = normalizedPanel;
        panelOrder.push(normalizedPanel.panelId);
    }
    var edges = [];
    var edgeByChildId = ({});
    for (var edgeIndex = 0; edgeIndex < graph.bendEdges.length; edgeIndex++) {
        var edge = graph.bendEdges[edgeIndex];
        var normalizedEdge = {
            bendId: String(edge.bendId || ("edge-" + edgeIndex)),
            sourceBendId: String(edge.sourceBendId || ""),
            operationRelationIndex: Number(edge.operationRelationIndex === undefined
                                           ? 0 : edge.operationRelationIndex),
            operationRelationCount: Number(edge.operationRelationCount === undefined
                                           ? 1 : edge.operationRelationCount),
            parentPanelId: String(edge.parentPanelId),
            childPanelId: String(edge.childPanelId),
            sequenceHint: edgeSequence(edge, edgeIndex + 1),
            hingeStart: edge.hingeStart,
            hingeEnd: edge.hingeEnd,
                hingeSegments: edge.hingeSegments.map(function(segment) {
                    return [segment[0], segment[1]]
                }),
            bendAngleDegrees: Number(edge.bendAngleDegrees),
            foldAngleDegrees: Number(edge.foldAngleDegrees !== undefined
                                     ? edge.foldAngleDegrees
                                     : (180 - Number(edge.bendAngleDegrees))),
            childSideSign: Number(edge.childSideSign),
            direction: String(edge.direction).toUpperCase(),
                insideRadius_in: Number(edge.insideRadius_in),
                thickness_in: Number(edge.thickness_in),
                kFactor: Number(edge.kFactor),
            provenance: String(edge.provenance || "")
        };
        edges.push(normalizedEdge);
        edgeByChildId[normalizedEdge.childPanelId] = normalizedEdge;
    }
    return {
        schemaVersion: Number(graph.schemaVersion),
        rootPanelId: String(graph.rootPanelId || "ROOT"),
        panelsById: panelsById,
        panelOrder: panelOrder,
        edges: edges,
        edgeByChildId: edgeByChildId,
        diagnostics: graph.diagnostics || ({})
    };
}

function visiblePanelIds(model, currentSequence) {
    var visible = [];
    for (var i = 0; model && i < model.panelOrder.length; i++) {
        var panelId = model.panelOrder[i];
        if (panelId === model.rootPanelId)
            continue;
        var edge = model.edgeByChildId[panelId];
        if (edge && edge.sequenceHint <= currentSequence + 1e-6)
            visible.push(panelId);
    }
    return visible;
}

function physicalPanelIds(model) {
    return model && Array.isArray(model.panelOrder) ? model.panelOrder.slice(0) : []
}
