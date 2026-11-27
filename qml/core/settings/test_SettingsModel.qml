// test_SettingsModel.qml — Phase 5.1 self-test for SettingsModel.js
// Verifies defaults, validateLocalSettings / validateUserSettings guards,
// the runPreviewDebugOverlaysEnabled file-key force-enable rule, load() default
// fallback, and the backup-guarded save() (incl. sandbox + refusal paths) using
// an in-memory fake IO backend — mock-safe (no file:// access).
//
// Run: $env:QML_XHR_ALLOW_FILE_READ=1; & "C:\Qt\6.10.1\mingw_64\bin\qml.exe" test_SettingsModel.qml
// Expect: RESULT N/N

import QtQuick 2.15
import "SettingsModel.js" as S

Item {
    width: 10; height: 10

    function makeFakeIo(store) {
        return {
            read: function (url) { return (url in store) ? store[url] : null },
            write: function (url, text) { store[url] = text; return true },
            exists: function (url) { return (url in store) }
        }
    }

    Component.onCompleted: {
        var pass = 0, total = 0
        function check(name, cond) { total++; if (cond) { pass++; console.log("PASS  " + name) } else console.log("FAIL  " + name) }
        function close(a, b) { return Math.abs(a - b) < 1e-9 }

        // ---- defaults ----------------------------------------------------------
        var dl = S.defaultLocalSettings()
        var du = S.defaultUserSettings()
        check("local default safetyPopupsEnabled true", dl.safetyPopupsEnabled === true)
        check("local default overlays true", dl.runPreviewDebugOverlaysEnabled === true)
        check("local default jogHoldTimeoutSeconds 300", dl.jogHoldTimeoutSeconds === 300)
        check("local default currentUnit INCH", dl.currentUnit === "INCH")
        check("local default backGaugeJogStep inches 0.1", close(dl.backGaugeJogStep.inchesValue, 0.1))
        check("local default contour classic", dl.runFlatPatternContourRenderer === "classic")
        check("local default tooling solid", dl.runToolingAppearance === "SOLID")
        check("user default materialClampRate 5.0", close(du.materialClampRate, 5.0))
        check("user default autoClampToBendEnabled true", du.autoClampToBendEnabled === true)
        check("user default defaultBackGaugeRPositionInch -0.25", close(du.defaultBackGaugeRPositionInch, -0.25))
        check("user default manualModeMaxTonnagePerRam 12.5", close(du.manualModeMaxTonnagePerRam, 12.5))
        check("user default measuredMaterialThickness invalid", du.measuredMaterialThickness
              && du.measuredMaterialThickness.valid === false)
        var legacyCal = S.validateUserSettings({ manualDieTopCalibration: { value: -1.78, valid: true } }, du)
        check("legacy calibration keeps value", close(legacyCal.manualDieTopCalibration.value, -1.78)
              && legacyCal.manualDieTopCalibration.valid === true)
        check("legacy calibration has no reference", legacyCal.manualDieTopCalibration.referenceThickness === null)
        check("missing measured thickness -> default", legacyCal.measuredMaterialThickness.valid === false)
        var fullCal = S.validateUserSettings({
            manualDieTopCalibration: { value: -1.78, valid: true, referenceThickness: 0.125,
                                       punchHeight: 4.059, dieHeight: 2.362, ramToTableOpening: 8.201 },
            measuredMaterialThickness: { value: 0.036, valid: true, onReferencePiece: true }
        }, du)
        check("calibration reference kept", close(fullCal.manualDieTopCalibration.referenceThickness, 0.125))
        check("calibration opening kept", close(fullCal.manualDieTopCalibration.ramToTableOpening, 8.201))
        check("measured thickness kept", close(fullCal.measuredMaterialThickness.value, 0.036)
              && fullCal.measuredMaterialThickness.onReferencePiece === true)
        var badMeasured = S.validateUserSettings({ measuredMaterialThickness: { value: -1, valid: true } }, du)
        check("non-positive measured thickness rejected", badMeasured.measuredMaterialThickness.valid === false)

        // ---- validateLocalSettings guards -------------------------------------
        // null -> defaults clone
        var vNull = S.validateLocalSettings(null, dl, null)
        check("local validate(null) -> defaults", vNull.currentUnit === "INCH" && vNull.jogHoldTimeoutSeconds === 300)

        // missing fields filled from defaults; bad numbers replaced
        var partial = { jogHoldTimeoutSeconds: -5, punchCoverageSideToleranceIn: -2, desktopRamToTableOpening: -1 }
        var rawPartial = JSON.stringify(partial) // contains no overlays key
        var vP = S.validateLocalSettings(partial, dl, rawPartial)
        check("local jogHoldTimeout<=0 -> default 300", vP.jogHoldTimeoutSeconds === 300)
        check("local punchCoverage<0 -> default 0.55", close(vP.punchCoverageSideToleranceIn, 0.55))
        check("local desktopRamToTable<0 -> default 0.0", close(vP.desktopRamToTableOpening, 0.0))
        check("local missing currentUnit filled", vP.currentUnit === "INCH")
        check("local missing jogRamSpeed filled", vP.jogRamSpeed && close(vP.jogRamSpeed.value, 5.0))
        check("local lastSelectedProgramId defaults to empty", vP.lastSelectedProgramId === "")
        check("local missing tooling appearance defaults solid", vP.runToolingAppearance === "SOLID")
        var translucent = S.validateLocalSettings({ runToolingAppearance: "translucent" }, dl, "{}")
        check("local tooling translucent accepted", translucent.runToolingAppearance === "TRANSLUCENT")
        check("local default measurement convergence off", dl.manualMeasurementConvergenceEnabled === false)
        check("local missing measurement convergence -> off", vP.manualMeasurementConvergenceEnabled === false)
        var convergence = S.validateLocalSettings({ manualMeasurementConvergenceEnabled: true }, dl, "{}")
        check("local measurement convergence true kept", convergence.manualMeasurementConvergenceEnabled === true)
        var badConvergence = S.validateLocalSettings({ manualMeasurementConvergenceEnabled: "yes" }, dl, "{}")
        check("local non-boolean measurement convergence -> off", badConvergence.manualMeasurementConvergenceEnabled === false)
        check("local default measuring tonnage 1.0", close(dl.manualMeasurementTonnage, 1.0))
        check("local missing measuring tonnage -> 1.0", close(vP.manualMeasurementTonnage, 1.0))
        var lowTonnage = S.validateLocalSettings({ manualMeasurementTonnage: 0.6 }, dl, "{}")
        check("local measuring tonnage 0.6 kept", close(lowTonnage.manualMeasurementTonnage, 0.6))
        var tooLow = S.validateLocalSettings({ manualMeasurementTonnage: 0.3 }, dl, "{}")
        check("local measuring tonnage below 0.5 -> 1.0", close(tooLow.manualMeasurementTonnage, 1.0))
        var tooHigh = S.validateLocalSettings({ manualMeasurementTonnage: 2.0 }, dl, "{}")
        check("local measuring tonnage above 1.0 -> 1.0", close(tooHigh.manualMeasurementTonnage, 1.0))

        // overlays key force-enable: raw WITHOUT the key forces true even if value was false
        var noKey = { runPreviewDebugOverlaysEnabled: false }
        // raw text deliberately omits the key string
        var vNoKey = S.validateLocalSettings(noKey, dl, "{ \"safetyPopupsEnabled\": false }")
        check("local overlays force-enabled when file lacks key", vNoKey.runPreviewDebugOverlaysEnabled === true)
        // overlays key present with false stays false
        var withKey = { runPreviewDebugOverlaysEnabled: false }
        var vWithKey = S.validateLocalSettings(withKey, dl, "{ \"runPreviewDebugOverlaysEnabled\": false }")
        check("local overlays stays false when file has key", vWithKey.runPreviewDebugOverlaysEnabled === false)

        // ---- validateUserSettings guards --------------------------------------
        var vUNull = S.validateUserSettings(null, du)
        check("user validate(null) -> defaults", close(vUNull.materialClampRate, 5.0))
        var uPartial = { materialClampRate: NaN, autoClampToBendDwellSec: NaN }
        var vU = S.validateUserSettings(uPartial, du)
        check("user NaN materialClampRate -> default 5.0", close(vU.materialClampRate, 5.0))
        check("user NaN dwellSec -> default", close(vU.autoClampToBendDwellSec, 3))
        check("user missing defaultBackGaugeRPositionInch filled", close(vU.defaultBackGaugeRPositionInch, -0.25))
        check("user missing jogStep filled", vU.jogStep && close(vU.jogStep.value, 0.1))
        check("user missing manualModeStartRamPosition filled", vU.manualModeStartRamPosition && close(vU.manualModeStartRamPosition.value, -1.0))

        // ---- load() with fake IO ----------------------------------------------
        var store = {}
        var io = makeFakeIo(store)
        // missing file -> defaults, loadedFromFile false
        var l1 = S.loadLocal("u://local", io)
        check("loadLocal missing -> defaults", l1.loadedFromFile === false && l1.settings.currentUnit === "INCH")
        // write a file then load it back
        store["u://local"] = JSON.stringify({ safetyPopupsEnabled: false, runPreviewDebugOverlaysEnabled: false, currentUnit: "MM" })
        var l2 = S.loadLocal("u://local", io)
        check("loadLocal existing parsed", l2.loadedFromFile === true && l2.settings.currentUnit === "MM" && l2.settings.safetyPopupsEnabled === false)
        check("loadLocal existing overlays honored (key present)", l2.settings.runPreviewDebugOverlaysEnabled === false)
        var lu = S.loadUser("u://user", io)
        check("loadUser missing -> defaults", lu.loadedFromFile === false && close(lu.settings.materialClampRate, 5.0))

        // NaN-tolerant parse
        store["u://nan"] = '{ "materialClampRate": NaN, "autoClampToBendEnabled": true }'
        var lnan = S.loadUser("u://nan", io)
        check("loadUser NaN-tolerant -> validated to default", close(lnan.settings.materialClampRate, 5.0) && lnan.settings.autoClampToBendEnabled === true)

        // ---- save() backup-guard + sandbox ------------------------------------
        var s2 = {}
        var io2 = makeFakeIo(s2)
        // first save (no pre-existing target) -> ok, no .bak
        var r1 = S.save("u://cfg", { a: 1 }, io2, {})
        check("save fresh ok", r1.ok === true && !("u://cfg.bak" in s2))
        check("save fresh wrote target", "u://cfg" in s2)
        // second save (target exists) -> writes .bak first
        var r2 = S.save("u://cfg", { a: 2 }, io2, {})
        check("save existing wrote backup", r2.ok === true && ("u://cfg.bak" in s2))
        check("save existing backup holds old content", s2["u://cfg.bak"].indexOf("\"a\": 1") >= 0 || s2["u://cfg.bak"].indexOf("\"a\":1") >= 0)
        // sandbox save never touches the real target
        var s3 = {}
        var io3 = makeFakeIo(s3)
        var r3 = S.save("u://real", { x: 9 }, io3, { sandbox: true, sandboxUrl: "u://sand" })
        check("save sandbox ok", r3.ok === true && r3.sandbox === true)
        check("save sandbox left real untouched", !("u://real" in s3) && ("u://sand" in s3))
        // backup refusal: io whose .bak write fails
        var refusingIo = {
            read: function (url) { return (url === "u://t") ? "OLD" : null },
            write: function (url, text) { return url.indexOf(".bak") >= 0 ? false : true }
        }
        var r4 = S.save("u://t", { y: 1 }, refusingIo, {})
        check("save refuses when backup fails", r4.ok === false && r4.reason === "backup-write-failed")
        // no-io path
        var r5 = S.save("u://x", {}, null, {})
        check("save no-io -> ok false", r5.ok === false && r5.reason === "no-io")

        // ---- coordinate system names ------------------------------------------
        var s4 = {}
        var io4 = makeFakeIo(s4)
        var cn0 = S.loadCoordinateSystemNames("u://cn", { G54: "Default" }, io4)
        check("coordNames missing -> defaults", cn0.G54 === "Default")
        S.saveCoordinateSystemNames("u://cn", { G54: "Front", G55: "Back" }, io4, {})
        var cn1 = S.loadCoordinateSystemNames("u://cn", {}, io4)
        check("coordNames round-trip", cn1.G54 === "Front" && cn1.G55 === "Back")

        console.log("RESULT " + pass + "/" + total)
        Qt.quit()
    }
}
