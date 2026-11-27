.pragma library

// ToolingPlanningEngine.js
// Faithful port of the PER-BEND tooling evaluation core of
//
// Scope of this module:
//   - evaluateDie / evaluatePunch penalty + warning model (exact Java weights)
//   - die-span coverage, predicted-inside-radius, profile/angle support helpers
//   - selectToolingForBend(): picks the lowest-cost (punch, die) for a single bend,
//     ordered with the same cost terms the Java beam search uses per step
//     (toolingPenalty + rule-of-8 opening penalty + predicted-radius penalty).
//   - dependency-safe CAD bend ordering that keeps identical assigned setups
//     contiguous and starts a shared setup with the shortest compatible bends
//   - assigned multi-bend segment phases whose installed layout covers every
//     bend in the phase, rather than independently minimizing each bend
//
// NOT yet ported here (tracked separately): Java's complete global beam search,
// formed-part collision windows, and Titan length charts. The assigned-plan
// phase/layout path below deliberately solves the already-selected tool pair.
//
// All dimensions in inches. Penalties are integers matching the Java weights so the
// ordering is identical for the subset implemented.

// ---- Java constants ----
var PREFERRED_PUNCH_BONUS = 1800;
var PREFERRED_DIE_BONUS = 1800;
var MAX_SEGMENTED_TOOLING_SPAN_IN = 44.0;

// not a gauge label, so preference resolution must use the nearest profile just
// like Material.resolveThicknessProfileLabel(double).
var CANONICAL_THICKNESS_PROFILES = [
    { label: "1/2 in", thicknessIn: 0.5000 },
    { label: "3/8 in", thicknessIn: 0.3750 },
    { label: "5/16 in", thicknessIn: 0.3125 },
    { label: "1/4 in", thicknessIn: 0.2500 },
    { label: "3/16 in", thicknessIn: 0.1875 },
    { label: "5/32 in", thicknessIn: 0.1563 },
    { label: "1/8 in", thicknessIn: 0.1250 },
    { label: "3/32 in", thicknessIn: 0.0938 },
    { label: "1/16 in", thicknessIn: 0.0625 },
    { label: "7 ga", thicknessIn: 0.1793 },
    { label: "8 ga", thicknessIn: 0.1644 },
    { label: "10 ga", thicknessIn: 0.1345 },
    { label: "11 ga", thicknessIn: 0.1196 },
    { label: "12 ga", thicknessIn: 0.1046 },
    { label: "13 ga", thicknessIn: 0.0897 },
    { label: "14 ga", thicknessIn: 0.0747 },
    { label: "16 ga", thicknessIn: 0.0598 },
    { label: "18 ga", thicknessIn: 0.0478 },
    { label: "20 ga", thicknessIn: 0.0359 },
    { label: "22 ga", thicknessIn: 0.0299 },
    { label: "24 ga", thicknessIn: 0.0239 }
];

// PunchProfileType: [providesClearance, defaultAngleDeg]
var PROFILE = {
    STANDARD:          { clearance: false, defaultAngle: 30.0 },
    ACUTE:             { clearance: true,  defaultAngle: 30.0 },
    GOOSENECK:         { clearance: true,  defaultAngle: 88.0 },
    EXTREME_GOOSENECK: { clearance: true,  defaultAngle: 85.0 }
};

function normalize(s) { return String(s || "").toLowerCase().trim(); }

function num(v) { return (typeof v === "number") ? v : Number(v); }
function isFiniteNum(v) { var n = num(v); return typeof n === "number" && isFinite(n); }

function resolvePunchProfile(punch) {
    var t = punch && punch.punchProfileType ? String(punch.punchProfileType) : "STANDARD";
    return PROFILE[t] || PROFILE.STANDARD;
}

function resolveMinimumSupportedPunchAngle(punch) {
    if (!punch) return NaN;
    var a = num(punch.punchAngleDegree);
    if (isFinite(a)) return a;
    return resolvePunchProfile(punch).defaultAngle;
}

// ToolDieFamily: 4-way vs acute (by name)
function classifyDieFamily(die) {
    return normalize(die && die.name).indexOf("4 way") >= 0 ? "FOUR_WAY" : "ACUTE";
}

// resolveAvailableDieSpanIn — sum of configured segment lengths, else NaN.
function resolveAvailableDieSpan(die) {
    if (!die) return NaN;
    var total = 0.0, configured = false;
    var parts = [
        [die.segmentCount16In, 16.0],
        [die.segmentCount8In, 8.0],
        [die.segmentCount4In, 4.0],
        [die.segmentCount2In, 2.0],
        [die.segmentCount1In, 1.0]
    ];
    for (var i = 0; i < parts.length; i++) {
        var c = num(parts[i][0]);
        if (isFinite(c) && c >= 0.0) { configured = true; total += Math.round(c) * parts[i][1]; }
    }
    return configured ? total : NaN;
}

// predicted inside radius (inches) — same formula as BendCalculator
function resolvePredictedInsideRadius(material, die) {
    var tensileScale = num(material.materialTensileStrengthPsi) / 60000.0;
    return num(die.vdieOpeningInch) * tensileScale * num(material.insideRadiusRuleOfThumb);
}

// Carbon-steel detection (parity with isCarbonSteel by material name)
function isCarbonSteel(name) {
    var n = normalize(name);
    return n.indexOf("steel") >= 0 || n.indexOf("a36") >= 0 || n.indexOf("a1008") >= 0
        || n.indexOf("a366") >= 0 || n.indexOf("crs") >= 0 || n.indexOf("hrs") >= 0;
}

// evaluateDie — penalty + warnings (Titan capability/length-chart omitted: no resource here).
// Without the Titan capability resource the Java code adds a flat +12000 ("no capability"),
// so we mirror that to keep ordering offsets consistent across all dies (constant => neutral).
function evaluateDie(material, bend, die, ruleOf8OpeningIn) {
    var warnings = [];
    var penalty = 0;
    var family = classifyDieFamily(die);
    var bendAngle = num(bend.angleDeg);
    var availableDieSpan = resolveAvailableDieSpan(die);

    // Titan capability unavailable in JS port → Java's else-branch (+12000, constant for all dies)
    penalty += 12000;

    if (isFinite(availableDieSpan) && (num(bend.lengthIn) - availableDieSpan) > 1e-6) {
        penalty += 90000;
        warnings.push("Available die segments do not cover bend length");
    }

    var openingPenalty = Math.abs(num(die.vdieOpeningInch) - ruleOf8OpeningIn);
    penalty += Math.round(openingPenalty * 1500.0);

    if (family === "ACUTE" && bendAngle < 90.0) penalty -= 250;

    if (material && material.preferredDieId && material.preferredDieId === die.id)
        penalty -= PREFERRED_DIE_BONUS;

    return { penalty: penalty, warnings: warnings };
}

