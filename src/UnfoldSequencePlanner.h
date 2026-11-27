#pragma once

#include <QObject>
#include <QElapsedTimer>
#include <QProcess>
#include <QString>
#include <QTimer>
#include <QVariantMap>

// Runs the external unfold planner (3D mesh collision search) as two child
// processes: Python 3 + shapely `engine/import_bend_package.py` (BEND -> model.json)
// then Node `tools/plan_sequence.mjs` (model.json -> plan.json). Geometry only;
// it never issues machine commands. Plans are cached by BEND SHA-256 so a
// re-import is instant. Unavailable (available() == false) on the press, where
// the plan embedded in the generated program is used instead.
//
// Locations: BENDCNC_UNFOLD_DIR, else ~/Documents/VSCode/unfold-v6, else the
// press copy, else ~/Documents/VSCode/unfold (legacy); see engineLabel.
// UNFOLD_PYTHON (default: python on PATH, else FreeCAD 1.1 bundled python),
// node from PATH.
class UnfoldSequencePlanner : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString progressText READ progressText NOTIFY progressTextChanged)
    // "unfold <v6|env|press|legacy> @ <revision> (<dir>)" - the engine actually used.
    Q_PROPERTY(QString engineLabel READ engineLabel CONSTANT)

public:
    explicit UnfoldSequencePlanner(QObject *parent = nullptr);
    ~UnfoldSequencePlanner() override;

    bool running() const { return m_process != nullptr; }
    QString progressText() const { return m_progressText; }

    QString engineLabel() const;
    Q_INVOKABLE bool available() const;
    Q_INVOKABLE QString unavailableReason() const;
    // Starts planning; emits finished(requestId, planJson) or failed(requestId, message).
    // preference: optional preferredPunchId/preferredDieId (material thickness
    // tooling preference), evaluated first; part of the plan cache key.
    Q_INVOKABLE bool start(const QString &bendFileUrl, const QString &requestId,
                           const QVariantMap &preference = {}, bool force = false);
    Q_INVOKABLE void cancel();

signals:
    void runningChanged();
    void progressTextChanged();
    void finished(const QString &requestId, const QString &planJson);
    void failed(const QString &requestId, const QString &message);

private:
    enum class Stage { Import, ImportRetry, Plan };

    QString unfoldDir() const;
    QPair<QString, QString> engineSelection() const;
    QString engineRevision() const;
    QString pythonPath() const;
    QString nodePath() const;
    QProcessEnvironment runtimeEnvironment() const;
    void launch(Stage stage);
    void onFinished(int exitCode, QProcess::ExitStatus status);
    void fail(const QString &message);
    void setProgress(const QString &text);
    void refreshProgress();
    void clearProcess();

    QElapsedTimer m_elapsed;
    QTimer m_ticker;
    QString m_phaseText;
    QByteArray m_stderrLine;

    QProcess *m_process = nullptr;
    Stage m_stage = Stage::Import;
    QString m_requestId;
    QString m_bendPath;
    QString m_workDir;
    QString m_cachePath;
    QString m_modelPath;
    bool m_splitHinges = false;
    QString m_progressText;
    QByteArray m_stderr;
};
