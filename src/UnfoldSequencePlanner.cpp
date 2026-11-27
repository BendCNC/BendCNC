#include "UnfoldSequencePlanner.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDebug>
#include <QPair>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSysInfo>
#include <QUrl>
#include <algorithm>
#include <cmath>

#ifndef BENDCNC_PLANNER_SOURCE_DIR
#define BENDCNC_PLANNER_SOURCE_DIR ""
#endif

namespace {
QString localPath(const QString &urlOrPath)
{
    const QUrl url(urlOrPath);
    return url.isLocalFile() ? url.toLocalFile() : urlOrPath;
}

// Same search options as unfold analysis/complex-sequence/options.json:
// 33 in bed, 13.97 mm (0.55 in) unsupported end allowance, two-finger backgauge.
// The RK3566 press runs the search ~10x slower than a desktop PC.
// Tools > Punch Coverage Side Tolerance (inches): 0..0.75 in, default 0.5 in.
double unsupportedEndMm(const QVariantMap &preference)
{
    bool ok = false;
    const double inches = preference.value(QStringLiteral("punchCoverageSideToleranceIn")).toDouble(&ok);
    if (!ok || !std::isfinite(inches) || inches < 0)
        return 13.97;
    return std::min(inches, 0.75) * 25.4;
}

QByteArray planOptions(const QVariantMap &preference, bool exploreAlternatives = false)
{
    bool ok = false;
    int budgetMs = qEnvironmentVariableIntValue("BENDCNC_UNFOLD_BUDGET_MS", &ok);
    if (!ok || budgetMs <= 0)
        budgetMs = QSysInfo::currentCpuArchitecture().startsWith(QLatin1String("arm")) ? 900000 : 120000;
    QJsonObject options{
        {QStringLiteral("bedLengthMm"), 838.2},
        {QStringLiteral("timeBudgetMs"), budgetMs},
        {QStringLiteral("maxUnsupportedEndMm"), unsupportedEndMm(preference)},
        // Same as the unfold viewer and the Fusion add-in: without these the
        // search can return a route whose exit only clears with no extra retract.
        {QStringLiteral("allowPartialBends"), true},
        {QStringLiteral("additionalRetractMm"), 6.35},
        {QStringLiteral("backgauge"), QJsonObject{{QStringLiteral("separationMm"), 100}, {QStringLiteral("centerYmm"), 0}}}};
    // Material/thickness tooling preference: tried first, planner search is the fallback.
    for (const QString &key : {QStringLiteral("preferredPunchId"), QStringLiteral("preferredDieId")}) {
        const QString id = preference.value(key).toString();
        if (!id.isEmpty())
            options.insert(key, id);
    }
    // CAD design (sheet-metal rule radius) driven candidate filter and alternatives.
    const QVariantMap selection = preference.value(QStringLiteral("toolingSelection")).toMap();
    if (!selection.isEmpty())
        options.insert(QStringLiteral("toolingSelection"), QJsonObject::fromVariantMap(selection));
    // Operator-fixed stroke order: the planner only chooses tooling/stations
    // for this order and verifies it (unfold-v6 operationTemplates).
    const QVariantList templates = preference.value(QStringLiteral("operationTemplates")).toList();
    if (!templates.isEmpty())
        options.insert(QStringLiteral("operationTemplates"), QJsonArray::fromVariantList(templates));
    // Setups already accepted in the previous plan: verified first, the full
    // search runs only if they do not clear (fast manual reorder on ARM).
    const QVariantList seeds = preference.value(QStringLiteral("seedSetups")).toList();
    if (!seeds.isEmpty())
        options.insert(QStringLiteral("seedSetups"), QJsonArray::fromVariantList(seeds));
    // Import: a verified route with the preferred tooling is used directly.
    // RE-RUN PLANNER (force) also searches the tooling alternatives; a
    // forced manual order does not.
    if (!exploreAlternatives || !templates.isEmpty())
        options.insert(QStringLiteral("stopWhenPreferredClear"), true);
    return QJsonDocument(options).toJson(QJsonDocument::Compact);
}
}

UnfoldSequencePlanner::UnfoldSequencePlanner(QObject *parent)
    : QObject(parent)
{
}

UnfoldSequencePlanner::~UnfoldSequencePlanner()
{
    cancel();
}