// evaluatePunch — anglePenalty + clearancePenalty + preferencePenalty + warnings
function evaluatePunch(material, bend, punch) {
    var warnings = [];
    var anglePenalty = 0, clearancePenalty = 0, preferencePenalty = 0;
    var bendAngle = num(bend.angleDeg);
    var profile = resolvePunchProfile(punch);
    var minAngle = resolveMinimumSupportedPunchAngle(punch);

    if (isFinite(minAngle) && (bendAngle + 1e-6) < minAngle) {
        anglePenalty += 100000;
        warnings.push("Acute angle unsupported by selected die/punch");
    }

    var clearanceRequired = num(bend.chainDepth) > 0
        || String(bend.referenceType || "").toUpperCase() === "PREVIOUS_BEND"
        || (bend.parentBendId !== undefined && bend.parentBendId !== null && bend.parentBendId !== "")
        || num(bend.processBgPositionIn) >= 5.0;
    if (clearanceRequired && !profile.clearance) clearancePenalty += 15000;

    if (material && material.preferredPunchId && material.preferredPunchId === punch.id)
        preferencePenalty -= PREFERRED_PUNCH_BONUS;

    return {
        anglePenalty: anglePenalty,
        clearancePenalty: clearancePenalty,
        preferencePenalty: preferencePenalty,
        penalty: anglePenalty + clearancePenalty + preferencePenalty,
        warnings: warnings
    };
}

// Resolve the material's per-thickness preferred punch/die ids for this bend.
// Mirrors MaterialContext.preferredPunchId/preferredDieId derived from
// thicknessToolingPreferences keyed by a thickness label. We match by the
// closest gauge label when a label is provided; otherwise fall back to the
// first preference (Java resolves a single context per material+thickness).
function resolveThicknessProfileLabel(thicknessIn) {
    var value = num(thicknessIn);
    if (!isFinite(value))
        return CANONICAL_THICKNESS_PROFILES.length > 0
            ? CANONICAL_THICKNESS_PROFILES[0].label : "";
    var best = null;
    for (var index = 0; index < CANONICAL_THICKNESS_PROFILES.length; index++) {
        var profile = CANONICAL_THICKNESS_PROFILES[index];
        var distance = Math.abs(profile.thicknessIn - value);
        if (!best || distance < best.distance) {
            best = { label: profile.label, distance: distance };
        }
    }
    return best ? best.label : "";
}

// A thickness only belongs to a profile within sheet tolerance: max(5 %, 0.004 in).
var THICKNESS_PROFILE_TOLERANCE_RATIO = 0.05;
var THICKNESS_PROFILE_TOLERANCE_IN = 0.004;

function thicknessProfileWithinTolerance(label, thicknessIn) {
    var value = num(thicknessIn);
    if (!isFinite(value) || value <= 0)
        return true;
    for (var i = 0; i < CANONICAL_THICKNESS_PROFILES.length; i++) {
        var profile = CANONICAL_THICKNESS_PROFILES[i];
        if (normalize(profile.label) === normalize(label))
            return Math.abs(profile.thicknessIn - value)
                <= Math.max(profile.thicknessIn * THICKNESS_PROFILE_TOLERANCE_RATIO, THICKNESS_PROFILE_TOLERANCE_IN);
    }
    return false;
}

function resolveMaterialPreferences(material, thicknessLabel, thicknessIn) {
    var prefs = (material && material.thicknessToolingPreferences) || [];
    var chosen = null;
    var resolvedLabel = thicknessLabel || resolveThicknessProfileLabel(thicknessIn);
    var outOfTolerance = !thicknessLabel && resolvedLabel !== ""
        && !thicknessProfileWithinTolerance(resolvedLabel, thicknessIn);
    if (outOfTolerance)
        resolvedLabel = "";
    if (resolvedLabel) {
        var want = normalize(resolvedLabel);
        for (var i = 0; i < prefs.length; i++) {
            if (normalize(prefs[i].thicknessLabel) === want) { chosen = prefs[i]; break; }
        }
    }
    // User-defined profiles carry an explicit thicknessIn: match the closest one within tolerance.
    var value = num(thicknessIn);
    if (!chosen && !thicknessLabel && isFinite(value) && value > 0) {
        var bestDist = Infinity;
        for (var j = 0; j < prefs.length; j++) {
            var t = num(prefs[j].thicknessIn);
            if (!isFinite(t) || t <= 0) continue;
            var d = Math.abs(t - value);
            if (d <= Math.max(t * THICKNESS_PROFILE_TOLERANCE_RATIO, THICKNESS_PROFILE_TOLERANCE_IN) && d < bestDist) {
                bestDist = d; chosen = prefs[j];
            }
        }
        if (chosen) { resolvedLabel = chosen.thicknessLabel; outOfTolerance = false; }
    }
    return {
        thicknessLabel: resolvedLabel,
        thicknessOutOfTolerance: outOfTolerance,
        preferredPunchId: chosen ? chosen.preferredPunchId : null,
        preferredDieId: chosen ? chosen.preferredDieId : null,
        punchToMaterialClearanceInch: chosen ? chosen.punchToMaterialClearanceInch : null,
        punchToMaterialClearancePercent: chosen ? chosen.punchToMaterialClearancePercent : null
    };
}

function findToolById(items, id) {
    var wanted = String(id || "");
    for (var index = 0; items && index < items.length; index++) {
        if (String(items[index] && items[index].id || "") === wanted)
            return items[index];
    }
    return null;
}

// Combined per-bend selection cost (Java per-step terms, no cross-bend change penalty):
//   toolingPenalty = dieEval.penalty + punchEval.penalty
//   + round(|vdie - ruleOf8|*1000) + round(predictedRadius*1000)
function bendSelectionCost(material, die, dieEval, punchEval, ruleOf8OpeningIn) {
    var cost = dieEval.penalty + punchEval.penalty;
    cost += Math.round(Math.abs(num(die.vdieOpeningInch) - ruleOf8OpeningIn) * 1000.0);
    cost += Math.round(resolvePredictedInsideRadius(material, die) * 1000.0);
    return cost;
}

// selectToolingForBend — choose lowest-cost (punch, die) for one bend.
//   material : material entity (with thicknessToolingPreferences, tensile, insideRadius)
//   bend     : { angleDeg, lengthIn, chainDepth, processBgPositionIn, parentBendId, referenceType, thicknessLabel }
//   punches, dies : arrays of entities
// Returns { punch, die, warnings, cost } or null when no tooling available.
function selectToolingForBend(material, bend, punches, dies) {
    if (!punches || punches.length === 0 || !dies || dies.length === 0) return null;
    var thicknessIn = num(bend.thicknessIn);
    if (!isFinite(thicknessIn)) thicknessIn = num(material && material.__thicknessIn);
    var ruleOf8 = (isFinite(thicknessIn) && thicknessIn > 0) ? thicknessIn * 8.0 : 0.315;

    // Inject resolved per-thickness preferences into the material context for evaluators.
    var prefs = resolveMaterialPreferences(material, bend.thicknessLabel, thicknessIn);
    var ctx = {
        materialTensileStrengthPsi: num(material.materialTensileStrengthPsi),
        insideRadiusRuleOfThumb: num(material.insideRadiusRuleOfThumb),
        name: material.name,
        preferredPunchId: prefs.preferredPunchId,
        preferredDieId: prefs.preferredDieId
    };

    var preferredPunch = findToolById(punches, prefs.preferredPunchId);
    var preferredDie = findToolById(dies, prefs.preferredDieId);
    // CadImportViewModel.applyPreferredMaterialTooling() gives a valid exact
    // thickness-profile pair first refusal. Preserve that precedence here;
    // when only one side is configured, constrain that side and rank the other.
    var punchCandidates = preferredPunch ? [preferredPunch] : punches;
    var dieCandidates = preferredDie ? [preferredDie] : dies;
    var best = null;
    for (var pi = 0; pi < punchCandidates.length; pi++) {
        var punch = punchCandidates[pi];
        var punchEval = evaluatePunch(ctx, bend, punch);
        for (var di = 0; di < dieCandidates.length; di++) {
            var die = dieCandidates[di];
            var dieEval = evaluateDie(ctx, bend, die, ruleOf8);
            var cost = bendSelectionCost(ctx, die, dieEval, punchEval, ruleOf8);
            if (best === null || cost < best.cost) {
                best = {
                    punch: punch,
                    die: die,
                    cost: cost,
                    thicknessLabel: prefs.thicknessLabel,
                    punchToMaterialClearanceInch: prefs.punchToMaterialClearanceInch,
                    punchToMaterialClearancePercent: prefs.punchToMaterialClearancePercent,
                    warnings: dieEval.warnings.concat(punchEval.warnings)
                };
            }
        }
    }
    return best;
}

