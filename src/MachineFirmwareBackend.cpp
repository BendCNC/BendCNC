#include "MachineFirmwareBackend.h"

#include "LicenseManager.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QSet>
#include <QRegularExpression>
#include <QSaveFile>
#include <QTimer>
#include <QUuid>

#include <cmath>

namespace {
const QString kHelper = QStringLiteral("/usr/local/sbin/bendcnc-flash-firmware");
const QString kSudo = QStringLiteral("/usr/bin/sudo");
const QString kHelperLogDir = QStringLiteral("/data/bendcnc-firmware/logs");
const QString kPressCatalogDir = QStringLiteral("/data/bendcnc-qt-state/firmware");
const QString kManifestName = QStringLiteral("firmware-catalog.json");
// Written only by the remote updater; never edited by hand.
const QString kRemoteManifestName = QStringLiteral("remote-firmware.json");
constexpr int kUpdateIntervalMs = 6 * 60 * 60 * 1000;
const QString kPendingName = QStringLiteral("last-flash-request.json");
const QString kRequestFile = QStringLiteral("/tmp/bendcnc-firmware.request");
constexpr qint64 kMinImageBytes = 4096;   // helper bounds
constexpr qint64 kMaxImageBytes = 262144;

QString fileSha256(const QString &path, qint64 *size = nullptr)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    if (size)
        *size = f.size();
    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (!hash.addData(&f))
        return {};
    return QString::fromLatin1(hash.result().toHex());
}

QMap<QString, QString> parseKeyValues(const QByteArray &text)
{
    QMap<QString, QString> values;
    const QList<QByteArray> lines = text.split('\n');
    for (const QByteArray &raw : lines) {
        const QByteArray line = raw.trimmed();
        const int eq = line.indexOf('=');
        if (eq > 0)
            values.insert(QString::fromUtf8(line.left(eq)), QString::fromUtf8(line.mid(eq + 1)));
    }
    return values;
}

bool terminalState(const QString &state)
{
    return state == QLatin1String("SUCCEEDED") || state == QLatin1String("FAILED")
        || state == QLatin1String("ROLLED_BACK");
}
} // namespace

MachineFirmwareBackend::MachineFirmwareBackend(bool offlineValidation, QObject *parent)
    : QObject(parent), m_offlineValidation(offlineValidation)
{
    const QByteArray overrideDir = qgetenv("BENDCNC_FIRMWARE_CATALOG_DIR");
#ifdef Q_OS_LINUX
    const bool onPress = !m_offlineValidation && QFileInfo(kHelper).isExecutable();
#else
    const bool onPress = false;
#endif
    if (!overrideDir.isEmpty())
        m_catalogDirectory = QDir::cleanPath(QString::fromLocal8Bit(overrideDir));
    else if (onPress)
        m_catalogDirectory = kPressCatalogDir;
    else
        m_catalogDirectory = QDir(QCoreApplication::applicationDirPath())
                                 .absoluteFilePath(QStringLiteral("firmware-catalog"));
    // ORIGINAL factory firmware ships inside every app bundle so rollback is
    // always possible, even on a fresh customer install.
    const QString bundled = QDir(QCoreApplication::applicationDirPath())
                                .absoluteFilePath(QStringLiteral("assets/firmware-catalog"));
    if (QFileInfo(bundled).isDir())
        m_bundledDirectory = bundled;

#ifdef BENDCNC_LICENSING
    m_remoteEnabled = !m_offlineValidation && qgetenv("BENDCNC_FIRMWARE_UPDATES") != "0";
#endif
    if (m_remoteEnabled) {
        m_net = new QNetworkAccessManager(this);
        QTimer::singleShot(30000, this, &MachineFirmwareBackend::checkForUpdate);
        auto *updateTimer = new QTimer(this);
        updateTimer->setInterval(kUpdateIntervalMs);
        connect(updateTimer, &QTimer::timeout, this, &MachineFirmwareBackend::checkForUpdate);
        updateTimer->start();
    }

    if (m_offlineValidation)
        m_unavailableReason = tr("Offline validation: firmware flashing is disabled.");
    else if (!onPress)
        m_unavailableReason = tr("Firmware flashing is only available on the press computer "
                                 "with the supervised flasher installed.");

    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(1000);
    connect(m_pollTimer, &QTimer::timeout, this, &MachineFirmwareBackend::pollStatus);

    refreshCatalog();
    loadPendingRequest();
    if (onPress)
        QTimer::singleShot(0, this, &MachineFirmwareBackend::refreshStatus);
}

