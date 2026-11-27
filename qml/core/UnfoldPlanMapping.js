.pragma library

// Maps an unfold sequence plan (tools/plan_sequence.mjs output, mm) onto
// BendCNC CAD rows (inches). The plan is authoritative for order, partial
// pre-bends, punch/die and station layout; it was searched with 3D meshes.
// One row per plan stage: a bend formed in two strokes yields two rows
// ("<id>P" pre-bend, then "<id>"), keyed by stage.id.

var MM_PER_IN = 25.4;

function baseBendId(id) {
    return String(id).split(":")[0];
}

// A CAD bend split into coaxial spans can be folded one span per stroke; it
// is only finished when every span is (minimum over its relations).
// The 3D view has one hinge per CAD bend, so it shows a split hinge folded
// from its first span stroke on (maximum over its relations).
function normalizeAmounts(amounts, display) {
    var result = ({});
    for (var key in amounts || {}) {
        var id = baseBendId(key), v = Number(amounts[key]) || 0;
        result[id] = result[id] === undefined ? v
                   : (display ? Math.max(result[id], v) : Math.min(result[id], v));
    }
    return result;
}

// Raw per-relation amounts of split hinges only (keys like "7:FACE:..."), so the
// 3D view folds just the span under the punch.
function spanAmounts(amounts) {
    var count = ({}), result = ({}), any = false;
    for (var key in amounts || {})
        count[baseBendId(key)] = (count[baseBendId(key)] || 0) + 1;
    for (key in amounts || {})
        if (count[baseBendId(key)] > 1) { result[key] = Number(amounts[key]) || 0; any = true; }
    return any ? result : null;
}

function spanInfo(stage) {
    var base = baseBendId(stage.bendId), keys = [];
    for (var key in stage.to || {})
        if (baseBendId(key) === base) keys.push(key);
    var done = 0;
    for (var i = 0; i < keys.length; i++)
        if (Number(stage.to[keys[i]]) >= 1 - 1e-6) done++;
    return { count: keys.length, done: done,
             relationTo: Number(stage.to[stage.bendId]) || 0 };
}

// True for the derived row view below (old BEND files may embed only this).
function isCompactPlan(plan) {
    return !!plan && plan.source === "unfold" && plan.schemaVersion === 1;
}

