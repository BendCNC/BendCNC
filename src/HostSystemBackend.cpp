#include "HostSystemBackend.h"
#include "LicenseManager.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QVersionNumber>

#include <QClipboard>
#include <QFutureWatcher>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QHostInfo>
#include <QProcess>
#include <QRandomGenerator>
#include <QThreadPool>
#include <QTcpServer>
#include <QTcpSocket>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QSet>
#include <QStorageInfo>
#include <QTimeZone>
#include <QSysInfo>
#include <QTemporaryFile>
#include <QTimer>
#include <QUuid>
#include <QtConcurrentRun>

#include <algorithm>
#include <cmath>
#include <limits>

#ifdef Q_OS_LINUX
#include <sys/sysinfo.h>
#endif

HostSystemBackend::HostSystemBackend(bool offlineValidation, QObject *parent)
    : QObject(parent), m_offlineValidation(offlineValidation)
{
    if (!m_offlineValidation) {
        m_wifiNetworks = activeWifiNetworks();
        emit wifiNetworksChanged();
        refreshSystemLogs();
        if (QFileInfo(QStringLiteral("/usr/local/sbin/bendcnc-import-keys")).isExecutable()) {
            refreshCadPairedDevices();
            startCadPairingListener();
        }

        applyPerformanceMode(performanceMode());

        m_wifiAutoconnectTimer = new QTimer(this);
        m_wifiAutoconnectTimer->setInterval(10000);
        connect(m_wifiAutoconnectTimer, &QTimer::timeout,
            this, &HostSystemBackend::attemptWifiAutoconnect);
        m_wifiAutoconnectTimer->start();
        QTimer::singleShot(0, this, &HostSystemBackend::attemptWifiAutoconnect);

        // Java BackupManager: hourly AUTO backup + retention.
        m_autoBackupTimer = new QTimer(this);
        m_autoBackupTimer->setInterval(60 * 60 * 1000);
        connect(m_autoBackupTimer, &QTimer::timeout, this, &HostSystemBackend::runAutoBackup);
        m_autoBackupTimer->start();
    }

    // Host health is read-only and safe in normal and offline-validation
    // modes. These procfs/sysfs reads are tiny and sampled at Java parity's
    // five-second cadence, so they do not compete with LIVE rendering.
    m_systemMetricsTimer = new QTimer(this);
    m_systemMetricsTimer->setInterval(5000);
    connect(m_systemMetricsTimer, &QTimer::timeout,
            this, &HostSystemBackend::sampleSystemMetrics);
    sampleSystemMetrics();
    m_systemMetricsTimer->start();
}

QString HostSystemBackend::applicationVersion() const
{
    return QCoreApplication::applicationVersion();
}

namespace {
// Root helper installed on the press (qt/deploy-arm64/bendcnc-app-update);
// cnc may run only its fixed `queue` and `status` actions through sudo -n.
const QString kAppUpdateHelper = QStringLiteral("/usr/local/sbin/bendcnc-app-update");
const QString kAppUpdateDir = QStringLiteral("/data/bendcnc-updates");
const QString kAppUpdateFile = QStringLiteral("/data/bendcnc-updates/app-update.tar.zst");
const QString kAppUpdateStatus = QStringLiteral("/data/bendcnc-updates/status");
constexpr int kAppUpdateIntervalMs = 6 * 60 * 60 * 1000;
} // namespace

void HostSystemBackend::setAppUpdateState(const QString &state, const QString &message, double progress)
{
    m_appUpdateState = state;
    m_appUpdateMessage = message;
    m_appUpdateProgress = progress;
    emit updateAvailabilityChanged();
}

QString HostSystemBackend::updateChannel() const
{
    return QSettings().value(QStringLiteral("updates/channel")).toString() == QLatin1String("beta")
        ? QStringLiteral("beta") : QStringLiteral("stable");
}

void HostSystemBackend::setUpdateChannel(const QString &channel)
{
    const QString value = channel == QLatin1String("beta") ? QStringLiteral("beta") : QStringLiteral("stable");
    if (value == updateChannel())
        return;
    QSettings settings;
    settings.setValue(QStringLiteral("updates/channel"), value);
    settings.sync();
    // Drop an offer from the other channel; the next check repopulates it.
    m_applicationUpdateAvailable = false;
    m_appUpdateMeta = {};
    emit updateAvailabilityChanged();
    checkForApplicationUpdates();
}

// Optional CPU+GPU "performance" governors (Settings toggle, default OFF).
// A root helper writes sysfs; the app only selects on/off via sudo -n.
namespace {
const QString kPerfModeHelper = QStringLiteral("/usr/local/sbin/bendcnc-perf-mode");
const QString kPerfModeKey = QStringLiteral("system/performanceMode");
}

bool HostSystemBackend::performanceMode() const
{
    return QSettings().value(kPerfModeKey, false).toBool();
}

bool HostSystemBackend::performanceModeAvailable() const
{
    return QFileInfo(kPerfModeHelper).isExecutable();
}

void HostSystemBackend::setPerformanceMode(bool enabled)
{
    if (enabled == performanceMode())
        return;
    QSettings settings;
    settings.setValue(kPerfModeKey, enabled);
    settings.sync();
    applyPerformanceMode(enabled);
    emit performanceModeChanged();
}

void HostSystemBackend::applyPerformanceMode(bool enabled)
{
    if (m_offlineValidation || !performanceModeAvailable())
        return;
    QPointer<HostSystemBackend> self(this);
    QThreadPool::globalInstance()->start([self, enabled] {
        if (!self)
            return;
        const CommandResult r = self->runBounded(QStringLiteral("/usr/bin/sudo"),
            {QStringLiteral("-n"), kPerfModeHelper,
             enabled ? QStringLiteral("on") : QStringLiteral("off")}, 5000);
        qInfo().noquote() << "PERF-MODE" << (enabled ? "on" : "off")
                          << "exit=" + QString::number(r.started ? r.exitCode : -1)
                          << QString::fromUtf8(r.out + r.err).simplified();
    });
}

