#pragma once

#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QUrl>
#include <QVariantList>
#include <QNetworkAccessManager>

class QNetworkReply;
class QTcpServer;
class QTcpSocket;

class QTimer;
class QProcess;
template<typename T> class QFutureWatcher;

class HostSystemBackend final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList wifiNetworks READ wifiNetworks NOTIFY wifiNetworksChanged)
    Q_PROPERTY(QString systemSummary READ systemSummary CONSTANT)
    Q_PROPERTY(QStringList systemLogs READ systemLogs NOTIFY systemLogsChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QString lastResult READ lastResult NOTIFY lastResultChanged)
    Q_PROPERTY(bool offlineValidation READ offlineValidation CONSTANT)
    Q_PROPERTY(bool operationActive READ operationActive NOTIFY operationChanged)
    Q_PROPERTY(double operationProgress READ operationProgress NOTIFY operationChanged)
    Q_PROPERTY(double cpuLoadPercent READ cpuLoadPercent NOTIFY systemMetricsChanged)
    Q_PROPERTY(bool cpuLoadAvailable READ cpuLoadAvailable NOTIFY systemMetricsChanged)
    Q_PROPERTY(double cpuTemperatureCelsius READ cpuTemperatureCelsius NOTIFY systemMetricsChanged)
    Q_PROPERTY(bool cpuTemperatureAvailable READ cpuTemperatureAvailable NOTIFY systemMetricsChanged)
    Q_PROPERTY(double memoryUsedPercent READ memoryUsedPercent NOTIFY systemMetricsChanged)
    Q_PROPERTY(bool memoryAvailable READ memoryAvailable NOTIFY systemMetricsChanged)
    Q_PROPERTY(QString memoryUsageText READ memoryUsageText NOTIFY systemMetricsChanged)
    Q_PROPERTY(qulonglong memoryUsedBytes READ memoryUsedBytes NOTIFY systemMetricsChanged)
    Q_PROPERTY(qulonglong memoryTotalBytes READ memoryTotalBytes NOTIFY systemMetricsChanged)
    Q_PROPERTY(QString applicationVersion READ applicationVersion CONSTANT)
    Q_PROPERTY(bool applicationUpdateAvailable READ applicationUpdateAvailable NOTIFY updateAvailabilityChanged)
    Q_PROPERTY(QString applicationUpdateVersion READ applicationUpdateVersion NOTIFY updateAvailabilityChanged)
    Q_PROPERTY(QString updateCheckError READ updateCheckError NOTIFY updateAvailabilityChanged)
    Q_PROPERTY(QString applicationUpdateNotes READ applicationUpdateNotes NOTIFY updateAvailabilityChanged)
    // IDLE / DOWNLOADING / INSTALLING / FAILED; message is operator-facing text.
    Q_PROPERTY(QString applicationUpdateState READ applicationUpdateState NOTIFY updateAvailabilityChanged)
    Q_PROPERTY(QString applicationUpdateMessage READ applicationUpdateMessage NOTIFY updateAvailabilityChanged)
    Q_PROPERTY(double applicationUpdateProgress READ applicationUpdateProgress NOTIFY updateAvailabilityChanged)
    // Result of the last installed update, read once at startup ("" if none).
    Q_PROPERTY(QString lastUpdateResult READ lastUpdateResult NOTIFY updateAvailabilityChanged)
    // "stable" (tested releases) or "beta" (fast improvements); persisted, sent on every check.
    Q_PROPERTY(QString updateChannel READ updateChannel WRITE setUpdateChannel NOTIFY updateAvailabilityChanged)
    Q_PROPERTY(bool performanceMode READ performanceMode WRITE setPerformanceMode NOTIFY performanceModeChanged)
    Q_PROPERTY(bool performanceModeAvailable READ performanceModeAvailable CONSTANT)
    // CAD PC pairing: a 6-digit code shown on the press authorizes one CAD PC
    // key for the upload-only `bendimport` account (see docs/cad-import-access).
    // The add-in sends a request (no code); the press shows it until the
    // operator accepts or rejects (or 60 s pass).
    Q_PROPERTY(bool cadPairingRequestPending READ cadPairingRequestPending NOTIFY cadPairingChanged)
    Q_PROPERTY(QString cadPairingRequestLabel READ cadPairingRequestLabel NOTIFY cadPairingChanged)
    Q_PROPERTY(QString cadPairingRequestAddress READ cadPairingRequestAddress NOTIFY cadPairingChanged)
    Q_PROPERTY(QString cadPairingRequestFingerprint READ cadPairingRequestFingerprint NOTIFY cadPairingChanged)
    Q_PROPERTY(QString cadPairingMessage READ cadPairingMessage NOTIFY cadPairingChanged)
    Q_PROPERTY(QStringList cadPairedDevices READ cadPairedDevices NOTIFY cadPairingChanged)

