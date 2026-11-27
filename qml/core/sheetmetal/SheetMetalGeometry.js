.pragma library

// SheetMetalGeometry.js
// Implements the deterministic 2D geometry primitives in
//   SheetMetalVector2, SheetMetalPoint2, SheetMetalTransform2D,
//   SheetMetalFrame2, UvReference, BendDirection.
//
// Java records are ported as factory functions returning plain objects with the
// same field names {x,y} / {m00..m12} / {origin,u,v}. Math is identical
// (Math.hypot, Math.atan2, same matrix multiply order). Validation throws the same
// way Java did (finite/non-zero/non-parallel) so callers see equivalent failures.

function _finite(v) { return typeof v === "number" && isFinite(v); }

// ---- SheetMetalVector2 ----
function vec2(x, y) {
    if (!_finite(x) || !_finite(y))
        throw new Error("vector coordinates must be finite");
    return { x: x, y: y };
}
function vecLength(a) { return Math.hypot(a.x, a.y); }
function vecNormalize(a) {
    var len = vecLength(a);
    if (len === 0.0) throw new Error("zero-length vector cannot be normalized");
    return vec2(a.x / len, a.y / len);
}
function vecScale(a, factor) {
    if (!_finite(factor)) throw new Error("factor must be finite");
    return vec2(a.x * factor, a.y * factor);
}
function vecDot(a, b) { return a.x * b.x + a.y * b.y; }
function vecCross(a, b) { return a.x * b.y - a.y * b.x; }

// ---- SheetMetalPoint2 ----
function point2(x, y) {
    if (!_finite(x) || !_finite(y))
        throw new Error("point coordinates must be finite");
    return { x: x, y: y };
}
function pointPlus(p, v) { return point2(p.x + v.x, p.y + v.y); }
function pointMinus(p, other) { return vec2(p.x - other.x, p.y - other.y); }
function pointDistanceTo(p, other) { return Math.hypot(p.x - other.x, p.y - other.y); }

// ---- SheetMetalTransform2D ----
function transform2(m00, m01, m02, m10, m11, m12) {
    if (!_finite(m00) || !_finite(m01) || !_finite(m02)
            || !_finite(m10) || !_finite(m11) || !_finite(m12))
        throw new Error("transform values must be finite");
    return { m00: m00, m01: m01, m02: m02, m10: m10, m11: m11, m12: m12 };
}
function transformIdentity() { return transform2(1, 0, 0, 0, 1, 0); }
function transformTranslation(x, y) { return transform2(1, 0, x, 0, 1, y); }
function transformRotation(radians) {
    if (!_finite(radians)) throw new Error("radians must be finite");
    var c = Math.cos(radians), s = Math.sin(radians);
    return transform2(c, -s, 0, s, c, 0);
}
function transformMultiply(t, o) {
    return transform2(
        t.m00 * o.m00 + t.m01 * o.m10,
        t.m00 * o.m01 + t.m01 * o.m11,
        t.m00 * o.m02 + t.m01 * o.m12 + t.m02,
        t.m10 * o.m00 + t.m11 * o.m10,
        t.m10 * o.m01 + t.m11 * o.m11,
        t.m10 * o.m02 + t.m11 * o.m12 + t.m12);
}
function transformApply(t, p) {
    return point2(t.m00 * p.x + t.m01 * p.y + t.m02,
                  t.m10 * p.x + t.m11 * p.y + t.m12);
}
// alignSegment: maps source segment onto target segment (translate→rotate→translate)
function transformAlignSegment(sourceStart, sourceEnd, targetStart, targetEnd) {
    var source = pointMinus(sourceEnd, sourceStart);
    var target = pointMinus(targetEnd, targetStart);
    var sLen = vecLength(source), tLen = vecLength(target);
    if (sLen === 0.0 || tLen === 0.0)
        throw new Error("segments must have non-zero length");
    var sAngle = Math.atan2(source.y, source.x);
    var tAngle = Math.atan2(target.y, target.x);
    return transformMultiply(
        transformMultiply(transformTranslation(targetStart.x, targetStart.y),
                          transformRotation(tAngle - sAngle)),
        transformTranslation(-sourceStart.x, -sourceStart.y));
}

// ---- SheetMetalFrame2 ----
function frame2(origin, u, v) {
    if (!origin || !u || !v) throw new Error("frame values are required");
    var un = vecNormalize(u), vn = vecNormalize(v);
    if (Math.abs(vecCross(un, vn)) < 1.0e-9)
        throw new Error("frame axes must not be parallel");
    return { origin: origin, u: un, v: vn };
}
function frameToWorld(f, local) {
    return pointPlus(pointPlus(f.origin, vecScale(f.u, local.x)), vecScale(f.v, local.y));
}

// ---- UvReference ----
var UvReference = {
    U_MIN_V_MIN: "U_MIN_V_MIN",
    U_MIN_V_MAX: "U_MIN_V_MAX",
    U_MAX_V_MIN: "U_MAX_V_MIN",
    U_MAX_V_MAX: "U_MAX_V_MAX",
    UNKNOWN: "UNKNOWN"
};

// ---- BendDirection ----
var BendDirection = { UP: "UP", DOWN: "DOWN", UNKNOWN: "UNKNOWN" };
function bendDirectionSign(dir) {
    return dir === "UP" ? 1 : (dir === "DOWN" ? -1 : 0);
}
function bendDirectionFromText(value) {
    if (value === null || value === undefined || String(value).trim() === "")
        return BendDirection.UNKNOWN;
    switch (String(value).trim().toUpperCase()) {
    case "UP": case "POS": case "POSITIVE": return BendDirection.UP;
    case "DOWN": case "NEG": case "NEGATIVE": return BendDirection.DOWN;
    default: return BendDirection.UNKNOWN;
    }
}