void HostSystemBackend::checkForApplicationUpdates()
{
#ifdef BENDCNC_LICENSING
    if (m_offlineValidation || m_appUpdateState == QLatin1String("DOWNLOADING")
        || m_appUpdateState == QLatin1String("INSTALLING"))
        return;
    static bool scheduled = false;
    if (!scheduled) {
        scheduled = true;
        QFile status(kAppUpdateStatus);
        if (status.open(QIODevice::ReadOnly))
            m_lastUpdateResult = QString::fromUtf8(status.readAll()).trimmed();
        auto *timer = new QTimer(this);
        timer->setInterval(kAppUpdateIntervalMs);
        connect(timer, &QTimer::timeout, this, &HostSystemBackend::checkForApplicationUpdates);
        timer->start();
    }
    QNetworkRequest req(QUrl(LicenseManager::serverUrl() + QStringLiteral("/v1/updates")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setTransferTimeout(20000);
    const QJsonObject body{{QStringLiteral("device_id"), LicenseManager::computeDeviceId()},
                           {QStringLiteral("app_version"), applicationVersion()},
                           {QStringLiteral("app_commit"), QStringLiteral(BENDCNC_GIT_COMMIT)},
                           {QStringLiteral("channel"), updateChannel()}};
    QNetworkReply *reply = m_updateNetwork.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() { handleUpdatesReply(reply); });
#endif
}

void HostSystemBackend::handleUpdatesReply(QNetworkReply *reply)
{
    reply->deleteLater();
    const QByteArray data = reply->readAll();
    if (reply->error() != QNetworkReply::NoError) {
        // Offline machines are normal; keep any previously verified offer.
        m_updateCheckError = QStringLiteral("Update check failed: %1").arg(reply->errorString());
        emit updateAvailabilityChanged();
        return;
    }
    m_updateCheckError.clear();
    const QJsonObject app = QJsonDocument::fromJson(data).object().value(QStringLiteral("app")).toObject();
    m_applicationUpdateAvailable = false;
    if (app.value(QStringLiteral("available")).toBool()) {
        // Only the signed manifest is trusted; the URL just points at the bytes.
        const QJsonObject meta = LicenseManager::verifyToken(
            app.value(QStringLiteral("release")).toString().toLatin1(), LicenseManager::publicKey());
        static const QRegularExpression shaRe(QStringLiteral("^[0-9a-f]{64}$"));
        const QVersionNumber remote = QVersionNumber::fromString(meta.value(QStringLiteral("version")).toString());
        const QVersionNumber current = QVersionNumber::fromString(applicationVersion());
        const QUrl url(app.value(QStringLiteral("download_url")).toString());
        if (meta.value(QStringLiteral("kind")).toString() != QLatin1String("app")
            || !shaRe.match(meta.value(QStringLiteral("sha256")).toString()).hasMatch()
            || meta.value(QStringLiteral("size")).toInteger() <= 0 || remote.isNull()
            || !url.isValid() || url.scheme() != QLatin1String("https")) {
            m_updateCheckError = QStringLiteral("Application update rejected: invalid signature or metadata.");
        } else if (!current.isNull() && QVersionNumber::compare(remote, current) > 0) {
            m_appUpdateMeta = meta;
            m_appUpdateUrl = url;
            m_applicationUpdateVersion = remote.toString();
            m_appUpdateNotes = meta.value(QStringLiteral("notes")).toString();
            m_applicationUpdateAvailable = true;
        }
    }
    emit updateAvailabilityChanged();
}

bool HostSystemBackend::installApplicationUpdate(bool confirmed)
{
    if (!confirmed)
        return setError(QStringLiteral("Application update requires explicit confirmation."));
    if (!m_applicationUpdateAvailable || m_appUpdateMeta.isEmpty())
        return setError(QStringLiteral("No verified application update is available."));
    if (m_appUpdateState == QLatin1String("DOWNLOADING") || m_appUpdateState == QLatin1String("INSTALLING"))
        return setError(QStringLiteral("An application update is already in progress."));
#ifndef Q_OS_LINUX
    return setError(QStringLiteral("Application updates install only on the press computer."));
#else
    if (m_offlineValidation || !QFileInfo(kAppUpdateHelper).isExecutable())
        return setError(QStringLiteral("The update installer is not installed on this machine."));
    if (!QDir().mkpath(kAppUpdateDir))
        return setError(QStringLiteral("Cannot create %1.").arg(kAppUpdateDir));
    auto *file = new QFile(kAppUpdateFile + QStringLiteral(".part"), this);
    if (!file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        delete file;
        return setError(QStringLiteral("Cannot write the update download."));
    }
    auto *hash = new QCryptographicHash(QCryptographicHash::Sha256);
    const qint64 expectedSize = m_appUpdateMeta.value(QStringLiteral("size")).toInteger();
    const QString expectedSha = m_appUpdateMeta.value(QStringLiteral("sha256")).toString();
    const QString version = m_applicationUpdateVersion;
    setAppUpdateState(QStringLiteral("DOWNLOADING"), QStringLiteral("Downloading BendCNC %1...").arg(version));

    QNetworkRequest req(m_appUpdateUrl);
    req.setTransferTimeout(120000);
    QNetworkReply *dl = m_updateNetwork.get(req);
    connect(dl, &QNetworkReply::readyRead, this, [dl, file, hash]() {
        const QByteArray chunk = dl->readAll();
        hash->addData(chunk);
        if (file->write(chunk) != chunk.size())
            dl->abort();
    });
    connect(dl, &QNetworkReply::downloadProgress, this, [this, dl, expectedSize](qint64 received, qint64) {
        if (received > expectedSize) {
            dl->abort();
            return;
        }
        m_appUpdateProgress = expectedSize > 0 ? double(received) / double(expectedSize) : 0.0;
        emit updateAvailabilityChanged();
    });
    connect(dl, &QNetworkReply::finished, this, [=, this]() {
        dl->deleteLater();
        const QByteArray tail = dl->readAll();
        hash->addData(tail);
        file->write(tail);
        file->close();
        const qint64 size = file->size();
        const QString sha = QString::fromLatin1(hash->result().toHex());
        delete hash;
        const QString partPath = file->fileName();
        file->deleteLater();
        if (dl->error() != QNetworkReply::NoError) {
            QFile::remove(partPath);
            setAppUpdateState(QStringLiteral("FAILED"), QStringLiteral("Download failed: %1").arg(dl->errorString()));
            return;
        }
        if (size != expectedSize || sha != expectedSha) {
            QFile::remove(partPath);
            setAppUpdateState(QStringLiteral("FAILED"),
                              QStringLiteral("Downloaded update failed SHA-256 verification; discarded."));
            return;
        }
        QFile::remove(kAppUpdateFile);
        QFile sidecar(kAppUpdateFile + QStringLiteral(".sha256"));
        if (!QFile::rename(partPath, kAppUpdateFile) || !sidecar.open(QIODevice::WriteOnly | QIODevice::Truncate)
            || sidecar.write(QStringLiteral("%1 %2\n").arg(sha, version).toLatin1()) <= 0) {
            setAppUpdateState(QStringLiteral("FAILED"), QStringLiteral("Could not stage the verified update."));
            return;
        }
        sidecar.close();
        setAppUpdateState(QStringLiteral("INSTALLING"),
                          QStringLiteral("Installing BendCNC %1. The screen will restart.").arg(version), 1.0);
        // The helper re-checks the SHA-256, then runs the transactional
        // deploy in its own systemd unit (this kiosk is stopped by it).
        const CommandResult r = runBounded(QStringLiteral("/usr/bin/sudo"),
                                           {QStringLiteral("-n"), kAppUpdateHelper, QStringLiteral("queue")}, 15000);
        if (!r.started || r.exitCode != 0)
            setAppUpdateState(QStringLiteral("FAILED"),
                              QStringLiteral("Installer refused the update: %1")
                                  .arg(QString::fromUtf8(r.err + r.out).trimmed().left(300)));
    });
    return true;
#endif
}

namespace {
// Root helper that owns /etc/bendcnc/import_authorized_keys (qt/deploy-arm64).
const QString kImportKeysHelper = QStringLiteral("/usr/local/sbin/bendcnc-import-keys");
constexpr quint16 kPairingPort = 8765;
// The add-in's request stays open while the operator decides on the press.
constexpr int kPairingDecisionMs = 60000;
// After a reject/timeout the same address is ignored for this long (anti-spam).
constexpr qint64 kPairingCooldownMs = 30000;
constexpr qsizetype kPairingMaxRequest = 8192;

QString keyFingerprint(const QString &base64Blob)
{
    const QByteArray digest = QCryptographicHash::hash(QByteArray::fromBase64(base64Blob.toLatin1()),
                                                       QCryptographicHash::Sha256);
    return QStringLiteral("SHA256:") + QString::fromLatin1(digest.toBase64(QByteArray::OmitTrailingEquals));
}
} // namespace

void HostSystemBackend::setPairMessage(const QString &message)
{
    m_pairMessage = message;
    emit cadPairingChanged();
}

void HostSystemBackend::refreshCadPairedDevices()
{
#ifdef Q_OS_LINUX
    const CommandResult r = runBounded(QStringLiteral("/usr/bin/sudo"),
                                       {QStringLiteral("-n"), kImportKeysHelper, QStringLiteral("list")}, 5000);
    m_pairedDevices = r.started && r.exitCode == 0
        ? QString::fromUtf8(r.out).split(QLatin1Char('\n'), Qt::SkipEmptyParts) : QStringList();
#endif
    emit cadPairingChanged();
}

bool HostSystemBackend::revokeCadAccess(bool confirmed)
{
    if (!confirmed)
        return setError(QStringLiteral("Revoking CAD access requires confirmation."));
    const CommandResult r = runBounded(QStringLiteral("/usr/bin/sudo"),
                                       {QStringLiteral("-n"), kImportKeysHelper, QStringLiteral("clear")}, 5000);
    refreshCadPairedDevices();
    if (!r.started || r.exitCode != 0)
        return setError(QStringLiteral("CAD access could not be revoked: %1")
                            .arg(QString::fromUtf8(r.err).trimmed().left(200)));
    clearError();
    setResult(QStringLiteral("All CAD PCs were unpaired."));
    return true;
}

void HostSystemBackend::startCadPairingListener()
{
    if (m_offlineValidation || m_pairServer || !QFileInfo(kImportKeysHelper).isExecutable())
        return;
    auto *server = new QTcpServer(this);
    if (!server->listen(QHostAddress::AnyIPv4, kPairingPort)) {
        setPairMessage(QStringLiteral("Pairing port %1 unavailable: %2").arg(kPairingPort).arg(server->errorString()));
        delete server;
        return;
    }
    m_pairServer = server;
    connect(server, &QTcpServer::newConnection, this, [this, server]() {
        while (QTcpSocket *s = server->nextPendingConnection())
            handlePairingSocket(s);
    });
}

void HostSystemBackend::sendPairingReply(QTcpSocket *socket, int status, const QByteArray &reply)
{
    if (!socket || socket->state() != QAbstractSocket::ConnectedState)
        return;
    const QByteArray reason = status == 200 ? "OK" : "Error";
    socket->write("HTTP/1.1 " + QByteArray::number(status) + ' ' + reason
                  + "\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: "
                  + QByteArray::number(reply.size()) + "\r\n\r\n" + reply);
    socket->disconnectFromHost();
}

static QByteArray pairingError(int *status, int code, const QString &msg)
{
    *status = code;
    return QJsonDocument(QJsonObject{{QStringLiteral("error"), msg}}).toJson(QJsonDocument::Compact);
}

void HostSystemBackend::finishPairingRequest(bool accepted, const QString &reason)
{
    if (!m_pairPending.active)
        return;
    QPointer<QTcpSocket> socket = m_pairPending.socket;
    const PendingPair pending = m_pairPending;
    m_pairPending = PendingPair{};
    if (m_pairDecisionTimer)
        m_pairDecisionTimer->stop();
    int status = 403;
    QByteArray reply;
    if (!accepted) {
        m_pairCooldown.insert(pending.peer, QDateTime::currentMSecsSinceEpoch() + kPairingCooldownMs);
        reply = pairingError(&status, 403, reason);
        setPairMessage(QStringLiteral("%1: %2").arg(pending.label, reason));
    } else {
        const CommandResult r = runBounded(QStringLiteral("/usr/bin/sudo"),
                                           {QStringLiteral("-n"), kImportKeysHelper, QStringLiteral("add"),
                                            pending.label, QStringLiteral("ssh-ed25519"), pending.keyBlob},
                                           5000);
        if (!r.started || r.exitCode != 0) {
            reply = pairingError(&status, 500, QStringLiteral("Press could not store the key."));
            setPairMessage(QStringLiteral("Could not store the key of %1.").arg(pending.label));
        } else {
            QFile hostKey(QStringLiteral("/etc/ssh/ssh_host_ed25519_key.pub"));
            const QString hostKeyText = hostKey.open(QIODevice::ReadOnly)
                ? QString::fromLatin1(hostKey.readAll()).section(QLatin1Char(' '), 0, 1).trimmed() : QString();
            status = 200;
            reply = QJsonDocument(QJsonObject{{QStringLiteral("ok"), true},
                                              {QStringLiteral("hostname"), QSysInfo::machineHostName()},
                                              {QStringLiteral("user"), QStringLiteral("bendimport")},
                                              {QStringLiteral("hostKey"), hostKeyText}})
                        .toJson(QJsonDocument::Compact);
            setPairMessage(QStringLiteral("Paired with %1.").arg(pending.label));
            refreshCadPairedDevices();
        }
    }
    sendPairingReply(socket, status, reply);
    emit cadPairingChanged();
}

void HostSystemBackend::acceptCadPairingRequest()
{
    finishPairingRequest(true, QString());
}

void HostSystemBackend::rejectCadPairingRequest()
{
    finishPairingRequest(false, QStringLiteral("Request rejected on the press."));
}

void HostSystemBackend::handlePairingSocket(QTcpSocket *socket)
{
    socket->setParent(this);
    auto *buffer = new QByteArray;
    // Header/body must arrive quickly; the decision wait is handled separately.
    QTimer::singleShot(5000, socket, [this, socket]() {
        if (m_pairPending.socket != socket)
            socket->abort();
    });
    connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
    connect(socket, &QObject::destroyed, this, [buffer]() { delete buffer; });
    connect(socket, &QTcpSocket::readyRead, this, [this, socket, buffer]() {
        buffer->append(socket->readAll());
        if (buffer->size() > kPairingMaxRequest) {
            socket->abort();
            return;
        }
        const qsizetype headerEnd = buffer->indexOf("\r\n\r\n");
        if (headerEnd < 0)
            return;
        const QByteArray head = buffer->left(headerEnd);
        static const QRegularExpression lenRe(QStringLiteral("(?im)^content-length:\\s*(\\d+)"));
        const auto m = lenRe.match(QString::fromLatin1(head));
        const qsizetype length = m.hasMatch() ? m.captured(1).toLongLong() : 0;
        if (buffer->size() < headerEnd + 4 + length)
            return;
        disconnect(socket, &QTcpSocket::readyRead, this, nullptr);
        int status = 404;
        QByteArray reply = R"({"error":"not found"})";
        if (head.startsWith("POST /v1/pair ")) {
            reply = queuePairingRequest(socket, buffer->mid(headerEnd + 4, length), &status);
            if (status == 0)
                return; // held open until the operator decides
        }
        sendPairingReply(socket, status, reply);
    });
}

QByteArray HostSystemBackend::queuePairingRequest(QTcpSocket *socket, const QByteArray &body, int *status)
{
    const QString peer = socket->peerAddress().toString();
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    for (auto it = m_pairCooldown.begin(); it != m_pairCooldown.end();)
        it = it.value() <= now ? m_pairCooldown.erase(it) : std::next(it);
    if (m_pairCooldown.contains(peer))
        return pairingError(status, 429, QStringLiteral("Request rejected recently. Try again in 30 s."));
    if (m_pairPending.active)
        return pairingError(status, 409, QStringLiteral("Another PC is waiting for approval on the press."));
    static const QRegularExpression keyRe(QStringLiteral("^ssh-ed25519 [A-Za-z0-9+/]{60,100}={0,2}$"));
    static const QRegularExpression labelRe(QStringLiteral("^[A-Za-z0-9._-]{1,40}$"));
    const QJsonObject req = QJsonDocument::fromJson(body).object();
    const QString key = req.value(QStringLiteral("publicKey")).toString().section(QLatin1Char(' '), 0, 1);
    QString label = req.value(QStringLiteral("label")).toString();
    label.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9._-]")), QStringLiteral("_"));
    if (!keyRe.match(key).hasMatch() || !labelRe.match(label).hasMatch())
        return pairingError(status, 400, QStringLiteral("Invalid public key or PC name."));
    m_pairPending.active = true;
    m_pairPending.socket = socket;
    m_pairPending.peer = peer;
    m_pairPending.label = label;
    m_pairPending.keyBlob = key.section(QLatin1Char(' '), 1, 1);
    m_pairPending.fingerprint = keyFingerprint(m_pairPending.keyBlob);
    if (!m_pairDecisionTimer) {
        m_pairDecisionTimer = new QTimer(this);
        m_pairDecisionTimer->setSingleShot(true);
        connect(m_pairDecisionTimer, &QTimer::timeout, this, [this]() {
            finishPairingRequest(false, QStringLiteral("No answer on the press."));
        });
    }
    m_pairDecisionTimer->start(kPairingDecisionMs);
    // PC closed the request (cancel): drop the popup without cooldown.
    connect(socket, &QTcpSocket::disconnected, this, [this, socket]() {
        if (m_pairPending.active && m_pairPending.socket == socket) {
            m_pairPending = PendingPair{};
            m_pairDecisionTimer->stop();
            emit cadPairingChanged();
        }
    });
    emit cadPairingChanged();
    *status = 0;
    return {};
}

