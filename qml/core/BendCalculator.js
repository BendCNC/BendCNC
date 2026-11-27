.pragma library
.import "MathUtil.js" as MathUtil

// BendCalculator.js
// Pure, qmlscene-compatible. No bindings; instead a single computeBend(inputs)
// that mirrors the Java binding graph evaluation order.
//
// All positions are in INCHES (matching the Java machine valid range and tooling fields).
// Tonnage in (short) tons. Field names follow the JSON shapes in qt/qml/data/current/*.json.
//
// Usage:
//   import "core/BendCalculator.js" as BendCalculator
//   var r = BendCalculator.computeBend({
//       bend:     { materialThickness, bendWidth, desiredBendAngle, angleCompensation,
//                   angleCompensationReversed, punchToMaterialClearance, additionalRetractAfterBend,
//                   overrideFinalBendPositionEnabled, overriddenFinalBendPosition },
//       punch:    { heightInch },
//       die:      { heightInch, vdieOpeningInch },
//       material: { materialTensileStrengthPsi, insideRadiusRuleOfThumb, materialSpringback },
//       settings: { materialClampRatePercentage },   // user-settings.materialClampRate
//       machine:  { ramToTableOpening, validRangeInchMin, validRangeInchMax, jogStepPaddingInch },
//       limits:   { tonnageWarningThreshold, tonnageErrorThreshold, punchToMaterialClearanceWarningThreshold }
//   });
//
// Returns an object with all computed properties + warning/error flags + errorCount.

//      BendCNCDeviceDatabase (device "press machine"). Used when the caller
//      omits machine/limits so the calculator still produces Java-parity values
//      in the disconnected (default) state. ----
var DEFAULTS = {
    machine: {
        // defaultMachineValidTravelRange.inches (limits.json)
        validRangeInchMin: -4.0,
        validRangeInchMax: -0.05,
        // ramToTableOpening: desktopRamToTableOpening default 0.0; EEPROM default is
        // applied at connect time. Disconnected default mirrors Java (0.0 unless set).
        ramToTableOpening: 0.0,
        // jogStepPreset.get(1).toInches() — ValuePreset.createDefault(4): index 1 = 0.01"
        jogStepPaddingInch: 0.01
    },
    limits: {
        tonnageWarningThreshold: 12.5,
        tonnageErrorThreshold: 25.0,
        punchToMaterialClearanceWarningThreshold: 0.3
    },
    settings: {
        materialClampRatePercentage: 5.0
    }
};

function _num(v) { return (typeof v === "number") ? v : NaN; }

// startSafetyClearance = ptmc + punchH + dieH + thickness - ramToTableOpening
function calcStartSafetyClearance(ptmc, punchHeightInch, dieHeightInch, thickness, ramToTableOpening) {
    return ptmc + punchHeightInch + dieHeightInch + thickness - ramToTableOpening;
}

// clampPosition = startSafetyClearance - ptmc - (clampRate%/100)*thickness
function calcClampPosition(startSafetyClearance, ptmc, materialClampRatePercentage, thickness) {
    return startSafetyClearance - ptmc - (materialClampRatePercentage / 100.0) * thickness;
}

// calculatedFinalBendPosition = startSafetyClearance - ptmc - totalBendStroke
function calcFinalBendPosition(startSafetyClearance, ptmc, totalBendStroke) {
    return startSafetyClearance - ptmc - totalBendStroke;
}

// retractAfterBend = min(startSafetyClearance + additionalRetract, validRange.max)
function calcRetractAfterBend(startSafetyClearance, additionalRetractAfterBend, validRangeInchMax) {
    var r = startSafetyClearance + additionalRetractAfterBend;
    return Math.min(r, validRangeInchMax);
}