// Derived view for the CAD rows and the preview. It never replaces the full
// planner result: that one (transfers, coordinated motion, access, retract,
// finger positions, validations) is what is persisted in the .bend.
function compactPlan(plan) {
    if (isCompactPlan(plan))
        return plan;
    var stages = [];
    var source = plan && Array.isArray(plan.stages) ? plan.stages : [];
    for (var i = 0; i < source.length; i++) {
        var s = source[i], c = s.config || {}, r = s.retraction || {};
        var segments = [];
        for (var k = 0; c.segments && k < c.segments.length; k++) {
            var g = c.segments[k];
            segments.push({ kind: g.kind, bankId: String(g.bankId || ""),
                            lengthMm: Number(g.lengthMm), centerY: Number(g.centerY),
                            mirror: g.mirror === true, punchId: String(g.punchId || "") });
        }
        var span = spanInfo(s);
        stages.push({
            id: String(s.id),
            bendId: baseBendId(s.bendId),
            spanCount: span.count,
            spanDone: span.done,
            spanRelationTo: span.relationTo,
            from: normalizeAmounts(s.from),
            to: normalizeAmounts(s.to),
            displayFrom: normalizeAmounts(s.from, true),
            displayTo: normalizeAmounts(s.to, true),
            spanFrom: spanAmounts(s.from),
            spanTo: spanAmounts(s.to),
            relationId: String(s.bendId),
            flip: s.flip === true,
            punchId: String(c.punchId || ""),
            dieId: String(c.dieId || ""),
            stationYmm: Number(c.stationYmm) || 0,
            // Machine-Y centre of this stroke's material (stationYmm is the
            // band-frame shift, which differs when the band is wider than the
            // material); drives the stack highlight.
            materialCenterYmm: materialCenterYmm(s),
            activeBankId: String(c.activeBankId || ""),
            segments: segments,
            // Flat point (mm) the planner placed at machine Y = stationYmm.
            placementOrigin: s.placementOrigin && Array.isArray(s.placementOrigin.pointMm)
                ? { pointMm: s.placementOrigin.pointMm.slice(0, 2),
                    bendId: String(s.placementOrigin.bendId || "") } : null,
            backgauge: compactBackgauge(s.backgauge),
            panelX: s.panelX || null,
            recommendedTipZMm: Number(r.recommendedTipZMm),
            gapFromEndMm: Number(r.gapFromEndMm),
            toolSupportAccepted: !s.toolSupport || s.toolSupport.accepted !== false
        });
    }
    var compact = {
        schemaVersion: 1,
        source: "unfold",
        status: String(plan && plan.status || ""),
        completeGeometricRouteSampleClear: !!(plan && plan.completeGeometricRouteSampleClear),
        backgaugeSampleClear: !!(plan && plan.backgaugeSampleClear),
        requiresManualSetupChange: !!(plan && plan.requiresManualSetupChange),
        cost: plan && plan.cost ? plan.cost : ({}),
        stages: stages
    };
    if (plan && plan.stationStudy)
        compact.stationStudy = { stations: plan.stationStudy.stations || [],
                                 stationTransfers: Number(plan.stationStudy.stationTransfers) || 0,
                                 dieDemand: plan.stationStudy.dieDemand || [] };
    if (plan && plan.singleStationCost)
        compact.singleStationCost = plan.singleStationCost;
    if (plan && Array.isArray(plan.toolingAdvice))
        compact.toolingAdvice = plan.toolingAdvice;
    if (plan && plan.toolingPreference)
        compact.toolingPreference = plan.toolingPreference;
    if (plan && plan.toolingSelection)
        compact.toolingSelection = plan.toolingSelection;
    if (plan && plan.planRequestKey)
        compact.planRequestKey = plan.planRequestKey;
    // Other collision-clear tooling alternatives, each a full compact plan.
    var alternatives = plan && Array.isArray(plan.alternativePlans) ? plan.alternativePlans : [];
    if (alternatives.length > 0) {
        compact.alternativePlans = [];
        for (var a = 0; a < alternatives.length; a++)
            compact.alternativePlans.push({ index: Number(alternatives[a].index),
                                            plan: compactPlan(alternatives[a].plan) });
    }
    return compact;
}

// Alternative cards: the active plan plus its clear alternatives, each with
// the ranking metrics of toolingSelection.alternatives[index].
function toolingOptions(plan) {
    var selection = plan && plan.toolingSelection;
    if (!selection || !Array.isArray(selection.alternatives))
        return [];
    var options = [];
    for (var i = 0; i < selection.alternatives.length; i++) {
        var meta = selection.alternatives[i];
        var entry = null;
        if (i === Number(selection.selectedIndex))
            entry = { plan: null, active: true };
        for (var k = 0; !entry && plan.alternativePlans && k < plan.alternativePlans.length; k++)
            if (Number(plan.alternativePlans[k].index) === i)
                entry = { plan: plan.alternativePlans[k].plan, active: false };
        if (!entry)
            entry = { plan: null, active: false };
        options.push({ index: i, meta: meta, active: entry.active, available: entry.active || entry.plan !== null,
                       plan: entry.plan });
    }
    return options;
}

// Swap the active plan with alternative `index`; selection metadata follows.
function selectAlternative(plan, index) {
    var options = toolingOptions(plan);
    var target = null;
    for (var i = 0; i < options.length; i++)
        if (options[i].index === index && options[i].plan)
            target = options[i].plan;
    if (!target)
        return null;
    var selection = JSON.parse(JSON.stringify(plan.toolingSelection));
    var previous = Number(selection.selectedIndex);
    var currentAsAlternative = {};
    for (var key in plan)
        if (key !== "alternativePlans" && key !== "toolingSelection" && key !== "toolingPreference")
            currentAsAlternative[key] = plan[key];
    var next = JSON.parse(JSON.stringify(target));
    next.toolingSelection = selection;
    next.toolingSelection.selectedIndex = index;
    next.toolingSelection.operatorSelected = true;
    if (plan.toolingPreference) {
        next.toolingPreference = JSON.parse(JSON.stringify(plan.toolingPreference));
        next.toolingPreference.applied = !!(selection.alternatives[index] && selection.alternatives[index].preferred);
    }
    next.alternativePlans = [];
    for (var a = 0; plan.alternativePlans && a < plan.alternativePlans.length; a++)
        if (Number(plan.alternativePlans[a].index) !== index)
            next.alternativePlans.push(plan.alternativePlans[a]);
    if (previous >= 0)
        next.alternativePlans.push({ index: previous, plan: currentAsAlternative });
    if (plan.planRequestKey)
        next.planRequestKey = plan.planRequestKey;
    return next;
}

