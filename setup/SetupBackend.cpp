#include "SetupBackend.h"

#include "../src/LicenseManager.h"

#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QSettings>
#include <QUrl>

#ifndef BENDCNC_LICENSE_SERVER
#define BENDCNC_LICENSE_SERVER "https://license.bendcnc.com"
#endif

SetupBackend::SetupBackend(QObject *parent)
    : QObject(parent)
    , m_net(new QNetworkAccessManager(this))
    , m_deviceId(LicenseManager::computeDeviceId())
{
    const QByteArray env = qgetenv("BENDCNC_LICENSE_SERVER");
    m_serverUrl = env.isEmpty() ? QStringLiteral(BENDCNC_LICENSE_SERVER) : QString::fromUtf8(env);
}

bool SetupBackend::dryRun() const { return qEnvironmentVariableIntValue("BENDCNC_SETUP_DRYRUN") == 1; }

QString SetupBackend::eulaText() const
{
    QFile f(QStringLiteral(":/eula.txt"));
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}

void SetupBackend::setBusy(bool b)
{
    if (m_busy != b) { m_busy = b; emit busyChanged(); }
}

void SetupBackend::setMessage(const QString &m)
{
    if (m_message != m) { m_message = m; emit messageChanged(); }
}

void SetupBackend::scanWifi()
{
    if (dryRun()) {
        m_networks = {QStringLiteral("Shop-WiFi"), QStringLiteral("Office")};
        emit networksChanged();
        return;
    }
    setBusy(true);
    setMessage(tr("Searching for networks..."));
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [this, p] {
        QStringList out;
        for (const QString &line : QString::fromUtf8(p->readAllStandardOutput()).split('\n')) {
            const QString ssid = line.section(':', 0, 0).trimmed();
            if (!ssid.isEmpty() && !out.contains(ssid))
                out << ssid;
        }
        m_networks = out;
        emit networksChanged();
        setMessage(out.isEmpty() ? tr("No networks found. Tap Scan to try again.") : QString());
        setBusy(false);
        p->deleteLater();
    });
    p->start(QStringLiteral("nmcli"), {"-t", "-f", "SSID", "dev", "wifi", "list", "--rescan", "yes"});
}

void SetupBackend::connectWifi(const QString &ssid, const QString &password)
{
    if (dryRun()) { emit wifiDone(true); return; }
    setBusy(true);
    setMessage(tr("Connecting to %1...").arg(ssid));
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [this, p](int code, QProcess::ExitStatus status) {
        const bool ok = status == QProcess::NormalExit && code == 0;
        const QString detail = QString::fromUtf8(p->readAllStandardError()).trimmed().section('\n', -1);
        qInfo().noquote() << "wifi connect rc" << code << detail;
        setMessage(ok ? QString()
                      : tr("Could not connect. Check the password and try again.")
                            + (detail.isEmpty() ? QString() : QStringLiteral("\n(%1)").arg(detail.left(160))));
        setBusy(false);
        emit wifiDone(ok);
        p->deleteLater();
    });
    // Root helper (sudoers): the wizard has no login session, so polkit 0.105
    // denies nmcli profile creation. Password goes via stdin, not argv.
    p->start(QStringLiteral("sudo"), {"-n", "/usr/local/sbin/bendcnc-wifi-connect", ssid});
    p->write(password.toUtf8() + '\n');
    p->closeWriteChannel();
}

// The ARM64 Qt build has no TLS backend (QSslSocket unsupported), so HTTPS on
// the board goes through the system curl/OpenSSL. curl also retries while
// DHCP/DNS settle and while systemd-timesyncd corrects the fake-hwclock date
// (certificates are rejected as "not yet valid" until the clock is right).
void SetupBackend::httpRequest(const QString &path, const QByteArray &jsonBody, int timeoutSec,
                               std::function<void(bool, int, const QByteArray &)> done)
{
#ifdef Q_OS_LINUX
    auto *p = new QProcess(this);
    QStringList args{"-sS", "-m", QString::number(timeoutSec), "--retry", "6", "--retry-delay", "5",
                     "--retry-all-errors", "--connect-timeout", "10", "-w", "\n%{http_code}"};
    if (!jsonBody.isNull())
        args << "-H" << "Content-Type: application/json" << "--data-binary" << "@-";
    args << m_serverUrl + path;
    connect(p, &QProcess::finished, this, [p, done](int code) {
        QByteArray out = p->readAllStandardOutput();
        const int nl = out.lastIndexOf('\n');
        const int status = out.mid(nl + 1).trimmed().toInt();
        out.truncate(qMax(0, nl));
        if (code != 0)
            qWarning("curl %d: %s", code, p->readAllStandardError().constData());
        done(code == 0 && status >= 200 && status < 300, status, out);
        p->deleteLater();
    });
    p->start(QStringLiteral("curl"), args);
    if (!jsonBody.isNull()) {
        p->write(jsonBody);
        p->closeWriteChannel();
    }
#else
    QNetworkRequest req(QUrl(m_serverUrl + path));
    req.setTransferTimeout(timeoutSec * 1000);
    QNetworkReply *r;
    if (jsonBody.isNull()) {
        r = m_net->get(req);
    } else {
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
        r = m_net->post(req, jsonBody);
    }
    connect(r, &QNetworkReply::finished, this, [r, done] {
        const int status = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        done(r->error() == QNetworkReply::NoError, status, r->readAll());
        r->deleteLater();
    });
#endif
}

