.pragma library
// MathUtil.js — pure math helpers ported from the Java app.
// qmlscene-compatible (no C++ types). Import with:
//   import "core/MathUtil.js" as MathUtil

function toRadians(deg) { return deg * Math.PI / 180.0; }
function toDegrees(rad) { return rad * 180.0 / Math.PI; }

function isFiniteNum(v) { return (typeof v === "number") && isFinite(v); }

// Java Double.isNaN parity (treats undefined/null as NaN too)
function isNaNLike(v) { return !(typeof v === "number" && !isNaN(v)); }

function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }

// mm <-> inch
function mmToInch(mm) { return mm / 25.4; }
function inchToMm(inch) { return inch * 25.4; }

// Round to N decimals (display parity helper)
function roundTo(v, decimals) {
    if (!isFiniteNum(v)) return v;
    var f = Math.pow(10, decimals);
    return Math.round(v * f) / f;
}