void MachineFirmwareBackend::refreshCatalog()
{
    m_images.clear();
    m_catalogError.clear();
    QStringList errors;
    appendCatalog(m_catalogDirectory, kManifestName, m_bundledDirectory.isEmpty(), errors);
    if (!m_bundledDirectory.isEmpty() && m_bundledDirectory != m_catalogDirectory)
        appendCatalog(m_bundledDirectory, kManifestName, true, errors);
    appendCatalog(m_catalogDirectory, kRemoteManifestName, false, errors);
    // Operators only need two choices: the factory ORIGINAL (rollback) and the
    // most recent verified custom image. Older custom images stay on disk.
    {
        const QString originalVersion = QStringLiteral("[LS-BEND v1.1]");
        QVariant original, newest;
        qint64 newestMs = -1;
        for (const QVariant &v : std::as_const(m_images)) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("expectedVersion")).toString() == originalVersion) {
                if (!original.isValid() || (!original.toMap().value(QStringLiteral("verified")).toBool()
                                            && m.value(QStringLiteral("verified")).toBool()))
                    original = v;
                continue;
            }
            const qint64 ms = m.value(QStringLiteral("verified")).toBool()
                ? m.value(QStringLiteral("modifiedMs")).toLongLong() : -2;
            if (!newest.isValid() || ms > newestMs) {
                newest = v;
                newestMs = ms;
            }
        }
        m_images.clear();
        if (newest.isValid())
            m_images.append(newest);
        if (original.isValid())
            m_images.append(original);
    }
    if (m_images.isEmpty())
        m_catalogError = errors.isEmpty() ? tr("Firmware catalog lists no images.") : errors.join(QStringLiteral("; "));
    emit catalogChanged();
}

