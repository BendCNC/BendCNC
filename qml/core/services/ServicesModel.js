// ServicesModel.js — Phase 5.2 (mock-safe)
// Deterministic cores of the legacy background services, ported so the Qt app can
// model the same step/progress/backup semantics WITHOUT performing real host
// operations (no cp/mv, no downloads, no serial flashing). The real side effects
// are isolated behind a pluggable executor/io so the packaged app can wire them
// later; by default everything is a safe no-op mock.
//
// Ported from:
//   - SoftwareUpdateService (3-step progress machine; UpdateStep enum)
//   - EntityStorageOrganizer backup logic (B<yyMMddHHmm><name>.zip naming, parse,
//     list sorted newest-first, create/delete/restore)
//   - FirmwareUpdaterService is intentionally deferred to Phase 6 (serial hardware).
//
// .pragma library — pure functions + plain data.
.pragma library

// ===========================================================================
// Software update progress machine (1:1 with SoftwareUpdateService steps)
// ===========================================================================

// UpdateStep enum (verbatim).
var UpdateStep = {
    UPDATE_STARTED: "UPDATE_STARTED",
    UPDATE_IN_PROGRESS: "UPDATE_IN_PROGRESS",
    UPDATE_FINISHED: "UPDATE_FINISHED"
}

// The exact progress fractions the Java service publishes.
//   fromPath: STARTED 0.2, IN_PROGRESS 0.4, 0.6, then replace 0.9, 1.0, FINISHED 1.0
//   fromUrl : STARTED 0.0, (download...) then replace 0.9, 1.0, FINISHED 1.0
function updateProgressSequence(source) {
    if (source === "url") {
        return [
            { step: UpdateStep.UPDATE_STARTED, progress: 0.0 },
            { step: UpdateStep.UPDATE_IN_PROGRESS, progress: 0.9 },
            { step: UpdateStep.UPDATE_IN_PROGRESS, progress: 1.0 },
            { step: UpdateStep.UPDATE_FINISHED, progress: 1.0 }
        ]
    }
    // default "path"
    return [
        { step: UpdateStep.UPDATE_STARTED, progress: 0.2 },
        { step: UpdateStep.UPDATE_IN_PROGRESS, progress: 0.4 },
        { step: UpdateStep.UPDATE_IN_PROGRESS, progress: 0.6 },
        { step: UpdateStep.UPDATE_IN_PROGRESS, progress: 0.9 },
        { step: UpdateStep.UPDATE_IN_PROGRESS, progress: 1.0 },
        { step: UpdateStep.UPDATE_FINISHED, progress: 1.0 }
    ]
}

// Run the update as a mock: synchronously walks the sequence, calling
// onProgress(step, progress) for each entry, then onSuccess(). The real
// executor (cp/mv/download) is NOT invoked unless an `executor` with
// .run(kind, arg) is supplied AND returns truthy for each side effect.
// Returns { busyRejected:false, steps:[...], success:true|false }.
function runSoftwareUpdate(source, arg, handlers, executor) {
    handlers = handlers || {}
    var seq = updateProgressSequence(source)
    var emitted = []
    var failed = false
    for (var i = 0; i < seq.length; i++) {
        // Side-effect points (mock no-op by default): just before the replace step
        // (progress 0.9) the Java code runs the cp/mv (or download). If a real
        // executor is provided and it fails, publish onFailure and stop.
        if (executor && typeof executor.run === "function" && seq[i].progress === 0.9) {
            var ok = executor.run(source === "url" ? "download+replace" : "copy+replace", arg)
            if (ok !== true) {
                failed = true
                if (typeof handlers.onFailure === "function") handlers.onFailure()
                break
            }
        }
        emitted.push(seq[i])
        if (typeof handlers.onProgress === "function")
            handlers.onProgress(seq[i].step, seq[i].progress)
    }
    if (!failed && typeof handlers.onSuccess === "function")
        handlers.onSuccess()
    return { busyRejected: false, steps: emitted, success: !failed }
}

// ===========================================================================
// Backup model (1:1 with EntityStorageOrganizer naming/parse/list)
// ===========================================================================