bool HostSystemBackend::readCpuCounters(quint64 *total, quint64 *idle) const
{
#ifdef Q_OS_LINUX
    QFile file(QStringLiteral("/proc/stat"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;
    const QByteArray line = file.readLine().trimmed();
    if (!line.startsWith("cpu "))
        return false;
    const QList<QByteArray> fields = line.simplified().split(' ');
    if (fields.size() < 5 || fields.first() != "cpu")
        return false;
    quint64 values[8] = {};
    const qsizetype count = std::min<qsizetype>(8, fields.size() - 1);
    for (int index = 0; index < count; ++index) {
        bool ok = false;
        values[index] = fields.at(index + 1).toULongLong(&ok);
        if (!ok)
            return false;
    }
    quint64 sum = 0;
    for (const quint64 value : values) {
        if (std::numeric_limits<quint64>::max() - sum < value)
            return false;
        sum += value;
    }
    if (std::numeric_limits<quint64>::max() - values[3] < values[4])
        return false;
    *total = sum;
    *idle = values[3] + values[4];
    return true;
#else
    Q_UNUSED(total)
    Q_UNUSED(idle)
    return false;
#endif
}

bool HostSystemBackend::readCpuTemperature(double *celsius)
{
#ifdef Q_OS_LINUX
    auto readTemperature = [celsius](const QString &path) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
            return false;
        bool ok = false;
        const qint64 raw = file.readAll().trimmed().toLongLong(&ok);
        const double value = raw / 1000.0;
        if (!ok || !std::isfinite(value) || value < -40.0 || value > 150.0)
            return false;
        *celsius = value;
        return true;
    };
    if (!m_cpuTemperaturePath.isEmpty()
            && readTemperature(m_cpuTemperaturePath))
        return true;

    struct Candidate { int score = 0; QString path; };
    QList<Candidate> candidates;
    const QDir thermalRoot(QStringLiteral("/sys/class/thermal"));
    const QFileInfoList zones = thermalRoot.entryInfoList(
        {QStringLiteral("thermal_zone*")}, QDir::Dirs | QDir::NoDotAndDotDot,
        QDir::Name);
    for (const QFileInfo &zone : zones) {
        QFile typeFile(QDir(zone.absoluteFilePath()).filePath(QStringLiteral("type")));
        if (!typeFile.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;
        const QString type = QString::fromUtf8(typeFile.readAll()).trimmed().toLower();
        int score = 10;
        if (type == QStringLiteral("soc-thermal") || type == QStringLiteral("soc_thermal"))
            score = 100;
        else if (type == QStringLiteral("cpu-thermal") || type == QStringLiteral("cpu_thermal"))
            score = 90;
        else if (type.contains(QStringLiteral("soc")))
            score = 80;
        else if (type.contains(QStringLiteral("cpu")))
            score = 70;
        else if (type.contains(QStringLiteral("package"))
                 || type.contains(QStringLiteral("x86_pkg_temp")))
            score = 60;
        candidates.append({score,
            QDir(zone.absoluteFilePath()).filePath(QStringLiteral("temp"))});
    }
    std::sort(candidates.begin(), candidates.end(),
              [](const Candidate &left, const Candidate &right) {
        return left.score > right.score;
    });
    for (const Candidate &candidate : candidates) {
        if (readTemperature(candidate.path)) {
            m_cpuTemperaturePath = candidate.path;
            return true;
        }
    }
    m_cpuTemperaturePath.clear();
    return false;
#else
    Q_UNUSED(celsius)
    return false;
#endif
}

bool HostSystemBackend::readMemoryUsage(quint64 *totalBytes,
                                        quint64 *availableBytes) const
{
#ifdef Q_OS_LINUX
    QFile file(QStringLiteral("/proc/meminfo"));
    quint64 totalKiB = 0;
    quint64 availableKiB = 0;
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        while (!file.atEnd() && (totalKiB == 0 || availableKiB == 0)) {
            const QByteArray line = file.readLine().trimmed();
            bool ok = false;
            if (line.startsWith("MemTotal:"))
                totalKiB = line.mid(sizeof("MemTotal:") - 1).simplified()
                    .split(' ').value(0).toULongLong(&ok);
            else if (line.startsWith("MemAvailable:"))
                availableKiB = line.mid(sizeof("MemAvailable:") - 1).simplified()
                    .split(' ').value(0).toULongLong(&ok);
            else
                continue;
            if (!ok)
                return false;
        }
    }
    if (totalKiB > 0 && availableKiB <= totalKiB
            && totalKiB <= std::numeric_limits<quint64>::max() / 1024) {
        *totalBytes = totalKiB * 1024;
        *availableBytes = availableKiB * 1024;
        return true;
    }

    struct sysinfo info {};
    if (sysinfo(&info) != 0 || info.totalram == 0)
        return false;
    const quint64 unit = std::max<unsigned int>(1, info.mem_unit);
    if (quint64(info.totalram) > std::numeric_limits<quint64>::max() / unit)
        return false;
    *totalBytes = quint64(info.totalram) * unit;
    const quint64 reclaimableUnits = quint64(info.freeram) + quint64(info.bufferram);
    *availableBytes = std::min(*totalBytes, reclaimableUnits * unit);
    return true;
#else
    Q_UNUSED(totalBytes)
    Q_UNUSED(availableBytes)
    return false;
#endif
}

QString HostSystemBackend::memoryUsageText() const
{
    return m_memoryAvailable
        ? QString::number(m_memoryUsedPercent, 'f', 1) + QLatin1Char('%')
        : QStringLiteral("--");
}

void HostSystemBackend::sampleSystemMetrics()
{
    bool changed = false;
    quint64 total = 0;
    quint64 idle = 0;
    if (readCpuCounters(&total, &idle)) {
        if (m_cpuBaselineAvailable && total >= m_previousCpuTotal
                && idle >= m_previousCpuIdle && total > m_previousCpuTotal) {
            const quint64 deltaTotal = total - m_previousCpuTotal;
            const quint64 deltaIdle = idle - m_previousCpuIdle;
            const double load = 100.0 * double(deltaTotal - std::min(deltaIdle, deltaTotal))
                / double(deltaTotal);
            const double clamped = std::clamp(load, 0.0, 100.0);
            changed = changed || !m_cpuLoadAvailable
                || !qFuzzyCompare(m_cpuLoadPercent + 1.0, clamped + 1.0);
            m_cpuLoadPercent = clamped;
            m_cpuLoadAvailable = true;
        }
        m_previousCpuTotal = total;
        m_previousCpuIdle = idle;
        m_cpuBaselineAvailable = true;
    } else {
        changed = changed || m_cpuLoadAvailable;
        m_cpuLoadAvailable = false;
        m_cpuBaselineAvailable = false;
    }

    double temperature = 0.0;
    const bool temperatureAvailable = readCpuTemperature(&temperature);
    changed = changed || temperatureAvailable != m_cpuTemperatureAvailable
        || (temperatureAvailable
            && !qFuzzyCompare(m_cpuTemperatureCelsius + 1.0, temperature + 1.0));
    m_cpuTemperatureAvailable = temperatureAvailable;
    if (temperatureAvailable)
        m_cpuTemperatureCelsius = temperature;

    quint64 memoryTotalBytes = 0;
    quint64 memoryAvailableBytes = 0;
    const bool memoryAvailable = readMemoryUsage(
        &memoryTotalBytes, &memoryAvailableBytes);
    const quint64 memoryUsedBytes = memoryAvailable
        ? memoryTotalBytes - memoryAvailableBytes : 0;
    const double memoryUsedPercent = memoryAvailable
        ? 100.0 * double(memoryUsedBytes) / double(memoryTotalBytes) : 0.0;
    changed = changed || memoryAvailable != m_memoryAvailable
        || (memoryAvailable
            && (!qFuzzyCompare(m_memoryUsedPercent + 1.0, memoryUsedPercent + 1.0)
                || m_memoryUsedBytes != memoryUsedBytes
                || m_memoryTotalBytes != memoryTotalBytes));
    const bool memoryAvailabilityChanged = memoryAvailable != m_memoryAvailable;
    m_memoryAvailable = memoryAvailable;
    if (memoryAvailable) {
        m_memoryUsedPercent = memoryUsedPercent;
        m_memoryUsedBytes = memoryUsedBytes;
        m_memoryTotalBytes = memoryTotalBytes;
    }
    if (memoryAvailabilityChanged || m_memorySampleCount == 0) {
        qInfo().noquote()
            << QStringLiteral("SYSTEM-METRICS RAM available=%1 used=%2 total=%3 percent=%4")
                   .arg(memoryAvailable ? QStringLiteral("1") : QStringLiteral("0"))
                   .arg(memoryUsedBytes)
                   .arg(memoryTotalBytes)
                   .arg(memoryAvailable ? QString::number(memoryUsedPercent, 'f', 1)
                                        : QStringLiteral("--"));
    }
    ++m_memorySampleCount;
    if (changed)
        emit systemMetricsChanged();
}

QString HostSystemBackend::systemSummary() const
{
    return QStringLiteral("%1 | %2 | %3 | %4")
        .arg(QHostInfo::localHostName(), QSysInfo::prettyProductName(),
             QSysInfo::currentCpuArchitecture(), QCoreApplication::applicationVersion());
}

bool HostSystemBackend::powerOff(bool confirmed)
{
    return systemPower(QStringLiteral("poweroff"), confirmed);
}

bool HostSystemBackend::reboot(bool confirmed)
{
    return systemPower(QStringLiteral("reboot"), confirmed);
}

bool HostSystemBackend::systemPower(const QString &verb, bool confirmed)
{
    if (!confirmed)
        return false;
#ifdef Q_OS_LINUX
    // logind via polkit (49-bendcnc-power.rules). startDetached cannot
    // report a denied request, so run bounded and check the exit code.
    const auto result = runBounded(QStringLiteral("/usr/bin/systemctl"),
                                   {QStringLiteral("--no-ask-password"), verb});
    if (result.started && result.exitCode == 0)
        return true;
    return setError(QStringLiteral("systemctl %1 failed: %2").arg(verb, QString::fromUtf8(result.err).trimmed()));
#else
    Q_UNUSED(verb);
    return false;
#endif
}

HostSystemBackend::CommandResult HostSystemBackend::runBounded(
    const QString &program, const QStringList &arguments, int timeoutMs) const
{
    CommandResult result;
    QProcess process;
    process.setProcessChannelMode(QProcess::SeparateChannels);
    process.start(program, arguments, QIODevice::ReadOnly);
    if (!process.waitForStarted(1500)) {
        result.err = process.errorString().toUtf8();
        return result;
    }
    result.started = true;
    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished(1000);
        result.err = QByteArrayLiteral("operation timed out");
        return result;
    }
    result.exitCode = process.exitCode();
    result.out = process.readAllStandardOutput();
    result.err = process.readAllStandardError();
    return result;
}

