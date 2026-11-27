.pragma library

// BendAllowanceCalculator.js
// Flat-pattern bend allowance / setback / deduction math. All inputs in consistent
// linear units (inches in this app), angles in degrees. Validation throws like Java.

var FULL_CIRCLE_DEGREES = 360.0;
var STRAIGHT_ANGLE_DEGREES = 180.0;

function _finite(v) { return typeof v === "number" && isFinite(v); }
function _toRadians(deg) { return deg * Math.PI / 180.0; }

// Factory: validates kFactor in [0,1].
function create(kFactor) {
    if (!_finite(kFactor) || kFactor < 0.0 || kFactor > 1.0)
        throw new Error("kFactor must be finite and between 0 and 1");

    function allowance(insideRadius, thickness, bendAngleDegrees) {
        if (!_finite(insideRadius) || insideRadius < 0.0)
            throw new Error("insideRadius must be finite and non-negative");
        if (!_finite(thickness) || thickness <= 0.0)
            throw new Error("thickness must be finite and positive");
        if (!_finite(bendAngleDegrees))
            throw new Error("bendAngleDegrees must be finite");
        var rad = _toRadians(Math.abs(bendAngleDegrees));
        return (insideRadius + kFactor * thickness) * rad;
    }

    function complementaryAngleDegrees(bendAngleDegrees) {
        if (!_finite(bendAngleDegrees))
            throw new Error("bendAngleDegrees must be finite");
        return Math.abs(STRAIGHT_ANGLE_DEGREES - Math.abs(bendAngleDegrees));
    }

    function outsideSetback(insideRadius, thickness, bendAngleDegrees) {
        if (!_finite(insideRadius) || insideRadius < 0.0)
            throw new Error("insideRadius must be finite and non-negative");
        if (!_finite(thickness) || thickness <= 0.0)
            throw new Error("thickness must be finite and positive");
        var abs = Math.abs(bendAngleDegrees);
        if (!_finite(abs))
            throw new Error("bendAngleDegrees must be finite");
        if (abs === 0.0) return 0.0;
        if (abs >= FULL_CIRCLE_DEGREES)
            throw new Error("bendAngleDegrees must be less than 360 degrees");
        return Math.tan(_toRadians(abs / 2.0)) * (insideRadius + thickness);
    }

    function bendDeduction(insideRadius, thickness, bendAngleDegrees) {
        var abs = Math.abs(bendAngleDegrees);
        if (abs === 0.0) return 0.0;
        if (abs >= FULL_CIRCLE_DEGREES)
            throw new Error("bendAngleDegrees must be less than 360 degrees");
        var setback = outsideSetback(insideRadius, thickness, abs);
        return 2.0 * setback - allowance(insideRadius, thickness, abs);
    }

    return {
        kFactor: function () { return kFactor; },
        allowance: allowance,
        complementaryAngleDegrees: complementaryAngleDegrees,
        outsideSetback: outsideSetback,
        bendDeduction: bendDeduction
    };
}

function ofKFactor(kFactor) { return create(kFactor); }