void MachineFirmwareBackend::appendCatalog(const QString &directory, const QString &manifestName,
                                           bool reportMissing, QStringList &errors)
{
    const QString manifestPath = QDir(directory).absoluteFilePath(manifestName);
    QFile f(manifestPath);
    if (!f.open(QIODevice::ReadOnly)) {
        if (reportMissing)
            errors << tr("No firmware catalog at %1").arg(manifestPath);
        return;
    }
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        errors << tr("Invalid firmware catalog %1: %2").arg(manifestPath, parseError.errorString());
        return;
    }
    QSet<QString> seenSha, seenId;
    for (const QVariant &v : std::as_const(m_images)) {
        seenSha.insert(v.toMap().value(QStringLiteral("sha256")).toString());
        seenId.insert(v.toMap().value(QStringLiteral("id")).toString());
    }
    static const QRegularExpression shaRe(QStringLiteral("^[0-9a-f]{64}$"));
    static const QRegularExpression labelRe(QStringLiteral("^[A-Za-z0-9._-]{1,64}$"));
    static const QRegularExpression fileRe(QStringLiteral("^[A-Za-z0-9._-]{1,96}$"));
    static const QStringList allowedVersions = {
        QStringLiteral("[LS-BEND v1.1]"), QStringLiteral("[LS-BEND v1.2]"), QStringLiteral("[LS-BEND v1.3]"),
        QStringLiteral("[BENDCNC v1.3]")};

    const QJsonArray entries = doc.object().value(QStringLiteral("images")).toArray();
    for (const QJsonValue &value : entries) {
        const QJsonObject o = value.toObject();
        QVariantMap image = o.toVariantMap();
        const QString file = o.value(QStringLiteral("file")).toString();
        const QString sha = o.value(QStringLiteral("sha256")).toString().toLower();
        const QString label = o.value(QStringLiteral("label")).toString();
        const QString expected = o.value(QStringLiteral("expectedVersion")).toString();
        if (seenSha.contains(sha))
            continue; // same image already listed by a higher-priority catalog
        if (seenId.contains(image.value(QStringLiteral("id")).toString()))
            image.insert(QStringLiteral("id"), image.value(QStringLiteral("id")).toString() + QStringLiteral("-") + sha.left(8));
        QString error;
        if (o.value(QStringLiteral("id")).toString().isEmpty())
            error = tr("missing id");
        else if (!fileRe.match(file).hasMatch())
            error = tr("invalid file name");
        else if (!shaRe.match(sha).hasMatch())
            error = tr("invalid sha256");
        else if (!labelRe.match(label).hasMatch())
            error = tr("invalid label");
        else if (!allowedVersions.contains(expected))
            error = tr("unsupported expected version %1").arg(expected);
        const QString path = QDir(directory).absoluteFilePath(file);
        qint64 size = -1;
        QString actual;
        if (error.isEmpty()) {
            actual = fileSha256(path, &size);
            if (actual.isEmpty())
                error = tr("image file missing");
            else if (actual != sha)
                error = tr("SHA-256 mismatch (%1)").arg(actual.left(12));
            else if (size < kMinImageBytes || size > kMaxImageBytes)
                error = tr("image size %1 B outside flasher bounds").arg(size);
        }
        image.insert(QStringLiteral("sha256"), sha);
        image.insert(QStringLiteral("path"), path);
        image.insert(QStringLiteral("actualSize"), size);
        image.insert(QStringLiteral("modifiedMs"), QFileInfo(path).exists()
            ? QFileInfo(path).lastModified().toMSecsSinceEpoch() : qint64(0));
        image.insert(QStringLiteral("verified"), error.isEmpty());
        image.insert(QStringLiteral("verifyError"), error);
        m_images.append(image);
        seenSha.insert(sha);
        seenId.insert(image.value(QStringLiteral("id")).toString());
    }
}

void MachineFirmwareBackend::remoteDone(const QString &state, const QString &message)
{
    m_remoteBusy = false;
    m_remoteState = state;
    m_remoteMessage = message;
    emit remoteChanged();
}