HostSystemBackend::CommandResult HostSystemBackend::runNmcli(
    const QStringList &arguments, int timeoutMs) const
{
    return runBounded(QStringLiteral("/usr/bin/nmcli"),
                      QStringList{QStringLiteral("--colors"), QStringLiteral("no"),
                                  QStringLiteral("--escape"), QStringLiteral("yes")}
                          + arguments,
                      timeoutMs);
}

QString HostSystemBackend::wirelessDevice() const
{
    const auto result = runNmcli({
        QStringLiteral("-t"), QStringLiteral("-f"),
        QStringLiteral("DEVICE,TYPE"), QStringLiteral("device"),
        QStringLiteral("status")});
    if (!result.started || result.exitCode != 0)
        return {};
    for (const QByteArray &rawLine : result.out.split('\n')) {
        const QList<QByteArray> fields = splitNmcliTerseLine(rawLine.trimmed());
        if (fields.size() >= 2 && fields.at(1) == "wifi")
            return QString::fromUtf8(fields.at(0));
    }
    return {};
}

QString HostSystemBackend::wifiDiagnostic() const
{
#ifdef Q_OS_LINUX
    const QDir networkRoot(QStringLiteral("/sys/class/net"));
    const QStringList interfaces = networkRoot.entryList(QDir::Dirs | QDir::NoDotAndDotDot,
                                                          QDir::Name);
    QStringList wirelessInterfaces;
    for (const QString &interfaceName : interfaces) {
        const QString interfacePath = networkRoot.filePath(interfaceName);
        if (QFileInfo::exists(QDir(interfacePath).filePath(QStringLiteral("wireless")))
                || QFileInfo::exists(QDir(interfacePath).filePath(QStringLiteral("phy80211"))))
            wirelessInterfaces.append(interfaceName);
    }
    const QDir phyRoot(QStringLiteral("/sys/class/ieee80211"));
    const QStringList phys = phyRoot.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    QStringList details;
    if (!wirelessInterfaces.isEmpty())
        details << QStringLiteral("kernel interfaces: %1").arg(wirelessInterfaces.join(','));
    if (!phys.isEmpty())
        details << QStringLiteral("wireless PHYs: %1").arg(phys.join(','));
    const auto nmResult = runNmcli({QStringLiteral("-t"), QStringLiteral("-f"),
                                    QStringLiteral("DEVICE,TYPE,STATE"),
                                    QStringLiteral("device"), QStringLiteral("status")});
    if (!nmResult.started)
        details << QStringLiteral("nmcli unavailable: %1")
                       .arg(QString::fromUtf8(nmResult.err).trimmed());
    else if (nmResult.exitCode != 0)
        details << QStringLiteral("NetworkManager query failed: %1")
                       .arg(QString::fromUtf8(nmResult.err).trimmed());
    else if (!nmResult.out.trimmed().isEmpty())
        details << QStringLiteral("NetworkManager devices: %1")
                       .arg(QString::fromUtf8(nmResult.out).trimmed().replace('\n', QStringLiteral(", ")));
    if (wirelessInterfaces.isEmpty() && phys.isEmpty())
        details.prepend(QStringLiteral("the kernel created no WiFi interface (driver, firmware, antenna module, or board revision)"));
    return details.join(QStringLiteral("; "));
#else
    return QStringLiteral("WiFi device diagnostics are available only on Linux");
#endif
}

QList<QByteArray> HostSystemBackend::splitNmcliTerseLine(const QByteArray &line)
{
    QList<QByteArray> fields;
    QByteArray field;
    bool escaped = false;
    for (const char value : line) {
        if (escaped) {
            field.append(value);
            escaped = false;
        } else if (value == '\\') {
            escaped = true;
        } else if (value == ':') {
            fields.append(field);
            field.clear();
        } else {
            field.append(value);
        }
    }
    if (escaped)
        field.append('\\');
    fields.append(field);
    return fields;
}