public:
    explicit HostSystemBackend(bool offlineValidation = false, QObject *parent = nullptr);

    QVariantList wifiNetworks() const { return m_wifiNetworks; }
    QString systemSummary() const;
    QStringList systemLogs() const { return m_systemLogs; }
    QString lastError() const { return m_lastError; }
    QString lastResult() const { return m_lastResult; }
    bool offlineValidation() const { return m_offlineValidation; }
    bool operationActive() const { return m_operationActive; }
    double operationProgress() const { return m_operationProgress; }
    double cpuLoadPercent() const { return m_cpuLoadPercent; }
    bool cpuLoadAvailable() const { return m_cpuLoadAvailable; }
    double cpuTemperatureCelsius() const { return m_cpuTemperatureCelsius; }
    bool cpuTemperatureAvailable() const { return m_cpuTemperatureAvailable; }
    double memoryUsedPercent() const { return m_memoryUsedPercent; }
    bool memoryAvailable() const { return m_memoryAvailable; }
    QString memoryUsageText() const;
    qulonglong memoryUsedBytes() const { return m_memoryUsedBytes; }
    qulonglong memoryTotalBytes() const { return m_memoryTotalBytes; }
    QString applicationVersion() const;
    bool applicationUpdateAvailable() const { return m_applicationUpdateAvailable; }
    QString applicationUpdateVersion() const { return m_applicationUpdateVersion; }
    QString updateCheckError() const { return m_updateCheckError; }
    QString applicationUpdateNotes() const { return m_appUpdateNotes; }
    QString applicationUpdateState() const { return m_appUpdateState; }
    QString applicationUpdateMessage() const { return m_appUpdateMessage; }
    double applicationUpdateProgress() const { return m_appUpdateProgress; }
    QString lastUpdateResult() const { return m_lastUpdateResult; }
    QString updateChannel() const;
    void setUpdateChannel(const QString &channel);
    bool performanceMode() const;
    void setPerformanceMode(bool enabled);
    bool performanceModeAvailable() const;
    bool cadPairingRequestPending() const { return m_pairPending.active; }
    QString cadPairingRequestLabel() const { return m_pairPending.label; }
    QString cadPairingRequestAddress() const { return m_pairPending.peer; }
    QString cadPairingRequestFingerprint() const { return m_pairPending.fingerprint; }
    QString cadPairingMessage() const { return m_pairMessage; }
    QStringList cadPairedDevices() const { return m_pairedDevices; }

    Q_INVOKABLE void acceptCadPairingRequest();
    Q_INVOKABLE void rejectCadPairingRequest();
    Q_INVOKABLE void refreshCadPairedDevices();
    Q_INVOKABLE bool revokeCadAccess(bool confirmed);

    Q_INVOKABLE void refreshWifi();
    Q_INVOKABLE bool connectWifi(const QString &ssid, const QString &password = QString());
    Q_INVOKABLE bool disconnectWifi(const QString &ssid = QString());
    Q_INVOKABLE void refreshSystemLogs();
    Q_INVOKABLE bool exportSystemLogs(const QString &destination = QString());
    Q_INVOKABLE bool copyTextToClipboard(const QString &text);
    Q_INVOKABLE bool exportMachineLog(const QString &text,
                                      const QString &destination = QString());
    // Uploads app/machine/system logs to the BendCNC support server (async;
    // result arrives via lastResult/lastError + debugReportFinished).
    Q_INVOKABLE bool sendDebugReport(const QString &machineLog, const QString &note = QString(),
                                     const QString &pressFirmware = QString(),
                                     double sinceEpochMs = 0);
    Q_INVOKABLE bool createBackup(const QString &destination);
    Q_INVOKABLE bool restoreBackup(const QString &source, bool confirmed);
    // Java BackupManager parity. Backups are folders B<yyMMddHHmm><name> in
    // AppData/backups; auto backups (no name) run hourly with Java retention.
    Q_INVOKABLE QVariantList listBackups() const;
    Q_INVOKABLE bool createNamedBackup(const QString &name);
    Q_INVOKABLE bool deleteBackup(const QString &path, bool confirmed);
    Q_INVOKABLE QVariantList listExternalVolumes() const;
    Q_INVOKABLE bool exportBackup(const QString &path, const QString &volumeRoot);
    Q_INVOKABLE QVariantList listExternalBackups() const;
    // Takes an AUTO backup, restores, then restarts the app so every view
    // reloads the restored data (kiosk: systemd Restart=on-failure).
    Q_INVOKABLE bool restoreBackupAndRestart(const QString &path, bool confirmed);
    Q_INVOKABLE bool importAndRestoreBackup(const QString &externalPath, bool confirmed);
    Q_INVOKABLE bool stageSoftwareUpdate(const QString &packagePath, bool confirmed);
    Q_INVOKABLE void checkForApplicationUpdates();
    // Downloads the signed bundle, verifies SHA-256 and hands it to the root
    // helper, which stops this kiosk, installs transactionally and rolls back
    // on a failed start. confirmed must be true; QML gates RUN/motion state.
    Q_INVOKABLE bool installApplicationUpdate(bool confirmed);
    // Software power-off of the Linux host (Orange Pi). Requires confirmed=true.
    Q_INVOKABLE bool powerOff(bool confirmed);
    Q_INVOKABLE bool reboot(bool confirmed);