// Rear-edge contact found by the planner's finger check (mm from the bend
// line, machine X). edgeXMm is the real part edge the fingers touch.
function compactBackgauge(bg) {
    if (!bg || !Array.isArray(bg.contacts))
        return null;
    var edge = -Infinity;
    for (var i = 0; i < bg.contacts.length; i++) {
        var c = bg.contacts[i];
        if (c && c.used && c.witness && c.witness.point)
            edge = Math.max(edge, Number(c.witness.point[0]));
    }
    if (!isFinite(edge))
        return null;
    var tried = Array.isArray(bg.referenceHeightsTriedMm) ? bg.referenceHeightsTriedMm : [];
    var referenceZ = Number(bg.referenceZ);
    var nominalZ = tried.length > 0 ? Number(tried[0]) : referenceZ;
    var offsetMm = isFinite(referenceZ - nominalZ) ? referenceZ - nominalZ : 0;
    // Exported R (add-in): centred on the touched face, >= 0 when raised over the die.
    var rIn = Number(bg.rPositionIn);
    // Planned finger contact (machine mm, +X toward the backgauge) for replay.
    var contacts = [];
    for (var k = 0; k < bg.contacts.length; k++) {
        var f = bg.contacts[k] || {};
        contacts.push({ fingerId: String(f.fingerId || ""), used: f.used === true,
                        witness: f.witness ? { point: f.witness.point, bodyId: String(f.witness.bodyId || "") } : null });
    }
    return { status: String(bg.status || ""), edgeXMm: edge,
             stationY: Array.isArray(bg.stationY) ? bg.stationY : [],
             contact: bg.contact || null, contacts: contacts,
             keyframes: Array.isArray(bg.keyframes) ? bg.keyframes : [],
             referenceMethod: String(bg.referenceMethod || ""),
             heightOffsetMm: offsetMm,
             rPositionIn: isFinite(rIn) ? rIn : Math.max(0, offsetMm / MM_PER_IN) };
}

function bankSpan(segments) {
    var lo = Infinity, hi = -Infinity;
    for (var i = 0; i < segments.length; i++) {
        lo = Math.min(lo, segments[i].centerY - segments[i].lengthMm / 2);
        hi = Math.max(hi, segments[i].centerY + segments[i].lengthMm / 2);
    }
    return { lo: lo, hi: hi };
}

// Widths (in) left to right plus the start (in) relative to `originMm`.
function stack(segments, kind, originMm) {
    var list = segments.filter(function(g) { return g.kind === kind; })
                       .sort(function(a, b) { return a.centerY - b.centerY; });
    if (list.length === 0)
        return { widths: [], startIn: NaN };
    var span = bankSpan(list);
    return { widths: list.map(function(g) { return g.lengthMm / MM_PER_IN; }),
             startIn: (span.lo - originMm) / MM_PER_IN };
}

// Operator setup rule: inside each contiguous set the largest piece goes
// outermost (away from `referenceIn`), then decreasing toward the centre,
// e.g. 1,2,4 left of centre becomes 4,2,1. Sets with internal gaps keep order.
function orderLargestOutward(widths, startIn, referenceIn) {
    var list = (widths || []).map(Number);
    if (list.length < 2 || !isFinite(startIn))
        return list;
    var total = 0;
    for (var i = 0; i < list.length; i++) total += list[i];
    var center = startIn + total / 2;
    // A stack straddling the reference has no outward side: keep the planner's
    // physical order. Otherwise a small station shift (e.g. 1.4 mm) would mirror
    // the same stack and show a false tool change.
    var smallest = Math.min.apply(null, list);
    if (Math.abs(center - referenceIn) < smallest / 2)
        return list;
    list.sort(function(a, b) { return center < referenceIn ? b - a : a - b; });
    return list;
}