void MachineFirmwareBackend::checkForUpdate()
{
    if (!m_remoteEnabled || m_remoteBusy)
        return;
    m_remoteBusy = true;
    m_remoteState = QStringLiteral("CHECKING");
    m_remoteMessage = tr("Checking for firmware updates...");
    emit remoteChanged();
    QNetworkRequest req(QUrl(LicenseManager::serverUrl() + QStringLiteral("/v1/firmware")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setTransferTimeout(20000);
    QJsonObject body{{QStringLiteral("device_id"), LicenseManager::computeDeviceId()},
                     {QStringLiteral("app_version"), QCoreApplication::applicationVersion()},
                     {QStringLiteral("app_commit"), QStringLiteral(BENDCNC_GIT_COMMIT)}};
    // Report what the press is actually running so the admin dashboard can show it.
    const QString pressVersion = m_machineControl
        ? m_machineControl->property("pressFirmwareVersion").toString() : QString();
    if (!pressVersion.isEmpty())
        body.insert(QStringLiteral("press_firmware"), pressVersion);
    if (!m_appliedHash.isEmpty())
        body.insert(QStringLiteral("firmware_sha"), m_appliedHash);
    QNetworkReply *reply = m_net->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() { handleFirmwareInfo(reply); });
}

static QString safeNetworkError(QNetworkReply *reply)
{
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (status > 0)
        return MachineFirmwareBackend::tr("update server unavailable (code %1), try again later").arg(status);
    return MachineFirmwareBackend::tr("no connection to the update server");
}

void MachineFirmwareBackend::handleFirmwareInfo(QNetworkReply *reply)
{
    reply->deleteLater();
    const QByteArray data = reply->readAll();
    if (reply->error() != QNetworkReply::NoError) {
        remoteDone(QStringLiteral("OFFLINE"), tr("Firmware update check failed: %1").arg(safeNetworkError(reply)));
        return;
    }
    const QJsonObject o = QJsonDocument::fromJson(data).object();
    if (!o.value(QStringLiteral("available")).toBool()) {
        remoteDone(QStringLiteral("UP_TO_DATE"), tr("No firmware update is published for this machine."));
        return;
    }
    // The signed metadata is the only trusted input; the URL just points at the bytes.
    const QJsonObject meta = LicenseManager::verifyToken(o.value(QStringLiteral("release")).toString().toLatin1(),
                                                         LicenseManager::publicKey());
    static const QRegularExpression shaRe(QStringLiteral("^[0-9a-f]{64}$"));
    static const QRegularExpression versionRe(QStringLiteral("^[A-Za-z0-9._-]{1,48}$"));
    static const QRegularExpression channelRe(QStringLiteral("^(stable|beta)$"));
    static const QRegularExpression bannerRe(QStringLiteral("^\\[(?:BENDCNC|LS-BEND) v\\d+\\.\\d+\\]$"));
    const QString sha = meta.value(QStringLiteral("sha256")).toString();
    const qint64 size = meta.value(QStringLiteral("size")).toInteger();
    if (meta.value(QStringLiteral("kind")).toString() != QLatin1String("firmware")
        || !shaRe.match(sha).hasMatch()
        || !versionRe.match(meta.value(QStringLiteral("version")).toString()).hasMatch()
        || !channelRe.match(meta.value(QStringLiteral("channel")).toString()).hasMatch()
        || !bannerRe.match(meta.value(QStringLiteral("expectedVersion")).toString()).hasMatch()
        || size < kMinImageBytes || size > kMaxImageBytes) {
        remoteDone(QStringLiteral("REJECTED"), tr("Firmware update rejected: invalid signature or metadata."));
        return;
    }
    for (const QVariant &v : std::as_const(m_images)) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("sha256")).toString() == sha && m.value(QStringLiteral("verified")).toBool()) {
            remoteDone(QStringLiteral("UP_TO_DATE"), tr("Latest firmware %1 is already on this machine.")
                                                         .arg(meta.value(QStringLiteral("version")).toString()));
            return;
        }
    }
    const QUrl url(o.value(QStringLiteral("download_url")).toString());
    if (!url.isValid() || url.scheme() != QLatin1String("https")) {
        remoteDone(QStringLiteral("OFFLINE"), tr("Firmware download link unavailable."));
        return;
    }
    m_remoteMessage = tr("Downloading firmware %1...").arg(meta.value(QStringLiteral("version")).toString());
    m_remoteState = QStringLiteral("DOWNLOADING");
    emit remoteChanged();
    QNetworkRequest req(url);
    req.setTransferTimeout(60000);
    QNetworkReply *dl = m_net->get(req);
    connect(dl, &QNetworkReply::downloadProgress, dl, [dl](qint64 received, qint64) {
        if (received > kMaxImageBytes)
            dl->abort();
    });
    connect(dl, &QNetworkReply::finished, this, [this, dl, meta]() { handleFirmwareDownload(dl, meta); });
}