signals:
    void wifiNetworksChanged();
    void wifiConnectionFinished(bool success, const QString &ssid, const QString &error);
    void systemLogsChanged();
    void lastErrorChanged();
    void lastResultChanged();
    void debugReportFinished(bool ok, const QString &message);
    void operationChanged();
    void systemMetricsChanged();
    void updateAvailabilityChanged();
    void performanceModeChanged();
    void cadPairingChanged();
    void backupsChanged();

private:
    struct CommandResult { bool started = false; int exitCode = -1; QByteArray out; QByteArray err; };
    struct WifiConnectionResult {
        bool success = false;
        QString ssid;
        QString error;
        QString message;
        QVariantList networks;
    };

    CommandResult runBounded(const QString &program, const QStringList &arguments,
                             int timeoutMs = 5000) const;
    CommandResult runNmcli(const QStringList &arguments, int timeoutMs = 5000) const;
    bool systemPower(const QString &verb, bool confirmed);
    QString wifiDiagnostic() const;
    QString wirelessDevice() const;
    QVariantList activeWifiNetworks() const;
    QString activeWifiConnectionUuid() const;
    QString savedAutoconnectWifiUuid() const;
    WifiConnectionResult performWifiConnection(const QString &ssid,
                                                const QString &password) const;
    void attemptWifiAutoconnect();
    void restoreWifiConnection(const QString &uuid) const;
    QVariantMap wifiNetworkFromFields(const QList<QByteArray> &fields) const;
    static QList<QByteArray> splitNmcliTerseLine(const QByteArray &line);
    bool setError(const QString &message);
    void clearError();
    void setResult(const QString &message);
    void setOperation(bool active, double progress);
    QString storageRoot() const;
    bool copyTree(const QString &sourceRoot, const QString &destinationRoot) const;
    QString backupsDirectory() const;
    QString createBackupFolder(const QString &name);
    bool isInsideBackups(const QString &path) const;
    void runAutoBackup();
    void applyAutoBackupRetention();
    void restartApplication();
    void sampleSystemMetrics();
    bool readCpuCounters(quint64 *total, quint64 *idle) const;
    bool readCpuTemperature(double *celsius);
    bool readMemoryUsage(quint64 *totalBytes, quint64 *availableBytes) const;
    void setAppUpdateState(const QString &state, const QString &message, double progress = 0.0);
    void handleUpdatesReply(QNetworkReply *reply);
    void handlePairingSocket(QTcpSocket *socket);
    QByteArray queuePairingRequest(QTcpSocket *socket, const QByteArray &body, int *status);
    void finishPairingRequest(bool accepted, const QString &reason);
    void sendPairingReply(QTcpSocket *socket, int status, const QByteArray &reply);
    void startCadPairingListener();
    void setPairMessage(const QString &message);

    struct PendingPair {
        bool active = false;
        QPointer<QTcpSocket> socket;
        QString peer;
        QString label;
        QString keyBlob;
        QString fingerprint;
    };
    QTcpServer *m_pairServer = nullptr;
    QTimer *m_pairDecisionTimer = nullptr;
    PendingPair m_pairPending;
    QHash<QString, qint64> m_pairCooldown;
    QString m_pairMessage;
    QStringList m_pairedDevices;

    QJsonObject m_appUpdateMeta;
    QUrl m_appUpdateUrl;
    QString m_appUpdateNotes;
    QString m_appUpdateState = QStringLiteral("IDLE");
    QString m_appUpdateMessage;
    double m_appUpdateProgress = 0.0;
    QString m_lastUpdateResult;

    bool m_offlineValidation = false;
    QVariantList m_wifiNetworks;
    QStringList m_systemLogs;
    QString m_lastError;
    QString m_lastResult;
    bool m_operationActive = false;
    double m_operationProgress = 0.0;
    QTimer *m_systemMetricsTimer = nullptr;
    QTimer *m_autoBackupTimer = nullptr;
    QTimer *m_wifiAutoconnectTimer = nullptr;
    QProcess *m_wifiAutoconnectProcess = nullptr;
    bool m_wifiAutoconnectProbeInFlight = false;
    void applyPerformanceMode(bool enabled);
    void startWifiAutoconnect(const QString &device, const QString &uuid);
    QFutureWatcher<WifiConnectionResult> *m_wifiConnectionWatcher = nullptr;
    quint64 m_previousCpuTotal = 0;
    quint64 m_previousCpuIdle = 0;
    bool m_cpuBaselineAvailable = false;
    double m_cpuLoadPercent = 0.0;
    bool m_cpuLoadAvailable = false;
    double m_cpuTemperatureCelsius = 0.0;
    bool m_cpuTemperatureAvailable = false;
    QString m_cpuTemperaturePath;
    double m_memoryUsedPercent = 0.0;
    bool m_memoryAvailable = false;
    quint64 m_memoryUsedBytes = 0;
    quint64 m_memoryTotalBytes = 0;
    quint64 m_memorySampleCount = 0;
    QNetworkAccessManager m_updateNetwork;
    bool m_applicationUpdateAvailable = false;
    QString m_applicationUpdateVersion;
    QString m_updateCheckError;
};