function setupIdentity(bend) {
    return String(bend && bend.punchId || "") + "|"
        + String(bend && bend.dieId || "");
}

function bendWidth(bend) {
    return num(bend && (bend.widthValue !== undefined
        ? bend.widthValue : bend.lengthIn));
}

function bendSide(bend) {
    return String(bend && (bend.closestSide !== undefined
        ? bend.closestSide : bend.closest_side) || "").toUpperCase();
}

// Wide parts are easier to handle when equal/near-equal long operations are
// completed before shorter sides. Keep the narrow-part shortest-first strategy
// used by Battery Plate; 29 in is the standard clear frame width and CAD WARN.
function prefersLongestFirst(bends) {
    var maximumWidth = 0;
    for (var widthIndex = 0; bends && widthIndex < bends.length; widthIndex++)
        maximumWidth = Math.max(maximumWidth, bendWidth(bends[widthIndex]));
    return maximumWidth > 29.0 + 1e-6;
}

function dependencySatisfied(bend, completedIds) {
    var referenceType = String(bend && (bend.refType !== undefined
        ? bend.refType : bend.referenceType) || "").toUpperCase();
    var parentId = bend && bend.parentBendId !== undefined
        ? String(bend.parentBendId) : "";
    if (referenceType !== "PREVIOUS_BEND" || parentId.length === 0 || parentId === "0")
        return true;
    return completedIds[parentId] === true;
}

// Greedy topological ordering for already-selected tooling. It finishes the
// current setup before switching, chooses the largest remaining setup group
// first, and orders compatible bends shortest-first. The latter lets an operator
// begin with the easier narrow bends while the phase layout is sized once for
// the widest bend that follows.
// ---- Formed-section punch collision (sequencing guard) ----
// Each bend carries `section` (attachSectionModel): distance from its hinge
// midpoint to the blank edge on each side of the line and the parallel bend
// lines crossed on the way. While bending, the part is posed with the current
// bend folding up symmetrically under the punch; already-completed crossed
// bends fold the profile further (same direction = same curl). Any profile
// point inside a conservative punch envelope means the order collides.

function pointInBoundaryLoop(loop, x, y) {
    var inside = false;
    for (var i = 0, j = loop.length - 1; i < loop.length; j = i++) {
        var xi = num(loop[i].x_in), yi = num(loop[i].y_in);
        var xj = num(loop[j].x_in), yj = num(loop[j].y_in);
        if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi)
            inside = !inside;
    }
    return inside;
}

function pointInBoundary(boundary, x, y) {
    if (!pointInBoundaryLoop(boundary.outerLoop, x, y))
        return false;
    var holes = boundary.holeLoops || [];
    for (var h = 0; h < holes.length; h++)
        if (holes[h] && holes[h].length > 2 && pointInBoundaryLoop(holes[h], x, y))
            return false;
    return true;
}

// Material test along one straight line in O(log n) per sample: every loop's
// edge crossings with the line are found once and sorted, so inside-ness at
// parameter t is the parity of crossings before t (same even-odd rule as
// pointInBoundary, evaluated in the line's own frame).
function loopLineCrossings(loop, ox, oy, dx, dy) {
    var out = [];
    var n = loop ? loop.length : 0;
    if (n < 3)
        return out;
    var nx = -dy, ny = dx;
    var pj = loop[n - 1];
    var xj = num(pj.x_in) - ox, yj = num(pj.y_in) - oy;
    var sj = xj * nx + yj * ny, tj = xj * dx + yj * dy;
    for (var i = 0; i < n; i++) {
        var xi = num(loop[i].x_in) - ox, yi = num(loop[i].y_in) - oy;
        var si = xi * nx + yi * ny, ti = xi * dx + yi * dy;
        if ((si > 0) !== (sj > 0))
            out.push(ti + (tj - ti) * (0 - si) / (sj - si));
        sj = si; tj = ti;
    }
    out.sort(function(a, b) { return a - b; });
    return out;
}

function countBelow(sorted, t) {
    var lo = 0, hi = sorted.length;
    while (lo < hi) {
        var mid = (lo + hi) >> 1;
        if (sorted[mid] < t) lo = mid + 1; else hi = mid;
    }
    return lo;
}

function lineMaterialProbe(boundary, ox, oy, dx, dy) {
    var outer = loopLineCrossings(boundary.outerLoop, ox, oy, dx, dy);
    var holes = [];
    var src = boundary.holeLoops || [];
    for (var h = 0; h < src.length; h++)
        if (src[h] && src[h].length > 2)
            holes.push(loopLineCrossings(src[h], ox, oy, dx, dy));
    return function(t) {
        if ((countBelow(outer, t) & 1) === 0)
            return false;
        for (var k = 0; k < holes.length; k++)
            if ((countBelow(holes[k], t) & 1) === 1)
                return false;
        return true;
    };
}

function bendLineOf(bend) {
    var x0 = num(bend.startXIn), y0 = num(bend.startYIn);
    var x1 = num(bend.endXIn), y1 = num(bend.endYIn);
    if (!isFinite(x0) || !isFinite(y0) || !isFinite(x1) || !isFinite(y1))
        return null;
    var len = Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    if (len <= 1e-6)
        return null;
    return { x0: x0, y0: y0, x1: x1, y1: y1, len: len,
             ux: (x1 - x0) / len, uy: (y1 - y0) / len,
             mx: (x0 + x1) / 2, my: (y0 + y1) / 2 };
}

