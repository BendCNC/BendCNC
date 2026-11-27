// BackGauge.js — Phase 6.3: Implements the back-gauge GRBL command layer
//
// The back gauge is a standard GRBL device on its own serial port: it accepts
// G-code lines (units G20/G21, absolute G90 / incremental G91, work coordinate
// systems G54..G59, feed moves G1, homing $H) and reports "<state|MPos:..|WPos:..>"
// GRBL status lines. This module builds the exact command strings the Java
// operations emit and decodes GRBL status reports. PURE (no IO) — a device
// (mock or C++ QSerialPort) transmits the strings and feeds status lines back.
//
// Verified by test_BackGauge.qml.

.pragma library

// ---- enums (1:1 with GrblCoordinateSystem / expcore.geometry.Axis) ----------
var CoordinateSystem = {
    G54: { name: "G54", altCode: "P1" },
    G55: { name: "G55", altCode: "P2" },
    G56: { name: "G56", altCode: "P3" },
    G57: { name: "G57", altCode: "P4" },
    G58: { name: "G58", altCode: "P5" },
    G59: { name: "G59", altCode: "P6" }
}
var Axis = { X: "X", Y: "Y", Z: "Z" }
var Unit = { INCH: "INCH", MILLIMETER: "MILLIMETER" }

function _unitWord(unit) { return unit === Unit.INCH ? "G20" : "G21" }
function _csName(cs) { return typeof cs === "string" ? cs : (cs && cs.name ? cs.name : String(cs)) }
function _f4(n) { return Number(n).toFixed(4) }
function _f2(n) { return Number(n).toFixed(2) }

// ---- command builders -------------------------------------------------------
// BackGaugeMoveToOperation: emits TWO G1 lines, ordered by current X vs target X.
// If retracting (currentX > targetX) move Y first, then X; else X first, then Y.
// Mirrors "%s G90 %s G1 X%.4f F%.2f" / "...Y%.4f...".
function moveToCommands(unit, coordinateSystem, currentWorkX, targetX, targetY, speed) {
    var u = _unitWord(unit)
    var cs = _csName(coordinateSystem)
    var xLine = u + " G90 " + cs + " G1 X" + _f4(targetX) + " F" + _f2(speed)
    var yLine = u + " G90 " + cs + " G1 Y" + _f4(targetY) + " F" + _f2(speed)
    if (currentWorkX > targetX)
        return [yLine, xLine]   // retract: Y first then X
    return [xLine, yLine]       // advance: X first then Y
}

// BackGaugeBumpOperation: single-axis incremental move.
// Mirrors "%s G91 %s %s %.4f F %.2f" (note the space before the feed value).
function bumpCommand(unit, coordinateSystem, axis, value, speed) {
    return _unitWord(unit) + " G91 " + _csName(coordinateSystem) + " " + axis
        + " " + _f4(value) + " F " + _f2(speed)
}

// Java's ContinuousJogOperation repeatedly emits short real-time jog lines and
// sends GRBL's jog-cancel byte when the operator releases the button.
function jogCommand(unit, coordinateSystem, axis, value, speed) {
    return "$J=" + _unitWord(unit) + " G91 " + _csName(coordinateSystem) + " " + axis
        + _f4(value) + " F" + _f2(speed)
}

function jogCancelCommand() { return String.fromCharCode(0x85) }
function feedHoldCommand() { return "!" }
function softResetCommand() { return "\x18" }

// BackGaugeHomingOperation: GRBL run-homing-cycle.
function homingCommand() { return "$H" }

// ---- GRBL status decode -----------------------------------------------------
// Decodes "<State|MPos:x,y,z|WPos:x,y,z|...>" (and the Bf/FS/WCO extras). Returns
// { state, mpos:{x,y,z}, wpos:{x,y,z}, ... } or null if not a GRBL status line.
function decodeStatus(line) {
    if (line === undefined || line === null) return null
    var s = String(line).trim()
    if (s.charAt(0) !== "<" || s.charAt(s.length - 1) !== ">") return null
    var body = s.substring(1, s.length - 1)
    var parts = body.split("|")
    if (parts.length === 0) return null
    var out = { state: parts[0], mpos: null, wpos: null, wco: null, feed: NaN, fields: {} }
    for (var i = 1; i < parts.length; i++) {
        var seg = parts[i]
        var c = seg.indexOf(":")
        if (c < 0) { out.fields[seg] = true; continue }
        var key = seg.substring(0, c)
        var val = seg.substring(c + 1)
        if (key === "MPos") out.mpos = _xyz(val)
        else if (key === "WPos") out.wpos = _xyz(val)
        else if (key === "WCO") out.wco = _xyz(val)
        else if (key === "FS" || key === "F") out.feed = parseFloat(val.split(",")[0])
        else out.fields[key] = val
    }
    // GRBL reports either WPos or MPos+WCO; derive WPos when only MPos+WCO present.
    if (!out.wpos && out.mpos && out.wco) {
        out.wpos = { x: out.mpos.x - out.wco.x, y: out.mpos.y - out.wco.y, z: out.mpos.z - out.wco.z }
    }
    return out
}

function _xyz(triple) {
    var p = String(triple).split(",")
    return {
        x: p.length > 0 ? parseFloat(p[0]) : NaN,
        y: p.length > 1 ? parseFloat(p[1]) : NaN,
        z: p.length > 2 ? parseFloat(p[2]) : NaN
    }
}

// ---- coordinate-system name helpers (pairs with SettingsModel coord names) --
// Resolve a friendly name from a CoordinateSystemNames map (G54.."...").
function coordinateSystemDisplayName(namesMap, cs) {
    var key = _csName(cs)
    if (namesMap && namesMap.list && namesMap.list[key]) return namesMap.list[key]
    if (namesMap && namesMap[key]) return namesMap[key]
    return key
}