// Applies orderLargestOutward to an active stack + co-stations sharing one
// coordinate frame. Reference = middle of all sets (table centre when alone).
function orderLayoutLargestOutward(layout, kindKey, startKey) {
    var sets = [{ o: layout, w: kindKey, s: startKey }];
    var co = layout.coStations || [];
    for (var c = 0; c < co.length; c++)
        sets.push({ o: co[c], w: kindKey === "punchSegmentWidths" ? "punchWidths" : (kindKey === "dieSegmentWidths" ? "dieWidths" : kindKey),
                    s: startKey === "punchSegmentStartIn" ? "punchStartIn" : (startKey === "dieSegmentStartIn" ? "dieStartIn" : startKey) });
    var lo = Infinity, hi = -Infinity;
    for (var i = 0; i < sets.length; i++) {
        var w = sets[i].o[sets[i].w] || [], s = Number(sets[i].o[sets[i].s]), t = 0;
        for (var k = 0; k < w.length; k++) t += Number(w[k]) || 0;
        if (w.length && isFinite(s)) { lo = Math.min(lo, s); hi = Math.max(hi, s + t); }
    }
    var reference = sets.length > 1 && isFinite(lo) ? (lo + hi) / 2 : -(Number(layout.stationOffsetIn !== undefined ? layout.stationOffsetIn : layout.toolingStationOffsetIn) || 0);
    for (var j = 0; j < sets.length; j++)
        sets[j].o[sets[j].w] = orderLargestOutward(sets[j].o[sets[j].w], Number(sets[j].o[sets[j].s]), reference);
}

function materialCenterYmm(s) {
    var iv = s && s.coverage && Array.isArray(s.coverage.materialIntervals) ? s.coverage.materialIntervals : [];
    var lo = Infinity, hi = -Infinity;
    for (var i = 0; i < iv.length; i++) {
        lo = Math.min(lo, Number(iv[i][0]), Number(iv[i][1]));
        hi = Math.max(hi, Number(iv[i][0]), Number(iv[i][1]));
    }
    return isFinite(lo) && isFinite(hi) ? (lo + hi) / 2 : null;
}