function attachSectionModel(bends, boundary) {
    if (!bends || !boundary || !boundary.outerLoop || boundary.outerLoop.length < 3)
        return bends;
    var lines = [];
    for (var i = 0; i < bends.length; i++)
        lines.push(bendLineOf(bends[i]));
    for (var b = 0; b < bends.length; b++) {
        var line = lines[b];
        if (!line)
            continue;
        var nx = -line.uy, ny = line.ux;
        // Several perpendicular sections along the hinge: holes and reliefs
        // can cut any single one short.
        var rays = [];
        for (var k = 1; k <= 9; k++) {
            var ox = line.x0 + line.ux * line.len * k / 10;
            var oy = line.y0 + line.uy * line.len * k / 10;
            // The part is rigid: material beyond holes/cutouts still swings
            // with the flange, so scan the whole part and keep a material
            // mask (0.05 in steps) instead of stopping at the first gap.
            var probe = lineMaterialProbe(boundary, ox, oy, nx, ny);
            var run = function(sign) {
                var mask = [], last = 0;
                for (var si = 1; si <= 1200; si++) {
                    var d = si * 0.05;
                    var inside = probe(d * sign);
                    mask.push(inside);
                    if (inside)
                        last = si;
                }
                mask.length = last;
                return mask;
            };
            var negMask = run(-1), posMask = run(1);
            var neg = negMask.length * 0.05, pos = posMask.length * 0.05;
            var crossings = [];
            for (var o = 0; o < bends.length; o++) {
                var other = lines[o];
                if (o === b || !other || Math.abs(other.ux * line.ux + other.uy * line.uy) < 0.999)
                    continue;
                // Signed normal offset of the parallel line, and whether this
                // perpendicular hits its span.
                var dist = (other.x0 - ox) * nx + (other.y0 - oy) * ny;
                var t0 = (other.x0 - ox) * line.ux + (other.y0 - oy) * line.uy;
                var t1 = (other.x1 - ox) * line.ux + (other.y1 - oy) * line.uy;
                if (Math.min(t0, t1) > 1e-3 || Math.max(t0, t1) < -1e-3)
                    continue;
                if (dist < -neg - 1e-3 || dist > pos + 1e-3 || Math.abs(dist) < 1e-3)
                    continue;
                crossings.push({ id: String(bends[o].id), dist: dist });
            }
            rays.push({ negIn: neg, posIn: pos, negMask: negMask, posMask: posMask, crossings: crossings });
        }
        bends[b].section = { rays: rays };
    }
    return bends;
}

function foldDeg(bend) {
    var a = num(bend.angleValue !== undefined ? bend.angleValue : bend.angleDeg);
    return isFinite(a) ? Math.max(0, Math.min(180, 180 - a)) : 90;
}

function bendDir(bend) {
    return String(bend.dir !== undefined ? bend.dir : bend.direction || "UP").toUpperCase() === "DOWN"
        ? "DOWN" : "UP";
}

// Real punch silhouette from the catalog DXF (one closed LWPOLYLINE, inches).
// Returned polygon is relative to the tip: tip at (0,0), +y up the punch.
function punchDxfFileForId(id) {
    var raw = String(id || "");
    var m = raw.match(/\[([^\]]+)\]/);
    var v = (m ? m[1] : raw).toLowerCase().replace(/^bc-/, "").trim();
    var files = {
        "8392": "Goodeneck 88° Punch [8392].dxf",
        "3924": "Extreme Gooseneck 85° Punch [3924].dxf",
        "3169": "Acute 30° Punch [3169].dxf",
        "9302": "Standart 30° Punch [9302].dxf",
        "2287": "Heavy Duty 35° Punch [2287].dxf"
    };
    return files[v] || "";
}

function dieDxfFileForId(id) {
    var raw = String(id || "");
    var m = raw.match(/\[([^\]]+)\]/);
    var v = (m ? m[1] : raw).toLowerCase().replace(/^bc-/, "").trim();
    var files = {
        "4387": "Standart 4-Way Die [4387].dxf",
        "9355": "Acute 26mm 30° Die [9355].dxf",
        "9858": "Acute 16.5mm 30° Die [9858].dxf",
        "5623": "Acute 8mm 30° Die [5623].dxf",
        "2285": "Acute 26mm 35° Die [2285].dxf"
    };
    return files[v] || "";
}

// Die outline with its top (sheet line) at y=0 and body below (y<0).
function dieSilhouetteFromDxf(text) {
    var poly = punchSilhouetteFromDxf(text);
    if (!poly)
        return null;
    var h = 0;
    for (var i = 0; i < poly.length; i++)
        h = Math.max(h, poly[i].y);
    var out = [];
    for (var k = 0; k < poly.length; k++)
        out.push({ x: poly[k].x, y: poly[k].y - h });
    return { poly: out, height: h };
}

// Lower tooling: real die outline, then riser/table below it. The table is
// 33 in long and treated as infinite downward, so nothing may pass beneath
// the die top within the table width.
var TABLE_HALF_WIDTH_IN = 1.44;
var RISER_HEIGHT_IN = 0.75;
function lowerToolingHits(die, x, y) {
    if (y > -0.03)
        return false;
    var height = die ? die.height : 2.36;
    // Table top (below die + 0.75 in riser) is a half-space: infinite
    // downward and sideways.
    if (y < -(height + RISER_HEIGHT_IN))
        return true;
    if (y < -height)
        return Math.abs(x) < TABLE_HALF_WIDTH_IN;
    if (die)
        return pointInPolygon(die.poly, x, y);
    return Math.abs(x) < 1.18;
}

function punchSilhouetteFromDxf(text) {
    if (!text)
        return null;
    var tokens = String(text).split(/\r?\n/);
    var best = null;
    for (var i = 0; i < tokens.length - 1; i += 2) {
        if (String(tokens[i]).trim() !== "0" || String(tokens[i + 1]).trim() !== "LWPOLYLINE")
            continue;
        var pts = [], cur = null;
        for (var k = i + 2; k < tokens.length - 1; k += 2) {
            var code = String(tokens[k]).trim();
            if (code === "0")
                break;
            var val = Number(tokens[k + 1]);
            if (code === "10") { cur = { x: val, y: NaN }; pts.push(cur); }
            else if (code === "20" && cur) cur.y = val;
        }
        if (pts.length > 2 && (!best || pts.length > best.length))
            best = pts;
    }
    if (!best)
        return null;
    var minY = Infinity;
    for (var p = 0; p < best.length; p++)
        minY = Math.min(minY, best[p].y);
    var eps = 0.01, sx = 0, n = 0;
    for (var q = 0; q < best.length; q++)
        if (best[q].y - minY <= eps) { sx += best[q].x; n++; }
    var tipX = n > 0 ? sx / n : 0;
    var poly = [];
    for (var r = 0; r < best.length; r++)
        poly.push({ x: best[r].x - tipX, y: best[r].y - minY });
    return poly;
}

function pointInPolygon(poly, x, y) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        var a = poly[i], b = poly[j];
        if ((a.y > y) !== (b.y > y) && x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x)
            inside = !inside;
    }
    return inside;
}

// Fallback envelope when no silhouette is available: 20° wedge, blade, holder.
function punchHits(silhouette, mirror, x, y) {
    if (y <= 0.06)
        return false;
    // Upper beam/clamp above the punch top: infinite upward and sideways.
    var top = 4.65;
    if (silhouette) {
        if (silhouette.topY === undefined) {
            var maxY = 0;
            for (var i = 0; i < silhouette.length; i++)
                maxY = Math.max(maxY, silhouette[i].y);
            silhouette.topY = maxY;
        }
        top = silhouette.topY;
    }
    if (y >= top)
        return true;
    if (silhouette)
        return pointInPolygon(silhouette, mirror ? -x : x, y);
    var half = Math.min(Math.tan(20 * Math.PI / 180) * y, y < 3.0 ? 0.30 : 0.75);
    return Math.abs(x) < half - 0.02;
}

