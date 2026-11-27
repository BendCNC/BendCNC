#include "LicenseManager.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QFile>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QSysInfo>
#include <QTimer>
#include <QUrl>

#ifdef BENDCNC_LICENSING
#include <openssl/evp.h>
#endif

#ifndef BENDCNC_LICENSE_SERVER
#define BENDCNC_LICENSE_SERVER "https://license.example.com"
#endif
// 32-byte raw Ed25519 public key, base64. Generate with
// license-server/keygen.py and pass -DBENDCNC_LICENSE_PUBKEY=...
#ifndef BENDCNC_LICENSE_PUBKEY
#define BENDCNC_LICENSE_PUBKEY ""
#endif

namespace {
constexpr qint64 kCheckInIntervalMs = 1LL * 60 * 60 * 1000; // every 1 h while running
constexpr int kClockRetryMs = 30 * 1000;
constexpr qint64 kClockToleranceSecs = 60 * 60;
const auto kB64 = QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals;

QSettings settings() { return QSettings(QStringLiteral("BendCNC"), QStringLiteral("License")); }
}

LicenseManager::LicenseManager(QObject *parent)
    : QObject(parent)
    , m_net(new QNetworkAccessManager(this))
    , m_deviceId(computeDeviceId())
{
    m_serverUrl = serverUrl();
    m_token = settings().value(QStringLiteral("token")).toByteArray();
    reevaluate();

    if (enforced()) {
        QTimer::singleShot(2000, this, &LicenseManager::checkIn);
        auto *timer = new QTimer(this);
        timer->setInterval(int(kCheckInIntervalMs));
        connect(timer, &QTimer::timeout, this, &LicenseManager::checkIn);
        timer->start();

        // The board has no RTC: after a power cycle the clock is stale until
        // NTP syncs over the network. Re-evaluate shortly afterwards instead of
        // waiting for the hourly check-in.
        auto *clockRetry = new QTimer(this);
        clockRetry->setInterval(kClockRetryMs);
        connect(clockRetry, &QTimer::timeout, this, [this]() {
            if (!m_clockStale)
                return;
            reevaluate();
            if (m_clockStale)
                checkIn();
        });
        clockRetry->start();
    }
}

bool LicenseManager::enforced() const
{
#ifdef BENDCNC_LICENSING
    return true;
#else
    return false;
#endif
}

QString LicenseManager::computeDeviceId()
{
    // Orange Pi (RK3566): the CPU serial burned in the Rockchip OTP eFuse is
    // exposed as /proc/device-tree/serial-number. It survives SD reflash and
    // is unique per chip. /etc/machine-id would be cloned by a shared OS image,
    // and the eth0 MAC is locally administered, so neither is used on ARM.
    QByteArray seed;
    QFile dtSerial(QStringLiteral("/proc/device-tree/serial-number"));
    if (dtSerial.open(QIODevice::ReadOnly)) {
        seed = dtSerial.readAll();
        seed.replace('\0', "");
        seed = seed.trimmed();
        if (!seed.isEmpty())
            seed.prepend("soc:");
    }
    if (seed.isEmpty())
        seed = QSysInfo::machineUniqueId(); // Windows: MachineGuid
    if (seed.isEmpty())
        seed = QSysInfo::machineHostName().toUtf8() + QSysInfo::currentCpuArchitecture().toUtf8();
    seed += "|bendcnc-license-v1";
    return QString::fromLatin1(QCryptographicHash::hash(seed, QCryptographicHash::Sha256).toHex().left(32));
}

QString LicenseManager::serverUrl()
{
    const QByteArray envUrl = qgetenv("BENDCNC_LICENSE_SERVER");
    return envUrl.isEmpty() ? QStringLiteral(BENDCNC_LICENSE_SERVER) : QString::fromUtf8(envUrl);
}

QByteArray LicenseManager::publicKey()
{
    return QByteArray::fromBase64(BENDCNC_LICENSE_PUBKEY);
}

QJsonObject LicenseManager::verifyToken(const QByteArray &token, const QByteArray &publicKeyRaw)
{
    const int dot = token.indexOf('.');
    if (dot <= 0 || publicKeyRaw.size() != 32)
        return {};
    const QByteArray payloadB64 = token.left(dot);
    const QByteArray sig = QByteArray::fromBase64(token.mid(dot + 1), kB64);
    if (sig.size() != 64)
        return {};
#ifdef BENDCNC_LICENSING
    EVP_PKEY *key = EVP_PKEY_new_raw_public_key(
        EVP_PKEY_ED25519, nullptr,
        reinterpret_cast<const unsigned char *>(publicKeyRaw.constData()), 32);
    if (!key)
        return {};
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    bool ok = ctx && EVP_DigestVerifyInit(ctx, nullptr, nullptr, nullptr, key) == 1
              && EVP_DigestVerify(ctx,
                                  reinterpret_cast<const unsigned char *>(sig.constData()), 64,
                                  reinterpret_cast<const unsigned char *>(payloadB64.constData()),
                                  size_t(payloadB64.size())) == 1;
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(key);
    if (!ok)
        return {};
    const QJsonDocument doc = QJsonDocument::fromJson(QByteArray::fromBase64(payloadB64, kB64));
    return doc.isObject() ? doc.object() : QJsonObject{};
#else
    return {};
#endif
}