// Engine selection is explicit and reported (engineLabel), never silent:
//   1. BENDCNC_UNFOLD_DIR ("env")
//   1b. sequence-planner submodule ("submodule")
//   2. ~/Documents/VSCode/unfold-v6 when it holds the planner ("v6")
//   3. /data/bendcnc-unfold on the press ("press")
//   4. ~/Documents/VSCode/unfold ("legacy", shown as such in the status)
QString UnfoldSequencePlanner::unfoldDir() const
{
    return engineSelection().first;
}

QPair<QString, QString> UnfoldSequencePlanner::engineSelection() const
{
    const QString env = qEnvironmentVariable("BENDCNC_UNFOLD_DIR");
    if (!env.isEmpty())
        return {env, QStringLiteral("env")};
    // sequence-planner git submodule: next to the executable, else the source checkout.
    for (const QString &sub : {QCoreApplication::applicationDirPath() + QStringLiteral("/sequence-planner"),
                               QStringLiteral(BENDCNC_PLANNER_SOURCE_DIR)}) {
        if (QFileInfo::exists(sub + QStringLiteral("/tools/plan_sequence.mjs")))
            return {sub, QStringLiteral("submodule")};
    }
    const QString v6 = QDir::homePath() + QStringLiteral("/Documents/VSCode/unfold-v6");
    if (QFileInfo::exists(v6 + QStringLiteral("/tools/plan_sequence.mjs")))
        return {v6, QStringLiteral("v6")};
    const QString home = QDir::homePath() + QStringLiteral("/Documents/VSCode/unfold");
    // Press: persistent /data partition (root is an overlay that resets on boot).
    const QString press = QStringLiteral("/data/bendcnc-unfold");
    if (!QFileInfo::exists(home) && QFileInfo::exists(press))
        return {press, QStringLiteral("press")};
    return {home, QStringLiteral("legacy")};
}

// Engine revision: ENGINE_REVISION file (packaged copies), else git HEAD.
QString UnfoldSequencePlanner::engineRevision() const
{
    const QString dir = unfoldDir();
    QFile stamp(dir + QStringLiteral("/ENGINE_REVISION"));
    if (stamp.open(QIODevice::ReadOnly))
        return QString::fromUtf8(stamp.readAll()).trimmed();
    QFile head(dir + QStringLiteral("/.git/HEAD"));
    if (!head.open(QIODevice::ReadOnly))
        return QStringLiteral("unknown");
    QString ref = QString::fromUtf8(head.readAll()).trimmed();
    if (ref.startsWith(QLatin1String("ref: "))) {
        QFile refFile(dir + QStringLiteral("/.git/") + ref.mid(5));
        if (!refFile.open(QIODevice::ReadOnly))
            return QStringLiteral("unknown");
        ref = QString::fromUtf8(refFile.readAll()).trimmed();
    }
    return ref.left(12);
}

QString UnfoldSequencePlanner::engineLabel() const
{
    const auto selection = engineSelection();
    return QStringLiteral("unfold %1 @ %2 (%3)")
        .arg(selection.second, engineRevision(), QDir::toNativeSeparators(selection.first));
}

QString UnfoldSequencePlanner::pythonPath() const
{
    // The v5 graph importer only needs Python 3 + shapely; FreeCAD is a fallback.
    const QString env = qEnvironmentVariable("UNFOLD_PYTHON");
    if (!env.isEmpty())
        return env;
    static QString resolved;
    if (!resolved.isEmpty())
        return resolved;
    QStringList candidates;
    const QString python3 = QStandardPaths::findExecutable(QStringLiteral("python3"));
    if (!python3.isEmpty() && !python3.contains(QStringLiteral("WindowsApps")))
        candidates << python3;
    const QString system = QStandardPaths::findExecutable(QStringLiteral("python"));
    if (!system.isEmpty() && !system.contains(QStringLiteral("WindowsApps")))
        candidates << system;
    const QDir pythons(QDir::homePath() + QStringLiteral("/AppData/Local/Programs/Python"));
    const QStringList versions = pythons.entryList({QStringLiteral("Python3*")}, QDir::Dirs, QDir::Name | QDir::Reversed);
    for (const QString &version : versions)
        candidates << pythons.filePath(version + QStringLiteral("/python.exe"));
    candidates << QStringLiteral("C:/Program Files/FreeCAD 1.1/bin/python.exe");
    // An activated venv on PATH may lack shapely; take the first that imports it.
    for (const QString &candidate : candidates) {
        if (!QFileInfo::exists(candidate))
            continue;
        QProcess probe;
        probe.setProcessEnvironment(runtimeEnvironment());
        probe.start(candidate, {QStringLiteral("-c"), QStringLiteral("import shapely")});
        if (probe.waitForFinished(15000) && probe.exitStatus() == QProcess::NormalExit
                && probe.exitCode() == 0)
            return resolved = candidate;
    }
    return candidates.isEmpty() ? QString() : candidates.last();
}

