// SettingsModel.js — Phase 5.1
// Implements the legacy settings models:
//   - UserSettingsModel   (...UserSettingsModel)
//   - CoordinateSystemNamesModel (...CoordinateSystemNamesModel)
//
// The Java models wrap a config JSON object (LocalSettings / UserSettings) in an
// mvvmfx ModelWrapper and expose typed properties. Here we keep the same
// shapes as plain JS objects and reproduce exactly:
//   * the default values (from json/default-local-settings.json / default-user-settings.json),
//   * the validateSettings(...) null/finite/range guards,
//   * load (with default fallback) and save (commit + folder create) semantics.
//
// IO is pluggable so this runs mock-safe under qml.exe (in-memory fake) AND in the
// packaged app (C++ FileIo with backup-guard). Mirrors the EntityStorage IO contract:
//   io.read(url)  -> string | null
//   io.write(url, text) -> boolean
//   io.exists(url) -> boolean   (optional)
//
// .pragma library — pure functions + plain data, no QML object deps.
.pragma library

// ---------------------------------------------------------------------------
// Defaults (verbatim from the Java resource JSON files)
// ---------------------------------------------------------------------------

function defaultLocalSettings() {
    return {
        safetyPopupsEnabled: true,
        legacyRunUiEnabled: false,
        serialDiagnosticLogsEnabled: true,
        runPreviewDebugLogsEnabled: false,
        runPreviewDebugOverlaysEnabled: false,
        punchCoverageSideToleranceIn: 0.55,
        desktopFrameDeflectionCompensationEnabled: false,
        // Manual Calibrate / Measure: accept the average once stable instead
        // of always waiting for the fixed sample count (opt-in, for comparison).
        manualMeasurementConvergenceEnabled: false,
        // Manual Measure force (US tons, 0.5–1.0); Calibrate keeps its own.
        manualMeasurementTonnage: 1.0,
        desktopRamToTableOpening: 0.0,
        lastSelectedProgramId: "",
        lastSelectedProgramName: "",
        programLoadFolder: "",
        virtualInputMode: "ALWAYS",
        autoBackupEnabled: true,
        backupIntervalMinute: 10,
        jogHoldTimeoutSeconds: 300,
        displaySleepMinutes: 0,
        currentUnit: "INCH",
        backGaugeJogStep: { millimetersValue: 2.5, inchesValue: 0.1 },
        backGaugeJogSpeed: { millimetersValue: 2540, inchesValue: 100.0 },
        backGaugeContinuousJog: true,
        bendRamSpeed: { value: 5.0, unit: "INCH" },
        jogRamSpeed: { value: 5.0, unit: "INCH" },
        runFlatPatternContourRenderer: "classic",
        runLiveProjectionMode: "SIDE",
        runLiveCameraOrientation: "ISO_TOP_LEFT",
        runToolingAppearance: "SOLID",
        lastBendMode: "PROGRAM_BEND_MODE"
    }
}

function defaultUserSettings() {
    return {
        materialClampRate: 5.0,
        autoClampToBendEnabled: true,
        autoClampToBendDwellSec: 3,
        backGaugeRetractBetweenBendsInch: 2.0,
        backGaugeBumpOffDistanceInch: 0.25,
        defaultBackGaugeRPositionInch: -0.25,
        manualModeSafetyPlaneClearance: { value: 0.05, unit: "INCH" },
        manualModeStartRamPosition: { value: -1.0, unit: "INCH" },
        manualModeEndRamPosition: { value: -1.0001, unit: "INCH" },
        manualModeMaxTonnagePerRam: 12.5,
        jogStep: { value: 0.1, unit: "INCH" },
        manualModeMoveToPosition: { value: -2.0, unit: "INCH" },
        manualDieTopCalibration: { value: 0.0, unit: "INCH", valid: false },
        // Last thickness measured in Manual > Measure and released by the
        // operator for bend programs (USE IN PROGRAM).
        measuredMaterialThickness: { value: 0.0, unit: "INCH", valid: false }
    }
}

function _positiveOrNull(v) {
    var n = Number(v)
    return (v !== null && v !== undefined && isFinite(n) && n > 0) ? n : null
}