// totalBendStroke — exact Java air-bending stroke model
function calcTotalBendStroke(desiredBendAngle, materialSpringback, angleCompensation,
                             angleCompensationReversed, vDieOpeningInch,
                             materialTensileStrengthPsi, insideRadiusRuleOfThumb, thickness) {
    var dir = angleCompensationReversed ? -1.0 : 1.0;
    var totalBendAngleRad = MathUtil.toRadians(desiredBendAngle - materialSpringback + angleCompensation * dir);
    var inverseBendAngleRad = Math.PI - totalBendAngleRad;
    var var1 = vDieOpeningInch * materialTensileStrengthPsi / 60000.0 * insideRadiusRuleOfThumb + thickness;
    var var2 = 2.0 * Math.tan(totalBendAngleRad / 2.0);
    var term1 = vDieOpeningInch / var2;
    var term2 = var1 * Math.sqrt(2.0 * (1.0 - Math.cos(inverseBendAngleRad))) / var2;
    var term3 = var1 * (1.0 - Math.cos(inverseBendAngleRad / 2.0));
    return term1 - (term2 - term3);
}

// overriddenTotalBendStroke = totalBendStroke + (override&calc finite ? calc-override : 0)
function calcOverriddenTotalBendStroke(totalBendStroke, overriddenFinalBendPosition, calculatedFinalBendPosition) {
    var correction = (!MathUtil.isNaNLike(overriddenFinalBendPosition) && !MathUtil.isNaNLike(calculatedFinalBendPosition))
        ? (calculatedFinalBendPosition - overriddenFinalBendPosition) : 0.0;
    return totalBendStroke + correction;
}

// bendTonnage = (thickness*25.4)^2 * tensile * 1.099644e-6 * bendWidth / vDie
function calcBendTonnage(thickness, materialTensileStrengthPsi, bendWidth, vDieOpeningInch) {
    var coefficient = 1.099644e-6;
    return Math.pow(thickness * 25.4, 2.0) * materialTensileStrengthPsi * coefficient * bendWidth / vDieOpeningInch;
}

// predictedInsideBendRadius = vDie * (tensile/60000) * insideRadiusRuleOfThumb
function calcPredictedInsideBendRadius(vDieOpeningInch, materialTensileStrengthPsi, insideRadiusRuleOfThumb) {
    return vDieOpeningInch * (materialTensileStrengthPsi / 60000.0) * insideRadiusRuleOfThumb;
}

// finalBendPositionLimits — determineFinalBendPosLimit()
//   padding = jogStepPreset[1].toInches()
//   min = min(travelLimit.min, clamp - padding)
//   max = max(travelLimit.min, clamp - padding)
function calcFinalBendPositionLimits(clampPosition, travelLimitInchMin, jogStepPaddingInch) {
    var p = clampPosition - jogStepPaddingInch;
    return {
        min: Math.min(travelLimitInchMin, p),
        max: Math.max(travelLimitInchMin, p)
    };
}