QString UnfoldSequencePlanner::nodePath() const
{
    const QString bundled = unfoldDir() + QStringLiteral("/runtime/node/bin/node");
    if (QFileInfo::exists(bundled))
        return bundled;
    return QStandardPaths::findExecutable(QStringLiteral("node"));
}

// Bundled Python packages (shapely, numpy, networkx) installed with pip --target.
QProcessEnvironment UnfoldSequencePlanner::runtimeEnvironment() const
{
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    const QString site = unfoldDir() + QStringLiteral("/runtime/python");
    if (QFileInfo::exists(site)) {
        const QString existing = env.value(QStringLiteral("PYTHONPATH"));
        env.insert(QStringLiteral("PYTHONPATH"), existing.isEmpty() ? site : site + QLatin1Char(':') + existing);
        env.insert(QStringLiteral("UNFOLD_NETWORKX_PATH"), site);
    }
    return env;
}

QString UnfoldSequencePlanner::unavailableReason() const
{
    const QString dir = unfoldDir();
    if (!QFileInfo::exists(dir + QStringLiteral("/tools/plan_sequence.mjs")))
        return QStringLiteral("unfold not found at ") + dir + QStringLiteral(" (") + engineSelection().second + QLatin1Char(')');
    if (!QFileInfo::exists(dir + QStringLiteral("/engine/import_bend_package.py")))
        return QStringLiteral("unfold importer missing in ") + dir;
    if (!QFileInfo::exists(pythonPath()))
        return QStringLiteral("Python (with shapely) not found: ") + pythonPath();
    if (nodePath().isEmpty())
        return QStringLiteral("node not found on PATH");
    return QString();
}

bool UnfoldSequencePlanner::available() const
{
    return unavailableReason().isEmpty();
}

bool UnfoldSequencePlanner::start(const QString &bendFileUrl, const QString &requestId,
                                  const QVariantMap &preference, bool force)
{
    cancel();
    m_requestId = requestId;
    const QString reason = unavailableReason();
    if (!reason.isEmpty()) {
        emit failed(requestId, reason);
        return false;
    }
    m_bendPath = localPath(bendFileUrl);
    QFile bend(m_bendPath);
    if (!bend.open(QIODevice::ReadOnly)) {
        emit failed(requestId, QStringLiteral("Cannot read ") + m_bendPath);
        return false;
    }
    const QByteArray optionsJson = planOptions(preference, force);
    // Engine identity is part of every cache key: switching engines never reuses
    // a model or plan produced by another engine/revision.
    QCryptographicHash hasher(QCryptographicHash::Sha256);
    if (!hasher.addData(&bend)) {
        emit failed(requestId, QStringLiteral("Cannot hash ") + m_bendPath);
        return false;
    }
    hasher.addData(engineLabel().toUtf8());
    const QByteArray bendHash = hasher.result().toHex();
    qInfo().noquote() << "Unfold planner engine:" << engineLabel();
    m_workDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation)
        + QStringLiteral("/unfold-plans");
    QDir().mkpath(m_workDir);
    // The model depends only on the .bend; the plan also on the tooling preference.
    const QString modelBase = m_workDir + QLatin1Char('/') + QString::fromLatin1(bendHash.left(24));
    // Plans whose stages bend split hinge segments separately (DCU Board
    // Mount 7S1/7) need the per-span model, as the Fusion add-in uses.
    m_splitHinges = preference.value(QStringLiteral("splitHinges")).toBool();
    m_modelPath = modelBase + (m_splitHinges ? QStringLiteral(".spans.model.json")
                                             : QStringLiteral(".model.json"));
    QByteArray planKey = bendHash.left(24);
    if (!preference.isEmpty())
        // Keyed on the import options so a RE-RUN result replaces the cached import plan.
        planKey += '-' + QCryptographicHash::hash(planOptions(preference), QCryptographicHash::Sha256).toHex().left(8);
    m_cachePath = m_workDir + QLatin1Char('/') + QString::fromLatin1(planKey) + QStringLiteral(".plan.json");
    QFile cached(m_cachePath);
    if (!force && cached.open(QIODevice::ReadOnly)) {
        const QString json = QString::fromUtf8(cached.readAll());
        emit finished(requestId, json);
        return true;
    }
    QSaveFile options(m_workDir + QStringLiteral("/options.json"));
    if (!options.open(QIODevice::WriteOnly) || options.write(optionsJson) < 0 || !options.commit()) {
        emit failed(requestId, QStringLiteral("Cannot write planner options"));
        return false;
    }
    launch(Stage::Import);
    return true;
}