function _finiteOrNull(v) {
    var n = Number(v)
    return (v !== null && v !== undefined && isFinite(n)) ? n : null
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function _isFiniteNum(v) {
    return typeof v === "number" && isFinite(v)
}

function _clone(obj) {
    if (obj === null || obj === undefined)
        return obj
    return JSON.parse(JSON.stringify(obj))
}

// NaN-tolerant parse (data JSON may contain bare NaN literals; mirror EntityStorage).
function _parse(text) {
    if (text === null || text === undefined)
        return null
    var s = String(text)
    if (s.length > 0 && s.charCodeAt(0) === 0xFEFF)
        s = s.slice(1)
    s = s.replace(/:\s*NaN/g, ":null")
    try {
        return JSON.parse(s)
    } catch (e) {
        return null
    }
}

function _stringify(obj) {
    return JSON.stringify(obj, null, 4) + "\n"
}

// ---------------------------------------------------------------------------
// validateSettings — 1:1 with LocalSettingsModel.validateSettings(...)
// `rawText` is the on-disk text (for the localSettingsFileContains check);
// pass null when the file did not exist.
// ---------------------------------------------------------------------------

function validateLocalSettings(settings, defaults, rawText) {
    if (settings === null || settings === undefined)
        return _clone(defaults)
    if (settings.programLoadFolder === null || settings.programLoadFolder === undefined)
        settings.programLoadFolder = defaults.programLoadFolder
    if (settings.virtualInputMode === null || settings.virtualInputMode === undefined)
        settings.virtualInputMode = defaults.virtualInputMode
    if (settings.currentUnit === null || settings.currentUnit === undefined)
        settings.currentUnit = defaults.currentUnit
    if (settings.backGaugeJogStep === null || settings.backGaugeJogStep === undefined)
        settings.backGaugeJogStep = _clone(defaults.backGaugeJogStep)
    if (settings.backGaugeJogSpeed === null || settings.backGaugeJogSpeed === undefined)
        settings.backGaugeJogSpeed = _clone(defaults.backGaugeJogSpeed)
    if (settings.jogRamSpeed === null || settings.jogRamSpeed === undefined)
        settings.jogRamSpeed = _clone(defaults.jogRamSpeed)
    if (settings.bendRamSpeed === null || settings.bendRamSpeed === undefined)
        settings.bendRamSpeed = _clone(defaults.bendRamSpeed)
    if (!(_isFiniteNum(settings.jogHoldTimeoutSeconds) && settings.jogHoldTimeoutSeconds > 0))
        settings.jogHoldTimeoutSeconds = defaults.jogHoldTimeoutSeconds
    if ([0, 5, 10, 30].indexOf(Number(settings.displaySleepMinutes)) < 0)
        settings.displaySleepMinutes = defaults.displaySleepMinutes
    else
        settings.displaySleepMinutes = Number(settings.displaySleepMinutes)
    if (!_isFiniteNum(settings.punchCoverageSideToleranceIn) || settings.punchCoverageSideToleranceIn < 0.0)
        settings.punchCoverageSideToleranceIn = defaults.punchCoverageSideToleranceIn
    else if (settings.punchCoverageSideToleranceIn > 0.75)
        settings.punchCoverageSideToleranceIn = 0.75
    if (settings.lastSelectedProgramId === null || settings.lastSelectedProgramId === undefined)
        settings.lastSelectedProgramId = ""
    if (settings.lastSelectedProgramName === null || settings.lastSelectedProgramName === undefined)
        settings.lastSelectedProgramName = ""
    if (typeof settings.serialDiagnosticLogsEnabled !== "boolean")
        settings.serialDiagnosticLogsEnabled = defaults.serialDiagnosticLogsEnabled !== false
    if (typeof settings.manualMeasurementConvergenceEnabled !== "boolean")
        settings.manualMeasurementConvergenceEnabled = defaults.manualMeasurementConvergenceEnabled === true
    if (!_isFiniteNum(settings.manualMeasurementTonnage)
            || settings.manualMeasurementTonnage < 0.5 || settings.manualMeasurementTonnage > 1.0)
        settings.manualMeasurementTonnage = defaults.manualMeasurementTonnage
    // Production rendering keeps diagnostic overlays explicit opt-in. Older
    // settings files without the key inherit the safe, lower-cost default.
    var fileHadOverlaysKey = (typeof rawText === "string") && rawText.indexOf("\"runPreviewDebugOverlaysEnabled\"") >= 0
    if (!fileHadOverlaysKey)
        settings.runPreviewDebugOverlaysEnabled = defaults.runPreviewDebugOverlaysEnabled === true
    if (!_isFiniteNum(settings.desktopRamToTableOpening) || settings.desktopRamToTableOpening < 0.0)
        settings.desktopRamToTableOpening = defaults.desktopRamToTableOpening
    var liveProjectionMode = String(settings.runLiveProjectionMode || "").toUpperCase()
    settings.runLiveProjectionMode = liveProjectionMode === "ISOMETRIC" ? "ISOMETRIC" : "SIDE"
    var cameraOrientation = String(settings.runLiveCameraOrientation || "").toUpperCase()
    var cameraOrientations = [
        "ISO_TOP_LEFT", "ISO_TOP_RIGHT", "ISO_BOTTOM_LEFT", "ISO_BOTTOM_RIGHT",
        "ISO_TOP", "ISO_BOTTOM", "ISO_LEFT", "ISO_RIGHT", "ISO_FRONT", "ISO_BACK"
    ]
    settings.runLiveCameraOrientation = cameraOrientations.indexOf(cameraOrientation) >= 0
        ? cameraOrientation : "ISO_TOP_LEFT"
    var toolingAppearance = String(settings.runToolingAppearance || "").toUpperCase()
    settings.runToolingAppearance = toolingAppearance === "TRANSLUCENT" ? "TRANSLUCENT" : "SOLID"
    var validBendModes = ["SINGLE_BEND_MODE", "SINGLE_BEND_REPEAT", "PROGRAM_BEND_MODE", "PROGRAM_BEND_LOOP"]
    if (validBendModes.indexOf(settings.lastBendMode) < 0)
        settings.lastBendMode = defaults.lastBendMode || "PROGRAM_BEND_MODE"
    return settings
}

// validateSettings — 1:1 with UserSettingsModel.validateSettings(...)
function validateUserSettings(settings, defaults) {
    if (settings === null || settings === undefined)
        return _clone(defaults)
    if (settings.backGaugeBumpOffDistanceInch === null || settings.backGaugeBumpOffDistanceInch === undefined)
        settings.backGaugeBumpOffDistanceInch = defaults.backGaugeBumpOffDistanceInch
    if (settings.defaultBackGaugeRPositionInch === null || settings.defaultBackGaugeRPositionInch === undefined) {
        var dv = defaults.defaultBackGaugeRPositionInch
        settings.defaultBackGaugeRPositionInch = (dv === null || dv === undefined) ? -0.25 : dv
    }
    if (settings.backGaugeRetractBetweenBendsInch === null || settings.backGaugeRetractBetweenBendsInch === undefined)
        settings.backGaugeRetractBetweenBendsInch = defaults.backGaugeRetractBetweenBendsInch
    if (!_isFiniteNum(settings.autoClampToBendDwellSec)) // Java: Double.isNaN(...)
        settings.autoClampToBendDwellSec = defaults.autoClampToBendDwellSec
    if (!_isFiniteNum(settings.materialClampRate))
        settings.materialClampRate = defaults.materialClampRate
    if (settings.manualModeSafetyPlaneClearance === null || settings.manualModeSafetyPlaneClearance === undefined)
        settings.manualModeSafetyPlaneClearance = _clone(defaults.manualModeSafetyPlaneClearance)
    if (settings.manualModeStartRamPosition === null || settings.manualModeStartRamPosition === undefined)
        settings.manualModeStartRamPosition = _clone(defaults.manualModeStartRamPosition)
    if (settings.manualModeEndRamPosition === null || settings.manualModeEndRamPosition === undefined)
        settings.manualModeEndRamPosition = _clone(defaults.manualModeEndRamPosition)
    if (settings.manualModeMaxTonnagePerRam === null || settings.manualModeMaxTonnagePerRam === undefined)
        settings.manualModeMaxTonnagePerRam = _clone(defaults.manualModeMaxTonnagePerRam)
    if (settings.jogStep === null || settings.jogStep === undefined)
        settings.jogStep = _clone(defaults.jogStep)
    if (settings.manualModeMoveToPosition === null || settings.manualModeMoveToPosition === undefined)
        settings.manualModeMoveToPosition = _clone(defaults.manualModeMoveToPosition)
    if (settings.manualDieTopCalibration === null
            || settings.manualDieTopCalibration === undefined
            || !_isFiniteNum(Number(settings.manualDieTopCalibration.value))) {
        settings.manualDieTopCalibration = _clone(defaults.manualDieTopCalibration)
    } else {
        var calibration = settings.manualDieTopCalibration
        calibration.value = Number(calibration.value)
        calibration.unit = "INCH"
        calibration.valid = calibration.valid === true
        // Optional metadata (older files lack it): the reference piece and the
        // tooling recorded when the die top was qualified.
        calibration.referenceThickness = _positiveOrNull(calibration.referenceThickness)
        calibration.punchHeight = _positiveOrNull(calibration.punchHeight)
        calibration.dieHeight = _positiveOrNull(calibration.dieHeight)
        calibration.ramToTableOpening = _positiveOrNull(calibration.ramToTableOpening)
        calibration.contactPosition = _finiteOrNull(calibration.contactPosition)
        calibration.punchId = calibration.punchId ? String(calibration.punchId) : ""
        calibration.punchName = calibration.punchName ? String(calibration.punchName) : ""
        calibration.dieId = calibration.dieId ? String(calibration.dieId) : ""
        calibration.dieName = calibration.dieName ? String(calibration.dieName) : ""
        calibration.calibratedAt = calibration.calibratedAt ? String(calibration.calibratedAt) : ""
    }
    var measured = settings.measuredMaterialThickness
    var measuredValue = measured ? _positiveOrNull(measured.value) : null
    if (measured === null || measured === undefined || measuredValue === null) {
        settings.measuredMaterialThickness = _clone(defaults.measuredMaterialThickness
            || { value: 0.0, unit: "INCH", valid: false })
    } else {
        measured.value = measuredValue
        measured.unit = "INCH"
        measured.valid = measured.valid === true
        measured.onReferencePiece = measured.onReferencePiece === true
        measured.referenceThickness = _positiveOrNull(measured.referenceThickness)
        measured.measuredAt = measured.measuredAt ? String(measured.measuredAt) : ""
    }
    return settings
}

// ---------------------------------------------------------------------------
// load — read + validate + default-fallback (mirrors *.loadSettings)
//   url      : settings file URL
//   defaults : default object (defaultLocalSettings()/defaultUserSettings())
//   kind     : "local" | "user" (selects validator)
//   io       : { read(url) -> string|null }
// returns { settings, loadedFromFile, rawText }
// ---------------------------------------------------------------------------

function load(url, defaults, kind, io) {
    var rawText = (io && typeof io.read === "function") ? io.read(url) : null
    var parsed = _parse(rawText)
    if (parsed === null) {
        // file not found / unparseable → defaults (Java: set+reload defaults)
        return { settings: _clone(defaults), loadedFromFile: false, rawText: null }
    }
    var validated = (kind === "user")
        ? validateUserSettings(parsed, defaults)
        : validateLocalSettings(parsed, defaults, rawText)
    return { settings: validated, loadedFromFile: true, rawText: rawText }
}

function loadLocal(url, io) {
    return load(url, defaultLocalSettings(), "local", io)
}

function loadUser(url, io) {
    return load(url, defaultUserSettings(), "user", io)
}

// ---------------------------------------------------------------------------
// save — commit + write (mirrors *.saveSettings). Backup-guarded when the IO
// backend supports read/exists (writes <file>.bak FIRST and refuses the
// production overwrite if the backup cannot be written). Sandbox mode redirects
// the write and never touches the real file.
//   opts: { sandbox: bool, sandboxUrl: string }
// returns { ok, sandbox, url, reason? }
// ---------------------------------------------------------------------------

function save(url, settings, io, opts) {
    opts = opts || {}
    if (!io || typeof io.write !== "function")
        return { ok: false, reason: "no-io", url: url }
    var text = _stringify(settings)
    if (opts.sandbox) {
        var sUrl = opts.sandboxUrl || (url + ".sandbox")
        var sOk = io.write(sUrl, text)
        return { ok: sOk === true, sandbox: true, url: sUrl }
    }
    // backup-guard: if a target already exists, write a .bak first.
    var existing = null
    if (typeof io.read === "function")
        existing = io.read(url)
    var targetExists = (existing !== null && existing !== undefined && String(existing).length > 0)
    if (targetExists) {
        var bakOk = io.write(url + ".bak", existing)
        if (bakOk !== true)
            return { ok: false, reason: "backup-write-failed", url: url }
    }
    var ok = io.write(url, text)
    return { ok: ok === true, sandbox: false, url: url }
}

// ---------------------------------------------------------------------------
// CoordinateSystemNamesModel — map of GrblCoordinateSystem -> display name.
// Container is { list: { G54: "...", ... } } in Java. We store the inner map.
// ---------------------------------------------------------------------------

function loadCoordinateSystemNames(url, defaultsMap, io) {
    var rawText = (io && typeof io.read === "function") ? io.read(url) : null
    var parsed = _parse(rawText)
    if (parsed === null)
        return _clone(defaultsMap || {})
    var map = parsed.list || parsed.map || parsed
    if (map === null || typeof map !== "object")
        return _clone(defaultsMap || {})
    return map
}

function saveCoordinateSystemNames(url, map, io, opts) {
    return save(url, { list: map }, io, opts)
}
