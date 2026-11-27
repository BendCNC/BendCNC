#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QObject>
#include <QString>

class QNetworkAccessManager;
class QNetworkReply;

// Cloud licensing client: 30-day trial per device + paid activation.
// Tokens are "<base64url(payload json)>.<base64url(ed25519 signature)>",
// signed by the license server and verified offline with an embedded
// public key. Checks only gate *starting* RUN; they never interrupt a cycle.
class LicenseManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString plan READ plan NOTIFY changed)
    Q_PROPERTY(int daysLeft READ daysLeft NOTIFY changed)
    Q_PROPERTY(bool runAllowed READ runAllowed NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(QString deviceId READ deviceId CONSTANT)
    Q_PROPERTY(bool enforced READ enforced CONSTANT)

public:
    explicit LicenseManager(QObject *parent = nullptr);

    QString status() const { return m_status; }
    QString plan() const { return m_payload.value(QStringLiteral("plan")).toString(); }
    int daysLeft() const;
    bool runAllowed() const;
    bool busy() const { return m_busy; }
    QString message() const { return m_message; }
    QString deviceId() const { return m_deviceId; }
    bool enforced() const;

    Q_INVOKABLE void startTrial(const QString &email);
    Q_INVOKABLE void redeemKey(const QString &licenseKey);
    Q_INVOKABLE void checkIn();
    Q_INVOKABLE void reevaluate();

    // Exposed for tests: returns empty object if signature/format invalid.
    static QJsonObject verifyToken(const QByteArray &token, const QByteArray &publicKeyRaw);
    // Shared with bendcnc-setup so both bind to the same Machine ID.
    static QString computeDeviceId();
    static QString serverUrl();
    static QByteArray publicKey();

signals:
    void changed();

private:
    void post(const QString &path, const QJsonObject &body);
    void handleReply(QNetworkReply *reply);
    void acceptToken(const QByteArray &token);
    void setMessage(const QString &msg);

    QNetworkAccessManager *m_net = nullptr;
    QString m_deviceId;
    QString m_serverUrl;
    QByteArray m_token;
    QJsonObject m_payload;
    QString m_status = QStringLiteral("unactivated");
    // Last trusted wall time (s). The board has no RTC, so after a power cycle
    // the clock lags until NTP syncs; evaluation uses max(now, m_lastSeen).
    qint64 m_lastSeen = 0;
    bool m_clockStale = false;
    QString m_message;
    bool m_busy = false;
};