QVariantMap HostSystemBackend::wifiNetworkFromFields(const QList<QByteArray> &fields) const
{
    QVariantMap network;
    if (fields.size() < 4)
        return network;
    network.insert(QStringLiteral("connected"), fields.at(0) == "*");
    network.insert(QStringLiteral("ssid"), QString::fromUtf8(fields.at(1)));
    network.insert(QStringLiteral("signal"), fields.at(2).toInt());
    const QString security = QString::fromUtf8(fields.at(3)).trimmed();
    network.insert(QStringLiteral("security"), security == QStringLiteral("--")
                       ? QString() : security);
    return network;
}

QVariantList HostSystemBackend::activeWifiNetworks() const
{
    QVariantList networks;
    if (m_offlineValidation)
        return networks;
    const QString device = wirelessDevice();
    if (device.isEmpty())
        return networks;
    const auto result = runNmcli({
        QStringLiteral("-t"), QStringLiteral("-f"),
        QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"),
        QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("list"),
        QStringLiteral("ifname"), device,
        QStringLiteral("--rescan"), QStringLiteral("no")});
    if (!result.started || result.exitCode != 0)
        return networks;
    const auto lines = result.out.split('\n');
    for (const QByteArray &rawLine : lines) {
        const QList<QByteArray> fields = splitNmcliTerseLine(rawLine.trimmed());
        const QVariantMap network = wifiNetworkFromFields(fields);
        if (!network.isEmpty() && network.value(QStringLiteral("connected")).toBool())
            networks.append(network);
    }
    return networks;
}

QString HostSystemBackend::activeWifiConnectionUuid() const
{
    const QString device = wirelessDevice();
    if (device.isEmpty())
        return {};
    const auto result = runNmcli({
        QStringLiteral("-t"), QStringLiteral("-f"),
        QStringLiteral("UUID,TYPE,DEVICE"),
        QStringLiteral("connection"), QStringLiteral("show"), QStringLiteral("--active")});
    if (!result.started || result.exitCode != 0)
        return {};
    const auto lines = result.out.split('\n');
    for (const QByteArray &rawLine : lines) {
        const QList<QByteArray> fields = splitNmcliTerseLine(rawLine.trimmed());
        if (fields.size() >= 3 && fields.at(1) == "802-11-wireless"
            && QString::fromUtf8(fields.at(2)) == device)
            return QString::fromUtf8(fields.at(0));
    }
    return {};
}

QString HostSystemBackend::savedAutoconnectWifiUuid() const
{
    const auto result = runNmcli({
        QStringLiteral("-t"), QStringLiteral("-f"),
        QStringLiteral("UUID,TYPE,AUTOCONNECT"),
        QStringLiteral("connection"), QStringLiteral("show")});
    if (!result.started || result.exitCode != 0)
        return {};
    for (const QByteArray &rawLine : result.out.split('\n')) {
        const QList<QByteArray> fields = splitNmcliTerseLine(rawLine.trimmed());
        if (fields.size() >= 3 && fields.at(1) == "802-11-wireless"
                && fields.at(2).compare("yes", Qt::CaseInsensitive) == 0)
            return QString::fromUtf8(fields.at(0));
    }
    return {};
}

void HostSystemBackend::attemptWifiAutoconnect()
{
    if (m_offlineValidation || m_operationActive || m_wifiAutoconnectProbeInFlight
            || (m_wifiAutoconnectProcess
                && m_wifiAutoconnectProcess->state() != QProcess::NotRunning))
        return;
    // The three blocking nmcli probes took ~125 ms on the press every 10 s,
    // stalling the GUI thread (visible Live 3D hitch). Probe off-thread;
    // runNmcli only uses a local QProcess.
    m_wifiAutoconnectProbeInFlight = true;
    QPointer<HostSystemBackend> self(this);
    QThreadPool::globalInstance()->start([self] {
        if (!self)
            return;
        const bool alreadyActive = !self->activeWifiConnectionUuid().isEmpty();
        const QString device = alreadyActive ? QString() : self->wirelessDevice();
        const QString uuid = alreadyActive ? QString() : self->savedAutoconnectWifiUuid();
        QMetaObject::invokeMethod(self.data(), [self, device, uuid] {
            if (!self)
                return;
            self->m_wifiAutoconnectProbeInFlight = false;
            self->startWifiAutoconnect(device, uuid);
        }, Qt::QueuedConnection);
    });
}

void HostSystemBackend::startWifiAutoconnect(const QString &device, const QString &uuid)
{
    if (device.isEmpty() || uuid.isEmpty() || m_offlineValidation || m_operationActive
            || (m_wifiAutoconnectProcess
                && m_wifiAutoconnectProcess->state() != QProcess::NotRunning))
        return;

    if (!m_wifiAutoconnectProcess) {
        m_wifiAutoconnectProcess = new QProcess(this);
        connect(m_wifiAutoconnectProcess,
                qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                this, [this](int exitCode, QProcess::ExitStatus exitStatus) {
            if (exitStatus == QProcess::NormalExit && exitCode == 0) {
                qInfo().noquote() << "WIFI-AUTOCONNECT result=connected";
                m_wifiNetworks = activeWifiNetworks();
                emit wifiNetworksChanged();
            } else {
                qWarning().noquote() << "WIFI-AUTOCONNECT result=retrying"
                                     << QString::fromUtf8(
                                            m_wifiAutoconnectProcess->readAllStandardError())
                                            .trimmed();
            }
        });
    }
    qInfo().noquote() << "WIFI-AUTOCONNECT state=attempting uuid=" + uuid
                      << "device=" + device;
    m_wifiAutoconnectProcess->start(QStringLiteral("/usr/bin/nmcli"), {
        QStringLiteral("--colors"), QStringLiteral("no"),
        QStringLiteral("--wait"), QStringLiteral("20"),
        QStringLiteral("connection"), QStringLiteral("up"),
        QStringLiteral("uuid"), uuid,
        QStringLiteral("ifname"), device});
}

void HostSystemBackend::restoreWifiConnection(const QString &uuid) const
{
    if (uuid.isEmpty())
        return;
    const QString device = wirelessDevice();
    if (device.isEmpty())
        return;
    const auto result = runNmcli({
        QStringLiteral("--wait"), QStringLiteral("20"),
        QStringLiteral("connection"), QStringLiteral("up"),
        QStringLiteral("uuid"), uuid,
        QStringLiteral("ifname"), device}, 25000);
    if (!result.started || result.exitCode != 0)
        qWarning().noquote() << "WIFI-RESTORE result=failed uuid=" + uuid
                             << QString::fromUtf8(result.err).trimmed();
    else
        qInfo().noquote() << "WIFI-RESTORE result=connected uuid=" + uuid;
}

bool HostSystemBackend::setError(const QString &message)
{
    m_lastError = message.trimmed();
    emit lastErrorChanged();
    return false;
}

void HostSystemBackend::setResult(const QString &message)
{
    m_lastResult = message.trimmed();
    emit lastResultChanged();
}

void HostSystemBackend::clearError()
{
    if (m_lastError.isEmpty())
        return;
    m_lastError.clear();
    emit lastErrorChanged();
}

void HostSystemBackend::setOperation(bool active, double progress)
{
    m_operationActive = active;
    m_operationProgress = progress;
    emit operationChanged();
}

void HostSystemBackend::refreshWifi()
{
    if (m_offlineValidation) {
        setError(QStringLiteral("WiFi control is disabled during offline validation."));
        return;
    }
    const QString device = wirelessDevice();
    if (device.isEmpty()) {
        setError(QStringLiteral("WiFi scan failed: %1").arg(wifiDiagnostic()));
        return;
    }
    const auto radioResult = runNmcli({QStringLiteral("radio"), QStringLiteral("wifi"),
                                      QStringLiteral("on")});
    if (!radioResult.started || radioResult.exitCode != 0) {
        setError(QStringLiteral("WiFi scan failed while enabling the radio: %1")
                     .arg(QString::fromUtf8(radioResult.err)));
        return;
    }
    const auto result = runNmcli({
        QStringLiteral("-t"), QStringLiteral("-f"),
        QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"),
        QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("list"),
        QStringLiteral("ifname"), device,
        QStringLiteral("--rescan"), QStringLiteral("yes")}, 15000);
    if (!result.started || result.exitCode != 0) {
        setError(QStringLiteral("WiFi scan failed: %1").arg(QString::fromUtf8(result.err)));
        return;
    }
    QVariantList networks;
    const auto lines = result.out.split('\n');
    for (const QByteArray &rawLine : lines) {
        const QByteArray line = rawLine.trimmed();
        if (line.isEmpty())
            continue;
        const QVariantMap network = wifiNetworkFromFields(splitNmcliTerseLine(line));
        if (!network.isEmpty() && !network.value(QStringLiteral("ssid")).toString().isEmpty())
            networks.append(network);
    }
    m_wifiNetworks = networks;
    clearError();
    emit wifiNetworksChanged();
}