void MachineFirmwareBackend::handleFirmwareDownload(QNetworkReply *reply, const QJsonObject &meta)
{
    reply->deleteLater();
    const QByteArray data = reply->readAll();
    if (reply->error() != QNetworkReply::NoError) {
        remoteDone(QStringLiteral("OFFLINE"), tr("Firmware download failed: %1").arg(safeNetworkError(reply)));
        return;
    }
    const QString sha = meta.value(QStringLiteral("sha256")).toString();
    if (data.size() != meta.value(QStringLiteral("size")).toInteger()
        || QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex()) != sha) {
        remoteDone(QStringLiteral("REJECTED"), tr("Downloaded firmware failed SHA-256 verification; discarded."));
        return;
    }
    const QString channel = meta.value(QStringLiteral("channel")).toString();
    const QString version = meta.value(QStringLiteral("version")).toString();
    const QString file = QStringLiteral("remote-%1-%2.bin").arg(channel, sha.left(12));
    QDir dir(m_catalogDirectory);
    dir.mkpath(QStringLiteral("."));
    QSaveFile bin(dir.absoluteFilePath(file));
    if (!bin.open(QIODevice::WriteOnly) || bin.write(data) != data.size() || !bin.commit()) {
        remoteDone(QStringLiteral("FAILED"), tr("Could not save the downloaded firmware in %1.").arg(m_catalogDirectory));
        return;
    }
    QJsonObject image{
        {QStringLiteral("id"), QStringLiteral("remote-") + channel},
        {QStringLiteral("kind"), QStringLiteral("current")},
        {QStringLiteral("title"), channel == QLatin1String("beta") ? QStringLiteral("BETA") : QStringLiteral("LATEST")},
        {QStringLiteral("version"), version},
        {QStringLiteral("description"), meta.value(QStringLiteral("notes")).toString()},
        {QStringLiteral("expectedVersion"), meta.value(QStringLiteral("expectedVersion")).toString()},
        {QStringLiteral("label"), QStringLiteral("remote-") + version},
        {QStringLiteral("file"), file},
        {QStringLiteral("sha256"), sha},
        {QStringLiteral("size"), data.size()},
        {QStringLiteral("autoRollback"), true},
        {QStringLiteral("remote"), true},
        {QStringLiteral("channel"), channel},
        {QStringLiteral("published"), meta.value(QStringLiteral("published"))}};
    const QJsonObject manifest{{QStringLiteral("schema"), 1}, {QStringLiteral("images"), QJsonArray{image}}};
    QSaveFile mf(dir.absoluteFilePath(kRemoteManifestName));
    const QByteArray text = QJsonDocument(manifest).toJson(QJsonDocument::Indented);
    if (!mf.open(QIODevice::WriteOnly) || mf.write(text) != text.size() || !mf.commit()) {
        remoteDone(QStringLiteral("FAILED"), tr("Could not save the firmware update manifest."));
        return;
    }
    // Keep only the newest downloaded image (ORIGINAL and local images are untouched).
    const QStringList old = dir.entryList({QStringLiteral("remote-*.bin")}, QDir::Files);
    for (const QString &name : old)
        if (name != file)
            dir.remove(name);
    refreshCatalog();
    // Customer-facing name: "[LS-BEND v1.3]" -> "BEND 1.3" (build id stays in the log).
    QString friendly = meta.value(QStringLiteral("expectedVersion")).toString();
    friendly.remove(QLatin1Char('[')).remove(QLatin1Char(']')).remove(QStringLiteral("LS-"));
    friendly.replace(QStringLiteral(" v"), QStringLiteral(" "));
    if (friendly.trimmed().isEmpty())
        friendly = version;
    remoteDone(QStringLiteral("DOWNLOADED"),
               tr("Firmware %1 is ready to install (machine idle, hydraulics off).").arg(friendly.trimmed()));
}

QVariantMap MachineFirmwareBackend::findImage(const QString &id) const
{
    for (const QVariant &v : m_images) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("id")).toString() == id)
            return m;
    }
    return {};
}