void UnfoldSequencePlanner::launch(Stage stage)
{
    m_stage = stage;
    m_stderr.clear();
    const bool wasRunning = running();
    m_process = new QProcess(this);
    m_process->setWorkingDirectory(unfoldDir());
    m_process->setProcessEnvironment(runtimeEnvironment());
    const QString modelPath = m_modelPath;
    QString program;
    QStringList arguments;
    if (stage == Stage::Plan) {
        program = nodePath();
        arguments << QStringLiteral("tools/plan_sequence.mjs")
                  << QStringLiteral("--model") << modelPath
                  << QStringLiteral("--options") << m_workDir + QStringLiteral("/options.json")
                  << QStringLiteral("--output") << m_cachePath + QStringLiteral(".tmp");
        m_phaseText = QStringLiteral("Planning 3D sequence (2/2): starting search");
    } else {
        program = pythonPath();
        arguments << QStringLiteral("engine/import_bend_package.py")
                  << QStringLiteral("--bcbend") << m_bendPath
                  << QStringLiteral("--output") << modelPath;
        if (m_splitHinges)
            arguments << QStringLiteral("--no-merge-split-hinges");
        // Bends without signedSweepDegrees: the BendCNC exporter's
        // direction is relative to the child flange.
        if (stage == Stage::ImportRetry)
            arguments << QStringLiteral("--sign-convention") << QStringLiteral("direction-child");
        m_phaseText = QStringLiteral("Planning 3D sequence (1/2): building 3D model");
    }
    m_stderrLine.clear();
    if (!wasRunning)
        m_elapsed.start();
    if (!m_ticker.isActive()) {
        m_ticker.setInterval(1000);
        connect(&m_ticker, &QTimer::timeout, this, &UnfoldSequencePlanner::refreshProgress, Qt::UniqueConnection);
        m_ticker.start();
    }
    refreshProgress();
    connect(m_process, &QProcess::readyReadStandardError, this, [this]() {
        const QByteArray chunk = m_process->readAllStandardError();
        m_stderr += chunk;
        m_stderrLine += chunk;
        int nl;
        while ((nl = m_stderrLine.indexOf('\n')) >= 0) {
            const QByteArray line = m_stderrLine.left(nl);
            m_stderrLine.remove(0, nl + 1);
            const QJsonObject p = QJsonDocument::fromJson(line).object();
            if (p.value(QStringLiteral("type")).toString() != QStringLiteral("progress"))
                continue;
            const QString phase = p.value(QStringLiteral("phase")).toString();
            const QString bend = p.value(QStringLiteral("bendId")).toVariant().toString().section(QLatin1Char(':'), 0, 0);
            const int explored = p.value(QStringLiteral("explored")).toInt(p.value(QStringLiteral("nodes")).toInt());
            const int transitions = p.value(QStringLiteral("transitions")).toInt();
            QString what;
            if (phase == QStringLiteral("checking-fixed-station"))
                what = QStringLiteral("trying fixed stations (0 tool changes)");
            else if (phase == QStringLiteral("checking-backgauge"))
                what = QStringLiteral("checking backgauge fingers");
            else if (phase == QStringLiteral("checking-final-setups"))
                what = QStringLiteral("verifying tool setups");
            else if (phase.startsWith(QStringLiteral("tooling")) || phase == QStringLiteral("preferred-tooling"))
                what = QStringLiteral("trying tooling options");
            else if (phase == QStringLiteral("candidate-found"))
                what = QStringLiteral("candidate found, verifying");
            else
                what = QStringLiteral("searching bend order");
            if (!bend.isEmpty())
                what += QStringLiteral(" - B") + bend;
            if (explored > 0)
                what += QStringLiteral(" - ") + QString::number(explored) + QStringLiteral(" states");
            else if (transitions > 0)
                what += QStringLiteral(" - ") + QString::number(transitions) + QStringLiteral(" checks");
            m_phaseText = QStringLiteral("Planning 3D sequence (2/2): ") + what;
            refreshProgress();
        }
    });
    connect(m_process, &QProcess::finished, this, &UnfoldSequencePlanner::onFinished);
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            fail(QStringLiteral("Failed to start ") + m_process->program());
    });