// Active station = the bank whose span contains stationYmm (nearest centre
// otherwise); every other bank becomes a co-station on the same table.
function stationLayout(stage) {
    var banks = ({}), order = [];
    // Segments without bankId (e.g. "punch-1" + "punch-extra" at another
    // station) are split into banks by Y contiguity; merging them into one
    // bank packed separate stations into a single stack and left the part
    // off the tooling.
    var unnamed = stage.segments.filter(function(g) { return !g.bankId; })
                                .sort(function(a, b) { return (a.centerY - a.lengthMm / 2) - (b.centerY - b.lengthMm / 2); });
    var clusterOf = [], clusterHi = -Infinity, cluster = -1;
    for (var u = 0; u < unnamed.length; u++) {
        var lo = unnamed[u].centerY - unnamed[u].lengthMm / 2;
        var hi = unnamed[u].centerY + unnamed[u].lengthMm / 2;
        if (lo > clusterHi + 1) { cluster++; clusterHi = hi; }
        else clusterHi = Math.max(clusterHi, hi);
        clusterOf.push(cluster);
    }
    for (var i = 0; i < stage.segments.length; i++) {
        var g = stage.segments[i];
        var key = g.bankId ? g.bankId : "~" + clusterOf[unnamed.indexOf(g)];
        if (!banks[key]) { banks[key] = []; order.push(key); }
        banks[key].push(g);
    }
    var active = "", best = Infinity;
    for (var b = 0; b < order.length; b++) {
        var span = bankSpan(banks[order[b]]);
        var d = stage.stationYmm >= span.lo - 1e-6 && stage.stationYmm <= span.hi + 1e-6
            ? 0 : Math.abs((span.lo + span.hi) / 2 - stage.stationYmm);
        if (d < best) { best = d; active = order[b]; }
    }
    var origin = stage.stationYmm;
    var activeSegments = banks[active] || [];
    var punch = stack(activeSegments, "punch", origin), die = stack(activeSegments, "die", origin);
    var coStations = [];
    for (var o = 0; o < order.length; o++) {
        if (order[o] === active) continue;
        var cp = stack(banks[order[o]], "punch", origin), cd = stack(banks[order[o]], "die", origin);
        // Bank ids can be names ("long"); the DXF lookup needs the punch id.
        var bankPunch = banks[order[o]].filter(function(g) { return g.kind === "punch" && g.punchId; })[0];
        coStations.push({ punchWidths: cp.widths, dieWidths: cd.widths,
                          punchStartIn: cp.startIn, dieStartIn: cd.startIn,
                          punchToken: bankPunch ? bankPunch.punchId : (stage.punchId || String(order[o])),
                          punchMirror: banks[order[o]].some(function(g) { return g.kind === "punch" && g.mirror; }) });
    }
    var layout = { punchWidths: punch.widths, dieWidths: die.widths,
             punchStartIn: punch.startIn, dieStartIn: die.startIn,
             stationOffsetIn: origin / MM_PER_IN, coStations: coStations };
    orderLayoutLargestOutward(layout, "punchWidths", "punchStartIn");
    orderLayoutLargestOutward(layout, "dieWidths", "dieStartIn");
    // Several banks mounted at once: the installation (not the active punch)
    // identifies the setup, so moving between stations is a transfer.
    // Relative to the installation's left edge: sliding the whole setup (or
    // the part) a few mm along the table is the same physical tooling.
    var allLo = bankSpan(stage.segments).lo;
    layout.signature = JSON.stringify(stage.segments.map(function(g) {
                 return [g.kind, g.bankId, g.lengthMm.toFixed(2), (g.centerY - allLo).toFixed(2), !!g.mirror];
             })) + "|" + (order.length > 1 ? "" : stage.punchId) + "|" + stage.dieId;
    // Part position inside the installation: changes when the part moves to
    // another station of the same rack even if stationYmm stays 0.
    layout.installStationMm = stage.stationYmm - allLo;
    layout.punchMirror = activeSegments.some(function(g) { return g.kind === "punch" && g.mirror; });
    return layout;
}

function foldDeg(row) {
    return Math.max(0, 180 - Number(row.angleValue));
}