HostSystemBackend::WifiConnectionResult HostSystemBackend::performWifiConnection(
    const QString &ssid, const QString &password) const
{
    WifiConnectionResult outcome;
    outcome.ssid = ssid;
    const QString device = wirelessDevice();
    if (device.isEmpty()) {
        outcome.error = QStringLiteral("WiFi connection failed: no wireless device is available.");
        return outcome;
    }
    const QString previousConnectionUuid = activeWifiConnectionUuid();
    QString createdConnectionUuid;
    QString createdConnectionName;
    QTemporaryFile passwordFile;
    CommandResult result;
    if (!password.isEmpty()) {
        createdConnectionName = QStringLiteral("BendCNC-%1")
                                    .arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
        passwordFile.setAutoRemove(true);
        if (!passwordFile.open()) {
            outcome.error = QStringLiteral("WiFi connection failed: secure credential staging failed.");
            return outcome;
        }
        passwordFile.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
        passwordFile.write(QByteArrayLiteral("802-11-wireless-security.psk:")
                           + password.toUtf8() + QByteArrayLiteral("\n"));
        passwordFile.flush();

        const auto addResult = runNmcli({
            QStringLiteral("connection"), QStringLiteral("add"),
            QStringLiteral("type"), QStringLiteral("wifi"),
            QStringLiteral("ifname"), device,
            QStringLiteral("con-name"), createdConnectionName,
            QStringLiteral("ssid"), ssid,
            QStringLiteral("wifi-sec.key-mgmt"), QStringLiteral("wpa-psk"),
            QStringLiteral("connection.autoconnect"), QStringLiteral("yes"),
            QStringLiteral("connection.permissions"), QString()});
        if (!addResult.started || addResult.exitCode != 0) {
            QString detail = QString::fromUtf8(addResult.err).trimmed();
            restoreWifiConnection(previousConnectionUuid);
            outcome.error = QStringLiteral("WiFi connection failed while creating the secure profile: %1")
                                .arg(detail);
            return outcome;
        }

        const auto uuidResult = runNmcli({
            QStringLiteral("-g"), QStringLiteral("connection.uuid"),
            QStringLiteral("connection"), QStringLiteral("show"),
            QStringLiteral("id"), createdConnectionName});
        if (uuidResult.started && uuidResult.exitCode == 0)
            createdConnectionUuid = QString::fromUtf8(uuidResult.out).trimmed().section('\n', 0, 0);
        if (createdConnectionUuid.isEmpty()) {
            runNmcli({QStringLiteral("connection"), QStringLiteral("delete"),
                      QStringLiteral("id"), createdConnectionName});
            restoreWifiConnection(previousConnectionUuid);
            outcome.error = QStringLiteral("WiFi connection failed: the secure profile UUID was unavailable.");
            return outcome;
        }

        result = runNmcli({
            QStringLiteral("--wait"), QStringLiteral("30"),
            QStringLiteral("connection"), QStringLiteral("up"),
            QStringLiteral("uuid"), createdConnectionUuid,
            QStringLiteral("ifname"), device,
            QStringLiteral("passwd-file"), passwordFile.fileName()}, 35000);
    } else {
        result = runNmcli({
            QStringLiteral("--wait"), QStringLiteral("30"),
            QStringLiteral("device"), QStringLiteral("wifi"),
            QStringLiteral("connect"), ssid,
            QStringLiteral("ifname"), device}, 35000);
    }
    if (!result.started || result.exitCode != 0) {
        QString detail = QString::fromUtf8(result.err);
        if (!password.isEmpty())
            detail.replace(password, QStringLiteral("[REDACTED]"));
        if (!createdConnectionUuid.isEmpty())
            runNmcli({QStringLiteral("connection"), QStringLiteral("delete"),
                      QStringLiteral("uuid"), createdConnectionUuid});
        restoreWifiConnection(previousConnectionUuid);
        outcome.error = QStringLiteral("WiFi connection failed: %1").arg(detail);
        return outcome;
    }
    const QString connectedUuid = activeWifiConnectionUuid();
    if (connectedUuid.isEmpty()) {
        restoreWifiConnection(previousConnectionUuid);
        outcome.error = QStringLiteral("WiFi connection failed: NetworkManager did not activate a saved profile.");
        return outcome;
    }
    QStringList persistArgs{
        QStringLiteral("connection"), QStringLiteral("modify"),
        QStringLiteral("uuid"), connectedUuid,
        QStringLiteral("connection.autoconnect"), QStringLiteral("yes"),
        QStringLiteral("connection.permissions"), QString()};
    if (!password.isEmpty() && connectedUuid == createdConnectionUuid) {
        // passwd-file only supplies the PSK for this activation; store it in the
        // system-owned profile (root-only keyfile) so WiFi reconnects after reboot.
        persistArgs << QStringLiteral("wifi-sec.psk-flags") << QStringLiteral("0")
                    << QStringLiteral("wifi-sec.psk") << password;
    }
    const auto persistResult = runNmcli(persistArgs);
    if (!persistResult.started || persistResult.exitCode != 0) {
        restoreWifiConnection(previousConnectionUuid);
        QString detail = QString::fromUtf8(persistResult.err).trimmed();
        if (!password.isEmpty())
            detail.replace(password, QStringLiteral("[REDACTED]"));
        outcome.error = QStringLiteral("WiFi connected but profile persistence failed: %1").arg(detail);
        return outcome;
    }
    outcome.success = true;
    outcome.message = QStringLiteral("Connected to %1.").arg(ssid);
    outcome.networks = activeWifiNetworks();
    return outcome;
}

bool HostSystemBackend::connectWifi(const QString &ssid, const QString &password)
{
    if (m_offlineValidation)
        return setError(QStringLiteral("WiFi control is disabled during offline validation."));
    const QString normalizedSsid = ssid.trimmed();
    if (normalizedSsid.isEmpty())
        return setError(QStringLiteral("An SSID is required."));
    if (m_operationActive)
        return setError(QStringLiteral("Another host operation is already in progress."));

    clearError();
    setOperation(true, 0.0);
    if (!m_wifiConnectionWatcher) {
        m_wifiConnectionWatcher = new QFutureWatcher<WifiConnectionResult>(this);
        connect(m_wifiConnectionWatcher, &QFutureWatcher<WifiConnectionResult>::finished,
                this, [this]() {
            const WifiConnectionResult outcome = m_wifiConnectionWatcher->result();
            setOperation(false, outcome.success ? 1.0 : 0.0);
            if (outcome.success) {
                m_lastResult = outcome.message;
                emit lastResultChanged();
                if (!outcome.networks.isEmpty()) {
                    m_wifiNetworks = outcome.networks;
                    emit wifiNetworksChanged();
                }
                clearError();
            } else {
                setError(outcome.error);
            }
            emit wifiConnectionFinished(outcome.success, outcome.ssid, outcome.error);
        });
    }
    m_wifiConnectionWatcher->setFuture(QtConcurrent::run(
        [this, normalizedSsid, password]() {
            return performWifiConnection(normalizedSsid, password);
        }));
    return true;
}

bool HostSystemBackend::disconnectWifi(const QString &ssid)
{
    if (m_offlineValidation)
        return setError(QStringLiteral("WiFi control is disabled during offline validation."));
    if (m_operationActive)
        return setError(QStringLiteral("Another host operation is already in progress."));
    if (ssid.trimmed().isEmpty())
        return setError(QStringLiteral("A connection name is required."));
    const QString connectionUuid = activeWifiConnectionUuid();
    if (connectionUuid.isEmpty())
        return setError(QStringLiteral("WiFi disconnect failed: the active connection was not found."));
    const auto result = runNmcli({
        QStringLiteral("--wait"), QStringLiteral("10"),
        QStringLiteral("connection"), QStringLiteral("down"),
        QStringLiteral("uuid"), connectionUuid}, 15000);
    if (!result.started || result.exitCode != 0)
        return setError(QStringLiteral("WiFi disconnect failed: %1").arg(QString::fromUtf8(result.err)));
    clearError();
    refreshWifi();
    setResult(QStringLiteral("Disconnected from %1.").arg(ssid));
    return true;
}

void HostSystemBackend::refreshSystemLogs()
{
    m_systemLogs.clear();
    if (!m_offlineValidation) {
        const auto result = runBounded(QStringLiteral("journalctl"), {
            QStringLiteral("--user"), QStringLiteral("-n"), QStringLiteral("200"),
            QStringLiteral("--no-pager"), QStringLiteral("-o"), QStringLiteral("short-iso")});
        if (result.started && result.exitCode == 0)
            m_systemLogs = QString::fromUtf8(result.out).split('\n', Qt::SkipEmptyParts);
        else
            setError(QStringLiteral("System log read failed: %1").arg(QString::fromUtf8(result.err)));
    }
    emit systemLogsChanged();
}