#ifdef Q_OS_LINUX
    // Lowest CPU/IO priority so the planner (3 fold workers) never starves
    // the HMI render thread or the press control link.
    if (QFile::exists(QStringLiteral("/usr/bin/nice"))) {
        arguments.prepend(program);
        arguments.prepend(QStringLiteral("19"));
        arguments.prepend(QStringLiteral("-n"));
        program = QStringLiteral("/usr/bin/nice");
    }
#endif
    m_process->start(program, arguments);
    if (!wasRunning)
        emit runningChanged();
}

void UnfoldSequencePlanner::onFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_process)
        return;
    const QByteArray out = m_process->readAllStandardOutput();
    m_stderr += m_process->readAllStandardError();
    if (status != QProcess::NormalExit) {
        fail(QStringLiteral("Planner process crashed"));
        return;
    }
    if (m_stage != Stage::Plan) {
        if (exitCode == 0) {
            m_process->deleteLater();
            m_process = nullptr;
            launch(Stage::Plan);
            return;
        }
        if (m_stage == Stage::Import && (out + m_stderr).contains("ambiguous-bend-sign")) {
            m_process->deleteLater();
            m_process = nullptr;
            launch(Stage::ImportRetry);
            return;
        }
        const QJsonObject error = QJsonDocument::fromJson(out.trimmed()).object();
        fail(QStringLiteral("3D model import failed: ")
             + error.value(QStringLiteral("message")).toString(QString::fromUtf8(m_stderr.right(400))));
        return;
    }
    // Exit 2 = plan written but not fully clear; QML reports the flags.
    const QString tmp = m_cachePath + QStringLiteral(".tmp");
    if (exitCode != 0 && exitCode != 2) {
        QFile::remove(tmp);
        fail(QStringLiteral("Sequence planner failed: ") + QString::fromUtf8(m_stderr.right(400)));
        return;
    }
    QFile planFile(tmp);
    if (!planFile.open(QIODevice::ReadOnly)) {
        fail(QStringLiteral("Planner produced no plan"));
        return;
    }
    const QByteArray json = planFile.readAll();
    planFile.close();
    const QJsonObject plan = QJsonDocument::fromJson(json).object();
    if (plan.value(QStringLiteral("stages")).toArray().isEmpty()) {
        QFile::remove(tmp);
        const QString planStatus = plan.value(QStringLiteral("status")).toString(QStringLiteral("NO_STAGES"));
        fail(planStatus == QLatin1String("SEARCH_BUDGET_EXHAUSTED")
             ? QStringLiteral("3D search budget exhausted (%1 s) without a sequence")
                   .arg(qRound(plan.value(QStringLiteral("diagnostics")).toObject()
                                   .value(QStringLiteral("searchElapsedMs")).toDouble(120000.0) / 1000.0))
             : QStringLiteral("3D planner returned no sequence (%1)").arg(planStatus));
        return;
    }
    if (exitCode == 0) {
        QFile::remove(m_cachePath);
        QFile::rename(tmp, m_cachePath);
    } else {
        QFile::remove(tmp);
    }
    const QString requestId = m_requestId;
    clearProcess();
    setProgress(QString());
    emit finished(requestId, QString::fromUtf8(json));
}

void UnfoldSequencePlanner::fail(const QString &message)
{
    const QString requestId = m_requestId;
    clearProcess();
    setProgress(QString());
    emit failed(requestId, message);
}

void UnfoldSequencePlanner::cancel()
{
    if (!m_process)
        return;
    m_process->disconnect(this);
    m_process->kill();
    m_process->waitForFinished(2000);
    clearProcess();
    setProgress(QString());
}

void UnfoldSequencePlanner::clearProcess()
{
    if (!m_process)
        return;
    m_process->disconnect(this);
    m_process->deleteLater();
    m_process = nullptr;
    emit runningChanged();
}

void UnfoldSequencePlanner::refreshProgress()
{
    if (!running()) {
        m_ticker.stop();
        return;
    }
    const qint64 s = m_elapsed.elapsed() / 1000;
    setProgress(m_phaseText + QStringLiteral(" (") + QString::number(s / 60) + QLatin1Char(':')
                + QString::number(s % 60).rightJustified(2, QLatin1Char('0')) + QLatin1Char(')'));
}

void UnfoldSequencePlanner::setProgress(const QString &text)
{
    if (m_progressText == text)
        return;
    m_progressText = text;
    emit progressTextChanged();
}
