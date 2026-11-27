#pragma once

#include <QObject>
#include <QByteArray>
#include <QElapsedTimer>
#include <QList>
#include <QString>
#include <QTimer>
#include <QVariantMap>

#include <limits>
#include <memory>

class MachineTransport;
class PressTelemetryRecorder;

class MachineControlBackend final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool transportAvailable READ transportAvailable NOTIFY transportAvailabilityChanged FINAL)
    Q_PROPERTY(bool discoveryAvailable READ discoveryAvailable NOTIFY transportAvailabilityChanged FINAL)
    Q_PROPERTY(bool pressTransportAvailable READ pressTransportAvailable NOTIFY transportAvailabilityChanged FINAL)
    Q_PROPERTY(bool moduleTransportAvailable READ moduleTransportAvailable NOTIFY transportAvailabilityChanged FINAL)
    Q_PROPERTY(QString pressEndpointName READ pressEndpointName NOTIFY transportAvailabilityChanged FINAL)
    Q_PROPERTY(QString moduleEndpointName READ moduleEndpointName NOTIFY transportAvailabilityChanged FINAL)
    Q_PROPERTY(bool pressConnected READ pressConnected NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(bool pressReady READ pressReady NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(bool pressHomed READ pressHomed NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(bool pressOperationActive READ pressOperationActive NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(bool pressSafetyStopUnconfirmed READ pressSafetyStopUnconfirmed NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(QString pressConnectionState READ pressConnectionState NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(QString pressMachineState READ pressMachineState NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(QString pressFirmwareVersion READ pressFirmwareVersion NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(bool panelJogSupported READ panelJogSupported NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(bool panelJogRequiresPhysicalInputs READ panelJogRequiresPhysicalInputs NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(bool moduleConnected READ moduleConnected NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(bool moduleReady READ moduleReady NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(bool moduleHomed READ moduleHomed NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(bool moduleOperationActive READ moduleOperationActive NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(QString moduleConnectionState READ moduleConnectionState NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(QString moduleState READ moduleState NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(QString moduleFirmwareVersion READ moduleFirmwareVersion NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(bool safetyJogLeft READ safetyJogLeft NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool safetyJogRight READ safetyJogRight NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool bendPedal READ bendPedal NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool physicalPedal READ physicalPedal NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool physicalPedalAvailable READ physicalPedalAvailable NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool antiBind READ antiBind NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool independentRamTelemetryAvailable READ independentRamTelemetryAvailable NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double ramPositionY1 READ ramPositionY1 NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double ramPositionY2 READ ramPositionY2 NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double ramLoadY1 READ ramLoadY1 NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double ramLoadY2 READ ramLoadY2 NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double ramVelocity READ ramVelocity NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool measuredRamVelocityAvailable READ measuredRamVelocityAvailable NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double measuredRamVelocity READ measuredRamVelocity NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool motorRpmAvailable READ motorRpmAvailable NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double motorRpmY1 READ motorRpmY1 NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double motorRpmY2 READ motorRpmY2 NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double ramTargetPosition READ ramTargetPosition NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double ramCommandedJogPosition READ ramCommandedJogPosition NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double ramJogSpeed READ ramJogSpeed NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double ramDistanceToGo READ ramDistanceToGo NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool pressTelemetryFresh READ pressTelemetryFresh NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(qulonglong pressTelemetrySequence READ pressTelemetrySequence NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double ramToTableOpening READ ramToTableOpening NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(int deflectionCompensation READ deflectionCompensation NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool manualModeEnabled READ manualModeEnabled NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(double manualModeMaxTonnagePerRam READ manualModeMaxTonnagePerRam NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool primingModeEnabled READ primingModeEnabled NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool primingLatchSupported READ primingLatchSupported NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool primingLatchY1 READ primingLatchY1 NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool primingLatchY2 READ primingLatchY2 NOTIFY telemetryChanged FINAL)
    Q_PROPERTY(bool nativeTonnageHoldSupported READ nativeTonnageHoldSupported NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(bool thcCommissioningSupported READ thcCommissioningSupported NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(QString thcCommissioningState READ thcCommissioningState NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(bool toolChangeSupported READ toolChangeSupported NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(QString toolChangeMode READ toolChangeMode NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(QString toolChangePhase READ toolChangePhase NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(double toolChangeContactPosition READ toolChangeContactPosition NOTIFY pressStateChanged FINAL)
    Q_PROPERTY(QVariantMap thcLiveTuning READ thcLiveTuning NOTIFY thcLiveTuningChanged FINAL)
    Q_PROPERTY(bool thcLiveTuningSupported READ thcLiveTuningSupported NOTIFY thcLiveTuningChanged FINAL)
    Q_PROPERTY(bool thcLiveTuningExtended READ thcLiveTuningExtended NOTIFY thcLiveTuningChanged FINAL)
    Q_PROPERTY(bool thcLiveTuningPending READ thcLiveTuningPending NOTIFY thcLiveTuningChanged FINAL)
    Q_PROPERTY(QString thcLiveTuningError READ thcLiveTuningError NOTIFY thcLiveTuningChanged FINAL)
    Q_PROPERTY(bool thcContinuousActive READ thcContinuousActive NOTIFY thcContinuousActiveChanged FINAL)
    Q_PROPERTY(QVariantMap thcLiveDiagnostics READ thcLiveDiagnostics NOTIFY thcLiveDiagnosticsChanged FINAL)
    Q_PROPERTY(QVariantMap thcFineLoad READ thcFineLoad NOTIFY thcFineLoadChanged FINAL)
    Q_PROPERTY(bool moduleTelemetryFresh READ moduleTelemetryFresh NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(double moduleWorkX READ moduleWorkX NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(double moduleWorkR READ moduleWorkR NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(double moduleMachineX READ moduleMachineX NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(double moduleMachineR READ moduleMachineR NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(bool moduleLimitX1 READ moduleLimitX1 NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(bool moduleLimitX2 READ moduleLimitX2 NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(bool moduleLimitR1 READ moduleLimitR1 NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(bool moduleLimitR2 READ moduleLimitR2 NOTIFY moduleStateChanged FINAL)
    Q_PROPERTY(QString lastRejectReason READ lastRejectReason NOTIFY lastRejectChanged FINAL)
    Q_PROPERTY(QString lastRejectedOperation READ lastRejectedOperation NOTIFY lastRejectChanged FINAL)
    Q_PROPERTY(qulonglong operationId READ operationId NOTIFY commandLifecycleChanged FINAL)
    Q_PROPERTY(QString operationDevice READ operationDevice NOTIFY commandLifecycleChanged FINAL)
    Q_PROPERTY(QString operationName READ operationName NOTIFY commandLifecycleChanged FINAL)
    Q_PROPERTY(QString operationState READ operationState NOTIFY commandLifecycleChanged FINAL)
    Q_PROPERTY(QString operationError READ operationError NOTIFY commandLifecycleChanged FINAL)
    Q_PROPERTY(bool commandOperationActive READ commandOperationActive NOTIFY commandLifecycleChanged FINAL)
    Q_PROPERTY(QString pressTelemetryLogPath READ pressTelemetryLogPath CONSTANT FINAL)
    Q_PROPERTY(bool serialDiagnosticLogsEnabled READ serialDiagnosticLogsEnabled WRITE setSerialDiagnosticLogsEnabled NOTIFY serialDiagnosticLogsEnabledChanged FINAL)

public:
    enum class ConnectionState {
        Disconnected,
        Connecting,
        Initializing,
        Ready,
        Resetting,
        Disconnecting,
        Faulted
    };
    Q_ENUM(ConnectionState)

    enum class CommandRejectionReason {
        None,
        TransportUnavailable,
        NotConnected,
        NotReady,
        NotHomed,
        OperationInProgress,
        Resetting,
        InvalidArgument,
        CommandDisabled
    };
    Q_ENUM(CommandRejectionReason)

    explicit MachineControlBackend(QObject *parent = nullptr);
    explicit MachineControlBackend(std::unique_ptr<MachineTransport> pressTransport,
                                   std::unique_ptr<MachineTransport> moduleTransport,
                                   QObject *parent = nullptr,
                                   int initializationTimeoutMs = 10000,
                                   int homingTimeoutMs = 120000,
                                   int reconnectBaseDelayMs = 1000);
    ~MachineControlBackend() override;

    bool transportAvailable() const;
    bool discoveryAvailable() const { return transportAvailable(); }
    bool pressTransportAvailable() const;
    bool moduleTransportAvailable() const;
    QString pressEndpointName() const;
    QString moduleEndpointName() const;

    bool pressConnected() const { return m_pressConnected; }
    bool pressReady() const { return m_pressReady; }
    bool pressHomed() const { return m_pressHomed; }
    bool pressOperationActive() const { return m_pressOperationActive; }
    QString pressConnectionState() const;
    QString pressMachineState() const { return m_pressMachineState; }
    QString pressFirmwareVersion() const { return m_pressFirmwareVersion; }
    bool panelJogSupported() const;
    bool panelJogRequiresPhysicalInputs() const { return originalManualFirmware(); }

    bool moduleConnected() const { return m_moduleConnected; }
    bool moduleReady() const { return m_moduleReady; }
    bool moduleHomed() const { return m_moduleHomed; }
    bool moduleOperationActive() const { return m_moduleOperationActive; }
    QString moduleConnectionState() const;
    QString moduleState() const { return m_moduleState; }
    QString moduleFirmwareVersion() const { return m_moduleFirmwareVersion; }

    bool safetyJogLeft() const { return m_safetyJogLeft; }
    bool safetyJogRight() const { return m_safetyJogRight; }
    bool bendPedal() const { return m_bendPedal; }
    bool physicalPedal() const { return m_physicalPedal; }
    bool physicalPedalAvailable() const { return m_physicalPedalAvailable; }
    bool antiBind() const { return m_antiBind; }
    bool independentRamTelemetryAvailable() const { return m_independentRamTelemetryAvailable; }
    double ramPositionY1() const { return m_ramPositionY1; }
    double ramPositionY2() const { return m_ramPositionY2; }
    double ramLoadY1() const { return m_ramLoadY1; }
    double ramLoadY2() const { return m_ramLoadY2; }
    double ramVelocity() const { return m_ramVelocity; }
    bool measuredRamVelocityAvailable() const { return m_measuredRamVelocityAvailable; }
    double measuredRamVelocity() const { return m_measuredRamVelocity; }
    bool motorRpmAvailable() const { return m_motorRpmAvailable; }
    double motorRpmY1() const { return m_motorRpmY1; }
    double motorRpmY2() const { return m_motorRpmY2; }
    double ramTargetPosition() const { return m_ramTargetPosition; }
    double ramCommandedJogPosition() const { return m_ramCommandedJogPosition; }
    double ramJogSpeed() const { return m_ramJogSpeed; }
    double ramDistanceToGo() const { return m_ramDistanceToGo; }
    bool pressTelemetryFresh() const { return m_pressTelemetryFresh; }
    qulonglong pressTelemetrySequence() const { return m_pressTelemetrySequence; }
    double ramToTableOpening() const { return m_ramToTableOpening; }
    // -1 = unknown (no {EEPROM:...} seen), 0 = off, 1 = on.
    int deflectionCompensation() const { return m_deflectionCompensation; }
    bool manualModeEnabled() const { return m_manualModeEnabled; }
    double manualModeMaxTonnagePerRam() const { return m_manualModeMaxTonnagePerRam; }
    bool primingModeEnabled() const { return m_primingModeEnabled; }
    bool primingLatchSupported() const { return m_primingLatchSupported; }
    bool primingLatchY1() const { return m_primingLatchY1; }
    bool primingLatchY2() const { return m_primingLatchY2; }
    bool nativeTonnageHoldSupported() const;
    bool thcCommissioningSupported() const;
    QString thcCommissioningState() const { return m_thcCommissioningState; }
    bool toolChangeSupported() const { return m_pressToolChangeSupported && thcCommissioningSupported(); }
    QString toolChangeMode() const { return m_toolChangeMode; }
    QString toolChangePhase() const { return m_toolChangePhase; }
    double toolChangeContactPosition() const { return m_toolChangeContactPosition; }
    // Desired, confirmed RAM settings, NOT instantaneous effective gains. These
    // properties/invokables are not routed by the existing V51 socket adapter.
    QVariantMap thcLiveTuning() const { return m_thcLiveTuning; }
    bool thcLiveTuningSupported() const { return m_thcLiveTuningSupported; }
    bool thcLiveTuningExtended() const { return m_thcLiveTuningSupported && m_thcLiveTuningVersion == 2; }
    bool thcLiveTuningPending() const { return m_thcLiveRequest != ThcLiveRequest::None; }
    QString thcLiveTuningError() const { return m_thcLiveTuningError; }
    bool thcContinuousActive() const { return m_thcV53Phase != ThcV53Phase::Inactive; }
    QVariantMap thcLiveDiagnostics() const { return m_thcLiveDiagnostics; }
    QVariantMap thcFineLoad() const;
    bool thcContactObserved() const { return m_thcContactProfileContactObserved; }
    // True only for the exact V51 acknowledgement of this still-owned cycle.
    bool thcV51RunningAcknowledged() const { return m_thcV51RunningAcknowledged; }
    bool pressSafetyStopUnconfirmed() const { return m_pressSafetyStopUnconfirmed; }
    QString thcV51PendingFailure() const {
        return m_operationDevice == QStringLiteral("press")
            && m_pressCommandPhase == PressCommandPhase::ThcV51
            && m_operationName == QStringLiteral("thc-contact-profile-v51")
            && commandOperationActive() && m_thcV51Phase == ThcV51Phase::AwaitCancel
            ? m_pendingThcFailure : QString();
    }
    // Proof belongs to this terminal owner, not to later Home/STOP operations.
    bool thcV51CancellationConfirmed() const {
        return m_operationDevice == QStringLiteral("press")
            && m_operationName == QStringLiteral("thc-contact-profile-v51")
            && m_operationState == QStringLiteral("FAILED")
            && m_thcV51CancellationConfirmed && !m_pressSafetyStopUnconfirmed;
    }
    bool moduleTelemetryFresh() const { return m_moduleTelemetryFresh; }
    double moduleWorkX() const { return m_moduleWorkX; }
    double moduleWorkR() const { return m_moduleWorkR; }
    double moduleMachineX() const { return m_moduleMachineX; }
    double moduleMachineR() const { return m_moduleMachineR; }
    bool moduleLimitX1() const { return m_moduleLimitX1; }
    bool moduleLimitX2() const { return m_moduleLimitX2; }
    bool moduleLimitR1() const { return m_moduleLimitR1; }
    bool moduleLimitR2() const { return m_moduleLimitR2; }

    QString lastRejectReason() const { return m_lastRejectReason; }
    QString lastRejectedOperation() const { return m_lastRejectedOperation; }
    qulonglong operationId() const { return m_operationId; }
    QString operationDevice() const { return m_operationDevice; }
    QString operationName() const { return m_operationName; }
    QString operationState() const { return m_operationState; }
    QString operationError() const { return m_operationError; }
    bool commandOperationActive() const { return m_operationState == QStringLiteral("QUEUED")
        || m_operationState == QStringLiteral("SENT")
        || m_operationState == QStringLiteral("ACKNOWLEDGED"); }
    QString pressTelemetryLogPath() const;
    bool serialDiagnosticLogsEnabled() const { return m_serialDiagnosticLogsEnabled; }
    Q_INVOKABLE void setSerialDiagnosticLogsEnabled(bool enabled);

    Q_INVOKABLE bool connectPress();
    Q_INVOKABLE bool disconnectPress();
    // While a supervised firmware flash owns the Press port, the UI keeps it
    // closed (no connect/auto-reconnect). Clearing it reconnects.
    Q_INVOKABLE void setFirmwareFlashActive(bool active);
    Q_INVOKABLE bool resetPress();
    Q_INVOKABLE bool homePress();
    Q_INVOKABLE bool startAdvanceJog(double speed = 12.0);
    Q_INVOKABLE bool startRetractJog(double speed = 12.0);
    Q_INVOKABLE bool releasePanelJog();
    Q_INVOKABLE bool holdPressMotion();
    Q_INVOKABLE bool stopPressMotion();
    Q_INVOKABLE bool abortPress();
    Q_INVOKABLE bool killHydraulics();
    Q_INVOKABLE bool startProgram();
    Q_INVOKABLE bool beginProgramRun();
    Q_INVOKABLE void endProgramRun();
    // RUN pedal mode 0..3 (firmware $PM=): 0 jog buttons/double-tap bend,
    // 1 jog buttons/single-tap bend, 2 double-tap jog/single-tap bend,
    // 3 single-tap jog/double-tap bend.
    Q_INVOKABLE bool setRunPedalMode(int mode);
    // Remote RUN through the commissioning socket; disabled unless the
    // operator enables it in Settings.
    Q_INVOKABLE void setRemoteRunAllowed(bool allowed) { m_remoteRunAllowed = allowed; }
    bool requestRemoteRun();
    Q_INVOKABLE bool startManualOperation(const QString &operation);
    Q_INVOKABLE bool jogPress(double targetPosition, double speed, const QString &jogType);
    Q_INVOKABLE bool startManualStroke(double retractPosition, double bendPosition,
                                       double jogSpeed, double bendSpeed);
    Q_INVOKABLE bool setPressRetractPlane(double retractPosition);
    Q_INVOKABLE bool setRamToTableOpening(double openingInches);
    Q_INVOKABLE bool setDeflectionCompensation(bool enabled);
    Q_INVOKABLE bool setManualModeEnabled(bool enabled);
    Q_INVOKABLE bool setManualModeMaxTonnage(double maxTonnagePerRam);
    Q_INVOKABLE bool setPrimingEnabled(bool enabled);
    Q_INVOKABLE bool setPrimingLatch(const QString &axis, bool enabled);
    Q_INVOKABLE bool startTonnageHold(double targetTonnage, double bendSpeed, double jogSpeed);
    // Tool change modes of the tonnage hold profile (firmware TCH capability).
    Q_INVOKABLE bool startToolChangeTouch(double backoff, double floor);
    Q_INVOKABLE bool heartbeatToolChangeTouch();
    Q_INVOKABLE bool startToolChangeMove(double target);
    Q_INVOKABLE bool startToolChangeSeat(double bendSpeed, double jogSpeed, double retractPlane);
    Q_INVOKABLE bool stopTonnageHold();
    Q_INVOKABLE bool armThcCommissioning(double targetTonnage, double speed, double floor);
    Q_INVOKABLE bool startThcCommissioning();
    Q_INVOKABLE bool heartbeatThcCommissioning();
    Q_INVOKABLE bool releaseThcCommissioning();
    Q_INVOKABLE bool cancelThcCommissioning();
    // The bare frame keeps the validated 1.0 T profile; any other target
    // sends THC:CONTACT_PROFILE:<T>, which needs the AUTO-target firmware.
    static constexpr double ThcContactProfileDefaultTargetT = 1.0;
    static constexpr double ThcContactProfileMinTargetT = 0.5;
    static constexpr double ThcContactProfileMaxTargetT = 20.0;
    Q_INVOKABLE bool startThcContactProfileCommissioning(double targetTons = ThcContactProfileDefaultTargetT,
                                                         double approachIpm = 0.0);
    Q_INVOKABLE bool startAutomaticThcContactProfile(double targetTons = ThcContactProfileDefaultTargetT,
                                                     double approachIpm = 0.0);
    // The hash is explicit client selection, NOT device attestation. v1.3 and
    // TH_CTRL OWNED_INTERVAL_V49 do not advertise V51 capability.
    bool startThcContactProfileV51Commissioning(const QString &binarySha256);
    Q_INVOKABLE bool queryThcTuning();
    void cancelThcTuningQuery();
    Q_INVOKABLE bool queryThcLiveTuning();
    Q_INVOKABLE bool applyThcLiveTuning(const QVariantMap &settings);
    Q_INVOKABLE bool startContinuousThcContactProfile();
    // Auto THC free-approach speed (current Bend speed); 0 = firmware default.
    Q_INVOKABLE void setThcApproachSpeed(double ipm) { m_thcApproachSpeed = ipm; }

    Q_INVOKABLE bool connectModule();
    Q_INVOKABLE bool disconnectModule();
    Q_INVOKABLE bool resetModule();
    Q_INVOKABLE bool homeModule();
    Q_INVOKABLE bool homeAll();
    Q_INVOKABLE bool jogModule(const QString &axis, int direction, double distance, double speed,
                               bool continuous);
    Q_INVOKABLE bool moveModule(double x, double r, double speed);
    Q_INVOKABLE bool incrementModule(const QString &axis, double distance, double speed);
    Q_INVOKABLE bool selectModuleCoordinateSystem(const QString &system);
    Q_INVOKABLE bool setModuleWorkPosition(const QString &system, const QString &axis,
                                           double value);
    Q_INVOKABLE bool stopModule();
    Q_INVOKABLE bool cancelCommandOperation();

signals:
    void transportAvailabilityChanged();
    void pressStateChanged();
    void remoteRunRequested();
    void moduleStateChanged();
    void telemetryChanged();
    void lastRejectChanged();
    void operationRejected(const QString &device, const QString &operation, const QString &reason);
    void connectionFailed(const QString &device, const QString &reason);
    void commandLifecycleChanged();
    void telemetryLogLine(const QString &device, const QString &line);
    void pressSerialLogLine(const QString &source, const QString &content);
    void thcTuningQueryFinished(bool ok, const QString &response, const QString &error);
    // event: CONTACT, BACKOFF, BACKOFF_DONE, MOVE_DONE, SEAT_ARMED,
    // SEAT_PAUSED, SEAT_RESUMED, SEAT_DONE. position NaN when not carried.
    void toolChangeEvent(const QString &event, double position);
    void thcLiveTuningChanged();
    void thcContinuousActiveChanged();
    void thcLiveDiagnosticsChanged();
    void thcFineLoadChanged();
    void commandOperationFinished(qulonglong id, const QString &device,
                                  const QString &operation, const QString &state,
                                  const QString &error);
    void serialDiagnosticLogsEnabledChanged();

private:
    // Values of every QML-visible property notified by pressStateChanged or
    // telemetryChanged (except the per-frame sequence counter). Lets the idle
    // telemetry path skip republishing identical state, which otherwise forces
    // continuous scene-graph frames on the press.
    QVariantList pressObservableSnapshot() const;
    QVariantList m_publishedPressSnapshot;

    static QString connectionStateName(ConnectionState state);
    static QString rejectionReasonName(CommandRejectionReason reason);

    void revokePrimingLatchPresentation();
    bool reject(const QString &device, const QString &operation, CommandRejectionReason reason);
    bool moduleHomeBlocked(CommandRejectionReason &reason) const;
    bool startModuleHome(bool concurrent);
    void recordRejectedCommand(const QString &device, const QString &operation,
                               CommandRejectionReason reason);
    bool rejectPressOperation(const QString &operation, bool requireReady, bool requireHomed);
    bool rejectModuleOperation(const QString &operation, bool requireReady, bool requireHomed);
    bool admitPressMotion(const QString &operation);
    bool admitModuleMotion(const QString &operation);
    void beginCommandOperation(const QString &device, const QString &operation);
    void acknowledgeCommandOperation();
    void finishCommandOperation(const QString &state, const QString &error = QString());
    void failActiveCommand(const QString &error);
    bool pressPhaseRequiresSafetyStop() const;
    void beginPressSafetyFailure(const QString &error, const QByteArray &frame);
    bool writePressCommand(const QByteArray &frame, const QString &operation);
    void continueManualStrokeAfterSetting();
    bool writeNextModuleFrame();
    void completeActivePressCommand();
    void completeActiveModuleCommand();
    bool pressStateIsMotion(const QString &state) const;
    void beginHomeOperation(const QString &device);
    void finishHomeOperation(const QString &device, const QString &state,
                             const QString &error = QString());
    void beginPressHomingSafetyFailure(const QString &reason);
    void tryCompletePressHomingSafetyFailure();
    void failPressHoming(const QString &reason, bool closeTransport = true);
    void failModuleHoming(const QString &reason, bool closeTransport = true);
    void clearPressState();
    void clearModuleState();
    void handlePressTransportClosed();
    void handleModuleTransportClosed();
    void handlePressTransportError(const QString &message);
    void handleModuleTransportError(const QString &message);
    bool attemptPressConnection(bool reportFailure);
    bool attemptModuleConnection(bool reportFailure);
    void handlePressAvailabilityChanged();
    void handleModuleAvailabilityChanged();
    void schedulePressReconnect(bool endpointRediscovered = false);
    void scheduleModuleReconnect(bool endpointRediscovered = false);
    void attemptPressReconnect();
    void attemptModuleReconnect();
    bool startPressHandshake();
    void startModuleHandshake();
    void handlePressFrame(const QByteArray &frame);
    void handleModuleFrame(const QByteArray &frame);
    void failPressInitialization(const QString &reason);
    void failModuleInitialization(const QString &reason);
    void pollModuleStatus();
    void sendPressKeepAlive();
    void sendTonnageHoldHeartbeat();
    void sendPrimingHeartbeat();
    void sendThcContactProfileHeartbeat();
    void resetThcV51Operation();
    void stopThcV51Timers();
    void setThcV51PhaseDeadline(qint64 deadlineMs);
    bool checkThcV51Deadlines();
    void sendThcV51Heartbeat();
    bool beginThcV51Cancellation(const QString &error);
    bool releaseThcV51();
    bool handleThcV51Frame(const QByteArray &frame, qulonglong arrival);
    void handleThcV51Telemetry(bool exactIdleTelemetry = false, qulonglong arrival = 0);
    bool rejectThcLiveRequest(const QString &error);
    void invalidateThcLiveTuning(const QString &error, bool clearConfirmed = false, bool notify = true);
    bool admitThcLiveRequest(bool mutation);
    bool handleThcLiveFrame(const QByteArray &frame, qulonglong arrival);
    bool thcFineOwnerActive() const;
    void invalidateThcFineLoad(bool notify = true);
    void observeThcFineLoad(const QVariantMap &values, qulonglong arrival);
    void observeThcFineLoadAt(const QVariantMap &values, qulonglong arrival, qint64 hostMs);
    void resetThcV53Operation();
    void stopThcV53Timers();
    void setThcV53PhaseDeadline(qint64 deadlineMs);
    bool checkThcV53Deadlines();
    void sendThcV53Heartbeat();
    bool beginThcV53Cancellation(const QString &error);
    bool releaseThcV53();
    bool handleThcV53Frame(const QByteArray &frame, qulonglong arrival);
    void handleThcV53Telemetry(bool exactIdleTelemetry, qulonglong arrival);
    void expirePressTelemetry();
    void expireModuleTelemetry();
    bool admitPressConfiguration(const QString &operation);
    bool isTonnageHoldPhase() const;
    void scheduleLegacyTonnageAdjustment(int delayMs);
    void evaluateLegacyTonnageHold();

    std::unique_ptr<MachineTransport> m_pressTransport;
    std::unique_ptr<MachineTransport> m_moduleTransport;
    std::unique_ptr<PressTelemetryRecorder> m_pressTelemetryRecorder;

    ConnectionState m_pressConnectionState = ConnectionState::Disconnected;
    bool m_pressConnected = false;
    bool m_pressReady = false;
    bool m_pressHomed = false;
    bool m_pressOperationActive = false;
    bool m_pressSafetyStopUnconfirmed = false;
    bool m_pressHomePending = false;
    bool m_pressHomeProgressObserved = false;
    QString m_pressHomeInitialState;
    QString m_pressMachineState = QStringLiteral("UNKNOWN");
    QString m_pressFirmwareVersion;
    QString m_pressFirmwareIdentity;

    ConnectionState m_moduleConnectionState = ConnectionState::Disconnected;
    bool m_moduleConnected = false;
    bool m_moduleReady = false;
    bool m_moduleHomed = false;
    bool m_moduleOperationActive = false;
    enum class ModuleHomePhase { Idle, AwaitUnlockAck, AwaitHomeAck, AwaitIdleTelemetry };
    ModuleHomePhase m_moduleHomePhase = ModuleHomePhase::Idle;
    bool m_moduleHomeConcurrent = false;
    qulonglong m_moduleConcurrentHomeId = 0;
    QString m_moduleState = QStringLiteral("UNKNOWN");
    QString m_moduleFirmwareVersion;

    bool m_safetyJogLeft = false;
    bool m_safetyJogRight = false;
    bool m_bendPedal = false;
    bool m_physicalPedal = false;
    bool m_physicalPedalAvailable = false;
    bool m_antiBind = false;
    bool m_independentRamTelemetryAvailable = false;
    double m_ramPositionY1 = 0.0;
    double m_ramPositionY2 = 0.0;
    double m_ramLoadY1 = 0.0;
    double m_ramLoadY2 = 0.0;
    double m_ramVelocity = 0.0;
    bool m_measuredRamVelocityAvailable = false;
    double m_measuredRamVelocity = 0.0;
    bool m_motorRpmAvailable = false;
    double m_motorRpmY1 = 0.0;
    double m_motorRpmY2 = 0.0;
    double m_ramTargetPosition = 0.0;
    double m_ramCommandedJogPosition = 0.0;
    double m_ramJogSpeed = 0.0;
    double m_ramDistanceToGo = 0.0;
    double m_ramToTableOpening = 0.0;
    bool m_pressTelemetryFresh = false;
    qulonglong m_pressTelemetrySequence = 0;
    bool m_manualModeEnabled = false;
    double m_manualModeMaxTonnagePerRam = 0.0;
    bool m_primingModeEnabled = false;
    bool m_primingLatchSupported = false;
    bool m_primingLatchY1 = false;
    bool m_primingLatchY2 = false;
    bool m_primingLatchRevocationPending = false;
    bool m_moduleTelemetryFresh = false;
    double m_moduleWorkX = 0.0;
    double m_moduleWorkR = 0.0;
    double m_moduleMachineX = 0.0;
    double m_moduleMachineR = 0.0;
    bool m_moduleLimitX1 = false;
    bool m_moduleLimitX2 = false;
    bool m_moduleLimitR1 = false;
    bool m_moduleLimitR2 = false;
    bool m_moduleInches = true;
    bool m_moduleUnitSettingSeen = false;
    bool m_moduleWcoAvailable = false;
    double m_moduleWcoX = 0.0;
    double m_moduleWcoR = 0.0;

    QString m_lastRejectReason;
    QString m_lastRejectedOperation;
    qulonglong m_operationId = 0;
    QString m_operationDevice;
    QString m_operationName;
    QString m_operationState = QStringLiteral("IDLE");
    QString m_operationError;
    bool m_serialDiagnosticLogsEnabled = false;

    enum class PressCommandPhase { Idle, AwaitProgress, AwaitIdle, AwaitHoldIdle,
                                   AwaitStopIdle,
                                   AwaitHydraulicShutdown,
                                   AwaitFailureStopIdle,
                                   AwaitHomeFailureStopIdle,
                                   AwaitSettingAck, AwaitRamToTableStop,
                                   AwaitRamToTableAck,
                                   AwaitManualModeStatus,
                                   AwaitManualTonnageAck, AwaitPrimingStatus,
                                   StrokeAwaitSetting,
                                   StrokeAwaitRetract, StrokeAwaitBend,
                                   NativeTonnageHold, LegacyTonnageApproach,
                                   LegacyTonnageAwaitApproachIdle,
                                   LegacyTonnageFineJog, LegacyTonnageMonitoring,
                                   TonnageHoldAwaitStopIdle, ThcCommissioning,
                                   ThcAwaitCancel, ThcV51, ThcV53 };
    PressCommandPhase m_pressCommandPhase = PressCommandPhase::Idle;
    QString m_pressCommandJogType;
    QString m_expectedPressStopState = QStringLiteral("IDLE");
    bool m_allowPressStopIdleRace = false;
    bool m_pressStopAcknowledged = false;
    bool m_tonnageHoldDoneAcknowledged = false;
    QString m_pendingThcFailure;
    friend class MachineControlBackendTests;
    friend class ThcV51OwnerProtocolTests;
    bool originalManualFirmware() const;
    bool writeRamToTableOpeningFrame();
    bool pressMotionFirmwareSupported(const QString &operation) const;
    QByteArray prepareOriginalManualStop(bool allowCancel);
    bool m_originalManualStop = false;
    bool m_originalManualCancel = false;
    bool m_originalCommandEchoSeen = false;
    bool m_originalStopHadFault = false;
    QByteArray m_originalExpectedEcho;
    qsizetype m_originalTelemetryDrainBytes = 0;
    double m_pressCommandTarget = 0.0;
    double m_pressStrokeRetractTarget = 0.0;
    // Last TEMP retract plane that did not match a pending $R (NaN = none).
    double m_pressRetractEchoMismatch = std::numeric_limits<double>::quiet_NaN();
    double m_pressStrokeBendTarget = 0.0;
    double m_pressStrokeJogSpeed = 0.0;
    double m_pressStrokeBendSpeed = 0.0;
    double m_thcApproachSpeed = 0.0;
    bool m_pressCommandProgressObserved = false;
    bool m_expectedManualModeEnabled = false;
    bool m_expectedPrimingModeEnabled = false;
    double m_requestedRamToTableOpening = 0.0;
    int m_deflectionCompensation = -1;
    // -1 = the pending EEPROM write is $3 (opening); 0/1 = it is $1.
    int m_requestedDeflectionCompensation = -1;
    int m_deflectionAdmission = -1;
    double m_requestedManualMaxTonnage = 0.0;
    double m_tonnageHoldTarget = 0.0;
    double m_tonnageHoldApproachSpeed = 0.0;
    double m_tonnageHoldJogSpeed = 0.0;
    QString m_thcCommissioningState = QStringLiteral("IDLE");
    bool m_thcContactProfileActive = false;
    bool m_pressToolChangeSupported = false;
    QString m_toolChangeMode;  // TOUCH / MOVE / SEAT while owned
    QString m_toolChangePhase = QStringLiteral("IDLE");
    double m_toolChangeContactPosition = 0.0;
    bool handleToolChangeFrame(const QString &line);
    bool m_thcContactProfileContactObserved = false;
    bool m_thcContactProfileAutomaticLifecycle = false;
    enum class ThcV51Phase { Inactive, AwaitStart, Approach, Acquisition, Holding,
                             AwaitRelease, Releasing, AwaitIdle, AwaitCancel };
    ThcV51Phase m_thcV51Phase = ThcV51Phase::Inactive;
    bool m_thcV51RunningAcknowledged = false;
    bool m_thcV51CancelAcknowledged = false;
    bool m_thcV51CancellationConfirmed = false;
    // Only a new, valid IDLE frame after the typed terminal ACK corroborates it.
    qulonglong m_thcV51TerminalTelemetrySequence = 0;
    qulonglong m_thcV51TerminalArrival = 0;
    qulonglong m_pressFrameArrival = 0;
    // Immutable nominal budgets; monotonic absolute deadlines never renew on
    // duplicate protocol frames or automatic MCU heartbeat ticks.
    static constexpr int ThcV51HeartbeatMs = 250;
    static constexpr int ThcV51ClientLeaseMs = 2000;
    static constexpr int ThcV51AckMs = 5000;
    static constexpr int ThcV51ApproachMs = 50000; // firmware: 45 s, from admission
    static constexpr int ThcV51AcquisitionMs = 185000; // firmware: 180 s
    static constexpr int ThcV51HoldMs = 60000; // release before firmware's 65 s
    static constexpr int ThcV51ReleaseMs = 45000; // firmware: 40 s, from send
    // Deliberately conservative: equal to firmware's 330 s overall limit,
    // not the possible 335 s delivery-margin observer. Never extend a cycle.
    static constexpr int ThcV51OverallMs = 330000;
    QElapsedTimer m_thcV51Clock;
    qint64 m_thcV51PhaseDeadlineMs = -1;
    qint64 m_thcV51OverallDeadlineMs = -1;
    qint64 m_thcV51ClientDeadlineMs = -1;
    qint64 m_thcV51ReleaseDeadlineMs = -1;
    QTimer m_thcV51HeartbeatTimer;
    QTimer m_thcV51ClientLeaseTimer;
    QTimer m_thcV51PhaseTimer;
    QTimer m_thcV51OverallTimer;
    enum class ThcLiveRequest { None, Query, Tune };
    ThcLiveRequest m_thcLiveRequest = ThcLiveRequest::None;
    QVariantMap m_thcLiveTuning;
    QVariantMap m_thcLiveExpected;
    // Capability/ACK correlation is separate from the unchanged settings map.
    int m_thcLiveTuningVersion = 0;
    int m_thcLiveExpectedVersion = 0;
    QVariantMap m_thcLiveDiagnostics;
    // Display-only stream: no lease, admission or general telemetry authority.
    QVariantMap m_thcFineLoad;
    QElapsedTimer m_thcFineHostClock;
    QTimer m_thcFineExpiryTimer;
    qulonglong m_thcFineGeneration = 0;
    qulonglong m_thcFineSequence = 0;
    qulonglong m_thcFineOwner = 0;
    qulonglong m_thcFineArrivalFloor = 0;
    bool m_thcFineAnchorValid = false;
    quint32 m_thcFineLastMcuSequence = 0;
    quint32 m_thcFineLastMcuMs = 0;
    quint32 m_thcFineLastSampleMs = 0;
    qint64 m_thcFineAnchorHostMs = 0;
    qint64 m_thcFineLastHostMs = 0;
    quint32 m_thcFineAnchorMcuMs = 0;
    bool m_thcLiveTuningSupported = false;
    // Unknown replies cannot correlate a later tokenless query in this stream.
    // Re-handshake first; never retry the mutation.
    bool m_thcLiveRecoveryRequired = false;
    QString m_thcLiveTuningError;
    QTimer m_thcLiveRequestTimer;
    QElapsedTimer m_thcLiveRequestClock;
    QElapsedTimer m_thcLiveCapabilityClock;
    qulonglong m_thcLiveRequestArrival = 0;
    // Local identity only: a reentrant write must not invalidate its successor.
    qulonglong m_thcLiveRequestId = 0;
    enum class ThcV53Phase { Inactive, AwaitStart, Approach, Acquisition, Holding,
                            AwaitRelease, Releasing, AwaitIdle, AwaitCancel };
    ThcV53Phase m_thcV53Phase = ThcV53Phase::Inactive;
    bool m_thcV53RunningAcknowledged = false;
    bool m_thcV53CancelAcknowledged = false;
    QString m_thcV53Failure;
    qulonglong m_thcV53TerminalTelemetrySequence = 0;
    qulonglong m_thcV53TerminalArrival = 0;
    QElapsedTimer m_thcV53Clock;
    qint64 m_thcV53PhaseDeadlineMs = -1;
    qint64 m_thcV53ClientDeadlineMs = -1;
    qint64 m_thcV53ReleaseDeadlineMs = -1;
    QTimer m_thcV53HeartbeatTimer;
    QTimer m_thcV53ClientLeaseTimer;
    QTimer m_thcV53PhaseTimer;
    QString m_pendingPressFailure;
    QString m_pendingPressHomeFailure;

    enum class ModuleCommandPhase { Idle, AwaitFirstAck, AwaitSecondAck,
                                    AwaitIdleTelemetry, ContinuousJogging,
                                    AwaitJogIdle, StopAwaitHold, StopAwaitResetWelcome,
                                    StopReinitializing };
    ModuleCommandPhase m_moduleCommandPhase = ModuleCommandPhase::Idle;
    QList<QByteArray> m_moduleCommandFrames;
    int m_moduleCommandFrameIndex = 0;
    double m_moduleTargetX = 0.0;
    double m_moduleTargetR = 0.0;
    bool m_moduleTargetRequired = false;
    QString m_moduleCoordinateSystem = QStringLiteral("G54");
    QString m_moduleContinuousAxis;
    int m_moduleContinuousDirection = 0;
    int m_moduleContinuousInFlight = 0;
    bool m_moduleJogCancelPending = false;
    bool m_moduleHomedBeforeStop = false;
    bool m_programRunActive = false;
    bool m_remoteRunAllowed = false;
    double m_moduleMaxRateX = 0.0;
    double m_moduleMaxRateR = 0.0;
    double m_moduleAccelerationX = 0.0;
    double m_moduleAccelerationR = 0.0;

    enum class PressHandshakeState { Idle, AwaitWelcome, AwaitTelemetry, Ready };
    enum class ModuleHandshakeState { Idle, AwaitWelcome, AwaitSettingsOk, AwaitModalOk,
                                      AwaitStatus, Ready };
    PressHandshakeState m_pressHandshakeState = PressHandshakeState::Idle;
    bool m_pressIdentityQueryRetriedAfterReset = false;
    ModuleHandshakeState m_moduleHandshakeState = ModuleHandshakeState::Idle;
    bool m_moduleSettingsSeen = false;
    bool m_moduleModalSeen = false;
    int m_initializationTimeoutMs = 10000;
    int m_homingTimeoutMs = 120000;
    int m_reconnectBaseDelayMs = 1000;
    static constexpr int MaximumReconnectAttempts = 6;
    bool m_pressReconnectDesired = false;
    bool m_firmwareFlashActive = false;
    bool m_moduleReconnectDesired = false;
    int m_pressReconnectAttempts = 0;
    int m_moduleReconnectAttempts = 0;
    QTimer m_pressInitializationTimer;
    QTimer m_moduleInitializationTimer;
    QTimer m_pressHomingTimer;
    QTimer m_moduleHomingTimer;
    QTimer m_pressKeepAliveTimer;
    QTimer m_moduleStatusPollTimer;
    QTimer m_pressTelemetryFreshnessTimer;
    QTimer m_moduleTelemetryFreshnessTimer;
    QTimer m_telemetryLogTimer;
    QTimer m_commandDeadlineTimer;
    QTimer m_tonnageHoldTimer;
    QTimer m_tonnageHoldHeartbeatTimer;
    QTimer m_primingHeartbeatTimer;
    QTimer m_thcContactProfileHeartbeatTimer;
    QTimer m_thcTuningQueryTimer;
    QTimer m_pressReconnectTimer;
    QTimer m_moduleReconnectTimer;
    bool m_thcTuningQueryPending = false;
    bool m_thcTuningQueryRecovery = false;
};
