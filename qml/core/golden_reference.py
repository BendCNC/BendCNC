"""Golden-reference computation for BendCalculator parity.

Computes the exact Java BendCalculator outputs (port of
qt/qml/data/current/*.json data, for every bend. Emits JSON that the QML
test harness (test_BendCalculator.qml) compares against.

Run:  python golden_reference.py  > golden_reference.json
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data", "current")

RAM_TO_TABLE_OPENING = 0.0          # desktopRamToTableOpening default
VALID_MIN = -4.0                    # defaultMachineValidTravelRange.inches.min
VALID_MAX = -0.05                   # defaultMachineValidTravelRange.inches.max
JOG_STEP_PADDING = 0.01             # jogStepPreset[1].toInches() (ValuePreset.createDefault(4))
TONNAGE_WARN = 12.5
TONNAGE_ERR = 25.0
PTMC_WARN = 0.3
CLAMP_RATE_PCT = 5.0                # user-settings materialClampRate default


def load(name):
    with open(os.path.join(DATA, name), "r", encoding="utf-8") as f:
        return json.load(f)


def by_id(items):
    return {it["id"]: it for it in items}


def num(v):
    return float(v) if v is not None else float("nan")


def total_bend_stroke(angle, springback, comp, reversed_, vdie, tensile, irrt, thick):
    d = -1.0 if reversed_ else 1.0
    total = math.radians(angle - springback + comp * d)
    inv = math.pi - total
    var1 = vdie * tensile / 60000.0 * irrt + thick
    var2 = 2.0 * math.tan(total / 2.0)
    t1 = vdie / var2
    t2 = var1 * math.sqrt(2.0 * (1.0 - math.cos(inv))) / var2
    t3 = var1 * (1.0 - math.cos(inv / 2.0))
    return t1 - (t2 - t3)


def compute(bend, punch, die, mat):
    thick = num(bend["materialThickness"])
    bw = num(bend["bendWidth"])
    angle = num(bend["desiredBendAngle"])
    comp = num(bend["angleCompensation"])
    rev = bool(bend.get("angleCompensationReversed"))
    ptmc = num(bend["punchToMaterialClearance"])
    add_retract = num(bend["additionalRetractAfterBend"])
    override = bool(bend.get("overrideFinalBendPositionEnabled"))
    overridden = num(bend.get("overriddenFinalBendPosition"))

    ph = num(punch["heightInch"]) if punch else float("nan")
    dh = num(die["heightInch"]) if die else float("nan")
    vdie = num(die["vdieOpeningInch"]) if die else float("nan")

    tensile = num(mat["materialTensileStrengthPsi"]) if mat else float("nan")
    irrt = num(mat["insideRadiusRuleOfThumb"]) if mat else float("nan")
    springback = num(mat["materialSpringback"]) if mat else float("nan")

    tbs = total_bend_stroke(angle, springback, comp, rev, vdie, tensile, irrt, thick)
    ssc = ptmc + ph + dh + thick - RAM_TO_TABLE_OPENING
    clamp = ssc - ptmc - (CLAMP_RATE_PCT / 100.0) * thick
    cfbp = ssc - ptmc - tbs
    in_use = overridden if override else cfbp
    retract = min(ssc + add_retract, VALID_MAX)
    tonnage = (thick * 25.4) ** 2 * tensile * 1.099644e-6 * bw / vdie
    pibr = vdie * (tensile / 60000.0) * irrt
    pad = clamp - JOG_STEP_PADDING
    fbp_min = min(VALID_MIN, pad)
    fbp_max = max(VALID_MIN, pad)

    ptmc_warn = ptmc > PTMC_WARN
    ton_err = tonnage > TONNAGE_ERR
    ton_warn = (tonnage > TONNAGE_WARN) and not ton_err
    upper = (in_use > VALID_MAX) or (ssc > VALID_MAX) or (clamp > VALID_MAX)
    lower = (in_use < VALID_MIN) or (ssc < VALID_MIN) or (clamp < VALID_MIN)
    fbp_out = (in_use > fbp_max) or (in_use < fbp_min)
    err_count = (1 if ton_err else 0) + (1 if upper else 0) + (1 if lower else 0)

    return {
        "startSafetyClearance": ssc,
        "clampPosition": clamp,
        "totalBendStroke": tbs,
        "calculatedFinalBendPosition": cfbp,
        "inUseFinalBendPosition": in_use,
        "retractAfterBend": retract,
        "bendTonnage": tonnage,
        "predictedInsideBendRadius": pibr,
        "finalBendPositionMin": fbp_min,
        "finalBendPositionMax": fbp_max,
        "punchToMaterialClearanceWarning": ptmc_warn,
        "tonnageWarning": ton_warn,
        "tonnageError": ton_err,
        "upperLimitExceededError": upper,
        "lowerLimitExceededError": lower,
        "finalBendPositionOutLimit": fbp_out,
        "errorCount": err_count,
    }


# --------------------------------------------------------------------------
# ToolingPlanningEngine per-bend selector (parity with ToolingPlanningEngine.js)
# --------------------------------------------------------------------------
PREFERRED_PUNCH_BONUS = 1800
PREFERRED_DIE_BONUS = 1800
PROFILE = {
    "STANDARD": (False, 30.0),
    "ACUTE": (True, 30.0),
    "GOOSENECK": (True, 88.0),
    "EXTREME_GOOSENECK": (True, 85.0),
}


def _norm(s):
    return str(s or "").lower().strip()


def punch_profile(p):
    return PROFILE.get(str((p or {}).get("punchProfileType") or "STANDARD"), PROFILE["STANDARD"])


def min_punch_angle(p):
    if not p:
        return float("nan")
    a = num(p.get("punchAngleDegree"))
    if math.isfinite(a):
        return a
    return punch_profile(p)[1]


def die_family(d):
    return "FOUR_WAY" if "4 way" in _norm((d or {}).get("name")) else "ACUTE"


def avail_die_span(d):
    if not d:
        return float("nan")
    total, configured = 0.0, False
    for key, length in (("segmentCount16In", 16.0), ("segmentCount8In", 8.0),
                        ("segmentCount4In", 4.0), ("segmentCount2In", 2.0), ("segmentCount1In", 1.0)):
        c = num(d.get(key))
        if math.isfinite(c) and c >= 0.0:
            configured = True
            total += round(c) * length
    return total if configured else float("nan")


def predicted_radius(mat, d):
    return num(d["vdieOpeningInch"]) * (num(mat["materialTensileStrengthPsi"]) / 60000.0) * num(mat["insideRadiusRuleOfThumb"])


def eval_die(ctx, bend, d, rule8):
    penalty, warns = 0, []
    penalty += 12000
    span = avail_die_span(d)
    if math.isfinite(span) and (num(bend["lengthIn"]) - span) > 1e-6:
        penalty += 90000
        warns.append("Available die segments do not cover bend length")
    penalty += round(abs(num(d["vdieOpeningInch"]) - rule8) * 1500.0)
    if die_family(d) == "ACUTE" and num(bend["angleDeg"]) < 90.0:
        penalty -= 250
    if ctx.get("preferredDieId") and ctx["preferredDieId"] == d["id"]:
        penalty -= PREFERRED_DIE_BONUS
    return penalty, warns


def eval_punch(ctx, bend, p):
    a_pen, c_pen, pref_pen, warns = 0, 0, 0, []
    prof = punch_profile(p)
    mina = min_punch_angle(p)
    if math.isfinite(mina) and (num(bend["angleDeg"]) + 1e-6) < mina:
        a_pen += 100000
        warns.append("Acute angle unsupported by selected die/punch")
    clearance_req = (num(bend.get("chainDepth")) > 0
                     or str(bend.get("referenceType") or "").upper() == "PREVIOUS_BEND"
                     or (bend.get("parentBendId") not in (None, "", float("nan")))
                     or num(bend.get("processBgPositionIn")) >= 5.0)
    if clearance_req and not prof[0]:
        c_pen += 15000
    if ctx.get("preferredPunchId") and ctx["preferredPunchId"] == p["id"]:
        pref_pen -= PREFERRED_PUNCH_BONUS
    return a_pen + c_pen + pref_pen, warns


def resolve_prefs(mat, label):
    prefs = (mat or {}).get("thicknessToolingPreferences") or []
    chosen = None
    if label:
        want = _norm(label)
        for pr in prefs:
            if _norm(pr.get("thicknessLabel")) == want:
                chosen = pr
                break
    if chosen is None and prefs:
        chosen = prefs[0]
    return (chosen.get("preferredPunchId") if chosen else None,
            chosen.get("preferredDieId") if chosen else None)


def select_tooling(mat, bend, punches, dies):
    if not punches or not dies:
        return None
    thick = num(bend.get("thicknessIn"))
    rule8 = thick * 8.0 if (math.isfinite(thick) and thick > 0) else 0.315
    ppid, pdid = resolve_prefs(mat, bend.get("thicknessLabel"))
    ctx = {
        "materialTensileStrengthPsi": num(mat["materialTensileStrengthPsi"]),
        "insideRadiusRuleOfThumb": num(mat["insideRadiusRuleOfThumb"]),
        "name": mat.get("name"),
        "preferredPunchId": ppid,
        "preferredDieId": pdid,
    }
    best = None
    for p in punches:
        pen_p, _ = eval_punch(ctx, bend, p)
        for d in dies:
            pen_d, _ = eval_die(ctx, bend, d, rule8)
            cost = pen_d + pen_p
            cost += round(abs(num(d["vdieOpeningInch"]) - rule8) * 1000.0)
            cost += round(predicted_radius(ctx, d) * 1000.0)
            if best is None or cost < best["cost"]:
                best = {"punchId": p["id"], "dieId": d["id"], "cost": cost}
    return best


def main():
    bends = load("bends.json")
    punches = by_id(load("punches.json"))
    dies = by_id(load("dies.json"))
    mats = by_id(load("materials.json"))
    punch_list = load("punches.json")
    die_list = load("dies.json")

    out = []
    for b in bends:
        p = punches.get(b.get("punchId"))
        d = dies.get(b.get("dieId"))
        m = mats.get(b.get("materialId"))
        entry = {"id": b["id"], "name": b.get("name"), "result": compute(b, p, d, m)}
        # Tooling selection golden: build the per-bend evaluation input from real fields.
        if m:
            tb = {
                "angleDeg": num(b.get("desiredBendAngle")),
                "lengthIn": num(b.get("bendWidth")),
                "thicknessIn": num(b.get("materialThickness")),
                "chainDepth": 0,
                "processBgPositionIn": abs(num(b.get("backGaugeXPosition"))) if b.get("backGaugeXPosition") is not None else 0.0,
                "parentBendId": None,
                "referenceType": None,
                "thicknessLabel": None,
            }
            entry["tooling"] = select_tooling(m, tb, punch_list, die_list)
        out.append(entry)
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