// DATE_FORMATTER = "yyMMddHHmm" (10 digits).
function formatBackupDate(date) {
    var d = date || new Date()
    function p2(n) { return (n < 10 ? "0" : "") + n }
    var yy = p2(d.getFullYear() % 100)
    var MM = p2(d.getMonth() + 1)
    var dd = p2(d.getDate())
    var HH = p2(d.getHours())
    var mm = p2(d.getMinutes())
    return yy + MM + dd + HH + mm
}

// Parse a 10-digit yyMMddHHmm token back into a Date (best-effort, local time).
function parseBackupDate(token) {
    if (typeof token !== "string" || !/^\d{10}$/.test(token))
        return null
    var yy = parseInt(token.substr(0, 2), 10)
    var MM = parseInt(token.substr(2, 2), 10)
    var dd = parseInt(token.substr(4, 2), 10)
    var HH = parseInt(token.substr(6, 2), 10)
    var mm = parseInt(token.substr(8, 2), 10)
    // 2-digit year → 2000+yy (matches the app's expected century).
    return new Date(2000 + yy, MM - 1, dd, HH, mm, 0, 0)
}

// Build the backup file name: B<date>.zip or B<date><name>.zip
function backupFileName(name, date) {
    var dateString = formatBackupDate(date)
    var trimmed = (typeof name === "string") ? name : ""
    var blank = trimmed.replace(/\s+/g, "").length === 0
    return blank ? ("B" + dateString + ".zip") : ("B" + dateString + trimmed + ".zip")
}

// NAME_PATTERN = B(?<date>\d{10})(?<name>.*).zip
// Returns { name, dateToken, date, fileName } or null if not a backup file.
function parseBackupFromFileName(fileName) {
    if (typeof fileName !== "string")
        return null
    var m = fileName.match(/^B(\d{10})(.*)\.zip$/)
    if (!m)
        return null
    var dateToken = m[1]
    var rawName = m[2] || ""
    return {
        name: rawName,
        dateToken: dateToken,
        date: parseBackupDate(dateToken),
        fileName: fileName,
        isAutomatic: rawName.length === 0  // auto backups have no name suffix
    }
}

// Build the in-memory backup list from a list of file names, sorted newest-first
// (Comparator.comparing(Backup::date).reversed()).
function buildBackupList(fileNames) {
    var list = []
    for (var i = 0; i < (fileNames ? fileNames.length : 0); i++) {
        var b = parseBackupFromFileName(fileNames[i])
        if (b !== null)
            list.push(b)
    }
    list.sort(function (a, b) {
        var ta = a.date ? a.date.getTime() : 0
        var tb = b.date ? b.date.getTime() : 0
        return tb - ta  // reversed (newest first)
    })
    return list
}

// Mock "create backup": resolves the target file name, refuses if it already
// exists (matches the Java guard), and returns a backup descriptor. The actual
// zip is produced only if a real `zipWriter(fileName, sourceFiles)` is supplied.
//   existingNames: array of file names already in the backup folder
//   returns { ok, reason?, backup? }
function createBackup(name, existingNames, date, zipWriter, sourceFiles) {
    var fileName = backupFileName(name, date)
    var existing = existingNames || []
    for (var i = 0; i < existing.length; i++) {
        if (existing[i] === fileName)
            return { ok: false, reason: "already-exists", fileName: fileName }
    }
    if (zipWriter && typeof zipWriter === "function") {
        var ok = zipWriter(fileName, sourceFiles || [])
        if (ok !== true)
            return { ok: false, reason: "zip-failed", fileName: fileName }
    }
    return { ok: true, fileName: fileName, backup: parseBackupFromFileName(fileName) }
}

// Mock "delete backup": removes the matching entry from a list, optionally
// invoking a real deleter(fileName). Returns the new list.
function deleteBackupFromList(list, fileName, deleter) {
    if (deleter && typeof deleter === "function")
        deleter(fileName)
    var out = []
    for (var i = 0; i < (list ? list.length : 0); i++) {
        if (list[i].fileName !== fileName)
            out.push(list[i])
    }
    return out
}