QString MachineFirmwareBackend::machineBlockReason() const
{
    QObject *mc = m_machineControl.data();
    if (!mc)
        return tr("Machine controller backend unavailable.");
    if (!mc->property("pressConnected").toBool())
        return tr("Press controller is not connected.");
    if (!mc->property("pressTelemetryFresh").toBool())
        return tr("Press telemetry is not fresh.");
    if (mc->property("pressOperationActive").toBool() || mc->property("commandOperationActive").toBool()
        || mc->property("thcContinuousActive").toBool())
        return tr("A machine operation is active.");
    const QString state = mc->property("pressMachineState").toString();
    static const QStringList allowed = {QStringLiteral("IDLE"), QStringLiteral("STARTUP_HOMING_REQUIRED"),
                                        QStringLiteral("HYDRAULIC_SHUTDOWN")};
    if (!allowed.contains(state))
        return tr("Machine state %1 does not allow flashing (requires IDLE, "
                  "STARTUP_HOMING_REQUIRED or HYDRAULIC_SHUTDOWN).").arg(state);
    const double velocity = mc->property("measuredRamVelocityAvailable").toBool()
        ? mc->property("measuredRamVelocity").toDouble()
        : mc->property("ramVelocity").toDouble();
    if (!std::isfinite(velocity) || std::abs(velocity) > 0.0005)
        return tr("Ram is moving.");
    if (mc->property("bendPedal").toBool() || mc->property("physicalPedal").toBool())
        return tr("Pedal is pressed.");
    return {};
}

void MachineFirmwareBackend::setState(const QString &state, const QString &message)
{
    m_state = state;
    m_message = message;
    emit flashStateChanged();
}

void MachineFirmwareBackend::fail(const QString &message)
{
    m_busy = false;
    m_activeImage.clear();
    setPressFlashLock(false);
    setState(QStringLiteral("FAILED"), message);
    emit flashFinished(false, message);
}

bool MachineFirmwareBackend::startFlash(const QString &imageId, bool confirmed, bool uiGateClear)
{
    if (m_busy)
        return false;
    if (!m_unavailableReason.isEmpty()) {
        setState(QStringLiteral("UNAVAILABLE"), m_unavailableReason);
        return false;
    }
    if (!confirmed) {
        setState(QStringLiteral("IDLE"), tr("Flash requires explicit confirmation."));
        return false;
    }
    if (!uiGateClear) {
        setState(QStringLiteral("BLOCKED"), tr("A run, tool change or press activation is active."));
        return false;
    }
    const QString block = machineBlockReason();
    if (!block.isEmpty()) {
        setState(QStringLiteral("BLOCKED"), block);
        return false;
    }
    refreshCatalog();
    const QVariantMap image = findImage(imageId);
    if (image.isEmpty() || !image.value(QStringLiteral("verified")).toBool()) {
        setState(QStringLiteral("BLOCKED"), image.isEmpty()
            ? tr("Firmware image %1 not found in catalog.").arg(imageId)
            : tr("Firmware image failed verification: %1").arg(image.value(QStringLiteral("verifyError")).toString()));
        return false;
    }
    m_activeImage = image;
    m_busy = true;
    m_logTail.clear();
    setState(QStringLiteral("PREFLIGHT"), tr("Checking supervised flasher and press USB binding..."));
    runPreflight();
    return true;
}

void MachineFirmwareBackend::runPreflight()
{
    auto *process = new QProcess(this);
    m_process = process;
    connect(process, &QProcess::finished, this, [this, process](int exitCode, QProcess::ExitStatus status) {
        const QByteArray out = process->readAllStandardOutput();
        const QByteArray err = process->readAllStandardError();
        process->deleteLater();
        m_process = nullptr;
        m_logTail = QString::fromUtf8(out + err).trimmed();
        if (status != QProcess::NormalExit || exitCode != 0 || !out.contains("FLASHER_READY=1")) {
            fail(tr("Flasher preflight failed (exit %1). Is the press controller connected?").arg(exitCode));
            return;
        }
        stageAndQueue();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        process->deleteLater();
        m_process = nullptr;
        fail(tr("Could not start the flasher preflight."));
    });
    process->start(kHelper, {QStringLiteral("--preflight")});
    QTimer::singleShot(30000, process, [process]() { process->kill(); });
}

