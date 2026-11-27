#pragma once

#include <QObject>
#include <QPointer>
#include <QString>
#include <QVariantList>

class QNetworkAccessManager;
class QNetworkReply;
class QProcess;
class QTimer;

// Settings -> Maintenance -> MACHINE FIRMWARE.
//
// Lists the firmware images stored on the press (catalog manifest
// `firmware-catalog.json`) and queues a flash of one of them through the
// existing supervised root helper `/usr/local/sbin/bendcnc-flash-firmware`
// using the exact upload/request/`sudo -n ... --queue` contract that
// firmware/deploy/flash-via-orangepi.ps1 uses. The helper stops the kiosk
// (this process), flashes, verifies the firmware banner and restarts the
// kiosk; the result is recovered from `--status` after restart.
class MachineFirmwareBackend final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList images READ images NOTIFY catalogChanged)
    Q_PROPERTY(QString catalogDirectory READ catalogDirectory CONSTANT)
    Q_PROPERTY(QString catalogError READ catalogError NOTIFY catalogChanged)
    Q_PROPERTY(bool flashSupported READ flashSupported CONSTANT)
    Q_PROPERTY(QString flashUnavailableReason READ flashUnavailableReason CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY flashStateChanged)
    Q_PROPERTY(QString flashState READ flashState NOTIFY flashStateChanged)
    Q_PROPERTY(QString flashMessage READ flashMessage NOTIFY flashStateChanged)
    Q_PROPERTY(QString flashLogTail READ flashLogTail NOTIFY flashStateChanged)
    Q_PROPERTY(QString appliedHash READ appliedHash NOTIFY flashStateChanged)
    Q_PROPERTY(QString pendingImageId READ pendingImageId NOTIFY flashStateChanged)
    Q_PROPERTY(QString pendingExpectedVersion READ pendingExpectedVersion NOTIFY flashStateChanged)
    // Remote channel (stable/beta) updates of the CURRENT firmware. Images are
    // downloaded and verified automatically; flashing stays a manual step.
    Q_PROPERTY(bool remoteUpdatesEnabled READ remoteUpdatesEnabled CONSTANT)
    Q_PROPERTY(bool remoteBusy READ remoteBusy NOTIFY remoteChanged)
    Q_PROPERTY(QString remoteState READ remoteState NOTIFY remoteChanged)
    Q_PROPERTY(QString remoteMessage READ remoteMessage NOTIFY remoteChanged)

public:
    explicit MachineFirmwareBackend(bool offlineValidation, QObject *parent = nullptr);

    void setMachineControl(QObject *machineControl) { m_machineControl = machineControl; }

    QVariantList images() const { return m_images; }
    QString catalogDirectory() const { return m_catalogDirectory; }
    QString catalogError() const { return m_catalogError; }
    bool flashSupported() const { return m_unavailableReason.isEmpty(); }
    QString flashUnavailableReason() const { return m_unavailableReason; }
    bool busy() const { return m_busy; }
    QString flashState() const { return m_state; }
    QString flashMessage() const { return m_message; }
    QString flashLogTail() const { return m_logTail; }
    QString appliedHash() const { return m_appliedHash; }
    QString pendingImageId() const { return m_pendingImageId; }
    QString pendingExpectedVersion() const { return m_pendingExpectedVersion; }
    bool remoteUpdatesEnabled() const { return m_remoteEnabled; }
    bool remoteBusy() const { return m_remoteBusy; }
    QString remoteState() const { return m_remoteState; }
    QString remoteMessage() const { return m_remoteMessage; }

    Q_INVOKABLE void checkForUpdate();

    Q_INVOKABLE void refreshCatalog();
    Q_INVOKABLE void refreshStatus();
    // Returns a non-empty reason when the machine state forbids flashing.
    Q_INVOKABLE QString machineBlockReason() const;
    // confirmed must be true (second UI step); uiGateClear carries QML-only
    // run/tool-change/activation state that this backend cannot observe.
    Q_INVOKABLE bool startFlash(const QString &imageId, bool confirmed, bool uiGateClear);

signals:
    void catalogChanged();
    void flashStateChanged();
    void flashFinished(bool success, const QString &message);
    void remoteChanged();

private:
    void appendCatalog(const QString &directory, const QString &manifestName, bool reportMissing,
                       QStringList &errors);
    void handleFirmwareInfo(QNetworkReply *reply);
    void handleFirmwareDownload(QNetworkReply *reply, const QJsonObject &meta);
    void remoteDone(const QString &state, const QString &message);
    QVariantMap findImage(const QString &id) const;
    void setState(const QString &state, const QString &message);
    void fail(const QString &message);
    void runPreflight();
    void stageAndQueue();
    void pollStatus();
    QString readLogTail(const QString &jobId) const;
    void writePendingRequest(const QString &jobId);
    void loadPendingRequest();
    void setPressFlashLock(bool active);
    bool m_pressFlashLocked = false;

    bool m_offlineValidation = false;
    QPointer<QObject> m_machineControl;
    QString m_catalogDirectory;
    QString m_bundledDirectory;
    QString m_catalogError;
    QNetworkAccessManager *m_net = nullptr;
    bool m_remoteEnabled = false;
    bool m_remoteBusy = false;
    QString m_remoteState = QStringLiteral("IDLE");
    QString m_remoteMessage;
    QString m_unavailableReason;
    QVariantList m_images;
    bool m_busy = false;
    QString m_state = QStringLiteral("IDLE");
    QString m_message;
    QString m_logTail;
    QString m_appliedHash;
    QString m_statusTargetHash;
    QString m_jobId;
    QString m_pendingImageId;
    QString m_pendingExpectedVersion;
    QString m_pendingSha256;
    QVariantMap m_activeImage;
    QProcess *m_process = nullptr;
    QTimer *m_pollTimer = nullptr;
};