// The operator may load the part either way round (which side faces the
// backgauge), so an order collides only when both orientations hit.
// completedIds[id]: true = fully formed, number = partially formed fold
// degrees (a pre-bend that is finished later in the sequence).
function formedFoldDeg(completedIds, bend) {
    var state = completedIds[String(bend.id)];
    if (state === true) return foldDeg(bend);
    var n = num(state);
    return isFinite(n) && n > 0 ? n : 0;
}

function sectionPunchCollision(bend, completedIds, byId) {
    var rays = bend && bend.section ? bend.section.rays : null;
    var silhouette = bend ? bend.punchSilhouette || null : null;
    var die = bend ? bend.dieSilhouette || null : null;
    if (!rays)
        return false;
    var fromDeg = formedFoldDeg(completedIds, bend);
    for (var mirror = 0; mirror < 2; mirror++) {
        var hit = false;
        for (var r = 0; r < rays.length && !hit; r++)
            hit = rayPunchCollision(bend, rays[r], completedIds, byId, silhouette, mirror === 1, die, fromDeg);
        if (!hit)
            return false;
    }
    return true;
}

// Checks the end of stroke (wings at fold/2) and the stroke start (sheet flat
// on the die), where hanging formed flanges are lowest against die/table.
function rayPunchCollision(bend, section, completedIds, byId, silhouette, mirror, die, fromDeg) {
    var full = foldDeg(bend);
    var from = Math.min(full, Math.max(0, num(fromDeg) || 0));
    var stages = [];
    for (var f = 4; f >= 0; f--)
        stages.push(from + (full - from) * f / 4);
    for (var st = 0; st < stages.length; st++)
        if (rayStageCollision(bend, section, completedIds, byId, silhouette, mirror, die, stages[st]))
            return true;
    return false;
}

function rayStageCollision(bend, section, completedIds, byId, silhouette, mirror, die, foldNow) {
    var fb = foldNow * Math.PI / 180;
    var dir = bendDir(bend);
    function side(sign) {
        var limit = sign > 0 ? section.posIn : section.negIn;
        var mask = sign > 0 ? section.posMask : section.negMask;
        function material(dist) {
            if (!mask)
                return true;
            var idx = Math.round(dist / 0.05) - 1;
            return idx < 0 || idx >= mask.length ? idx < 0 : mask[idx] === true;
        }
        var marks = [];
        for (var i = 0; i < section.crossings.length; i++) {
            var c = section.crossings[i];
            if (c.dist * sign > 0)
                marks.push({ d: Math.abs(c.dist), bend: byId[c.id] });
        }
        marks.sort(function(a, b) { return a.d - b.d; });
        var heading = sign > 0 ? fb / 2 : Math.PI - fb / 2;
        var x = 0, y = 0, travelled = 0, curled = false;
        marks.push({ d: limit, bend: null });
        for (var m = 0; m < marks.length; m++) {
            var segment = Math.max(0, Math.min(limit, marks[m].d) - travelled);
            for (var s = 0.05; s <= segment + 1e-9; s += 0.05) {
                var px = x + Math.cos(heading) * s, py = y + Math.sin(heading) * s;
                // The straight run from the hinge rests on the punch face by
                // design; only material past an already formed bend can hit.
                if (!material(travelled + s))
                    continue;
                if (curled && travelled + s > 0.25 && punchHits(silhouette, mirror, px, py))
                    return true;
                if (curled && lowerToolingHits(die, mirror ? -px : px, py))
                    return true;
            }
            x += Math.cos(heading) * segment;
            y += Math.sin(heading) * segment;
            travelled += segment;
            var nb = marks[m].bend;
            var nbFormed = nb ? formedFoldDeg(completedIds, nb) : 0;
            if (nbFormed > 0) {
                var curl = (bendDir(nb) === dir ? 1 : -1) * nbFormed * Math.PI / 180;
                heading += sign > 0 ? curl : -curl;
                curled = true;
            }
            if (travelled >= limit - 1e-9)
                break;
        }
        return false;
    }
    return side(1) || side(-1);
}

// Order search re-tests the same (bend, formed-state) pairs many times; the
// result depends only on those, so it is memoized per search.
var collisionMemo = null;
function memoCollision(bend, completedIds, byId) {
    if (!collisionMemo)
        return sectionPunchCollision(bend, completedIds, byId);
    var parts = [];
    for (var k in completedIds) {
        var v = completedIds[k];
        if (v !== undefined && v !== false)
            parts.push(k + "=" + String(v));
    }
    parts.sort();
    var key = String(bend.id) + "|" + String(bend.partialFoldDeg) + "|" + parts.join(",");
    var hit = collisionMemo[key];
    if (hit === undefined) {
        hit = sectionPunchCollision(bend, completedIds, byId);
        collisionMemo[key] = hit;
    }
    return hit;
}

function orderCost(order) {
    var byId = ({});
    for (var i = 0; i < order.length; i++)
        byId[String(order[i].id)] = order[i];
    var completed = ({});
    var collisions = 0, changes = 0;
    for (var k = 0; k < order.length; k++) {
        if (memoCollision(order[k], completed, byId))
            collisions++;
        if (k > 0 && setupIdentity(order[k]) !== setupIdentity(order[k - 1]))
            changes++;
        completed[String(order[k].id)] = true;
    }
    return { collisions: collisions, changes: changes };
}

// Exhaustive dependency-safe search for small parts when the setup-reuse
// order collides: fewest collisions, then fewest setup changes, then closest
// to the preferred order.
function collisionFreeOrder(preferred) {
    var n = preferred.length;
    if (n > 9)
        return preferred;
    var rank = ({});
    for (var r = 0; r < n; r++)
        rank[String(preferred[r].id)] = r;
    var byId = ({});
    for (var i = 0; i < n; i++)
        byId[String(preferred[i].id)] = preferred[i];
    var best = null, bestKey = null;
    var path = [], used = ({}), completed = ({});
    function better(key) {
        if (!bestKey) return true;
        for (var q = 0; q < key.length; q++)
            if (key[q] !== bestKey[q]) return key[q] < bestKey[q];
        return false;
    }
    function dfs(collisions, changes, deviation) {
        if (bestKey && (collisions > bestKey[0]
                || (collisions === bestKey[0] && changes > bestKey[1])))
            return;
        if (path.length === n) {
            var key = [collisions, changes, deviation];
            if (better(key)) { best = path.slice(0); bestKey = key; }
            return;
        }
        for (var c = 0; c < n; c++) {
            var bend = preferred[c];
            var id = String(bend.id);
            if (used[id] || !dependencySatisfied(bend, completed))
                continue;
            var hit = memoCollision(bend, completed, byId) ? 1 : 0;
            var change = path.length > 0 && setupIdentity(path[path.length - 1]) !== setupIdentity(bend) ? 1 : 0;
            used[id] = true; completed[id] = true; path.push(bend);
            dfs(collisions + hit, changes + change, deviation + Math.abs(rank[id] - (path.length - 1)));
            path.pop(); used[id] = false; completed[id] = false;
        }
    }
    dfs(0, 0, 0);
    return best || preferred;
}