bool HostSystemBackend::exportSystemLogs(const QString &destination)
{
    if (m_offlineValidation)
        return setError(QStringLiteral("Log export is disabled during offline validation."));
    QString path = QUrl(destination).isLocalFile() ? QUrl(destination).toLocalFile() : destination;
    if (path.trimmed().isEmpty()) {
        const QString directory = QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation))
            .filePath(QStringLiteral("exports"));
        QDir().mkpath(directory);
        path = QDir(directory).filePath(QStringLiteral("bendcnc-system-%1.log")
            .arg(QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-hhmmss"))));
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return setError(QStringLiteral("System log export could not be opened."));
    const QByteArray text = m_systemLogs.join(QLatin1Char('\n')).toUtf8();
    if (file.write(text) != text.size() || !file.commit())
        return setError(QStringLiteral("System log export failed."));
    clearError();
    setResult(QStringLiteral("System logs exported to %1").arg(path));
    return true;
}

bool HostSystemBackend::sendDebugReport(const QString &machineLog, const QString &note,
                                        const QString &pressFirmware, double sinceEpochMs)
{
    if (m_offlineValidation)
        return setError(QStringLiteral("Debug reports are disabled during offline validation."));
    QStringList sections;
    sections << QStringLiteral("== BendCNC debug report ==")
             << QStringLiteral("time_utc=%1").arg(QDateTime::currentDateTimeUtc().toString(Qt::ISODate))
             << QStringLiteral("app_version=%1").arg(QCoreApplication::applicationVersion())
             << QStringLiteral("app_commit=%1").arg(QStringLiteral(BENDCNC_GIT_COMMIT))
             << QStringLiteral("press_firmware=%1").arg(pressFirmware)
             << QStringLiteral("note=%1").arg(note)
             << systemSummary() << QString();
    sections << QStringLiteral("== Machine log ==") << machineLog << QString();
    QStringList journalArgs{QStringLiteral("-b"), QStringLiteral("-n"), QStringLiteral("4000"),
                            QStringLiteral("--no-pager"), QStringLiteral("-o"), QStringLiteral("short-iso")};
    if (sinceEpochMs > 0)
        journalArgs << QStringLiteral("--since")
                    << QStringLiteral("@%1").arg(qint64(sinceEpochMs / 1000.0));
    const auto journal = runBounded(QStringLiteral("journalctl"), journalArgs);
    sections << (sinceEpochMs > 0
                     ? QStringLiteral("== System journal (since %1) ==")
                           .arg(QDateTime::fromMSecsSinceEpoch(qint64(sinceEpochMs)).toUTC().toString(Qt::ISODate))
                     : QStringLiteral("== System journal (this boot) =="))
             << (journal.started && journal.exitCode == 0 ? QString::fromUtf8(journal.out)
                                                          : QStringLiteral("unavailable: ") + QString::fromUtf8(journal.err));
    QString text = sections.join(QLatin1Char('\n'));
    constexpr int kMax = 3 * 1024 * 1024;
    if (text.size() > kMax)
        text = text.right(kMax);

    QNetworkRequest req(QUrl(LicenseManager::serverUrl() + QStringLiteral("/v1/debug-report")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setTransferTimeout(60000);
    const QJsonObject body{{QStringLiteral("device_id"), LicenseManager::computeDeviceId()},
                           {QStringLiteral("note"), note.left(500)},
                           {QStringLiteral("app_version"), QCoreApplication::applicationVersion()},
                           {QStringLiteral("press_firmware"), pressFirmware.left(48)},
                           {QStringLiteral("log"), text}};
    QNetworkReply *reply = m_updateNetwork.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    setResult(QStringLiteral("Sending debug report..."));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        const QJsonObject o = QJsonDocument::fromJson(reply->readAll()).object();
        if (reply->error() != QNetworkReply::NoError) {
            const QString detail = o.value(QStringLiteral("detail")).toString();
            setError(QStringLiteral("Debug report failed: %1").arg(detail.isEmpty() ? reply->errorString() : detail));
            emit debugReportFinished(false, m_lastError);
            return;
        }
        clearError();
        setResult(QStringLiteral("Debug report #%1 sent to BendCNC support.")
                      .arg(o.value(QStringLiteral("id")).toInt()));
        emit debugReportFinished(true, m_lastResult);
    });
    return true;
}

bool HostSystemBackend::copyTextToClipboard(const QString &text)
{
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard)
        return setError(QStringLiteral("Clipboard is unavailable."));
    clipboard->setText(text);
    clearError();
    setResult(QStringLiteral("Machine log copied to the clipboard."));
    return true;
}

bool HostSystemBackend::exportMachineLog(const QString &text, const QString &destination)
{
    QString path = QUrl(destination).isLocalFile() ? QUrl(destination).toLocalFile() : destination;
    if (path.trimmed().isEmpty()) {
        QString directory = QDir(QStringLiteral("/tmp")).exists()
            ? QStringLiteral("/tmp")
            : QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
        if (directory.isEmpty())
            directory = QDir::homePath();
        path = QDir(directory).filePath(QStringLiteral("machine_log_%1.txt")
            .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"))));
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return setError(QStringLiteral("Machine log export could not be opened."));
    const QByteArray bytes = text.toUtf8();
    if (file.write(bytes) != bytes.size() || !file.commit())
        return setError(QStringLiteral("Machine log export failed."));
    clearError();
    setResult(QStringLiteral("Machine log exported to %1").arg(path));
    return true;
}

QString HostSystemBackend::storageRoot() const
{
    QString root = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (root.isEmpty())
        root = QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("data"));
    return QDir(root).filePath(QStringLiteral("current"));
}

bool HostSystemBackend::copyTree(const QString &sourceRoot, const QString &destinationRoot) const
{
    const QDir source(sourceRoot);
    if (!source.exists())
        return false;
    QDir().mkpath(destinationRoot);
    const QFileInfoList entries = source.entryInfoList(QDir::NoDotAndDotDot | QDir::Files | QDir::Dirs);
    for (const QFileInfo &entry : entries) {
        const QString destination = QDir(destinationRoot).filePath(entry.fileName());
        if (entry.isDir()) {
            if (!copyTree(entry.absoluteFilePath(), destination))
                return false;
        } else {
            QFile::remove(destination);
            if (!QFile::copy(entry.absoluteFilePath(), destination))
                return false;
        }
    }
    return true;
}

bool HostSystemBackend::createBackup(const QString &destination)
{
    if (m_offlineValidation)
        return setError(QStringLiteral("Backup is disabled during offline validation."));
    QString path = QUrl(destination).isLocalFile() ? QUrl(destination).toLocalFile() : destination;
    if (path.trimmed().isEmpty()) {
        const QString directory = QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation))
            .filePath(QStringLiteral("backups"));
        path = QDir(directory).filePath(QStringLiteral("backup-%1")
            .arg(QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-hhmmss"))));
    }
    setOperation(true, 0.1);
    const bool ok = copyTree(storageRoot(), path);
    setOperation(false, ok ? 1.0 : 0.0);
    if (!ok)
        return setError(QStringLiteral("Backup could not be created."));
    clearError();
    setResult(QStringLiteral("Backup created at %1").arg(path));
    return true;
}

bool HostSystemBackend::restoreBackup(const QString &source, bool confirmed)
{
    if (!confirmed)
        return setError(QStringLiteral("Restore requires explicit confirmation."));
    if (m_offlineValidation)
        return setError(QStringLiteral("Restore is disabled during offline validation."));
    const QString sourcePath = QUrl(source).isLocalFile() ? QUrl(source).toLocalFile() : source;
    if (!QDir(sourcePath).exists())
        return setError(QStringLiteral("Backup source does not exist."));
    const QString root = storageRoot();
    const QString rollback = root + QStringLiteral(".rollback-")
        + QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMddhhmmsszzz"));
    setOperation(true, 0.1);
    if (QDir(root).exists() && !copyTree(root, rollback)) {
        setOperation(false, 0.0);
        return setError(QStringLiteral("Restore rollback snapshot could not be created."));
    }
    QDir(root).removeRecursively();
    const bool ok = copyTree(sourcePath, root);
    if (!ok) {
        QDir(root).removeRecursively();
        copyTree(rollback, root);
    }
    setOperation(false, ok ? 1.0 : 0.0);
    if (!ok)
        return setError(QStringLiteral("Restore failed; rollback was attempted."));
    clearError();
    setResult(QStringLiteral("Backup restored from %1").arg(sourcePath));
    return true;
}

// ---------------------------------------------------------------------------
// Backup manager (Java BackupManager parity)
// ---------------------------------------------------------------------------
namespace {
const QRegularExpression &backupNamePattern()
{
    static const QRegularExpression re(QStringLiteral("^B(\\d{10})(.*)$"));
    return re;
}
const QRegularExpression &legacyBackupPattern()
{
    static const QRegularExpression re(QStringLiteral("^backup-(\\d{8}-\\d{6})$"));
    return re;
}

QVariantMap describeBackupFolder(const QFileInfo &info)
{
    const QString folder = info.fileName();
    QDateTime when;
    QString name;
    bool recognized = false;
    const auto m = backupNamePattern().match(folder);
    if (m.hasMatch()) {
        when = QDateTime::fromString(QStringLiteral("20") + m.captured(1),
                                     QStringLiteral("yyyyMMddHHmm"));
        name = m.captured(2);
        recognized = when.isValid();
    } else {
        const auto legacy = legacyBackupPattern().match(folder);
        if (legacy.hasMatch()) {
            when = QDateTime::fromString(legacy.captured(1), QStringLiteral("yyyyMMdd-hhmmss"));
            when.setTimeZone(QTimeZone::UTC);
            when = when.toLocalTime();
            recognized = when.isValid();
        }
    }
    if (!recognized)
        return {};
    const bool isAuto = name.isEmpty();
    QVariantMap row;
    row.insert(QStringLiteral("path"), info.absoluteFilePath());
    row.insert(QStringLiteral("folder"), folder);
    row.insert(QStringLiteral("auto"), isAuto);
    row.insert(QStringLiteral("label"), isAuto
        ? QStringLiteral("AUTO %1").arg(when.toString(QStringLiteral("yyMMddHHmm")))
        : name);
    row.insert(QStringLiteral("dateMs"), double(when.toMSecsSinceEpoch()));
    row.insert(QStringLiteral("dateText"), when.toString(QStringLiteral("MMM. d, yyyy HH:mm")));
    return row;
}

QVariantList describeBackupsIn(const QString &directory)
{
    QVariantList rows;
    const QFileInfoList entries = QDir(directory).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QFileInfo &entry : entries) {
        const QVariantMap row = describeBackupFolder(entry);
        if (!row.isEmpty())
            rows.append(row);
    }
    std::sort(rows.begin(), rows.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("dateMs")).toDouble()
             > b.toMap().value(QStringLiteral("dateMs")).toDouble();
    });
    return rows;
}
} // namespace

QString HostSystemBackend::backupsDirectory() const
{
    return QDir(QFileInfo(storageRoot()).absolutePath()).filePath(QStringLiteral("backups"));
}

bool HostSystemBackend::isInsideBackups(const QString &path) const
{
    const QString root = QDir::cleanPath(QFileInfo(backupsDirectory()).absoluteFilePath()) + QLatin1Char('/');
    const QString candidate = QDir::cleanPath(QFileInfo(path).absoluteFilePath());
    return candidate.startsWith(root, Qt::CaseInsensitive) && !candidate.mid(root.size()).contains(QLatin1Char('/'));
}

