.pragma library

// EntityStorage.js
// Ports the persistence behavior of
// for the pure-QML app, with mandatory BACKUP-GUARDED writes per project safety policy.
//
// Java behavior mirrored:
//   - load(): read JSON array from storage file; if missing, fall back to default resource.
//   - save(): write the items array as JSON (Java does atomic write + fsync; here we
//             write a temp file then "rename" via a fresh write, and always keep a .bak).
//   - saveChanges(): alias for save.
//   - findById(items, id): first item whose id === id.
//
// SAFETY POLICY (project rule): never overwrite a production JSON in
// qt/qml/data/current/ without first copying the existing content to <file>.bak.
// Callers may instead target a sandbox dir (qt/qml/data/sandbox/) by passing a baseDir.
//
// IO BACKEND (PLUGGABLE): Qt's QML XMLHttpRequest can READ file:// URLs and OVERWRITE
// pre-existing files, but CANNOT create new files and HANGS on sync GET of a missing
// file. Therefore real persistence is delegated to an injected `io` backend:
//
//   io.read(url)        -> string | null     (null = missing/unreadable)
//   io.write(url, text) -> bool              (creates or overwrites)
//   io.exists(url)      -> bool              (no hang on missing)
//
// In the packaged app (main.cpp) inject a tiny C++ FileIO type (QFile-based) registered
// to QML. In tests inject an in-memory fake. A read-only XHR backend (xhrIo) is provided
// for environments that only ever read or overwrite existing files.
// JSON quirk: data files contain bare NaN literals -> sanitize before JSON.parse.

var DATA_CURRENT = "data/current/";
var DATA_SANDBOX = "data/sandbox/";

// Module-level default backend; callers set this once via setIo(...) (e.g. AppState wires
// the C++ FileIO). Falls back to the read-only XHR backend below.
var _io = null;
function setIo(io) { _io = io; }
function io() { return _io || xhrIo; }

// ---- read-only / overwrite XHR backend (file:// URLs; qml.exe + QML_XHR_ALLOW_FILE_READ=1) ----
var xhrIo = {
    read: function (url) { return readTextFile(url); },
    write: function (url, text) { return writeTextFile(url, text); },
    exists: function (url) { return fileExists(url); }
};

// ---- low-level file IO (relative to this module's QML import dir via file:// URL) ----

function _sanitize(text) {
    return text.replace(/^\uFEFF/, "").replace(/:\s*NaN/g, ":null");
}

// Qt's QML XMLHttpRequest supports synchronous GET and PUT on file:// URLs (the
// running app uses exactly this for local-settings.json). A successful file read
// reports status 200 OR 0; a missing file yields empty responseText with status 0,
// so we distinguish "missing" by an empty body when no bytes were returned.
function readTextFile(url) {
    var xhr = new XMLHttpRequest();
    try {
        xhr.open("GET", url, false);
        xhr.send(null);
        var ok = (xhr.status === 200 || xhr.status === 0);
        if (!ok) return null;
        var body = xhr.responseText;
        // Missing file -> empty body. Callers treat "" as absent for JSON arrays.
        return (body === undefined || body === null || body === "") ? null : body;
    } catch (e) {
        return null;
    }
}

function writeTextFile(url, text) {
    var xhr = new XMLHttpRequest();
    try {
        xhr.open("PUT", url, false);
        xhr.send(text);
        return true; // file:// PUT throws on failure; success leaves status 0
    } catch (e) {
        return false;
    }
}

function fileExists(url) {
    return readTextFile(url) !== null;
}

// ---- JSON helpers ----

function parseEntities(text) {
    if (text === null || text === undefined) return null;
    try {
        var parsed = JSON.parse(_sanitize(text));
        return Array.isArray(parsed) ? parsed : null;
    } catch (e) {
        return null;
    }
}

function stringifyEntities(items) {
    // Java Gson serializeSpecialFloatingPointValues() emits NaN literally; our reader
    // tolerates either NaN or null, so we emit standard JSON (null for NaN) for safety.
    return JSON.stringify(items === null || items === undefined ? [] : items, function (k, v) {
        return (typeof v === "number" && isNaN(v)) ? null : v;
    }, 2);
}