void LicenseManager::reevaluate()
{
    const QString before = m_status;
    m_payload = {};
    m_clockStale = false;
    const qint64 now = QDateTime::currentSecsSinceEpoch();

    if (!enforced()) {
        m_status = QStringLiteral("unenforced");
    } else if (m_token.isEmpty()) {
        m_status = QStringLiteral("unactivated");
    } else {
        const QByteArray pub = QByteArray::fromBase64(BENDCNC_LICENSE_PUBKEY);
        const QJsonObject p = verifyToken(m_token, pub);
        QSettings s = settings();
        const qint64 lastSeen = s.value(QStringLiteral("lastSeen"), 0).toLongLong();
        if (p.isEmpty() || p.value(QStringLiteral("device_id")).toString() != m_deviceId) {
            m_status = QStringLiteral("invalid");
        } else {
            // A clock behind the last trusted time (no RTC after power cycle,
            // or a rewind) is not an error: evaluate at the last trusted time.
            // Rewinding therefore never extends the license; the 30 s retry
            // re-evaluates once NTP syncs.
            const qint64 iat = qint64(p.value(QStringLiteral("iat")).toDouble());
            m_clockStale = now + kClockToleranceSecs < lastSeen || now + kClockToleranceSecs < iat;
            const qint64 effectiveNow = qMax(now, qMax(lastSeen, m_clockStale ? iat : qint64(0)));
            m_payload = p;
            m_lastSeen = effectiveNow;
            if (!m_clockStale)
                s.setValue(QStringLiteral("lastSeen"), qMax(now, lastSeen));
            const bool live = effectiveNow < qint64(p.value(QStringLiteral("exp")).toDouble());
            const bool trial = p.value(QStringLiteral("plan")).toString() == QLatin1String("trial");
            m_status = !live ? QStringLiteral("expired")
                             : (trial ? QStringLiteral("trial") : QStringLiteral("licensed"));
        }
    }
    Q_UNUSED(before);
    emit changed();
}

int LicenseManager::daysLeft() const
{
    if (m_payload.isEmpty())
        return 0;
    const qint64 secs = qint64(m_payload.value(QStringLiteral("exp")).toDouble())
                        - qMax(QDateTime::currentSecsSinceEpoch(), m_lastSeen);
    return secs <= 0 ? 0 : int((secs + 86399) / 86400);
}

bool LicenseManager::runAllowed() const
{
    return m_status == QLatin1String("unenforced") || m_status == QLatin1String("trial")
           || m_status == QLatin1String("licensed");
}

void LicenseManager::startTrial(const QString &email)
{
    post(QStringLiteral("/v1/trial"), {{QStringLiteral("device_id"), m_deviceId},
                                       {QStringLiteral("email"), email.trimmed()}});
}

void LicenseManager::redeemKey(const QString &licenseKey)
{
    post(QStringLiteral("/v1/redeem"), {{QStringLiteral("device_id"), m_deviceId},
                                        {QStringLiteral("license_key"), licenseKey.trimmed()}});
}

void LicenseManager::checkIn()
{
    if (!enforced() || m_token.isEmpty() || m_busy)
        return;
    post(QStringLiteral("/v1/refresh"), {{QStringLiteral("device_id"), m_deviceId},
                                         {QStringLiteral("token"), QString::fromLatin1(m_token)},
                                         {QStringLiteral("app_version"), QCoreApplication::applicationVersion()},
                                         {QStringLiteral("app_commit"), QStringLiteral(BENDCNC_GIT_COMMIT)}});
}

void LicenseManager::post(const QString &path, const QJsonObject &body)
{
    if (!enforced())
        return;
    QNetworkRequest req(QUrl(m_serverUrl + path));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setTransferTimeout(15000);
    m_busy = true;
    emit changed();
    QNetworkReply *reply = m_net->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply] { handleReply(reply); });
}

void LicenseManager::handleReply(QNetworkReply *reply)
{
    reply->deleteLater();
    m_busy = false;
    const QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
    if (reply->error() != QNetworkReply::NoError && obj.isEmpty()) {
        // Offline: keep the cached token; it stays valid until its exp.
        setMessage(tr("Sin conexión con el servidor de licencias: %1").arg(reply->errorString()));
        return;
    }
    const QByteArray token = obj.value(QStringLiteral("token")).toString().toLatin1();
    if (!token.isEmpty())
        acceptToken(token);
    setMessage(obj.value(QStringLiteral("message")).toString(
        obj.value(QStringLiteral("detail")).toString()));
}

void LicenseManager::acceptToken(const QByteArray &token)
{
    const QJsonObject p = verifyToken(token, QByteArray::fromBase64(BENDCNC_LICENSE_PUBKEY));
    if (p.isEmpty() || p.value(QStringLiteral("device_id")).toString() != m_deviceId) {
        setMessage(tr("El servidor devolvió una licencia no válida."));
        return;
    }
    m_token = token;
    settings().setValue(QStringLiteral("token"), m_token);
    reevaluate();
}

void LicenseManager::setMessage(const QString &msg)
{
    m_message = msg;
    emit changed();
}