void MachineFirmwareBackend::stageAndQueue()
{
    // Final re-checks immediately before the irreversible queue step.
    const QString block = machineBlockReason();
    if (!block.isEmpty()) {
        fail(block);
        return;
    }
    const QString path = m_activeImage.value(QStringLiteral("path")).toString();
    const QString sha = m_activeImage.value(QStringLiteral("sha256")).toString();
    qint64 size = -1;
    if (fileSha256(path, &size) != sha) {
        fail(tr("SHA-256 verification failed immediately before staging."));
        return;
    }
    if (QFileInfo::exists(kRequestFile)) {
        fail(tr("Another flash request is already pending (%1).").arg(kRequestFile));
        return;
    }
    setState(QStringLiteral("STAGING"), tr("Staging verified image %1...").arg(sha.left(12)));

    const QString token = QUuid::createUuid().toString(QUuid::Id128);
    const QString image = QStringLiteral("/tmp/bendcnc-firmware-%1.bin").arg(token);
    const QString manifest = QStringLiteral("/tmp/bendcnc-firmware-%1.manifest").arg(token);
    auto cleanup = [image, manifest]() { QFile::remove(image); QFile::remove(manifest); };

    QFile::remove(image + QStringLiteral(".part"));
    if (!QFile::copy(path, image + QStringLiteral(".part"))
        || fileSha256(image + QStringLiteral(".part")) != sha
        || !QFile::rename(image + QStringLiteral(".part"), image)) {
        QFile::remove(image + QStringLiteral(".part"));
        fail(tr("Could not stage the firmware image in /tmp."));
        return;
    }
    const bool autoRollback = m_activeImage.value(QStringLiteral("autoRollback")).toBool();
    const QByteArray manifestText = QStringLiteral("SHA256=%1\nEXPECTED_VERSION=%2\nAUTO_ROLLBACK=%3\nLABEL=%4\nKIOSK_MODE=keep\n")
        .arg(sha, m_activeImage.value(QStringLiteral("expectedVersion")).toString(),
             autoRollback ? QStringLiteral("1") : QStringLiteral("0"),
             m_activeImage.value(QStringLiteral("label")).toString()).toLatin1();
    {
        QSaveFile mf(manifest);
        if (!mf.open(QIODevice::WriteOnly) || mf.write(manifestText) != manifestText.size() || !mf.commit()) {
            cleanup();
            fail(tr("Could not write the flash manifest."));
            return;
        }
    }
    {
        QFile request(kRequestFile);
        if (!request.open(QIODevice::WriteOnly | QIODevice::NewOnly)) {
            cleanup();
            fail(tr("Could not create the flash request (already pending?)."));
            return;
        }
        request.write(token.toLatin1() + '\n');
    }

    m_pendingImageId = m_activeImage.value(QStringLiteral("id")).toString();
    m_pendingExpectedVersion = m_activeImage.value(QStringLiteral("expectedVersion")).toString();
    m_pendingSha256 = sha;
    setState(QStringLiteral("QUEUING"), tr("Queuing supervised flash job..."));
    // KIOSK_MODE=keep: the UI stays running; it closes the Press port and
    // keeps it closed until the helper reports a terminal state.
    setPressFlashLock(true);

    auto *process = new QProcess(this);
    m_process = process;
    connect(process, &QProcess::finished, this, [this, process, cleanup](int exitCode, QProcess::ExitStatus status) {
        const QByteArray out = process->readAllStandardOutput();
        const QByteArray err = process->readAllStandardError();
        process->deleteLater();
        m_process = nullptr;
        m_logTail = QString::fromUtf8(out + err).trimmed();
        const QString jobId = parseKeyValues(out).value(QStringLiteral("QUEUED_JOB"));
        if (status != QProcess::NormalExit || exitCode != 0 || jobId.isEmpty()) {
            cleanup();
            QFile::remove(kRequestFile);
            fail(tr("The supervised flasher rejected the queue request (exit %1).").arg(exitCode));
            return;
        }
        m_jobId = jobId;
        writePendingRequest(jobId);
        setState(QStringLiteral("QUEUED"),
                 tr("Job %1 queued. Installing firmware; the Press reconnects automatically "
                    "when finished.").arg(jobId));
        m_pollTimer->start();
    });
    process->start(kSudo, {QStringLiteral("-n"), kHelper, QStringLiteral("--queue")});
    QTimer::singleShot(30000, process, [process]() { process->kill(); });
}