// Partial pre-bend: when an order still collides, a bend may be formed to
// PARTIAL_FRACTION of its fold first and finished later, once the bends that
// would hit its full flange are done.
var PARTIAL_FRACTION = 0.5;
var MAX_PARTIAL_BENDS = 2;

function partialBendRow(bend) {
    var copy = {};
    for (var key in bend) copy[key] = bend[key];
    var fold = foldDeg(bend) * PARTIAL_FRACTION;
    copy.id = String(bend.id) + "P";
    copy.partialOf = bend.id;
    copy.partialFoldDeg = fold;
    copy.angleValue = 180 - fold;
    copy.angle = (180 - fold).toFixed(1);
    copy.warnings = (bend.warnings || []).slice(0);
    copy.errors = (bend.errors || []).slice(0);
    copy.notes = (bend.notes || []).slice(0);
    copy.notes.push("Partial pre-bend of B" + String(bend.id) + " (finished later)");
    return copy;
}

// Marks a sequenced row (full or partial) as formed in completedIds.
function markFormed(completedIds, row) {
    if (row && row.partialOf !== undefined)
        completedIds[String(row.partialOf)] = row.partialFoldDeg;
    else if (row)
        completedIds[String(row.id)] = true;
}

function collisionFreeOrderWithPartials(preferred) {
    var n = preferred.length;
    if (n > 7)
        return null;
    var rank = ({}), byId = ({});
    for (var i = 0; i < n; i++) {
        rank[String(preferred[i].id)] = i;
        byId[String(preferred[i].id)] = preferred[i];
    }
    var best = null, bestKey = null, path = [], completed = ({});
    function better(key) {
        if (!bestKey) return true;
        for (var q = 0; q < key.length; q++)
            if (key[q] !== bestKey[q]) return key[q] < bestKey[q];
        return false;
    }
    function dfs(done, collisions, partials, changes, deviation) {
        if (bestKey && (collisions > bestKey[0]
                || (collisions === bestKey[0] && partials > bestKey[1])
                || (collisions === bestKey[0] && partials === bestKey[1] && changes > bestKey[2])))
            return;
        if (done === n) {
            var key = [collisions, partials, changes, deviation];
            if (better(key)) { best = path.slice(0); bestKey = key; }
            return;
        }
        for (var c = 0; c < n; c++) {
            var bend = preferred[c], id = String(bend.id), state = completed[id];
            if (state === true || !dependencySatisfied(bend, completed))
                continue;
            var change = path.length > 0 && setupIdentity(path[path.length - 1].bend) !== setupIdentity(bend) ? 1 : 0;
            var hit = memoCollision(bend, completed, byId) ? 1 : 0;
            completed[id] = true; path.push({ bend: bend, partial: false });
            dfs(done + 1, collisions + hit, partials, changes + change,
                deviation + Math.abs(rank[id] - (done)));
            path.pop(); completed[id] = state;
            // Pre-bend only when finishing now collides and it has not started.
            if (hit && state === undefined && partials < MAX_PARTIAL_BENDS) {
                var pre = partialBendRow(bend);
                var preHit = memoCollision(pre, completed, byId) ? 1 : 0;
                completed[id] = pre.partialFoldDeg; path.push({ bend: bend, partial: true, row: pre });
                dfs(done, collisions + preHit, partials + 1, changes + change, deviation);
                path.pop(); completed[id] = state;
            }
        }
    }
    dfs(0, 0, 0, 0, 0);
    if (!best) return null;
    var rows = [];
    for (var k = 0; k < best.length; k++)
        rows.push(best[k].partial ? best[k].row : best[k].bend);
    return { rows: rows, collisions: bestKey[0] };
}

function orderBendsForSetupReuse(bends) {
    collisionMemo = ({});
    try {
        return orderBendsForSetupReuseSearch(bends);
    } finally {
        collisionMemo = null;
    }
}

function orderBendsForSetupReuseSearch(bends) {
    var ordered = orderBendsForSetupReuseGreedy(bends);
    if (orderCost(ordered).collisions === 0)
        return ordered;
    var plain = collisionFreeOrder(ordered);
    var plainCost = orderCost(plain).collisions;
    if (plainCost === 0)
        return plain;
    var staged = collisionFreeOrderWithPartials(ordered);
    return staged && staged.collisions < plainCost ? staged.rows : plain;
}

function orderBendsForSetupReuseGreedy(bends) {
    var remaining = [];
    for (var sourceIndex = 0; bends && sourceIndex < bends.length; sourceIndex++)
        remaining.push(bends[sourceIndex]);
    var ordered = [];
    var completedIds = ({});
    var activeSetup = "";
    var longestFirst = prefersLongestFirst(remaining);
    while (remaining.length > 0) {
        var available = [];
        for (var index = 0; index < remaining.length; index++) {
            if (dependencySatisfied(remaining[index], completedIds))
                available.push(remaining[index]);
        }
        // Preserve deterministic progress for malformed/cyclic legacy input;
        // validation remains responsible for surfacing the bad dependency.
        if (available.length === 0)
            available.push(remaining[0]);
        var groupCounts = ({});
        for (var countIndex = 0; countIndex < remaining.length; countIndex++) {
            var countKey = setupIdentity(remaining[countIndex]);
            groupCounts[countKey] = Number(groupCounts[countKey] || 0) + 1;
        }
        available.sort(function(a, b) {
            var aKey = setupIdentity(a);
            var bKey = setupIdentity(b);
            var aActive = aKey === activeSetup ? 1 : 0;
            var bActive = bKey === activeSetup ? 1 : 0;
            if (aActive !== bActive)
                return bActive - aActive;
            if (groupCounts[aKey] !== groupCounts[bKey])
                return groupCounts[bKey] - groupCounts[aKey];
            var aWidth = bendWidth(a);
            var bWidth = bendWidth(b);
            if (Math.abs(aWidth - bWidth) > 1e-6)
                return longestFirst ? bWidth - aWidth : aWidth - bWidth;
            if (longestFirst && bendSide(a) !== bendSide(b)) {
                if (bendSide(a) === "POS")
                    return -1;
                if (bendSide(b) === "POS")
                    return 1;
            }
            var aHint = num(a.sequenceHint);
            var bHint = num(b.sequenceHint);
            if (isFinite(aHint) && isFinite(bHint) && aHint !== bHint)
                return aHint - bHint;
            return String(a.id || "").localeCompare(String(b.id || ""));
        });
        var chosen = available[0];
        ordered.push(chosen);
        completedIds[String(chosen.id)] = true;
        activeSetup = setupIdentity(chosen);
        for (var removeIndex = 0; removeIndex < remaining.length; removeIndex++) {
            if (remaining[removeIndex] === chosen) {
                remaining.splice(removeIndex, 1);
                break;
            }
        }
    }
    return ordered;
}