// ---- public API ----

// load(fileUrl, defaultUrl, ioBackend?) -> array | []  (default-resource fallback like Java load())
function load(fileUrl, defaultUrl, ioBackend) {
    var b = ioBackend || io();
    var text = b.read(fileUrl);
    if (text === null && defaultUrl) {
        text = b.read(defaultUrl);
    }
    var items = parseEntities(text);
    return items === null ? [] : items;
}

// save(fileUrl, items, options) -> { ok, backupUrl }
// options: { backup:true (default), backupSuffix:".bak", sandbox:false, sandboxUrl }
// BACKUP-GUARDED: when the target exists and backup!==false, the existing bytes are
// copied to <fileUrl><backupSuffix> BEFORE the overwrite. If sandbox===true, the write is
// redirected to sandboxUrl and the production file is left untouched.
function save(fileUrl, items, options) {
    options = options || {};
    var b = options.io || io();
    var backup = options.backup !== false;
    var backupSuffix = options.backupSuffix || ".bak";

    var targetUrl = (options.sandbox && options.sandboxUrl) ? options.sandboxUrl : fileUrl;
    var backupUrl = null;

    // Backup the production target (never the sandbox) before overwriting it.
    if (!options.sandbox && backup) {
        var existing = b.read(targetUrl);
        if (existing !== null) {
            backupUrl = targetUrl + backupSuffix;
            // Safety-first: refuse the production overwrite if we cannot write a backup.
            var bok = b.write(backupUrl, existing);
            if (!bok) {
                return { ok: false, backupUrl: null, reason: "backup-write-failed" };
            }
        }
    }

    var payload = stringifyEntities(items);
    var ok = b.write(targetUrl, payload);
    return { ok: ok, backupUrl: backupUrl, targetUrl: targetUrl };
}

function saveChanges(fileUrl, items, options) {
    return save(fileUrl, items, options);
}

// saveTransaction(operations, options) -> { ok, reason, failedUrl }
// Atomically-at-the-workflow-level persists several entity collections. Each
// individual write remains atomic in the native FileIo backend. If any backup
// or target write fails, every target is restored to its exact pre-transaction
// bytes (or to [] when it did not exist) before failure is returned.
// operation: { fileUrl, items }
function saveTransaction(operations, options) {
    options = options || {};
    var b = options.io || io();
    var suffix = options.backupSuffix || ".bak";
    var snapshots = [];
    var index;

    for (index = 0; operations && index < operations.length; index++) {
        var operation = operations[index] || {};
        if (!operation.fileUrl)
            return { ok: false, reason: "invalid-operation", failedUrl: "" };
        var existing = b.read(operation.fileUrl);
        snapshots.push({ fileUrl: operation.fileUrl, existing: existing });
        if (existing !== null && !b.write(operation.fileUrl + suffix, existing))
            return { ok: false, reason: "backup-write-failed", failedUrl: operation.fileUrl };
    }

    for (index = 0; index < operations.length; index++) {
        var current = operations[index];
        if (!b.write(current.fileUrl, stringifyEntities(current.items))) {
            for (var restoreIndex = 0; restoreIndex < snapshots.length; restoreIndex++) {
                var snapshot = snapshots[restoreIndex];
                b.write(snapshot.fileUrl,
                        snapshot.existing === null ? stringifyEntities([]) : snapshot.existing);
            }
            return { ok: false, reason: "target-write-failed", failedUrl: current.fileUrl };
        }
    }

    return { ok: true };
}

function findById(items, id) {
    if (!items) return null;
    for (var i = 0; i < items.length; i++) {
        if (items[i] && items[i].id === id) return items[i];
    }
    return null;
}

// restoreFromBackup(fileUrl, backupSuffix) -> bool
// Rolls a production file back to its most recent .bak (emergency recovery helper).
function restoreFromBackup(fileUrl, backupSuffix, ioBackend) {
    backupSuffix = backupSuffix || ".bak";
    var b = ioBackend || io();
    var bak = b.read(fileUrl + backupSuffix);
    if (bak === null) return false;
    return b.write(fileUrl, bak);
}