void MachineFirmwareBackend::setPressFlashLock(bool active)
{
    if (m_pressFlashLocked == active)
        return;
    m_pressFlashLocked = active;
    if (m_machineControl)
        QMetaObject::invokeMethod(m_machineControl, "setFirmwareFlashActive", Q_ARG(bool, active));
}

void MachineFirmwareBackend::refreshStatus()
{
    if (!m_unavailableReason.isEmpty() || m_process)
        return;
    pollStatus();
}

void MachineFirmwareBackend::pollStatus()
{
    QProcess process;
    process.start(kHelper, {QStringLiteral("--status")});
    if (!process.waitForFinished(3000) || process.exitCode() != 0)
        return;
    const QMap<QString, QString> s = parseKeyValues(process.readAllStandardOutput());
    const QString state = s.value(QStringLiteral("STATE"));
    const QString jobId = s.value(QStringLiteral("JOB_ID"));
    m_appliedHash = s.value(QStringLiteral("APPLIED_HASH"));
    m_statusTargetHash = s.value(QStringLiteral("TARGET_HASH"));
    if (m_appliedHash == QLatin1String("none"))
        m_appliedHash.clear();
    const bool ownJob = !m_jobId.isEmpty() && jobId == m_jobId;
    if (ownJob)
        m_logTail = readLogTail(jobId);
    const QString message = tr("Flasher %1: %2 (job %3, updated %4)")
        .arg(state, s.value(QStringLiteral("MESSAGE")), jobId, s.value(QStringLiteral("UPDATED_UTC")));
    if (ownJob && terminalState(state)) {
        m_pollTimer->stop();
        m_busy = false;
        m_activeImage.clear();
        setPressFlashLock(false);
        setState(state, message);
        emit flashFinished(state == QLatin1String("SUCCEEDED"), message);
        return;
    }
    if (ownJob || !m_busy)
        setState(state.isEmpty() ? QStringLiteral("IDLE") : state, message);
    else
        emit flashStateChanged();
}

QString MachineFirmwareBackend::readLogTail(const QString &jobId) const
{
    static const QRegularExpression jobRe(QStringLiteral("^[0-9A-Za-z-]{8,64}$"));
    if (!jobRe.match(jobId).hasMatch())
        return {};
    QFile f(QDir(kHelperLogDir).absoluteFilePath(jobId + QStringLiteral(".log")));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    QStringList lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
    // dfu-util progress uses carriage returns; keep only the final segment.
    for (QString &line : lines)
        line = line.section(QLatin1Char('\r'), -1);
    lines.removeAll(QString());
    return lines.mid(qMax(0, lines.size() - 14)).join(QLatin1Char('\n'));
}

void MachineFirmwareBackend::writePendingRequest(const QString &jobId)
{
    QJsonObject o;
    o.insert(QStringLiteral("jobId"), jobId);
    o.insert(QStringLiteral("imageId"), m_pendingImageId);
    o.insert(QStringLiteral("expectedVersion"), m_pendingExpectedVersion);
    o.insert(QStringLiteral("sha256"), m_pendingSha256);
    o.insert(QStringLiteral("requestedUtc"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    QSaveFile f(QDir(m_catalogDirectory).absoluteFilePath(kPendingName));
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(o).toJson(QJsonDocument::Indented));
        f.commit();
    }
}

void MachineFirmwareBackend::loadPendingRequest()
{
    QFile f(QDir(m_catalogDirectory).absoluteFilePath(kPendingName));
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
    m_jobId = o.value(QStringLiteral("jobId")).toString();
    m_pendingImageId = o.value(QStringLiteral("imageId")).toString();
    m_pendingExpectedVersion = o.value(QStringLiteral("expectedVersion")).toString();
    m_pendingSha256 = o.value(QStringLiteral("sha256")).toString();
}