QVariantList HostSystemBackend::listBackups() const
{
    return describeBackupsIn(backupsDirectory());
}

QString HostSystemBackend::createBackupFolder(const QString &name)
{
    QString clean = name.trimmed();
    clean.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9 _.-]")), QStringLiteral("_"));
    const QString folder = QStringLiteral("B%1%2")
        .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyMMddHHmm")), clean);
    const QString path = QDir(backupsDirectory()).filePath(folder);
    if (QDir(path).exists()) {
        setError(QStringLiteral("Backup \"%1\" already exists.").arg(folder));
        return {};
    }
    setOperation(true, 0.1);
    const bool ok = copyTree(storageRoot(), path);
    setOperation(false, ok ? 1.0 : 0.0);
    if (!ok) {
        QDir(path).removeRecursively();
        setError(QStringLiteral("Backup could not be created."));
        return {};
    }
    clearError();
    setResult(QStringLiteral("Backup created: %1").arg(folder));
    emit backupsChanged();
    return path;
}

bool HostSystemBackend::createNamedBackup(const QString &name)
{
    if (m_offlineValidation)
        return setError(QStringLiteral("Backup is disabled during offline validation."));
    return !createBackupFolder(name).isEmpty();
}

void HostSystemBackend::runAutoBackup()
{
    if (m_offlineValidation || !QDir(storageRoot()).exists())
        return;
    createBackupFolder(QString());
    applyAutoBackupRetention();
}

void HostSystemBackend::applyAutoBackupRetention()
{
    // Java: newest 24 auto backups kept (hourly); up to index 54 one per day;
    // older ones one per month. Named backups are never pruned.
    const QVariantList rows = listBackups();
    int index = 0;
    QSet<QString> keptDays;
    QSet<QString> keptMonths;
    bool removed = false;
    for (const QVariant &value : rows) {
        const QVariantMap row = value.toMap();
        if (!row.value(QStringLiteral("auto")).toBool())
            continue;
        const QDateTime when = QDateTime::fromMSecsSinceEpoch(
            qint64(row.value(QStringLiteral("dateMs")).toDouble()));
        const QString day = when.toString(QStringLiteral("yyyyMMdd"));
        const QString month = when.toString(QStringLiteral("yyyyMM"));
        bool keep;
        if (index < 24) {
            keep = true;
        } else if (index < 54) {
            keep = !keptDays.contains(day);
        } else {
            keep = !keptMonths.contains(month);
        }
        keptDays.insert(day);
        keptMonths.insert(month);
        if (!keep) {
            QDir(row.value(QStringLiteral("path")).toString()).removeRecursively();
            removed = true;
        }
        ++index;
    }
    if (removed)
        emit backupsChanged();
}

bool HostSystemBackend::deleteBackup(const QString &path, bool confirmed)
{
    if (!confirmed)
        return setError(QStringLiteral("Delete requires explicit confirmation."));
    if (m_offlineValidation)
        return setError(QStringLiteral("Backup delete is disabled during offline validation."));
    if (!isInsideBackups(path) || !QDir(path).exists())
        return setError(QStringLiteral("Backup not found."));
    if (!QDir(path).removeRecursively())
        return setError(QStringLiteral("Backup could not be deleted."));
    clearError();
    setResult(QStringLiteral("Backup deleted."));
    emit backupsChanged();
    return true;
}

QVariantList HostSystemBackend::listExternalVolumes() const
{
    QVariantList volumes;
    const QString systemRoot = QDir::rootPath();
    for (const QStorageInfo &volume : QStorageInfo::mountedVolumes()) {
        if (!volume.isValid() || !volume.isReady() || volume.isReadOnly())
            continue;
        const QString root = volume.rootPath();
#ifdef Q_OS_WIN
        if (root.compare(systemRoot, Qt::CaseInsensitive) == 0)
            continue;
#else
        if (!root.startsWith(QStringLiteral("/media/")) && !root.startsWith(QStringLiteral("/run/media/"))
            && !root.startsWith(QStringLiteral("/mnt/")))
            continue;
#endif
        QVariantMap row;
        row.insert(QStringLiteral("root"), root);
        const QString label = volume.displayName().isEmpty() ? root : volume.displayName();
        row.insert(QStringLiteral("label"), label);
        volumes.append(row);
    }
    return volumes;
}

bool HostSystemBackend::exportBackup(const QString &path, const QString &volumeRoot)
{
    if (!isInsideBackups(path) || !QDir(path).exists())
        return setError(QStringLiteral("Backup not found."));
    bool knownVolume = false;
    for (const QVariant &v : listExternalVolumes())
        knownVolume = knownVolume || v.toMap().value(QStringLiteral("root")).toString() == volumeRoot;
    if (!knownVolume)
        return setError(QStringLiteral("USB drive not available."));
    const QString target = QDir(QDir(volumeRoot).filePath(QStringLiteral("BendCNC-backups")))
        .filePath(QFileInfo(path).fileName());
    setOperation(true, 0.1);
    QDir(target).removeRecursively();
    const bool ok = copyTree(path, target);
    setOperation(false, ok ? 1.0 : 0.0);
    if (!ok)
        return setError(QStringLiteral("Backup could not be copied to the USB drive."));
#ifdef Q_OS_LINUX
    runBounded(QStringLiteral("sync"), {}, 15000);
#endif
    clearError();
    setResult(QStringLiteral("Backup copied to %1").arg(target));
    return true;
}

QVariantList HostSystemBackend::listExternalBackups() const
{
    QVariantList rows;
    for (const QVariant &v : listExternalVolumes()) {
        const QVariantMap volume = v.toMap();
        const QString root = volume.value(QStringLiteral("root")).toString();
        for (const QString &dir : {QDir(root).filePath(QStringLiteral("BendCNC-backups")), root}) {
            for (const QVariant &rowValue : describeBackupsIn(dir)) {
                QVariantMap row = rowValue.toMap();
                row.insert(QStringLiteral("volume"), volume.value(QStringLiteral("label")));
                rows.append(row);
            }
        }
    }
    return rows;
}

void HostSystemBackend::restartApplication()
{
    // Give QML a moment to show the result, then restart. On the kiosk a
    // non-zero exit makes systemd (Restart=on-failure) relaunch; elsewhere
    // relaunch ourselves with the same arguments.
    QTimer::singleShot(400, qApp, [] {
#ifndef Q_OS_LINUX
        QProcess::startDetached(QCoreApplication::applicationFilePath(),
                                QCoreApplication::arguments().mid(1));
        QCoreApplication::exit(0);
#else
        if (QCoreApplication::arguments().contains(QStringLiteral("--fullscreen"))) {
            QCoreApplication::exit(75);
        } else {
            QProcess::startDetached(QCoreApplication::applicationFilePath(),
                                    QCoreApplication::arguments().mid(1));
            QCoreApplication::exit(0);
        }
#endif
    });
}

bool HostSystemBackend::restoreBackupAndRestart(const QString &path, bool confirmed)
{
    if (!confirmed)
        return setError(QStringLiteral("Restore requires explicit confirmation."));
    if (m_offlineValidation)
        return setError(QStringLiteral("Restore is disabled during offline validation."));
    if (!isInsideBackups(path) || !QDir(path).exists())
        return setError(QStringLiteral("Backup not found."));
    // Java: always snapshot current data as an AUTO backup before restoring.
    if (QDir(storageRoot()).exists() && createBackupFolder(QString()).isEmpty()
        && !m_lastError.contains(QStringLiteral("already exists")))
        return false;
    if (!restoreBackup(path, true))
        return false;
    setResult(QStringLiteral("Backup restored. Restarting BendCNC..."));
    restartApplication();
    return true;
}

bool HostSystemBackend::importAndRestoreBackup(const QString &externalPath, bool confirmed)
{
    if (!confirmed)
        return setError(QStringLiteral("Restore requires explicit confirmation."));
    if (m_offlineValidation)
        return setError(QStringLiteral("Restore is disabled during offline validation."));
    bool known = false;
    for (const QVariant &v : listExternalBackups())
        known = known || v.toMap().value(QStringLiteral("path")).toString() == externalPath;
    if (!known)
        return setError(QStringLiteral("External backup not found."));
    const QString target = QDir(backupsDirectory()).filePath(QFileInfo(externalPath).fileName());
    if (!QDir(target).exists() && !copyTree(externalPath, target)) {
        QDir(target).removeRecursively();
        return setError(QStringLiteral("Backup could not be copied from the USB drive."));
    }
    emit backupsChanged();
    return restoreBackupAndRestart(target, true);
}

bool HostSystemBackend::stageSoftwareUpdate(const QString &packagePath, bool confirmed)
{
    if (!confirmed)
        return setError(QStringLiteral("Software update requires explicit confirmation."));
    if (m_offlineValidation)
        return setError(QStringLiteral("Software update is disabled during offline validation."));
    const QString source = QUrl(packagePath).isLocalFile() ? QUrl(packagePath).toLocalFile() : packagePath;
    const QFileInfo info(source);
    if (!info.isFile())
        return setError(QStringLiteral("Update package does not exist."));
    const QString stageDir = QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation))
        .filePath(QStringLiteral("updates/staged"));
    QDir().mkpath(stageDir);
    const QString destination = QDir(stageDir).filePath(info.fileName());
    setOperation(true, 0.1);
    QFile::remove(destination);
    const bool ok = QFile::copy(source, destination);
    setOperation(false, ok ? 1.0 : 0.0);
    if (!ok)
        return setError(QStringLiteral("Update package could not be staged."));
    clearError();
    setResult(QStringLiteral("Update staged at %1. It has not been applied.").arg(destination));
    return true;
}