function toolSegmentInventory(tool) {
    var widths = [16, 8, 4, 2, 1];
    var counts = [];
    for (var index = 0; index < widths.length; index++) {
        var count = num(tool && tool["segmentCount" + String(widths[index]) + "In"]);
        counts.push({
            widthIn: widths[index],
            count: isFinite(count) && count >= 0 ? Math.max(0, Math.round(count)) : -1
        });
    }
    return counts;
}

function resolveSegmentCombination(requiredWidth, tool) {
    var required = Math.max(0.25, num(requiredWidth));
    var inventory = toolSegmentInventory(tool);
    var best = null;
    function visit(index, widths, total) {
        if (total + 1e-6 >= required) {
            if (best === null || total < best.total - 1e-6
                    || (Math.abs(total - best.total) <= 1e-6
                        && widths.length < best.widths.length))
                best = { total: total, widths: widths.slice(0) };
            return;
        }
        if (index >= inventory.length)
            return;
        var item = inventory[index];
        var maximum = item.count >= 0 ? item.count
            : Math.max(0, Math.ceil((required - total) / item.widthIn));
        for (var count = 0; count <= maximum; count++) {
            var next = widths.slice(0);
            for (var copy = 0; copy < count; copy++)
                next.push(item.widthIn);
            visit(index + 1, next, total + count * item.widthIn);
        }
    }
    visit(0, [], 0);
    if (best !== null)
        return { widths: best.widths, total: best.total, inventoryShortage: false };
    var fallback = [];
    var remaining = required;
    var available = [16, 8, 4, 2, 1];
    for (var widthIndex = 0; widthIndex < available.length; widthIndex++) {
        while (remaining >= available[widthIndex] - 0.05) {
            fallback.push(available[widthIndex]);
            remaining -= available[widthIndex];
        }
    }
    if (remaining > 0.05)
        fallback.push(1);
    var total = 0;
    for (var fallbackIndex = 0; fallbackIndex < fallback.length; fallbackIndex++)
        total += fallback[fallbackIndex];
    return { widths: fallback, total: total, inventoryShortage: true };
}

// Largest stack whose total does not exceed maxWidth (flange clearance).
function resolveSegmentCombinationMax(maxWidth, tool) {
    var limit = num(maxWidth);
    var inventory = toolSegmentInventory(tool);
    var best = { total: 0, widths: [] };
    function visit(index, widths, total) {
        if (total > best.total + 1e-6
                || (Math.abs(total - best.total) <= 1e-6 && widths.length < best.widths.length))
            best = { total: total, widths: widths.slice(0) };
        if (index >= inventory.length)
            return;
        var item = inventory[index];
        var fit = Math.floor((limit - total + 1e-6) / item.widthIn);
        var maximum = item.count >= 0 ? Math.min(item.count, fit) : fit;
        for (var count = maximum; count >= 0; count--) {
            var next = widths.slice(0);
            for (var copy = 0; copy < count; copy++)
                next.push(item.widthIn);
            visit(index + 1, next, total + count * item.widthIn);
        }
    }
    visit(0, [], 0);
    return best;
}

function isClearanceSetup(bend) {
    return String(bend && bend.setup || "").toLowerCase().indexOf("clearance") >= 0;
}

// Longest segments go to both ends of the stack so the corners of the
// part are always supported by a long, stable piece.
function cornerOrdered(layout) {
    var sorted = layout.widths.slice(0).sort(function(a, b) { return num(b) - num(a); });
    var left = [], right = [];
    for (var i = 0; i < sorted.length; i++)
        (i % 2 === 0 ? left : right).push(sorted[i]);
    return { widths: left.concat(right.reverse()), total: layout.total,
             inventoryShortage: layout.inventoryShortage };
}

// Holder length on the press bed/ram that physically supports segments.
var MACHINE_SUPPORT_WIDTH_IN = 33.0;

// A centered stack overhangs the holder beyond +/-16.5 in; every segment
// must keep at least half of its length on the holder.
function stackUnsupported(widths) {
    var total = 0, i;
    for (i = 0; i < widths.length; i++) total += num(widths[i]);
    var half = MACHINE_SUPPORT_WIDTH_IN / 2, x = -total / 2;
    for (i = 0; i < widths.length; i++) {
        var w = num(widths[i]);
        var overlap = Math.min(x + w, half) - Math.max(x, -half);
        if (overlap < w / 2 - 1e-6) return true;
        x += w;
    }
    return false;
}

// Reuse the previous stack by removing pieces only from its ends: the
// largest contiguous window that still covers the bend and fits the cap.
function trimmedWindow(previousWidths, requiredWidth, capWidth) {
    var best = null;
    for (var a = 0; a < previousWidths.length; a++) {
        var total = 0;
        for (var b = a; b < previousWidths.length; b++) {
            total += num(previousWidths[b]);
            if (total > capWidth + 1e-6) break;
            if (total >= requiredWidth - 1e-6 && (!best || total > best.total))
                best = { widths: previousWidths.slice(a, b + 1), total: total, inventoryShortage: false };
        }
    }
    return best;
}