// Main entry — mirrors the Java binding-graph evaluation order exactly.
function computeBend(inputs) {
    var bend = inputs.bend || {};
    var punch = inputs.punch || {};
    var die = inputs.die || {};
    var material = inputs.material || {};
    var settings = Object.assign({}, DEFAULTS.settings, inputs.settings || {});
    var machine = Object.assign({}, DEFAULTS.machine, inputs.machine || {});
    var limits = Object.assign({}, DEFAULTS.limits, inputs.limits || {});

    // Raw inputs (NaN when missing, matching Java orElse(Double.NaN))
    var thickness = _num(bend.materialThickness);
    var bendWidth = _num(bend.bendWidth);
    var desiredBendAngle = _num(bend.desiredBendAngle);
    var angleCompensation = _num(bend.angleCompensation);
    var angleCompensationReversed = !!bend.angleCompensationReversed;
    var ptmc = _num(bend.punchToMaterialClearance);
    var additionalRetract = _num(bend.additionalRetractAfterBend);
    var overrideEnabled = !!bend.overrideFinalBendPositionEnabled;
    var overriddenFinalBendPosition = _num(bend.overriddenFinalBendPosition);

    var punchHeightInch = _num(punch.heightInch);
    var dieHeightInch = _num(die.heightInch);
    var vDieOpeningInch = _num(die.vdieOpeningInch);

    var tensile = _num(material.materialTensileStrengthPsi);
    var insideRadiusRuleOfThumb = _num(material.insideRadiusRuleOfThumb);
    // JSON field is "materialSpringback" (lowercase b); Java property was materialSpringBack.
    var materialSpringback = _num(material.materialSpringback);

    var ramToTableOpening = _num(machine.ramToTableOpening);
    var validMin = _num(machine.validRangeInchMin);
    var validMax = _num(machine.validRangeInchMax);

    // ---- Compute in Java order ----
    var totalBendStroke = calcTotalBendStroke(
        desiredBendAngle, materialSpringback, angleCompensation, angleCompensationReversed,
        vDieOpeningInch, tensile, insideRadiusRuleOfThumb, thickness);

    var startSafetyClearance = calcStartSafetyClearance(
        ptmc, punchHeightInch, dieHeightInch, thickness, ramToTableOpening);

    var clampPosition = calcClampPosition(
        startSafetyClearance, ptmc, settings.materialClampRatePercentage, thickness);

    var calculatedFinalBendPosition = calcFinalBendPosition(
        startSafetyClearance, ptmc, totalBendStroke);

    var inUseFinalBendPosition = overrideEnabled ? overriddenFinalBendPosition : calculatedFinalBendPosition;

    var retractAfterBend = calcRetractAfterBend(startSafetyClearance, additionalRetract, validMax);

    var bendTonnage = calcBendTonnage(thickness, tensile, bendWidth, vDieOpeningInch);

    var overriddenTotalBendStroke = calcOverriddenTotalBendStroke(
        totalBendStroke, overriddenFinalBendPosition, calculatedFinalBendPosition);

    var predictedInsideBendRadius = calcPredictedInsideBendRadius(
        vDieOpeningInch, tensile, insideRadiusRuleOfThumb);

    var finalBendPositionLimits = calcFinalBendPositionLimits(
        clampPosition, validMin, machine.jogStepPaddingInch);

    // ---- Warning/error flags (Java order) ----
    var punchToMaterialClearanceWarning = ptmc > limits.punchToMaterialClearanceWarningThreshold;
    var tonnageError = bendTonnage > limits.tonnageErrorThreshold;
    var tonnageWarning = (bendTonnage > limits.tonnageWarningThreshold) && !tonnageError;

    var upperLimitExceededError =
        (inUseFinalBendPosition > validMax) ||
        (startSafetyClearance > validMax) ||
        (clampPosition > validMax);
    var lowerLimitExceededError =
        (inUseFinalBendPosition < validMin) ||
        (startSafetyClearance < validMin) ||
        (clampPosition < validMin);

    var finalBendPositionOutLimit =
        (inUseFinalBendPosition > finalBendPositionLimits.max) ||
        (inUseFinalBendPosition < finalBendPositionLimits.min);

    var errorCount =
        (tonnageError ? 1 : 0) +
        (upperLimitExceededError ? 1 : 0) +
        (lowerLimitExceededError ? 1 : 0);

    return {
        // positions / values
        startSafetyClearance: startSafetyClearance,
        clampPosition: clampPosition,
        totalBendStroke: totalBendStroke,
        overriddenTotalBendStroke: overriddenTotalBendStroke,
        calculatedFinalBendPosition: calculatedFinalBendPosition,
        inUseFinalBendPosition: inUseFinalBendPosition,
        retractAfterBend: retractAfterBend,
        bendTonnage: bendTonnage,
        predictedInsideBendRadius: predictedInsideBendRadius,
        finalBendPositionLimits: finalBendPositionLimits,
        finalBendPositionMin: finalBendPositionLimits.min,
        finalBendPositionMax: finalBendPositionLimits.max,
        overrideFinalBendPositionEnabled: overrideEnabled,
        overriddenFinalBendPosition: overriddenFinalBendPosition,
        // flags
        punchToMaterialClearanceWarning: punchToMaterialClearanceWarning,
        tonnageWarning: tonnageWarning,
        tonnageError: tonnageError,
        upperLimitExceededError: upperLimitExceededError,
        lowerLimitExceededError: lowerLimitExceededError,
        finalBendPositionOutLimit: finalBendPositionOutLimit,
        errorCount: errorCount
    };
}
