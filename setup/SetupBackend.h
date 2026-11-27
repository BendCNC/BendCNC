#pragma once

#include <QJsonObject>
#include <QObject>
#include <QStringList>

class QNetworkAccessManager;

// First-boot setup: WiFi (nmcli), email registration, license acceptance and
// BendCNC app install. BENDCNC_SETUP_DRYRUN=1 skips nmcli and the installer so
// the flow can be exercised on a PC against the real license server.
class SetupBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString deviceId READ deviceId CONSTANT)
    Q_PROPERTY(QString eulaText READ eulaText CONSTANT)
    Q_PROPERTY(QString eulaVersion READ eulaVersion CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)
    Q_PROPERTY(QStringList networks READ networks NOTIFY networksChanged)

public:
    explicit SetupBackend(QObject *parent = nullptr);

    QString deviceId() const { return m_deviceId; }
    QString eulaText() const;
    QString eulaVersion() const { return QStringLiteral("2"); }
    bool busy() const { return m_busy; }
    QString message() const { return m_message; }
    QStringList networks() const { return m_networks; }

    Q_INVOKABLE void scanWifi();
    Q_INVOKABLE void connectWifi(const QString &ssid, const QString &password);
    Q_INVOKABLE void checkOnline();
    Q_INVOKABLE void registerEmail(const QString &email);
    Q_INVOKABLE void verifyCode(const QString &code);
    Q_INVOKABLE void install();
    Q_INVOKABLE void finish();

signals:
    void busyChanged();
    void messageChanged();
    void networksChanged();
    void wifiDone(bool ok);
    void onlineDone(bool ok);
    void codeSent();
    void verified();
    void installDone(bool ok);

private:
    void setBusy(bool b);
    void setMessage(const QString &m);
    void httpRequest(const QString &path, const QByteArray &jsonBody, int timeoutSec,
                     std::function<void(bool ok, int status, const QByteArray &body)> done);
    void post(const QString &path, const QJsonObject &body,
              std::function<void(const QJsonObject &)> onOk);
    bool dryRun() const;

    QNetworkAccessManager *m_net;
    QString m_serverUrl;
    QString m_deviceId;
    bool m_busy = false;
    QString m_message;
    QStringList m_networks;
    QString m_release;
    QString m_downloadUrl;
};