function assignedSegmentPlan(bends, punches, dies, sideToleranceIn) {
    var phases = [];
    var recommendations = [];
    var index = 0;
    while (bends && index < bends.length) {
        var first = bends[index];
        var identity = setupIdentity(first);
        var end = index + 1;
        var requiredWidth = 0.25;
        var fullWidth = 0.25;
        // Clearance (between-flange) bends cap the stack at their own length;
        // a wider stack would collide with the already formed flanges.
        var maxAllowed = Number.POSITIVE_INFINITY;
        var dieMaxAllowed = Number.POSITIVE_INFINITY;
        while (end <= bends.length) {
            var candidate = bends[end - 1];
            if (setupIdentity(candidate) !== identity)
                break;
            var physicalWidth = Math.max(0.25, num(candidate.widthValue !== undefined
                ? candidate.widthValue : candidate.lengthIn));
            var tolerance = Math.min(Math.max(0, num(sideToleranceIn)), physicalWidth / 2);
            var nextRequired = Math.max(requiredWidth, physicalWidth - 2 * tolerance);
            var nextMax = isClearanceSetup(candidate) ? Math.min(maxAllowed, physicalWidth) : maxAllowed;
            // Material crossing the bend line beyond a relief/cutout caps the
            // stack: a wider punch would also bend that material.
            var materialCap = num(candidate.maxPunchWidthIn);
            var nextDieMax = dieMaxAllowed;
            if (isFinite(materialCap) && materialCap > 0) {
                nextMax = Math.min(nextMax, Math.max(physicalWidth, materialCap));
                // The die would also support/press that material (and hit
                // its formed flanges), so it gets the same cap.
                nextDieMax = Math.min(nextDieMax, Math.max(physicalWidth, materialCap));
            }
            // Incompatible with the current phase: start a new tooling phase.
            if (end > index + 1 && nextRequired > nextMax + 1e-6)
                break;
            requiredWidth = nextRequired;
            maxAllowed = nextMax;
            dieMaxAllowed = nextDieMax;
            fullWidth = Math.max(fullWidth, physicalWidth);
            end++;
        }
        var punch = findToolById(punches, first.punchId);
        var die = findToolById(dies, first.dieId);
        // Prefer a stack that covers the full bend length; fall back to the
        // side-tolerance minimum only when inventory cannot cover it.
        function coveringLayout(tool, capWidth) {
            var maxAllowed = capWidth;
            var full = resolveSegmentCombination(Math.min(fullWidth, maxAllowed), tool);
            if (!full.inventoryShortage && full.total <= maxAllowed + 1e-6)
                return full;
            var minimal = resolveSegmentCombination(requiredWidth, tool);
            if (!minimal.inventoryShortage && minimal.total <= maxAllowed + 1e-6)
                return minimal;
            if (isFinite(maxAllowed)) {
                var capped = resolveSegmentCombinationMax(maxAllowed, tool);
                return { widths: capped.widths, total: capped.total,
                         inventoryShortage: minimal.inventoryShortage };
            }
            return minimal;
        }
        // Clearance limits only the punch (flanges rise around it). The die
        // is kept from the previous phase when it still covers the bend,
        // so a punch-only change does not cost a die change.
        var previous = phases.length > 0 ? phases[phases.length - 1] : null;
        var punchLayout = cornerOrdered(coveringLayout(punch, maxAllowed));
        if (previous && previous.punchId === first.punchId) {
            var window = trimmedWindow(previous.punchWidths,
                Math.min(requiredWidth, punchLayout.total), maxAllowed);
            if (window && window.total >= punchLayout.total - 1e-6)
                punchLayout = window;
        }
        var dieReused = !!(previous && previous.dieId === first.dieId
            && !previous.dieInventoryShortage && previous.dieTotal >= requiredWidth - 1e-6
            && previous.dieTotal <= dieMaxAllowed + 1e-6);
        var dieLayout = dieReused
            ? { widths: previous.dieWidths.slice(0), total: previous.dieTotal, inventoryShortage: false }
            : cornerOrdered(coveringLayout(die, dieMaxAllowed));
        var punchReused = !!(previous && previous.punchId === first.punchId
            && previous.punchWidths.join(",") === punchLayout.widths.join(","));
        var phaseIndex = phases.length;
        var phase = {
            index: phaseIndex,
            punchId: first.punchId,
            dieId: first.dieId,
            punchWidths: punchLayout.widths,
            dieWidths: dieLayout.widths,
            punchStartIn: -punchLayout.total / 2,
            dieStartIn: -dieLayout.total / 2,
            dieTotal: dieLayout.total,
            punchUnsupported: stackUnsupported(punchLayout.widths),
            dieUnsupported: stackUnsupported(dieLayout.widths),
            punchInventoryShortage: punchLayout.inventoryShortage,
            dieInventoryShortage: dieLayout.inventoryShortage
        };
        phases.push(phase);
        for (var recommendationIndex = index;
                recommendationIndex < end - 1; recommendationIndex++) {
            recommendations.push({
                bendId: bends[recommendationIndex].id,
                phaseIndex: phaseIndex,
                changeLabel: recommendationIndex === index
                    ? (phaseIndex === 0 ? "START"
                       : dieReused ? (punchReused ? "SAME" : "PUNCH")
                       : (punchReused ? "DIE" : "TOOLING")) : "SAME"
            });
        }
        index = end - 1;
    }
    assignSideBySideStations(phases, recommendations, punches, dies);
    return { phases: phases, recommendations: recommendations };
}

// Test mode: install several setups side by side on the 33 in table so a
// complex part runs without a tooling-change pause. Setups share the ram
// stroke, so their punch+die shut heights must match.
var STATION_GAP_IN = 2.0;
var sideBySideStationsEnabled = true;
function setSideBySideStationsEnabled(enabled) { sideBySideStationsEnabled = !!enabled; }
// Largest flat-part extent: the part may swing anywhere around the active
// station, so neighbours must stay at least this far from its stack.
var stationPartClearanceIn = 0;
function setStationPartClearance(extentIn) { stationPartClearanceIn = Math.max(0, num(extentIn) || 0); }

function stackTotal(widths) {
    var t = 0;
    for (var i = 0; i < (widths || []).length; i++) t += num(widths[i]);
    return t;
}

function shutHeight(phase, punches, dies) {
    var p = findToolById(punches, phase.punchId), d = findToolById(dies, phase.dieId);
    var ph = p ? num(p.heightInch) : NaN, dh = d ? num(d.heightInch) : NaN;
    return isFinite(ph) && ph > 0 && isFinite(dh) && dh > 0 ? ph + dh : NaN;
}

function stationsCompatible(a, b, punches, dies) {
    if (a.punchId === b.punchId && a.dieId === b.dieId) return true;
    var ha = shutHeight(a, punches, dies), hb = shutHeight(b, punches, dies);
    return isFinite(ha) && isFinite(hb) && Math.abs(ha - hb) <= 0.005;
}

function assignSideBySideStations(phases, recommendations, punches, dies) {
    var i;
    for (i = 0; i < phases.length; i++) {
        phases[i].rackIndex = i;
        phases[i].stationOffsetIn = 0;
        phases[i].stationWidthIn = Math.max(stackTotal(phases[i].punchWidths), stackTotal(phases[i].dieWidths));
        phases[i].coStations = [];
    }
    if (!sideBySideStationsEnabled || phases.length < 2) return;
    var gap = Math.max(STATION_GAP_IN, stationPartClearanceIn);
    // Greedy racks: consecutive phases share a table load while they fit.
    var racks = [], rack = null;
    for (i = 0; i < phases.length; i++) {
        var ph = phases[i];
        var fits = rack && rack.used + gap + ph.stationWidthIn <= MACHINE_SUPPORT_WIDTH_IN + 1e-6;
        for (var k = 0; fits && k < rack.phases.length; k++)
            fits = stationsCompatible(rack.phases[k], ph, punches, dies);
        if (!fits) {
            rack = { phases: [], used: -gap };
            racks.push(rack);
        }
        rack.phases.push(ph);
        rack.used += gap + ph.stationWidthIn;
    }
    for (var r = 0; r < racks.length; r++) {
        var members = racks[r].phases;
        var cursor = -racks[r].used / 2;
        for (i = 0; i < members.length; i++) {
            members[i].rackIndex = r;
            members[i].stationOffsetIn = cursor + members[i].stationWidthIn / 2;
            cursor += members[i].stationWidthIn + gap;
        }
        for (i = 0; i < members.length; i++) {
            for (var j = 0; j < members.length; j++) {
                if (i === j) continue;
                var o = members[j], delta = o.stationOffsetIn - members[i].stationOffsetIn;
                members[i].coStations.push({
                    punchWidths: o.punchWidths.slice(0), dieWidths: o.dieWidths.slice(0),
                    punchStartIn: o.punchStartIn + delta, dieStartIn: o.dieStartIn + delta
                });
            }
        }
    }
    // A phase that starts inside an already loaded rack needs no pause.
    for (i = 0; i < recommendations.length; i++) {
        var rec = recommendations[i], phase = phases[rec.phaseIndex];
        if (rec.changeLabel !== "SAME" && rec.changeLabel !== "START"
                && rec.phaseIndex > 0 && phases[rec.phaseIndex - 1].rackIndex === phase.rackIndex)
            rec.changeLabel = "STATION";
    }
}
