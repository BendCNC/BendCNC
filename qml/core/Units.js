.pragma library

// Display-only unit helpers. All stored/internal values stay in inches (IPM).
// Metric: lengths show as mm below 100 mm and as cm above; speed as mm/s.
var MM_PER_IN = 25.4

function lenValue(inches, metric) {
    var v = Number(inches)
    if (!isFinite(v))
        return NaN
    return metric ? v * MM_PER_IN : v
}

// "0.5000 in" or "12.70 mm" / "12.70 cm". Pass unit=false for the bare number.
function len(inches, metric, inchDecimals, withUnit) {
    var v = Number(inches)
    if (!isFinite(v))
        return String(inches)
    var unit = withUnit === false ? "" : null
    if (!metric)
        return v.toFixed(inchDecimals === undefined ? 4 : inchDecimals) + (unit === null ? " in" : "")
    var mm = v * MM_PER_IN
    if (Math.abs(mm) >= 100)
        return (mm / 10).toFixed(2) + (unit === null ? " cm" : "")
    return mm.toFixed(2) + (unit === null ? " mm" : "")
}

// Inch decimal string such as "-1.0000" -> display text.
function lenText(text, metric, withUnit) {
    return len(Number(text), metric, 4, withUnit)
}

function speedLabel(metric) {
    return metric ? "mm/s" : "IPM"
}

function speedText(ipm, metric) {
    var v = Number(ipm)
    if (!isFinite(v))
        return String(ipm)
    return metric ? (v * MM_PER_IN / 60).toFixed(2) : v.toFixed(3)
}
function lenUnit(inches, metric) {
    if (!metric)
        return "in"
    return Math.abs(Number(inches) * MM_PER_IN) >= 100 ? "cm" : "mm"
}

// Keyboard/edit-field input is always mm (metric) or in; returns inches.
function inchesFromInput(v, metric) {
    var n = Number(v)
    return metric ? n / MM_PER_IN : n
}

// Edit-field display value: mm (2 dec) in metric, inch decimals otherwise.
function editLen(inches, metric, inchDecimals) {
    var n = Number(inches)
    if (!isFinite(n))
        return ""
    return metric ? (n * MM_PER_IN).toFixed(2) : n.toFixed(inchDecimals === undefined ? 3 : inchDecimals)
}

function ipmFromInput(v, metric) {
    var n = Number(v)
    return metric ? n * 60 / MM_PER_IN : n
}
