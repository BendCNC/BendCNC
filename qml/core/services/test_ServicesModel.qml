// test_ServicesModel.qml — Phase 5.2 self-test for ServicesModel.js
// Verifies the software-update progress sequences (path/url + exact fractions),
// the mock update runner (success + executor-failure), and the backup model
// (date format, name build/parse, list sort newest-first, create refusal on
// duplicate, delete). All mock-safe — no host operations.
//
// Run: $env:QML_XHR_ALLOW_FILE_READ=1; & "C:\Qt\6.10.1\mingw_64\bin\qml.exe" test_ServicesModel.qml
// Expect: RESULT N/N

import QtQuick 2.15
import "ServicesModel.js" as Svc

Item {
    width: 10; height: 10

    Component.onCompleted: {
        var pass = 0, total = 0
        function check(name, cond) { total++; if (cond) { pass++; console.log("PASS  " + name) } else console.log("FAIL  " + name) }
        function close(a, b) { return Math.abs(a - b) < 1e-9 }

        // ---- update progress sequences ---------------------------------------
        var seqPath = Svc.updateProgressSequence("path")
        check("path seq starts STARTED 0.2", seqPath[0].step === "UPDATE_STARTED" && close(seqPath[0].progress, 0.2))
        check("path seq ends FINISHED 1.0", seqPath[seqPath.length - 1].step === "UPDATE_FINISHED" && close(seqPath[seqPath.length - 1].progress, 1.0))
        check("path seq has 6 entries", seqPath.length === 6)
        check("path seq includes 0.9 replace point", seqPath.some(function (e) { return close(e.progress, 0.9) }))

        var seqUrl = Svc.updateProgressSequence("url")
        check("url seq starts STARTED 0.0", seqUrl[0].step === "UPDATE_STARTED" && close(seqUrl[0].progress, 0.0))
        check("url seq ends FINISHED 1.0", seqUrl[seqUrl.length - 1].step === "UPDATE_FINISHED")
        check("url seq has 4 entries", seqUrl.length === 4)

        // ---- mock update runner: success -------------------------------------
        var emitted = []
        var sawSuccess = false, sawFailure = false
        var res = Svc.runSoftwareUpdate("path", "/tmp/app.jar", {
            onProgress: function (step, p) { emitted.push({ step: step, p: p }) },
            onSuccess: function () { sawSuccess = true },
            onFailure: function () { sawFailure = true }
        }, null) // null executor -> pure mock (no side effects)
        check("mock update emitted full sequence", emitted.length === 6)
        check("mock update success fired", sawSuccess === true && sawFailure === false)
        check("mock update result.success", res.success === true && res.busyRejected === false)

        // ---- mock update runner: executor failure ----------------------------
        var emitted2 = [], success2 = false, failure2 = false
        var failingExecutor = { run: function (kind, arg) { return false } }
        var res2 = Svc.runSoftwareUpdate("url", "http://x/app.jar", {
            onProgress: function (step, p) { emitted2.push(p) },
            onSuccess: function () { success2 = true },
            onFailure: function () { failure2 = true }
        }, failingExecutor)
        check("update halts at failing replace (no FINISHED)", emitted2.indexOf(1.0) === -1 || res2.success === false)
        check("update failure fired, success not", failure2 === true && success2 === false)
        check("update result.success false", res2.success === false)

        // a passing executor should let it finish
        var success3 = false
        var okExecutor = { run: function (kind, arg) { return true } }
        var res3 = Svc.runSoftwareUpdate("path", "/tmp/app.jar", { onSuccess: function () { success3 = true } }, okExecutor)
        check("update with ok executor finishes", res3.success === true && success3 === true)

        // ---- backup date format/parse ----------------------------------------
        var d = new Date(2026, 5, 21, 9, 7) // 2026-06-21 09:07
        check("formatBackupDate 10 digits", /^\d{10}$/.test(Svc.formatBackupDate(d)))
        check("formatBackupDate value", Svc.formatBackupDate(d) === "2606210907")
        var pd = Svc.parseBackupDate("2606210907")
        check("parseBackupDate round-trip", pd && pd.getFullYear() === 2026 && pd.getMonth() === 5 && pd.getDate() === 21 && pd.getHours() === 9 && pd.getMinutes() === 7)
        check("parseBackupDate rejects non-10-digit", Svc.parseBackupDate("123") === null)

        // ---- backup file name build/parse ------------------------------------
        check("backupFileName named", Svc.backupFileName("MyBackup", d) === "B2606210907MyBackup.zip")
        check("backupFileName blank -> auto", Svc.backupFileName("", d) === "B2606210907.zip")
        check("backupFileName whitespace -> auto", Svc.backupFileName("   ", d) === "B2606210907.zip")

        var p1 = Svc.parseBackupFromFileName("B2606210907MyBackup.zip")
        check("parse named backup", p1 && p1.name === "MyBackup" && p1.dateToken === "2606210907" && p1.isAutomatic === false)
        var p2 = Svc.parseBackupFromFileName("B2606210907.zip")
        check("parse auto backup", p2 && p2.name === "" && p2.isAutomatic === true)
        check("parse rejects non-backup", Svc.parseBackupFromFileName("notes.txt") === null)

        // ---- backup list sort newest-first -----------------------------------
        var list = Svc.buildBackupList([
            "B2601010800Old.zip",
            "B2606210907New.zip",
            "B2603151200Mid.zip",
            "ignore-me.txt"
        ])
        check("buildBackupList filters non-backups", list.length === 3)
        check("buildBackupList newest first", list[0].name === "New" && list[1].name === "Mid" && list[2].name === "Old")

        // ---- create backup refusal on duplicate ------------------------------
        var existing = ["B2606210907Dup.zip"]
        var cDup = Svc.createBackup("Dup", existing, d, null, null)
        check("createBackup refuses duplicate", cDup.ok === false && cDup.reason === "already-exists")
        var cNew = Svc.createBackup("Fresh", existing, d, null, null)
        check("createBackup fresh ok", cNew.ok === true && cNew.fileName === "B2606210907Fresh.zip" && cNew.backup.name === "Fresh")
        // zip writer failure path
        var cZipFail = Svc.createBackup("Zf", [], d, function () { return false }, ["a.json"])
        check("createBackup zip failure", cZipFail.ok === false && cZipFail.reason === "zip-failed")
        var deleterCalled = ""
        var cZipOk = Svc.createBackup("Zok", [], d, function (fn, files) { return files.length === 1 }, ["a.json"])
        check("createBackup zip ok with writer", cZipOk.ok === true)

        // ---- delete from list -------------------------------------------------
        var after = Svc.deleteBackupFromList(list, "B2603151200Mid.zip", function (fn) { deleterCalled = fn })
        check("deleteBackupFromList removed entry", after.length === 2 && !after.some(function (b) { return b.name === "Mid" }))
        check("deleteBackupFromList invoked deleter", deleterCalled === "B2603151200Mid.zip")

        console.log("RESULT " + pass + "/" + total)
        Qt.quit()
    }
}