void SetupBackend::checkOnline()
{
    setBusy(true);
    setMessage(tr("Checking internet connection..."));
    httpRequest(QStringLiteral("/healthz"), QByteArray(), 15, [this](bool ok, int, const QByteArray &) {
        setMessage(ok ? QString() : tr("No internet connection. Check the network and try again."));
        setBusy(false);
        emit onlineDone(ok);
    });
}

void SetupBackend::post(const QString &path, const QJsonObject &body,
                        std::function<void(const QJsonObject &)> onOk)
{
    setBusy(true);
    httpRequest(path, QJsonDocument(body).toJson(QJsonDocument::Compact), 20,
                [this, onOk](bool ok, int status, const QByteArray &data) {
        const QJsonObject o = QJsonDocument::fromJson(data).object();
        setBusy(false);
        if (ok) {
            setMessage(QString());
            onOk(o);
        } else {
            const QString detail = o.value(QStringLiteral("detail")).toString();
            setMessage(!detail.isEmpty() ? detail
                       : status == 0 ? tr("No internet connection. Check the network and try again.")
                                     : tr("Server unavailable. Please try again."));
        }
    });
}

void SetupBackend::registerEmail(const QString &email)
{
    post(QStringLiteral("/v1/register"),
         {{"device_id", m_deviceId}, {"email", email.trimmed()}, {"eula_version", eulaVersion()}},
         [this](const QJsonObject &) { emit codeSent(); });
}

void SetupBackend::verifyCode(const QString &code)
{
    post(QStringLiteral("/v1/verify"), {{"device_id", m_deviceId}, {"code", code.trimmed()}},
         [this](const QJsonObject &o) {
             // Same store LicenseManager reads, so the app starts already activated.
             // Written under both organization names (BendCNC and legacy BendCNC builds).
             for (const auto org : {QStringLiteral("BendCNC"), QStringLiteral("BendCNC")}) {
                 QSettings s(org, QStringLiteral("License"));
                 s.setValue(QStringLiteral("token"), o.value(QStringLiteral("token")).toString().toUtf8());
                 s.sync();
             }
             m_release = o.value(QStringLiteral("release")).toString();
             m_downloadUrl = o.value(QStringLiteral("download_url")).toString();
             emit verified();
         });
}

void SetupBackend::install()
{
    if (dryRun()) { setMessage(tr("Dry run: install skipped.")); emit installDone(true); return; }
    if (m_release.isEmpty() || m_downloadUrl.isEmpty()) {
        setMessage(tr("No download is available yet. Please contact support."));
        emit installDone(false);
        return;
    }
    setBusy(true);
    setMessage(tr("Downloading BendCNC..."));
    auto *p = new QProcess(this);
    p->setProcessChannelMode(QProcess::MergedChannels);
    connect(p, &QProcess::readyRead, this, [this, p] {
        const QString line = QString::fromUtf8(p->readAll()).trimmed().section('\n', -1);
        if (line.startsWith(QStringLiteral("STATUS ")))
            setMessage(line.mid(7));
    });
    connect(p, &QProcess::finished, this, [this, p](int code) {
        const bool ok = code == 0;
        setMessage(ok ? tr("BendCNC installed.") : tr("Install failed (code %1). Tap Retry.").arg(code));
        setBusy(false);
        emit installDone(ok);
        p->deleteLater();
    });
    p->start(QStringLiteral("sudo"), {"-n", "/usr/lib/bendcnc/bendcnc-install.sh", m_downloadUrl, m_release});
}

void SetupBackend::finish()
{
    if (!dryRun())
        QProcess::startDetached(QStringLiteral("sudo"), {"-n", "/usr/lib/bendcnc/bendcnc-install.sh", "--finish"});
    QCoreApplication::quit();
}