// baseRows: one CAD row per bend (no partial rows). copyRow clones a row.
// Returns { rows, error }. Rows carry unfoldStageId/unfoldFrom/unfoldTo.
function stageRows(baseRows, plan, copyRow) {
    var byId = ({});
    for (var i = 0; i < baseRows.length; i++)
        if (baseRows[i].partialOf === undefined)
            byId[String(baseRows[i].id)] = baseRows[i];
    var stages = plan && plan.stages ? plan.stages : [];
    var finalCount = ({}), rows = [], signatures = [], previous = null;
    for (var s = 0; s < stages.length; s++) {
        if (!byId[stages[s].bendId])
            return { rows: [], error: "plan bend " + stages[s].bendId + " not in CAD file" };
        if (Number(stages[s].to[stages[s].bendId]) >= 1 - 1e-6)
            finalCount[stages[s].bendId] = (finalCount[stages[s].bendId] || 0) + 1;
    }
    for (var id in byId)
        if (finalCount[id] !== 1)
            return { rows: [], error: "plan does not finish bend " + id + " exactly once" };
    for (s = 0; s < stages.length; s++) {
        var stage = stages[s], base = byId[stage.bendId];
        var row = copyRow(base);
        var to = Number(stage.to[stage.bendId]), from = Number(stage.from[stage.bendId]) || 0;
        var spans = Number(stage.spanCount) || 1;
        if (spans > 1 && to < 1 - 1e-6 && Number(stage.spanRelationTo) >= 1 - 1e-6) {
            // One span of a split hinge, full angle; other spans follow later.
            row.id = String(base.id) + "S" + String(stage.spanDone);
            row.partialOf = base.id;
            row.notes.push("Span " + String(stage.spanDone) + " of " + String(spans)
                           + " of B" + String(base.id) + " (split hinge, same angle)");
        } else if (spans > 1 && to >= 1 - 1e-6 && from < 1 - 1e-6 && Number(stage.spanDone) > 1) {
            row.notes.push("Last span " + String(spans) + " of " + String(spans) + " of B" + String(base.id));
        } else if (to < 1 - 1e-6) {
            var fold = foldDeg(base) * to;
            row.id = String(base.id) + "P";
            row.partialOf = base.id;
            row.partialFoldDeg = fold;
            row.angleValue = 180 - fold;
            row.angle = (180 - fold).toFixed(1);
            row.notes.push("Partial pre-bend of B" + String(base.id) + " to "
                           + fold.toFixed(1) + " deg (finished later)");
        } else if (from > 1e-6) {
            row.notes.push("Finishes B" + String(base.id) + " from "
                           + (foldDeg(base) * from).toFixed(1) + " deg pre-bend");
        }
        var layout = stationLayout(stage);
        var rack = signatures.indexOf(layout.signature);
        if (rack < 0) { signatures.push(layout.signature); rack = signatures.length - 1; }
        else if (previous && previous.rack === rack
                 && JSON.stringify(previous.punchWidths.slice().sort()) === JSON.stringify(layout.punchWidths.slice().sort())
                 && JSON.stringify(previous.dieWidths.slice().sort()) === JSON.stringify(layout.dieWidths.slice().sort())) {
            // Same installed tooling and same active station: keep the
            // operator's piece order (another station of the same rack keeps
            // its own pieces).
            layout.punchWidths = previous.punchWidths;
            layout.dieWidths = previous.dieWidths;
        }
        row.unfoldStageId = stage.id;
        row.unfoldFrom = stage.displayFrom || stage.from;
        row.unfoldTo = stage.displayTo || stage.to;
        row.unfoldSpanFrom = stage.spanFrom || null;
        row.unfoldSpanTo = stage.spanTo || null;
        row.unfoldRelationId = stage.relationId || "";
        row.unfoldFlip = stage.flip;
        row.unfoldPanelX = stage.panelX || null;
        row.unfoldBackgauge = stage.backgauge || null;
        row.unfoldSegments = stage.segments;
        row.unfoldPlacementOrigin = stage.placementOrigin || null;
        row.unfoldPunchId = stage.punchId;
        row.unfoldDieId = stage.dieId;
        row.unfoldRetractTipZIn = stage.recommendedTipZMm / MM_PER_IN;
        if (stage.backgauge) {
            // The CAD file's references assume Fusion's order; the planner
            // measured the actual rear edge for this stroke in this order.
            var gaugeIn = stage.backgauge.edgeXMm / MM_PER_IN;
            row.referenceDistance = gaugeIn;
            row.processBgPosition = gaugeIn;
            row.bg = gaugeIn.toFixed(4);
            row.refType = "EDGE";
            row.parentBendId = 0;
            row.ref = "EDGE";
            row.unfoldGaugeIn = gaugeIn;
            // Finger R from the planner's checked finger path: centred on the
            // touched face (may be negative); >= 0 with a minimum gap above the
            // die top when the centred path would hit the die.
            row.unfoldBgrOffsetIn = stage.backgauge.rPositionIn;
            row.bgrValue = stage.backgauge.rPositionIn;
            row.bgr = Number(row.bgrValue).toFixed(4);
        }
        row.toolingPhaseIndex = rack;
        row.toolingRackIndex = rack;
        row.punchSegmentWidths = layout.punchWidths;
        row.dieSegmentWidths = layout.dieWidths;
        row.punchSegmentStartIn = layout.punchStartIn;
        row.dieSegmentStartIn = layout.dieStartIn;
        row.toolingStationOffsetIn = layout.stationOffsetIn;
        // Machine-Y centre of the material on the stack strips (in).
        row.toolingBendCenterIn = stage.materialCenterYmm !== null && stage.materialCenterYmm !== undefined
            && isFinite(Number(stage.materialCenterYmm)) ? Number(stage.materialCenterYmm) / MM_PER_IN : null;
        row.toolingCoStations = layout.coStations;
        row.punchInventoryShortage = false;
        row.dieInventoryShortage = false;
        row.punchUnsupported = !stage.toolSupportAccepted;
        row.dieUnsupported = !stage.toolSupportAccepted;
        row.chg = !previous ? "START"
            : (previous.rack !== rack ? "CHANGE"
               : (Math.abs(previous.station - layout.stationOffsetIn) > 1e-6
                  || Math.abs(previous.install - layout.installStationMm) > 25.4 ? "STATION" : "SAME"));
        if (previous && previous.flip !== stage.flip)
            row.notes.push("Flip part over before this bend");
        row.unfoldPunchMirror = layout.punchMirror;
        if (layout.punchMirror && (!previous || !previous.mirror))
            row.notes.push("Punch mounted reversed (tool orientation, not part flip)");
        if (row.chg === "STATION")
            row.notes.push("Move part to station " + (stage.activeBankId || (layout.punchWidths.reduce(function(a, w) { return a + w; }, 0).toFixed(2) + " in stack")) + " (no tool change)");
        previous = { rack: rack, station: layout.stationOffsetIn, install: layout.installStationMm, flip: stage.flip, mirror: layout.punchMirror,
                     punchWidths: layout.punchWidths, dieWidths: layout.dieWidths };
        rows.push(row);
    }
    return { rows: rows, error: "" };
}

// Operator-reordered plan rows: each stroke keeps its own fold delta and
// planner placement, but from/to are re-accumulated in the new order so the
// 3D preview folds the right bends (no replan). Returns false when a row has
// no planner stage data.
function resequenceStageRows(rows) {
    function delta(from, to) {
        var d = ({});
        for (var k in to || {}) {
            var dv = (Number(to[k]) || 0) - (Number((from || {})[k]) || 0);
            if (Math.abs(dv) > 1e-9) d[k] = dv;
        }
        return d;
    }
    function advance(state, d) {
        var next = ({});
        for (var k in state) next[k] = state[k];
        for (k in d) next[k] = Math.min(1, Math.max(0, (Number(next[k]) || 0) + d[k]));
        return next;
    }
    function zero(map) {
        if (!map) return null;
        var z = ({});
        for (var k in map) z[k] = 0;
        return z;
    }
    if (!rows.length) return false;
    for (var i = 0; i < rows.length; i++)
        if (!rows[i].unfoldFrom || !rows[i].unfoldTo) return false;
    var state = zero(rows[0].unfoldFrom), span = null;
    for (i = 0; i < rows.length; i++)
        if (rows[i].unfoldSpanFrom) { span = ({}); break; }
    var deltas = [], spanDeltas = [];
    for (i = 0; i < rows.length; i++) {
        for (var k in rows[i].unfoldTo) if (state[k] === undefined) state[k] = 0;
        deltas.push(delta(rows[i].unfoldFrom, rows[i].unfoldTo));
        spanDeltas.push(rows[i].unfoldSpanFrom ? delta(rows[i].unfoldSpanFrom, rows[i].unfoldSpanTo) : null);
        if (span) for (k in rows[i].unfoldSpanTo || {}) span[k] = 0;
    }
    for (i = 0; i < rows.length; i++) {
        var next = advance(state, deltas[i]);
        rows[i].unfoldFrom = state;
        rows[i].unfoldTo = next;
        state = next;
        if (span) {
            var spanNext = advance(span, spanDeltas[i] || ({}));
            if (rows[i].unfoldSpanFrom) {
                rows[i].unfoldSpanFrom = span;
                rows[i].unfoldSpanTo = spanNext;
            }
            span = spanNext;
        }
    }
    return true;
}

// Per-stage fold progress for the 3D preview (keyed by CAD bend id).
function previewStagePlan(rows) {
    var result = [];
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        if (!row.unfoldFrom)
            return [];
        result.push({ bendId: String(row.partialOf !== undefined ? row.partialOf : row.id),
                      from: row.unfoldFrom, to: row.unfoldTo, flip: row.unfoldFlip === true,
                      spanFrom: row.unfoldSpanFrom || null, spanTo: row.unfoldSpanTo || null,
                      relationId: row.unfoldRelationId || "",
                      gaugeIn: row.unfoldGaugeIn, bgrOffsetIn: row.unfoldBgrOffsetIn || 0,
                      panelX: row.unfoldPanelX || null, backgauge: row.unfoldBackgauge || null,
                      placementOrigin: row.unfoldPlacementOrigin || null,
                      segments: row.unfoldSegments || [] });
    }
    return result;
}
