#include "MachineControlBackend.h"

#include <QMetaProperty>
#include <tuple>

#include "MachineProtocolParsers.h"
#include "MachineTransport.h"
#include "NullMachineTransport.h"
#include "PressTelemetryRecorder.h"

#include <QDebug>
#include <QRegularExpression>
#include <QSet>

#include <cmath>
#include <utility>

namespace {
constexpr int ThcAcquisitionHostObserverMs = 65000;
constexpr int ThcHoldingObservationMs = 60000;
constexpr int ThcReleaseHostObserverMs = 45000;
constexpr int ThcCancelConfirmationMs = 10000;
// $R is a non-motion setting acknowledged by an immediate TEMP echo.
constexpr int RetractPlaneAckTimeoutMs = 3000;
constexpr int ThcTuningQueryTimeoutMs = 2000;
constexpr int ThcV53CapabilityFreshMs = 10000;
constexpr int ThcV53ApproachMs = 45000;
constexpr int ThcV53AcquisitionMs = 60000;
constexpr int ThcV53ReleaseMs = 40000;
constexpr int ThcFineFreshMs = 750;
constexpr int ThcFineSampleAgeMs = 250;
constexpr int ThcFineClockToleranceMs = 250;
const QStringList ThcV53Keys = {QStringLiteral("kp"), QStringLiteral("ki"),
    QStringLiteral("kd"), QStringLiteral("rate"), QStringLiteral("cq"), QStringLiteral("fs")};

// Technical wire ceiling, NOT a physical/tuning safety limit: each field is
// at most 9 integer digits + '.' + 6 decimals inside a 128-byte payload.
constexpr double ThcV53TechnicalMax = 999999999.999999;

bool canonicalV53ExtendedNumber(const QString &text)
{
    static const QRegularExpression pattern(QStringLiteral(
        "\\A(?:0|[1-9][0-9]{0,8})\\.[0-9]{6}\\z"));
    return pattern.match(text).hasMatch();
}

bool validV53Values(const QVariantMap &values, int version = 1)
{
    if (version != 1 && version != 2) return false;
    const double low[] = {0, 0, 0, 0.002, 0.005, 0.020};
    const double high[] = {0.30, 0.04, 0.06, 0.010, 0.020, 0.100};
    for (int i = 0; i < 6; ++i) {
        const QVariant value = values.value(ThcV53Keys[i]);
        // QML supplies numbers as doubles; never coerce strings/bools/null.
        const int type = value.metaType().id();
        if (type != QMetaType::Double && type != QMetaType::Float
            && type != QMetaType::Int && type != QMetaType::UInt
            && type != QMetaType::LongLong && type != QMetaType::ULongLong) return false;
        const double n = value.toDouble();
        const double minimum = version == 2 ? (i == 5 ? 0.000001 : 0.0) : low[i];
        const double maximum = version == 2 ? ThcV53TechnicalMax : high[i];
        if (!std::isfinite(n) || n < minimum || n > maximum) return false;
    }
    return values.value(QStringLiteral("fs")).toDouble() > values.value(QStringLiteral("cq")).toDouble();
}

QVariantMap parseV53Reply(const QByteArray &frame, int *version = nullptr)
{
    if (version) *version = 0;
    static const QRegularExpression pattern(QStringLiteral(
        "\\A\\{THC:V53:v=([12]),kp=([0-9]+\\.[0-9]{6}),ki=([0-9]+\\.[0-9]{6}),kd=([0-9]+\\.[0-9]{6}),rate=([0-9]+\\.[0-9]{6}),cq=([0-9]+\\.[0-9]{6}),fs=([0-9]+\\.[0-9]{6}),revision=(0|[1-9][0-9]{0,9})\\}\\z"));
    if (frame.size() > 160) return {};
    const auto match = pattern.match(QString::fromLatin1(frame));
    if (!match.hasMatch()) return {};
    const int parsedVersion = match.captured(1).toInt();
    QVariantMap values;
    for (int i = 0; i < 6; ++i) {
        const QString text = match.captured(i + 2);
        if (parsedVersion == 2 && !canonicalV53ExtendedNumber(text)) return {};
        values.insert(ThcV53Keys[i], text.toDouble());
    }
    bool ok = false;
    const auto revision = match.captured(8).toULongLong(&ok);
    if (!ok || revision > 4294967295ULL || !validV53Values(values, parsedVersion)) return {};
    values.insert(QStringLiteral("revision"), QVariant::fromValue(revision));
    if (version) *version = parsedVersion;
    return values;
}

// Optional diagnostic publications have no admission, ACK or lease authority.
QVariantMap parseV53Diagnostics(const QByteArray &frame, int version)
{
    if (frame.size() > 512 || !frame.endsWith(']')) return {};
    const bool control = frame.startsWith("[TH_CTRL ");
    const bool effective = frame.startsWith("[TH_V53 ");
    if (!control && !effective) return {};
    QStringList keys = control
        ? QStringList{QStringLiteral("ms"), QStringLiteral("age"), QStringLiteral("ph"),
            QStringLiteral("f1"), QStringLiteral("f2"), QStringLiteral("req"), QStringLiteral("v"),
            QStringLiteral("p"), QStringLiteral("i"), QStringLiteral("d"), QStringLiteral("ev1"),
            QStringLiteral("ev2"), QStringLiteral("ap1"), QStringLiteral("ap2"), QStringLiteral("clamp"),
            QStringLiteral("hr"), QStringLiteral("hn"), QStringLiteral("hl"), QStringLiteral("ha"),
            QStringLiteral("fr"), QStringLiteral("profile")}
        : QStringList{QStringLiteral("revision"), QStringLiteral("effectiveRevision"),
            QStringLiteral("rampMs"), QStringLiteral("hold"), QStringLiteral("kp"),
            QStringLiteral("ki"), QStringLiteral("kd"), QStringLiteral("rate"),
            QStringLiteral("cq"), QStringLiteral("fs")};
    const auto fields = frame.mid(control ? 9 : 8, frame.size() - (control ? 10 : 9)).split(' ');
    // DiagnosticTelemetryQueue appends seq to both publications. Retain the
    // historical unsequenced layout for diagnostics, never for fine history.
    if (fields.size() == keys.size() + 1) keys.append(QStringLiteral("seq"));
    if (fields.size() != keys.size()) return {};
    static const QRegularExpression number(QStringLiteral("\\A-?[0-9]+(?:\\.[0-9]+)?\\z"));
    QVariantMap values;
    for (int i = 0; i < fields.size(); ++i) {
        const QByteArray prefix = keys[i].toLatin1() + '=';
        if (!fields[i].startsWith(prefix)) return {};
        const QString text = QString::fromLatin1(fields[i].mid(prefix.size()));
        if (keys[i] == QStringLiteral("profile")) {
            if (text != QStringLiteral("V46_LIVE_V53")) return {};
            values.insert(keys[i], text);
            continue;
        }
        bool ok = false;
        const double n = text.toDouble(&ok);
        if (!number.match(text).hasMatch() || !ok || !std::isfinite(n) || std::abs(n) > 4294967295.0) return {};
        if (effective && version == 2 && ThcV53Keys.contains(keys[i])
            && !canonicalV53ExtendedNumber(text)) return {};
        const bool integer = keys[i] == "ms" || keys[i] == "age" || keys[i] == "ph"
            || keys[i] == "clamp" || keys[i] == "hr" || keys[i] == "hn" || keys[i] == "hl"
            || keys[i] == "fr" || keys[i] == "revision" || keys[i] == "effectiveRevision"
            || keys[i] == "rampMs" || keys[i] == "hold" || keys[i] == "seq";
        if (integer && (n < 0 || n != std::floor(n) || text.contains('.'))) return {};
        if ((keys[i] == "clamp" || keys[i] == "hl" || keys[i] == "fr" || keys[i] == "hold") && n > 1) return {};
        if ((keys[i] == "ph" && n > 4) || (keys[i] == "rampMs" && n > 500)) return {};
        values.insert(keys[i], n);
    }
    if (effective && !validV53Values(values, version == 2 ? 2 : 1)) return {};
    if (control) {
        static const QRegularExpression fine(QStringLiteral("\\Af[12]=-?[0-9]+\\.[0-9]{5}\\z"));
        values.insert(QStringLiteral("finePrecision"), fine.match(QString::fromLatin1(fields[3])).hasMatch()
            && fine.match(QString::fromLatin1(fields[4])).hasMatch());
        values.insert(QStringLiteral("force"), values.value("f1").toDouble() + values.value("f2").toDouble());
        values.insert(QStringLiteral("request"), values.value("req"));
        values.insert(QStringLiteral("velocity"), values.value("v"));
        // V53 TH_CTRL publishes ha (learned holding authority), not a boot field.
        values.insert(QStringLiteral("raw"), QString::fromLatin1(frame));
    }
    return values;
}
}

MachineControlBackend::MachineControlBackend(QObject *parent)
    : MachineControlBackend(std::make_unique<NullMachineTransport>(),
                            std::make_unique<NullMachineTransport>(), parent)
{
}

MachineControlBackend::MachineControlBackend(std::unique_ptr<MachineTransport> pressTransport,
                                             std::unique_ptr<MachineTransport> moduleTransport,
                                             QObject *parent,
                                             int initializationTimeoutMs,
                                             int homingTimeoutMs,
                                             int reconnectBaseDelayMs)
    : QObject(parent)
    , m_pressTransport(std::move(pressTransport))
    , m_moduleTransport(std::move(moduleTransport))
    , m_pressTelemetryRecorder(std::make_unique<PressTelemetryRecorder>())
    , m_initializationTimeoutMs(initializationTimeoutMs)
    , m_homingTimeoutMs(homingTimeoutMs)
    , m_reconnectBaseDelayMs(qMax(1, reconnectBaseDelayMs))
{
        Q_ASSERT(m_pressTransport);
        Q_ASSERT(m_moduleTransport);
    m_thcFineHostClock.start();
    connect(this, &MachineControlBackend::pressStateChanged, this,
            [this] { m_publishedPressSnapshot = pressObservableSnapshot(); });
    connect(this, &MachineControlBackend::telemetryChanged, this,
            [this] { m_publishedPressSnapshot = pressObservableSnapshot(); });
    connect(this, &MachineControlBackend::thcContinuousActiveChanged,
        this, &MachineControlBackend::thcFineLoadChanged);
        connect(this, &MachineControlBackend::commandLifecycleChanged, this, [this] {
            if (m_thcFineOwner != m_operationId || !thcFineOwnerActive()) invalidateThcFineLoad();
        });
    m_thcFineExpiryTimer.setSingleShot(true);
    m_thcFineExpiryTimer.setTimerType(Qt::PreciseTimer);
    connect(&m_thcFineExpiryTimer, &QTimer::timeout, this, [this] {
        invalidateThcFineLoad(); // Display expiry never sends a command.
    });
        connect(m_pressTransport.get(), &MachineTransport::availabilityChanged,
            this, &MachineControlBackend::handlePressAvailabilityChanged);
        connect(m_moduleTransport.get(), &MachineTransport::availabilityChanged,
            this, &MachineControlBackend::handleModuleAvailabilityChanged);
        connect(m_pressTransport.get(), &MachineTransport::closed,
            this, &MachineControlBackend::handlePressTransportClosed);
        connect(m_moduleTransport.get(), &MachineTransport::closed,
            this, &MachineControlBackend::handleModuleTransportClosed);
        connect(m_pressTransport.get(), &MachineTransport::transportError,
            this, &MachineControlBackend::handlePressTransportError);
        connect(m_pressTransport.get(), &MachineTransport::transportError,
                this, [this](const QString &message) {
                    m_pressTelemetryRecorder->recordError(QStringLiteral("TRANSPORT"), message);
                });
        connect(m_moduleTransport.get(), &MachineTransport::transportError,
            this, &MachineControlBackend::handleModuleTransportError);
            connect(m_pressTransport.get(), &MachineTransport::frameReceived,
                this, &MachineControlBackend::handlePressFrame);
            connect(m_pressTransport.get(), &MachineTransport::frameReceived,
                this, [this](const QByteArray &frame) {
                    m_pressTelemetryRecorder->recordRawFrame(QStringLiteral("RX"), frame);
                });
            connect(m_pressTransport.get(), &MachineTransport::frameWriteAttempted,
                this, [this](const QByteArray &frame) {
                    m_pressTelemetryRecorder->recordRawFrame(QStringLiteral("TX"), frame);
                });
            connect(m_pressTransport.get(), &MachineTransport::frameReceived,
                this, [this](const QByteArray &frame) {
                    emit pressSerialLogLine(QStringLiteral("MACHINE"),
                                            QString::fromLatin1(frame));
                });
            connect(m_pressTransport.get(), &MachineTransport::frameWritten,
                this, [this](const QByteArray &frame) {
                    emit pressSerialLogLine(QStringLiteral("SOFTWARE"),
                                            QString::fromLatin1(frame));
                });
            connect(m_moduleTransport.get(), &MachineTransport::frameReceived,
                this, &MachineControlBackend::handleModuleFrame);

            m_pressInitializationTimer.setSingleShot(true);
            m_moduleInitializationTimer.setSingleShot(true);
            m_pressInitializationTimer.setInterval(m_initializationTimeoutMs);
            m_moduleInitializationTimer.setInterval(m_initializationTimeoutMs);
            connect(&m_pressInitializationTimer, &QTimer::timeout, this, [this] {
            failPressInitialization(QStringLiteral("INITIALIZATION_TIMEOUT"));
            });
            connect(&m_moduleInitializationTimer, &QTimer::timeout, this, [this] {
            failModuleInitialization(QStringLiteral("INITIALIZATION_TIMEOUT"));
            });

            m_pressHomingTimer.setSingleShot(true);
            m_moduleHomingTimer.setSingleShot(true);
            m_pressHomingTimer.setInterval(m_homingTimeoutMs);
            m_moduleHomingTimer.setInterval(m_homingTimeoutMs);
            connect(&m_pressHomingTimer, &QTimer::timeout, this, [this] {
                beginPressHomingSafetyFailure(QStringLiteral("HOMING_TIMEOUT"));
            });
            connect(&m_moduleHomingTimer, &QTimer::timeout, this, [this] {
                failModuleHoming(QStringLiteral("HOMING_TIMEOUT"));
            });

            // Firmware HEARTBEAT_TIMEOUT_MS is 30 s and an already-connected
            // <?> is silent. A 25 s period left only ~5 s of GUI-thread stall
            // margin before the MCU heartbeat fault/reset; 5 s leaves ~25 s.
            m_pressKeepAliveTimer.setInterval(5000);
            connect(&m_pressKeepAliveTimer, &QTimer::timeout,
                this, &MachineControlBackend::sendPressKeepAlive);
            m_primingHeartbeatTimer.setInterval(250);
            connect(&m_primingHeartbeatTimer, &QTimer::timeout,
                this, &MachineControlBackend::sendPrimingHeartbeat);
            m_moduleStatusPollTimer.setInterval(200);
            connect(&m_moduleStatusPollTimer, &QTimer::timeout,
                this, &MachineControlBackend::pollModuleStatus);
            m_pressTelemetryFreshnessTimer.setSingleShot(true);
            m_pressTelemetryFreshnessTimer.setInterval(3000);
            connect(&m_pressTelemetryFreshnessTimer, &QTimer::timeout,
                this, &MachineControlBackend::expirePressTelemetry);
            m_moduleTelemetryFreshnessTimer.setSingleShot(true);
            // GRBL status is requested every 200 ms. Allow several missed
            // replies and GUI/CPU scheduling stalls before revoking readiness;
            // the previous 1.2 s window could expire while a dense Run preview
            // was rebuilt during program selection. Homing remains latched
            // across telemetry staleness and is still revoked by transport
            // loss, reset, alarm, or a failed/new homing lifecycle.
            m_moduleTelemetryFreshnessTimer.setInterval(3000);
            connect(&m_moduleTelemetryFreshnessTimer, &QTimer::timeout,
                this, &MachineControlBackend::expireModuleTelemetry);

            m_telemetryLogTimer.setInterval(500);
            connect(&m_telemetryLogTimer, &QTimer::timeout, this, [this] {
                if (m_pressConnected && m_pressTelemetryFresh) {
                    emit telemetryLogLine(
                        QStringLiteral("press"),
                        QStringLiteral("%1 | Y1 %2 in | Y2 %3 in | LOAD %4 / %5 T | V %6 IPM")
                            .arg(m_pressMachineState)
                            .arg(m_ramPositionY1, 0, 'f', 4)
                            .arg(m_ramPositionY2, 0, 'f', 4)
                            .arg(m_ramLoadY1, 0, 'f', 1)
                            .arg(m_ramLoadY2, 0, 'f', 1)
                            .arg(m_ramVelocity, 0, 'f', 1));
                }
                if (m_moduleConnected && m_moduleTelemetryFresh) {
                    QStringList limits;
                    if (m_moduleLimitX1) limits.push_back(QStringLiteral("X1"));
                    if (m_moduleLimitX2) limits.push_back(QStringLiteral("X2"));
                    if (m_moduleLimitR1) limits.push_back(QStringLiteral("R1"));
                    if (m_moduleLimitR2) limits.push_back(QStringLiteral("R2"));
                    emit telemetryLogLine(
                        QStringLiteral("module"),
                        QStringLiteral("%1 | WORK X %2 R %3 in | MACHINE X %4 R %5 in | LIMITS %6")
                            .arg(m_moduleState)
                            .arg(m_moduleWorkX, 0, 'f', 4)
                            .arg(m_moduleWorkR, 0, 'f', 4)
                            .arg(m_moduleMachineX, 0, 'f', 4)
                            .arg(m_moduleMachineR, 0, 'f', 4)
                            .arg(limits.isEmpty() ? QStringLiteral("none")
                                                  : limits.join(QLatin1Char(' '))));
                }
            });
            m_telemetryLogTimer.start();

            m_commandDeadlineTimer.setSingleShot(true);
            m_commandDeadlineTimer.setInterval(120000);
            connect(&m_commandDeadlineTimer, &QTimer::timeout, this, [this] {
                if (!commandOperationActive())
                    return;
                const QString device = m_operationDevice;
                if (device == QStringLiteral("press")) {
                    if (m_pressCommandPhase == PressCommandPhase::ThcV53) {
                        checkThcV53Deadlines();
                        return;
                    }
                    if (m_pressCommandPhase == PressCommandPhase::ThcV51) {
                        checkThcV51Deadlines();
                        return;
                    }
                    if (m_pressCommandPhase == PressCommandPhase::ThcCommissioning) {
                        if (m_thcContactProfileActive
                            && m_thcContactProfileAutomaticLifecycle
                            && m_thcCommissioningState == QStringLiteral("HOLDING")) {
                            // Qualification begins a deliberate 60-second
                            // observation hold. Its expiry advances through
                            // the normal typed release instead of cancelling
                            // an otherwise healthy force-control cycle.
                            if (!m_pressTransport->writeFrame(QByteArrayLiteral("<THC:RELEASE>\n"))) {
                                failActiveCommand(QStringLiteral("THC_RELEASE_WRITE_FAILED"));
                                return;
                            }
                            m_commandDeadlineTimer.setInterval(ThcReleaseHostObserverMs);
                            m_commandDeadlineTimer.start();
                            return;
                        }
                        // THC has firmware-owned motion.  A host observation
                        // timeout must revoke that lease first, then report a
                        // failure only after firmware confirms cancellation.
                        m_pendingThcFailure = QStringLiteral("THC_COMMAND_TIMEOUT");
                        m_pressCommandPhase = PressCommandPhase::ThcAwaitCancel;
                        m_thcCommissioningState = QStringLiteral("CANCELLING");
                        emit pressStateChanged();
                        if (!m_pressTransport->writeFrame(QByteArrayLiteral("<THC:CANCEL>\n"))) {
                            failActiveCommand(QStringLiteral("THC_CANCEL_WRITE_FAILED"));
                            return;
                        }
                        m_commandDeadlineTimer.setInterval(ThcCancelConfirmationMs);
                        m_commandDeadlineTimer.start();
                        return;
                    }
                    if (m_pressCommandPhase == PressCommandPhase::ThcAwaitCancel) {
                        failActiveCommand(m_pendingThcFailure + QStringLiteral("_CANCEL_CONFIRMATION_TIMEOUT"));
                        return;
                    }
                    if (m_pressCommandPhase == PressCommandPhase::AwaitSettingAck
                        || m_pressCommandPhase == PressCommandPhase::StrokeAwaitSetting) {
                        // Never advance on timeout alone: the plane was not
                        // verified, so the operation fails without motion.
                        failActiveCommand(std::isfinite(m_pressRetractEchoMismatch)
                                          ? QStringLiteral("RETRACT_PLANE_NOT_ACCEPTED")
                                          : QStringLiteral("RETRACT_PLANE_ACK_TIMEOUT"));
                        return;
                    }
                    if (m_pressCommandPhase == PressCommandPhase::AwaitHomeFailureStopIdle) {
                        const QString originalError = m_pendingPressHomeFailure.isEmpty()
                            ? QStringLiteral("HOMING_FAILED") : m_pendingPressHomeFailure;
                        m_pressCommandPhase = PressCommandPhase::Idle;
                        m_pressSafetyStopUnconfirmed = true;
                        failPressHoming(originalError
                                        + QStringLiteral("_STOP_CONFIRMATION_TIMEOUT"));
                    } else if (m_pressCommandPhase == PressCommandPhase::AwaitFailureStopIdle) {
                        const QString originalError = m_pendingPressFailure.isEmpty()
                            ? QStringLiteral("COMMAND_TIMEOUT") : m_pendingPressFailure;
                        failActiveCommand(originalError
                                          + QStringLiteral("_STOP_CONFIRMATION_TIMEOUT"));
                    } else if (m_pressCommandPhase == PressCommandPhase::AwaitStopIdle
                               || m_pressCommandPhase
                                   == PressCommandPhase::AwaitHydraulicShutdown
                               || m_pressCommandPhase
                                   == PressCommandPhase::TonnageHoldAwaitStopIdle) {
                        failActiveCommand(QStringLiteral("STOP_CONFIRMATION_TIMEOUT"));
                    } else if (m_pressCommandPhase == PressCommandPhase::AwaitRamToTableStop) {
                        failActiveCommand(QStringLiteral("RAM_TO_TABLE_STOP_TIMEOUT"));
                    } else if (originalManualFirmware()
                               && m_pressCommandPhase == PressCommandPhase::AwaitProgress
                               && !m_pressCommandProgressObserved
                               && m_pressTelemetryFresh
                               && m_pressMachineState == QStringLiteral("IDLE")
                               && (m_pressCommandJogType == QStringLiteral("safety")
                                   || m_pressCommandJogType == QStringLiteral("retract"))) {
                        // A short/no-op legacy jog may finish between status samples.
                        // No correlation proves completion, but STOP would start a new
                        // release-load retract. Lock admission without commanding motion.
                        // Staleness, alarms and observed motion retain fault-stop handling.
                        m_pressSafetyStopUnconfirmed = true;
                        failActiveCommand(QStringLiteral("LEGACY_COMPLETION_UNCONFIRMED"));
                    } else if (pressPhaseRequiresSafetyStop()) {
                        beginPressSafetyFailure(QStringLiteral("COMMAND_TIMEOUT"),
                                                QByteArrayLiteral("<stop>\n"));
                    } else {
                        failActiveCommand(QStringLiteral("COMMAND_TIMEOUT"));
                    }
                } else if (device == QStringLiteral("module")) {
                    failActiveCommand(QStringLiteral("COMMAND_TIMEOUT"));
                    if (m_moduleTransport->isOpen())
                        m_moduleTransport->writeFrame(QByteArrayLiteral("!"));
                }
            });

                    m_tonnageHoldTimer.setSingleShot(true);
                    connect(&m_tonnageHoldTimer, &QTimer::timeout,
                        this, &MachineControlBackend::evaluateLegacyTonnageHold);
                    // TH is not covered by the 5 s press keepalive. The
                    // controller explicitly renews the firmware's short TH
                    // lease only while it owns an armed/active TH operation.
                    m_tonnageHoldHeartbeatTimer.setInterval(1000);
                    connect(&m_tonnageHoldHeartbeatTimer, &QTimer::timeout,
                        this, &MachineControlBackend::sendTonnageHoldHeartbeat);
                    m_thcContactProfileHeartbeatTimer.setInterval(250);
                    connect(&m_thcContactProfileHeartbeatTimer, &QTimer::timeout,
                        this, &MachineControlBackend::sendThcContactProfileHeartbeat);
                    m_thcV51HeartbeatTimer.setInterval(ThcV51HeartbeatMs);
                    m_thcV51HeartbeatTimer.setTimerType(Qt::PreciseTimer);
                    connect(&m_thcV51HeartbeatTimer, &QTimer::timeout,
                            this, &MachineControlBackend::sendThcV51Heartbeat);
                    for (QTimer *timer : {&m_thcV51ClientLeaseTimer,
                                         &m_thcV51PhaseTimer, &m_thcV51OverallTimer}) {
                        timer->setSingleShot(true);
                        timer->setTimerType(Qt::PreciseTimer);
                        connect(timer, &QTimer::timeout, this, [this] {
                            checkThcV51Deadlines();
                        });
                    }
                    m_thcTuningQueryTimer.setSingleShot(true);
                    m_thcLiveRequestTimer.setSingleShot(true);
                    m_thcLiveRequestTimer.setInterval(ThcTuningQueryTimeoutMs);
                    connect(&m_thcLiveRequestTimer, &QTimer::timeout, this, [this] {
                        if (!thcLiveTuningPending()) return;
                        const auto owner = m_operationId;
                        m_thcLiveRecoveryRequired = true;
                        invalidateThcLiveTuning(QStringLiteral("V53_ACK_TIMEOUT"));
                        if (m_operationId == owner && thcContinuousActive())
                            beginThcV53Cancellation(QStringLiteral("THC_V53_TUNING_ACK_TIMEOUT"));
                    });
                    m_thcV53HeartbeatTimer.setInterval(250);
                    m_thcV53HeartbeatTimer.setTimerType(Qt::PreciseTimer);
                    connect(&m_thcV53HeartbeatTimer, &QTimer::timeout, this, &MachineControlBackend::sendThcV53Heartbeat);
                    for (QTimer *timer : {&m_thcV53ClientLeaseTimer, &m_thcV53PhaseTimer}) {
                        timer->setSingleShot(true);
                        timer->setTimerType(Qt::PreciseTimer);
                        connect(timer, &QTimer::timeout, this, [this] { checkThcV53Deadlines(); });
                    }
                    m_thcTuningQueryTimer.setInterval(ThcTuningQueryTimeoutMs);
                    connect(&m_thcTuningQueryTimer, &QTimer::timeout, this, [this] {
                        if (!m_thcTuningQueryPending)
                            return;
                        m_thcTuningQueryPending = false;
                        m_thcTuningQueryRecovery = true;
                        emit thcTuningQueryFinished(false, QString(),
                                                    QStringLiteral("TIMEOUT"));
                        // The firmware reply has no correlation token. Close
                        // and re-handshake before admitting another query so a
                        // late reply cannot satisfy a later request.
                        m_pressTransport->close();
                    });

                    m_pressReconnectTimer.setSingleShot(true);
                    m_moduleReconnectTimer.setSingleShot(true);
                    connect(&m_pressReconnectTimer, &QTimer::timeout,
                        this, &MachineControlBackend::attemptPressReconnect);
                    connect(&m_moduleReconnectTimer, &QTimer::timeout,
                        this, &MachineControlBackend::attemptModuleReconnect);

                    // Connection intent is persistent in production. Discovery
                    // may become ready after QML startup (especially while the
                    // Uno R4 re-enumerates), so request both safe handshakes
                    // without requiring an operator toggle first.
                    m_pressReconnectDesired = true;
                    m_moduleReconnectDesired = true;
                    QTimer::singleShot(0, this, [this] {
                        schedulePressReconnect(true);
                        scheduleModuleReconnect(true);
                    });
}

MachineControlBackend::~MachineControlBackend() = default;

bool MachineControlBackend::queryThcTuning()
{
    const QString operation = QStringLiteral("thc-tuning-query");
    if (thcLiveTuningPending())
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::OperationInProgress);
    if (m_pressConnectionState == ConnectionState::Resetting
        || m_pressConnectionState == ConnectionState::Disconnecting)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::Resetting);
    if (!m_pressConnected)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::NotConnected);
    if (m_pressConnectionState != ConnectionState::Ready || !m_pressReady
        || !m_pressTelemetryFresh || m_pressMachineState == QStringLiteral("UNKNOWN"))
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::NotReady);
    if (m_pressOperationActive || commandOperationActive() || m_primingModeEnabled
        || m_primingLatchY1 || m_primingLatchY2 || m_thcTuningQueryPending
        || m_thcTuningQueryRecovery)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::OperationInProgress);
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<THC:TUNE?>\n")))
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::TransportUnavailable);
    m_thcTuningQueryPending = true;
    m_thcTuningQueryTimer.start();
    return true;
}

void MachineControlBackend::cancelThcTuningQuery()
{
    if (!m_thcTuningQueryPending)
        return;
    m_thcTuningQueryPending = false;
    m_thcTuningQueryRecovery = true;
    m_thcTuningQueryTimer.stop();
    m_pressTransport->close();
}

bool MachineControlBackend::rejectThcLiveRequest(const QString &error)
{
    m_thcLiveTuningError = error;
    emit thcLiveTuningChanged();
    return false; // Never overwrite the motion owner's command lifecycle.
}

void MachineControlBackend::invalidateThcLiveTuning(const QString &error, bool clearConfirmed, bool notify)
{
    const bool hadFineData = !m_thcFineLoad.isEmpty();
    invalidateThcFineLoad(false);
    // Clearing desired/cache values is not retirement of the tokenless reply
    // stream. Even an idle query can leave an indistinguishable late ACK.
    if (thcLiveTuningPending()) m_thcLiveRecoveryRequired = true;
    ++m_thcLiveRequestId;
    m_thcLiveRequestTimer.stop();
    m_thcLiveRequestClock.invalidate();
    m_thcLiveCapabilityClock.invalidate();
    m_thcLiveRequest = ThcLiveRequest::None;
    m_thcLiveExpected.clear();
    m_thcLiveExpectedVersion = 0;
    m_thcLiveTuningVersion = 0;
    m_thcLiveTuningSupported = false;
    m_thcLiveTuningError = error;
    if (clearConfirmed) m_thcLiveTuning.clear();
    m_thcLiveDiagnostics.clear();
    if (notify) {
        emit thcLiveTuningChanged();
        emit thcLiveDiagnosticsChanged();
        if (hadFineData) emit thcFineLoadChanged();
    }
}

bool MachineControlBackend::admitThcLiveRequest(bool mutation)
{
    if (thcLiveTuningPending() || m_thcTuningQueryPending || m_thcTuningQueryRecovery)
        return rejectThcLiveRequest(QStringLiteral("V53_REQUEST_BUSY"));
    if (m_thcLiveRecoveryRequired) {
        // A tokenless query cannot distinguish a late mutation ACK. Recovery
        // is an explicit new query after safe cancellation and re-handshake.
        if (!thcContinuousActive() && !commandOperationActive() && !m_pressOperationActive)
            m_pressTransport->close();
        return rejectThcLiveRequest(QStringLiteral("V53_RECONNECT_QUERY_REQUIRED"));
    }
    if (!m_pressConnected || !m_pressTransport->isOpen()
        || m_pressConnectionState != ConnectionState::Ready || !m_pressReady
        || !m_pressTelemetryFresh || m_pressHomePending || m_pressSafetyStopUnconfirmed
        || m_programRunActive || m_primingModeEnabled || m_primingLatchY1 || m_primingLatchY2
        || m_antiBind || m_physicalPedal || m_bendPedal)
        return rejectThcLiveRequest(QStringLiteral("V53_NOT_READY"));
    if (thcContinuousActive()) {
        if (!checkThcV53Deadlines() || !thcContinuousActive()
            || (mutation && m_thcV53Phase != ThcV53Phase::Holding))
            return rejectThcLiveRequest(QStringLiteral("V53_NOT_HOLDING"));
    } else if (commandOperationActive() || m_pressOperationActive
               || m_pressMachineState != QStringLiteral("IDLE") || (mutation && !m_pressHomed)) {
        return rejectThcLiveRequest(QStringLiteral("V53_OWNER_BUSY"));
    }
    if (mutation && (!m_thcLiveTuningSupported || !m_physicalPedalAvailable))
        return rejectThcLiveRequest(QStringLiteral("V53_QUERY_REQUIRED"));
    return true;
}

bool MachineControlBackend::queryThcLiveTuning()
{
    if (!admitThcLiveRequest(false)) return false;
    const auto owner = m_operationId;
    const auto request = ++m_thcLiveRequestId;
    m_thcLiveTuningSupported = false;
    m_thcLiveTuningVersion = 0;
    m_thcLiveExpectedVersion = 0;
    m_thcLiveExpected.clear();
    m_thcLiveCapabilityClock.invalidate();
    m_thcLiveTuningError.clear();
    m_thcLiveRequest = ThcLiveRequest::Query;
    m_thcLiveRequestArrival = m_pressFrameArrival;
    m_thcLiveRequestClock.start();
    m_thcLiveRequestTimer.start();
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<THC:V53?>\n"))) {
        if (m_thcLiveRequestId != request || m_operationId != owner) return false;
        m_thcLiveRecoveryRequired = true;
        invalidateThcLiveTuning(QStringLiteral("V53_QUERY_WRITE_FAILED"));
        if (m_operationId == owner && thcContinuousActive())
            beginThcV53Cancellation(QStringLiteral("THC_V53_QUERY_WRITE_FAILED"));
        return false;
    }
    emit thcLiveTuningChanged();
    return m_thcLiveRequestId == request && (thcLiveTuningPending() || m_thcLiveTuningSupported);
}

bool MachineControlBackend::applyThcLiveTuning(const QVariantMap &settings)
{
    if (!admitThcLiveRequest(true)) return false;
    const int version = m_thcLiveTuningVersion;
    if (settings.size() != 6 || !validV53Values(settings, version))
        return rejectThcLiveRequest(QStringLiteral("V53_ARGUMENT"));
    const auto revision = m_thcLiveTuning.value(QStringLiteral("revision")).toULongLong();
    if (revision >= 4294967295ULL) return rejectThcLiveRequest(QStringLiteral("V53_REVISION_EXHAUSTED"));
    QVariantMap canonical;
    QByteArray frame = "<THC:V53:TUNE:" + QByteArray::number(revision + 1);
    for (const QString &key : ThcV53Keys) {
        const double n = settings.value(key).toDouble();
        const QByteArray value = QByteArray::number(version == 2 && n == 0.0 ? 0.0 : n, 'f', 6);
        if (version == 2 && !canonicalV53ExtendedNumber(QString::fromLatin1(value)))
            return rejectThcLiveRequest(QStringLiteral("V53_ARGUMENT_PRECISION"));
        frame += ',' + value;
        canonical.insert(key, value.toDouble());
    }
    if (!validV53Values(canonical, version)) return rejectThcLiveRequest(QStringLiteral("V53_ARGUMENT_PRECISION"));
    canonical.insert(QStringLiteral("revision"), QVariant::fromValue(revision + 1));
    frame += ">\n";
    if (frame.size() - 3 > 128) return rejectThcLiveRequest(QStringLiteral("V53_ARGUMENT_PRECISION"));
    const auto owner = m_operationId;
    const auto request = ++m_thcLiveRequestId;
    m_thcLiveExpected = canonical;
    m_thcLiveExpectedVersion = version; // Set before any reentrant transport callback.
    m_thcLiveTuningError.clear();
    m_thcLiveRequest = ThcLiveRequest::Tune;
    m_thcLiveRequestArrival = m_pressFrameArrival;
    m_thcLiveRequestClock.start();
    m_thcLiveRequestTimer.start();
    // No beginCommandOperation(), motion reset, retry or heartbeat renewal.
    if (!m_pressTransport->writeFrame(frame)) {
        if (m_thcLiveRequestId != request || m_operationId != owner) return false;
        m_thcLiveRecoveryRequired = true;
        invalidateThcLiveTuning(QStringLiteral("V53_TUNE_WRITE_FAILED"));
        if (m_operationId == owner && thcContinuousActive())
            beginThcV53Cancellation(QStringLiteral("THC_V53_TUNE_WRITE_FAILED"));
        return false;
    }
    emit thcLiveTuningChanged();
    return m_thcLiveRequestId == request
        && (thcLiveTuningPending() || (m_thcLiveTuningSupported && m_thcLiveTuning == canonical));
}

bool MachineControlBackend::thcFineOwnerActive() const
{
    // Observation only; deliberately do not call the command deadline checker.
    return m_operationDevice == QStringLiteral("press")
        && m_operationName == QStringLiteral("thc-contact-profile-v53")
        && commandOperationActive() && m_pressCommandPhase == PressCommandPhase::ThcV53
        && m_thcV53RunningAcknowledged && m_pressConnected && m_pressTransport->isOpen()
        && m_pressTelemetryFresh
        && (m_thcV53Phase == ThcV53Phase::Approach || m_thcV53Phase == ThcV53Phase::Acquisition
            || m_thcV53Phase == ThcV53Phase::Holding)
        && m_thcV53Clock.isValid() && m_thcV53Clock.elapsed() < m_thcV53ClientDeadlineMs
        && (m_thcV53PhaseDeadlineMs < 0 || m_thcV53Clock.elapsed() < m_thcV53PhaseDeadlineMs);
}

QVariantMap MachineControlBackend::thcFineLoad() const
{
    if (m_thcFineLoad.isEmpty() || !thcFineOwnerActive() || m_thcFineOwner != m_operationId
        || m_thcFineHostClock.elapsed() - m_thcFineLoad.value("receivedMs").toLongLong() >= ThcFineFreshMs)
        return {};
    return m_thcFineLoad;
}

void MachineControlBackend::invalidateThcFineLoad(bool notify)
{
    const bool hadData = !m_thcFineLoad.isEmpty();
    m_thcFineExpiryTimer.stop();
    m_thcFineLoad.clear();
    m_thcFineAnchorValid = false;
    m_thcFineArrivalFloor = m_pressFrameArrival;
    ++m_thcFineGeneration;
    if (hadData && notify) emit thcFineLoadChanged();
}

void MachineControlBackend::observeThcFineLoad(const QVariantMap &values, qulonglong arrival)
{
    observeThcFineLoadAt(values, arrival, m_thcFineHostClock.elapsed());
}

void MachineControlBackend::observeThcFineLoadAt(const QVariantMap &values, qulonglong arrival, qint64 hostMs)
{
    if (!thcFineOwnerActive() || arrival != m_pressFrameArrival || arrival <= m_thcFineArrivalFloor
        || !values.contains("seq") || !values.value("finePrecision").toBool()
        || values.value("age").toUInt() > ThcFineSampleAgeMs) return;
    // Firmware phase 1 includes BOTH approach and post-contact acquisition.
    const int expectedPhase = m_thcV53Phase == ThcV53Phase::Holding ? 2 : 1;
    if (values.value("ph").toInt() != expectedPhase) return;
    const quint32 ms = values.value("ms").toUInt();
    const quint32 seq = values.value("seq").toUInt();
    const quint32 sampleMs = ms - values.value("age").toUInt();
    if (m_thcFineOwner != m_operationId) invalidateThcFineLoad(false);
    if (m_thcFineAnchorValid && hostMs - m_thcFineLastHostMs >= ThcFineFreshMs) {
        invalidateThcFineLoad();
        return; // No event-loop dispatch is needed to detect an expired anchor.
    }
    if (!m_thcFineAnchorValid) {
        // A tokenless publication cannot certify owner or queue latency. The
        // first row establishes a local time fence and is NOT a plotted sample.
        m_thcFineOwner = m_operationId;
        m_thcFineAnchorHostMs = hostMs;
        m_thcFineLastHostMs = hostMs;
        m_thcFineAnchorMcuMs = ms;
        m_thcFineLastMcuMs = ms;
        m_thcFineLastMcuSequence = seq;
        m_thcFineLastSampleMs = sampleMs;
        m_thcFineAnchorValid = true;
        m_thcFineExpiryTimer.start(ThcFineFreshMs);
        return;
    }
    const quint32 dt = ms - m_thcFineLastMcuMs;
    const quint32 ds = seq - m_thcFineLastMcuSequence;
    const quint32 sampleDt = sampleMs - m_thcFineLastSampleMs;
    // Unsigned forward differences admit natural uint32 rollover, not repeats,
    // backwards/replayed rows or multiple reports of the same ADC sample.
    if (!dt || dt >= 0x80000000U || !ds || ds >= 0x80000000U
        || !sampleDt || sampleDt >= 0x80000000U) return;
    const qint64 hostDt = hostMs - m_thcFineAnchorHostMs;
    const quint32 mcuDt = ms - m_thcFineAnchorMcuMs;
    if (mcuDt >= 0x80000000U || std::abs(qint64(mcuDt) - hostDt) > ThcFineClockToleranceMs) {
        invalidateThcFineLoad();
        return; // Clock discontinuity/backlog: re-anchor, never restamp it.
    }
    m_thcFineLastMcuMs = ms;
    m_thcFineLastMcuSequence = seq;
    m_thcFineLastSampleMs = sampleMs;
    m_thcFineLastHostMs = hostMs;
    // Warm-up also expires. Repeated/stale ADC publications never renew it.
    if (m_thcFineLoad.isEmpty()) m_thcFineExpiryTimer.start(ThcFineFreshMs);
    // Drain uncertainty after each owner/timeout boundary before publishing.
    if (hostDt < ThcFineFreshMs) return;
    if (!m_thcFineLoad.isEmpty()
        && hostMs - m_thcFineLoad.value("receivedMs").toLongLong() >= ThcFineFreshMs) {
        invalidateThcFineLoad();
        return;
    }
    const bool breakBefore = m_thcFineLoad.isEmpty() || dt > ThcFineSampleAgeMs
        || sampleDt > ThcFineSampleAgeMs;
    m_thcFineLoad = {{QStringLiteral("source"), QStringLiteral("TH_CTRL_FILTERED_PRE_DEADZONE")},
        {QStringLiteral("ownerId"), QString::number(m_operationId)},
        {QStringLiteral("generation"), QString::number(m_thcFineGeneration)},
        {QStringLiteral("sequence"), QVariant::fromValue(++m_thcFineSequence)},
        {QStringLiteral("arrival"), QVariant::fromValue(arrival)},
        {QStringLiteral("mcuSequence"), seq}, {QStringLiteral("mcuMs"), ms},
        {QStringLiteral("sampleMs"), sampleMs}, {QStringLiteral("sampleAgeMs"), values.value("age")},
        {QStringLiteral("receivedMs"), hostMs}, {QStringLiteral("breakBefore"), breakBefore},
        {QStringLiteral("f1"), values.value("f1")}, {QStringLiteral("f2"), values.value("f2")}};
    m_thcFineExpiryTimer.start(ThcFineFreshMs);
    emit thcFineLoadChanged();
}

bool MachineControlBackend::handleThcLiveFrame(const QByteArray &frame, qulonglong arrival)
{
    const QByteArray classified = frame.trimmed().toUpper();
    if (classified.startsWith("[TH_CTRL ") || classified.startsWith("[TH_V53 ")) {
        if (thcContinuousActive() && m_thcV53RunningAcknowledged
            && m_thcV53Phase != ThcV53Phase::AwaitCancel && m_pressTelemetryFresh) {
            const auto values = parseV53Diagnostics(frame, m_thcLiveTuningVersion);
            if (!values.isEmpty()) {
                const auto owner = m_operationId;
                if (frame.startsWith("[TH_CTRL ")) observeThcFineLoad(values, arrival);
                if (owner != m_operationId || arrival != m_pressFrameArrival
                    || !thcContinuousActive() || !m_thcV53RunningAcknowledged) return true;
                if (frame.startsWith("[TH_V53 ")) m_thcLiveDiagnostics.insert(QStringLiteral("effective"), values);
                else {
                    const QVariant effective = m_thcLiveDiagnostics.value(QStringLiteral("effective"));
                    m_thcLiveDiagnostics = values;
                    if (effective.isValid()) m_thcLiveDiagnostics.insert(QStringLiteral("effective"), effective);
                }
                emit thcLiveDiagnosticsChanged();
            }
        }
        return true;
    }
    if (!classified.startsWith("{THC:V53:")) return false;
    if (!thcLiveTuningPending() || m_thcLiveRecoveryRequired) return true;
    const auto owner = m_operationId;
    const auto request = m_thcLiveRequestId;
    if (thcContinuousActive() && !checkThcV53Deadlines()) return true;
    if (m_operationId != owner || m_thcLiveRequestId != request
        || !thcLiveTuningPending() || arrival != m_pressFrameArrival) return true;
    QString error;
    int version = 0;
    const auto values = parseV53Reply(frame, &version);
    if (!m_thcLiveRequestClock.isValid() || m_thcLiveRequestClock.elapsed() >= ThcTuningQueryTimeoutMs
        || arrival <= m_thcLiveRequestArrival) error = QStringLiteral("V53_ACK_TIMEOUT");
    else if (values.isEmpty()) error = QStringLiteral("V53_INVALID_REPLY:") + QString::fromLatin1(frame);
    else if (m_thcLiveRequest == ThcLiveRequest::Tune
             && (version != m_thcLiveExpectedVersion || values != m_thcLiveExpected))
        error = QStringLiteral("V53_ACK_MISMATCH");
    if (!error.isEmpty()) {
        m_thcLiveRecoveryRequired = true;
        invalidateThcLiveTuning(error);
        if (m_operationId == owner && thcContinuousActive())
            beginThcV53Cancellation(QStringLiteral("THC_V53_TUNING_FAILURE:") + error);
        return true;
    }
    m_thcLiveTuning = values;
    m_thcLiveTuningVersion = version;
    m_thcLiveExpected.clear();
    m_thcLiveExpectedVersion = 0;
    m_thcLiveRequest = ThcLiveRequest::None;
    m_thcLiveRequestTimer.stop();
    m_thcLiveRequestClock.invalidate();
    m_thcLiveCapabilityClock.start();
    m_thcLiveTuningSupported = true;
    m_thcLiveTuningError.clear();
    emit thcLiveTuningChanged();
    return true;
}

bool MachineControlBackend::startContinuousThcContactProfile()
{
    const QString operation = QStringLiteral("thc-contact-profile-v53");
    const double approachSpeed = m_thcApproachSpeed;
    if (approachSpeed != 0.0 && (!std::isfinite(approachSpeed) || approachSpeed < 0.5 || approachSpeed > 15.0))
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::InvalidArgument);
    if (!m_thcLiveTuningSupported || thcLiveTuningPending()
        || !m_thcLiveCapabilityClock.isValid() || m_thcLiveCapabilityClock.elapsed() >= ThcV53CapabilityFreshMs)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::CommandDisabled);
    if (!admitPressMotion(operation)) return false;
    if (!m_physicalPedalAvailable || m_programRunActive || m_primingModeEnabled || m_primingLatchY1 || m_primingLatchY2
        || m_antiBind || m_physicalPedal || m_bendPedal || m_thcTuningQueryRecovery)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    resetThcV53Operation();
    const auto owner = ++m_operationId;
    m_operationDevice = QStringLiteral("press");
    m_operationName = operation;
    m_operationState = QStringLiteral("SENT");
    m_operationError.clear();
    m_commandDeadlineTimer.stop();
    m_pressCommandPhase = PressCommandPhase::ThcV53;
    m_pressOperationActive = true;
    m_thcContactProfileContactObserved = false;
    m_thcV53Phase = ThcV53Phase::AwaitStart;
    m_thcCommissioningState = QStringLiteral("CONTACT_PROFILE_V53_ARMING");
    m_thcV53Clock.start();
    m_thcV53ClientDeadlineMs = 2000;
    m_thcV53ClientLeaseTimer.start(2000);
    setThcV53PhaseDeadline(ThcTuningQueryTimeoutMs);
    emit commandLifecycleChanged();
    if (m_operationId != owner || m_thcV53Phase != ThcV53Phase::AwaitStart) return false;
    emit thcContinuousActiveChanged();
    emit pressStateChanged();
    if (m_operationId != owner || m_thcV53Phase != ThcV53Phase::AwaitStart || !checkThcV53Deadlines()) return false;
    const QByteArray startFrame = approachSpeed > 0.0
        ? QStringLiteral("<THC:CONTACT_PROFILE_V53:%1>\n").arg(approachSpeed, 0, 'f', 3).toLatin1()
        : QByteArrayLiteral("<THC:CONTACT_PROFILE_V53>\n");
    if (!m_pressTransport->writeFrame(startFrame)) {
        if (m_operationId == owner && thcContinuousActive()) beginThcV53Cancellation(QStringLiteral("THC_V53_START_WRITE_FAILED"));
        return false;
    }
    if (m_operationId != owner || !thcContinuousActive() || m_thcV53Phase == ThcV53Phase::AwaitCancel) return false;
    m_thcV53HeartbeatTimer.start();
    return true;
}

void MachineControlBackend::stopThcV53Timers()
{
    m_thcV53HeartbeatTimer.stop();
    m_thcV53ClientLeaseTimer.stop();
    m_thcV53PhaseTimer.stop();
}

void MachineControlBackend::resetThcV53Operation()
{
    invalidateThcFineLoad(false);
    stopThcV53Timers();
    m_thcV53Phase = ThcV53Phase::Inactive;
    m_thcV53RunningAcknowledged = false;
    m_thcV53CancelAcknowledged = false;
    m_thcV53Failure.clear();
    m_thcV53TerminalTelemetrySequence = 0;
    m_thcV53TerminalArrival = 0;
    m_thcV53Clock.invalidate();
    m_thcV53PhaseDeadlineMs = -1;
    m_thcV53ClientDeadlineMs = -1;
    m_thcV53ReleaseDeadlineMs = -1;
}

void MachineControlBackend::setThcV53PhaseDeadline(qint64 deadlineMs)
{
    m_thcV53PhaseDeadlineMs = deadlineMs;
    if (deadlineMs < 0) m_thcV53PhaseTimer.stop();
    else m_thcV53PhaseTimer.start(int(qMax(qint64(1), deadlineMs - m_thcV53Clock.elapsed())));
}

bool MachineControlBackend::checkThcV53Deadlines()
{
    if (!thcContinuousActive() || m_pressCommandPhase != PressCommandPhase::ThcV53
        || !commandOperationActive() || !m_thcV53Clock.isValid()) return false;
    const auto now = m_thcV53Clock.elapsed();
    if (m_thcV53Phase == ThcV53Phase::AwaitCancel) {
        if (now >= m_thcV53PhaseDeadlineMs)
            failActiveCommand(m_thcV53Failure + QStringLiteral("_CANCEL_CONFIRMATION_TIMEOUT"));
        return false;
    }
    QString error;
    if (!m_pressConnected || !m_pressTransport->isOpen()) error = QStringLiteral("THC_V53_TRANSPORT_CLOSED");
    else if (!m_pressTelemetryFresh) error = QStringLiteral("THC_V53_TELEMETRY_STALE");
    else if (m_antiBind || m_physicalPedal || m_bendPedal || !m_physicalPedalAvailable
             || m_primingModeEnabled || m_primingLatchY1 || m_primingLatchY2 || !m_pressHomed)
        error = QStringLiteral("THC_V53_CONTROLLER_GUARD");
    else if (m_thcV53Phase != ThcV53Phase::AwaitIdle && now >= m_thcV53ClientDeadlineMs)
        error = QStringLiteral("THC_V53_CLIENT_LEASE_EXPIRED");
    else if (m_thcV53PhaseDeadlineMs >= 0 && now >= m_thcV53PhaseDeadlineMs)
        error = QStringLiteral("THC_V53_PHASE_TIMEOUT");
    if (error.isEmpty()) return true;
    beginThcV53Cancellation(error);
    return false;
}

void MachineControlBackend::sendThcV53Heartbeat()
{
    const auto owner = m_operationId;
    if (!checkThcV53Deadlines() || m_thcV53Phase == ThcV53Phase::AwaitIdle) return;
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<THC:HB>\n"))) {
        if (m_operationId == owner && thcContinuousActive()) beginThcV53Cancellation(QStringLiteral("THC_V53_HEARTBEAT_WRITE_FAILED"));
        return;
    }
    if (m_operationId != owner || !thcContinuousActive()
        || m_thcV53Phase == ThcV53Phase::AwaitCancel || m_thcV53Phase == ThcV53Phase::AwaitIdle) return;
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<?>\n")))
        if (m_operationId == owner && thcContinuousActive()) beginThcV53Cancellation(QStringLiteral("THC_V53_KEEP_ALIVE_WRITE_FAILED"));
}

bool MachineControlBackend::beginThcV53Cancellation(const QString &error)
{
    if (!thcContinuousActive()) return false;
    if (m_thcV53Phase == ThcV53Phase::AwaitCancel) {
        checkThcV53Deadlines();
        return m_thcV53Phase == ThcV53Phase::AwaitCancel;
    }
    const auto owner = m_operationId;
    stopThcV53Timers();
    m_thcV53Phase = ThcV53Phase::AwaitCancel;
    m_thcV53Failure = error;
    m_thcV53RunningAcknowledged = false;
    m_thcV53CancelAcknowledged = false;
    m_thcCommissioningState = QStringLiteral("CANCELLING");
    m_pressSafetyStopUnconfirmed = true;
    setThcV53PhaseDeadline(m_thcV53Clock.elapsed() + ThcTuningQueryTimeoutMs);
    // Finalize state without callbacks, then publish the latch before tuning
    // subscribers can synchronously deliver cancellation proof or replace it.
    invalidateThcLiveTuning(m_thcLiveTuningError.isEmpty() ? QStringLiteral("V53_CANCELLED") : m_thcLiveTuningError,
                            false, false);
    emit pressStateChanged();
    emit thcLiveTuningChanged();
    emit thcLiveDiagnosticsChanged();
    if (m_operationId != owner || m_thcV53Phase != ThcV53Phase::AwaitCancel) return false;
    if (!m_pressConnected || !m_pressTransport->isOpen()
        || !m_pressTransport->writeFrame(QByteArrayLiteral("<THC:CANCEL>\n"))) {
        if (m_operationId == owner && m_thcV53Phase == ThcV53Phase::AwaitCancel)
            failActiveCommand(error + QStringLiteral("_CANCEL_WRITE_FAILED"));
        return false;
    }
    return m_operationId == owner && (m_thcV53Phase == ThcV53Phase::AwaitCancel
        || (!thcContinuousActive() && !m_pressSafetyStopUnconfirmed && m_operationState == QStringLiteral("FAILED")));
}

bool MachineControlBackend::releaseThcV53()
{
    if (!checkThcV53Deadlines() || !m_thcV53RunningAcknowledged
        || (m_thcV53Phase != ThcV53Phase::Acquisition && m_thcV53Phase != ThcV53Phase::Holding)) return false;
    const auto owner = m_operationId;
    m_thcV53Phase = ThcV53Phase::AwaitRelease;
    m_thcCommissioningState = QStringLiteral("RELEASE_PENDING");
    m_thcV53ReleaseDeadlineMs = m_thcV53Clock.elapsed() + ThcV53ReleaseMs;
    setThcV53PhaseDeadline(m_thcV53Clock.elapsed() + ThcTuningQueryTimeoutMs);
    invalidateThcLiveTuning(QStringLiteral("V53_RELEASE_PENDING"));
    emit pressStateChanged();
    if (m_operationId != owner || m_thcV53Phase != ThcV53Phase::AwaitRelease) return false;
    if (!checkThcV53Deadlines() || m_operationId != owner
        || m_thcV53Phase != ThcV53Phase::AwaitRelease) return false;
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<THC:RELEASE>\n"))) {
        if (m_operationId == owner && thcContinuousActive()) beginThcV53Cancellation(QStringLiteral("THC_V53_RELEASE_WRITE_FAILED"));
        return false;
    }
    return m_operationId == owner && m_thcV53Phase != ThcV53Phase::AwaitCancel
        && (thcContinuousActive() || m_operationState == QStringLiteral("COMPLETED"));
}

bool MachineControlBackend::handleThcV53Frame(const QByteArray &frame, qulonglong arrival)
{
    const QByteArray classified = frame.trimmed().toUpper();
    if (!thcContinuousActive()) return classified.contains("CONTACT_PROFILE_V53");
    const auto owner = m_operationId;
    checkThcV53Deadlines();
    if (m_operationId != owner || arrival != m_pressFrameArrival || !thcContinuousActive()) return true;
    if (!classified.startsWith("{THC:") && !classified.startsWith("{TH:")) return false;
    if (m_thcV53Phase == ThcV53Phase::AwaitCancel) {
        if (frame == QByteArrayLiteral("{THC:CANCELLED}") && !m_thcV53CancelAcknowledged) {
            m_thcV53CancelAcknowledged = true;
            m_thcV53TerminalArrival = arrival;
            m_thcV53TerminalTelemetrySequence = m_pressTelemetrySequence;
        }
        return true; // NOT_ACTIVE / IDLE alone cannot prove cancellation.
    }
    if (classified.startsWith("{THC:ERROR") || classified.startsWith("{TH:ERROR") || classified == "{TH:TIMEOUT}") {
        beginThcV53Cancellation(QStringLiteral("THC_V53_FIRMWARE_ERROR:") + QString::fromLatin1(classified));
        return true;
    }
    if (frame == QByteArrayLiteral("{THC:HB}")) return true;
    const auto now = m_thcV53Clock.elapsed();
    bool accepted = true;
    if (frame == QByteArrayLiteral("{THC:CONTACT_PROFILE_V53_RUNNING}")) {
        if (m_thcV53Phase == ThcV53Phase::AwaitStart) {
            m_thcV53RunningAcknowledged = true;
            m_thcV53Phase = ThcV53Phase::Approach;
            m_thcCommissioningState = QStringLiteral("CONTACT_PROFILE_V53_RUNNING");
            setThcV53PhaseDeadline(ThcV53ApproachMs); // from admission, never ACK
            acknowledgeCommandOperation();
        } else accepted = m_thcV53RunningAcknowledged;
    } else if (frame == QByteArrayLiteral("{THC:CONTACT}")) {
        if (m_thcV53Phase == ThcV53Phase::Approach) {
            m_thcContactProfileContactObserved = true;
            m_thcV53Phase = ThcV53Phase::Acquisition;
            m_thcCommissioningState = QStringLiteral("CONTACT");
            setThcV53PhaseDeadline(now + ThcV53AcquisitionMs);
        } else accepted = m_thcContactProfileContactObserved;
    } else if (frame == QByteArrayLiteral("{THC:HOLDING}")) {
        if (m_thcV53Phase == ThcV53Phase::Acquisition) {
            m_thcV53Phase = ThcV53Phase::Holding;
            m_thcCommissioningState = QStringLiteral("HOLDING");
            setThcV53PhaseDeadline(-1); // ONLY the NORMAL observation bound is removed.
        } else accepted = m_thcV53Phase == ThcV53Phase::Holding;
    } else if (frame == QByteArrayLiteral("{THC:RELEASING}")) {
        if (m_thcV53Phase == ThcV53Phase::AwaitRelease) {
            m_thcV53Phase = ThcV53Phase::Releasing;
            m_thcCommissioningState = QStringLiteral("RELEASING");
            setThcV53PhaseDeadline(m_thcV53ReleaseDeadlineMs);
        } else accepted = m_thcV53Phase == ThcV53Phase::Releasing;
    } else if (frame == QByteArrayLiteral("{THC:DONE}")) {
        if (m_thcV53Phase == ThcV53Phase::Releasing) {
            m_thcV53Phase = ThcV53Phase::AwaitIdle;
            m_thcV53TerminalArrival = arrival;
            m_thcV53TerminalTelemetrySequence = m_pressTelemetrySequence;
            m_thcCommissioningState = QStringLiteral("DONE");
            m_thcV53HeartbeatTimer.stop();
            m_thcV53ClientLeaseTimer.stop();
            setThcV53PhaseDeadline(qMin(m_thcV53ReleaseDeadlineMs, now + ThcTuningQueryTimeoutMs));
        } else accepted = m_thcV53Phase == ThcV53Phase::AwaitIdle;
    } else accepted = false;
    if (!accepted && m_operationId == owner && thcContinuousActive())
        beginThcV53Cancellation(QStringLiteral("THC_V53_UNEXPECTED_ACK"));
    emit pressStateChanged();
    return true;
}

void MachineControlBackend::handleThcV53Telemetry(bool exactIdleTelemetry, qulonglong arrival)
{
    const auto owner = m_operationId;
    checkThcV53Deadlines();
    if (m_operationId != owner || !thcContinuousActive()) return;
    const bool terminalIdle = exactIdleTelemetry && m_pressTelemetryFresh && m_pressConnected
        && m_pressTransport->isOpen() && !m_antiBind && m_pressMachineState == QStringLiteral("IDLE")
        && arrival > m_thcV53TerminalArrival && arrival == m_pressFrameArrival
        && m_pressTelemetrySequence > m_thcV53TerminalTelemetrySequence;
    if (m_thcV53Phase == ThcV53Phase::AwaitCancel) {
        if (m_thcV53CancelAcknowledged && terminalIdle) {
            const QString reason = m_thcV53Failure;
            resetThcV53Operation();
            m_pressSafetyStopUnconfirmed = false;
            emit pressStateChanged();
            failActiveCommand(reason);
            emit thcContinuousActiveChanged();
        }
        return;
    }
    if (m_antiBind || m_physicalPedal || m_bendPedal || m_primingModeEnabled
        || m_primingLatchY1 || m_primingLatchY2 || !m_pressHomed || !m_physicalPedalAvailable
        || MachineProtocolParsers::pressStateIsAlarm(m_pressMachineState)) {
        beginThcV53Cancellation(QStringLiteral("THC_V53_CONTROLLER_GUARD"));
        return;
    }
    if (m_thcV53Phase == ThcV53Phase::AwaitIdle && m_thcV53RunningAcknowledged && terminalIdle) {
        resetThcV53Operation();
        completeActivePressCommand();
        emit thcContinuousActiveChanged();
    }
}

void MachineControlBackend::setSerialDiagnosticLogsEnabled(bool enabled)
{
    if (m_pressTransport)
        m_pressTransport->setDiagnosticLoggingEnabled(enabled);
    if (m_moduleTransport)
        m_moduleTransport->setDiagnosticLoggingEnabled(enabled);
    if (m_serialDiagnosticLogsEnabled == enabled)
        return;
    m_serialDiagnosticLogsEnabled = enabled;
    qInfo().noquote() << "SERIAL-DIAGNOSTICS enabled="
                      << (enabled ? QStringLiteral("true") : QStringLiteral("false"));
    emit serialDiagnosticLogsEnabledChanged();
}

bool MachineControlBackend::transportAvailable() const
{
    return pressTransportAvailable() || moduleTransportAvailable();
}

QString MachineControlBackend::pressTelemetryLogPath() const
{
    return m_pressTelemetryRecorder ? m_pressTelemetryRecorder->logPath() : QString();
}

bool MachineControlBackend::pressTransportAvailable() const
{
    return m_pressTransport && m_pressTransport->isAvailable();
}

bool MachineControlBackend::moduleTransportAvailable() const
{
    return m_moduleTransport && m_moduleTransport->isAvailable();
}

QString MachineControlBackend::pressEndpointName() const
{
    return m_pressTransport ? m_pressTransport->endpointDisplayName() : QString();
}

QString MachineControlBackend::moduleEndpointName() const
{
    return m_moduleTransport ? m_moduleTransport->endpointDisplayName() : QString();
}

QString MachineControlBackend::pressConnectionState() const
{
    return connectionStateName(m_pressConnectionState);
}

QString MachineControlBackend::moduleConnectionState() const
{
    return connectionStateName(m_moduleConnectionState);
}

bool MachineControlBackend::nativeTonnageHoldSupported() const
{
    static const QRegularExpression versionPattern(
        QStringLiteral("(?:^|[^0-9])1\\.(\\d+)(?:[^0-9]|$)"),
        QRegularExpression::CaseInsensitiveOption);
    if (!m_pressFirmwareIdentity.contains(QStringLiteral("BEND"), Qt::CaseInsensitive))
        return false;
    const QRegularExpressionMatch match = versionPattern.match(m_pressFirmwareVersion);
    // Current v1.3 owns pedal processing and target regulation in firmware.
    // Earlier stock/custom parsers do not understand the three-speed TH frame.
    return match.hasMatch() && match.captured(1).toInt() == 3;
}

bool MachineControlBackend::thcCommissioningSupported() const
{
    // THC was introduced with the custom v1.3 protocol and is intentionally
    // absent from the production TH compatibility path.
    return nativeTonnageHoldSupported();
}

bool MachineControlBackend::originalManualFirmware() const
{
    return m_pressFirmwareIdentity == QStringLiteral("[LS-BEND v1.1]")
        && m_pressFirmwareVersion == QStringLiteral("1.1");
}

bool MachineControlBackend::pressMotionFirmwareSupported(const QString &operation) const
{
    const bool custom = (m_pressFirmwareVersion == QStringLiteral("1.2")
                         || m_pressFirmwareVersion == QStringLiteral("1.3"))
        && (m_pressFirmwareIdentity == QStringLiteral("[BENDCNC v%1]").arg(m_pressFirmwareVersion)
            || m_pressFirmwareIdentity == QStringLiteral("[LS-BEND v%1]").arg(m_pressFirmwareVersion));
    if (custom)
        return true;
    // Original supports only single supervised jogs here. Chained stroke/hold
    // operations cannot safely correlate cancellation or intermediate completion.
    // "run-program" is only the program lease: like Java BendProgramModel, the
    // AppState RUN issues one separately admitted and correlated
    // set-retract-plane/safety/retract/clamp/bend operation per phase.
    return originalManualFirmware()
        && (operation == QStringLiteral("jog-safety")
            || operation == QStringLiteral("jog-retract")
            || operation == QStringLiteral("jog-clamp")
            || operation == QStringLiteral("jog-bend")
            || operation == QStringLiteral("set-retract-plane")
            || operation == QStringLiteral("run-program"));
}

QByteArray MachineControlBackend::prepareOriginalManualStop(bool allowCancel)
{
    m_originalManualStop = originalManualFirmware();
    const QSet<QString> cancelStates = {QStringLiteral("RETRACT_JOG"),
        QStringLiteral("SAFETY_JOG_HOLD"), QStringLiteral("CLAMP_JOG_HOLD"),
        QStringLiteral("BEND_JOG_HOLD"), QStringLiteral("IDLE")};
    m_originalManualCancel = m_originalManualStop && allowCancel
        && m_pressTelemetryFresh && cancelStates.contains(m_pressMachineState);
    m_originalStopHadFault = m_pressSafetyStopUnconfirmed;
    m_originalCommandEchoSeen = false;
    m_originalTelemetryDrainBytes = 0;
    m_originalExpectedEcho = m_originalManualCancel
        ? QByteArrayLiteral("[RECEIVED STRING: cancel]")
        : QByteArrayLiteral("[RECEIVED STRING: stop]");
    if (m_originalManualStop)
        m_pressSafetyStopUnconfirmed = true;
    return m_originalManualCancel ? QByteArrayLiteral("<cancel>\n")
                                  : QByteArrayLiteral("<stop>\n");
}

bool MachineControlBackend::connectPress()
{
    m_pressReconnectDesired = true;
    m_pressReconnectAttempts = 0;
    m_pressReconnectTimer.stop();
    return attemptPressConnection(true);
}

void MachineControlBackend::setFirmwareFlashActive(bool active)
{
    if (m_firmwareFlashActive == active)
        return;
    m_firmwareFlashActive = active;
    qInfo().noquote() << "MACHINE-FIRMWARE-FLASH-LOCK active=" + QString::number(active);
    if (active) {
        if (m_pressConnected)
            disconnectPress();
        m_pressReconnectDesired = false;
        m_pressReconnectTimer.stop();
    } else {
        connectPress();
    }
}

bool MachineControlBackend::attemptPressConnection(bool reportFailure)
{
    if (m_firmwareFlashActive)
        return false;
    qInfo().noquote() << "MACHINE-CONNECT device=press state=" + pressConnectionState()
                      << "available=" + QString::number(pressTransportAvailable())
                      << "endpoint=" + pressEndpointName();
    if (m_pressConnectionState == ConnectionState::Faulted) {
        clearPressState();
        emit pressStateChanged();
        emit telemetryChanged();
    }
    if (!m_pressTransport || !m_pressTransport->isAvailable()) {
        const QString reason = rejectionReasonName(CommandRejectionReason::TransportUnavailable);
        if (reportFailure) {
            emit connectionFailed(QStringLiteral("press"), reason);
            return reject(QStringLiteral("press"), QStringLiteral("connect"),
                          CommandRejectionReason::TransportUnavailable);
        }
        return false;
    }
    if (m_pressConnectionState != ConnectionState::Disconnected) {
        if (reportFailure)
            return reject(QStringLiteral("press"), QStringLiteral("connect"),
                          CommandRejectionReason::OperationInProgress);
        return false;
    }
    m_pressConnectionState = ConnectionState::Connecting;
    emit pressStateChanged();
    if (!m_pressTransport->open()) {
        const bool transportReportedFailure =
            m_pressConnectionState == ConnectionState::Faulted;
        clearPressState();
        emit pressStateChanged();
        const QString reason = rejectionReasonName(CommandRejectionReason::TransportUnavailable);
        if (reportFailure && !transportReportedFailure) {
            emit connectionFailed(QStringLiteral("press"), reason);
            return reject(QStringLiteral("press"), QStringLiteral("connect"),
                          CommandRejectionReason::TransportUnavailable);
        }
        if (!transportReportedFailure)
            schedulePressReconnect();
        return false;
    }
    m_pressConnected = true;
    m_pressConnectionState = ConnectionState::Initializing;
    emit pressStateChanged();
    qInfo().noquote() << "MACHINE-STATE device=press state=INITIALIZING";
    return startPressHandshake();
}

bool MachineControlBackend::disconnectPress()
{
    if (thcContinuousActive()) beginThcV53Cancellation(QStringLiteral("THC_V53_DISCONNECT"));
    if (m_thcV51Phase != ThcV51Phase::Inactive)
        beginThcV51Cancellation(QStringLiteral("THC_V51_DISCONNECT"));
    m_pressReconnectDesired = false;
    m_pressReconnectAttempts = 0;
    m_pressReconnectTimer.stop();
    if (!m_pressConnected)
        return reject(QStringLiteral("press"), QStringLiteral("disconnect"),
                      CommandRejectionReason::NotConnected);
    m_pressConnectionState = ConnectionState::Disconnecting;
    emit pressStateChanged();
    m_pressTransport->close();
    if (m_pressConnectionState != ConnectionState::Disconnected) {
        clearPressState();
        emit pressStateChanged();
    }
    return true;
}

bool MachineControlBackend::resetPress()
{
    return !rejectPressOperation(QStringLiteral("reset"), true, false);
}

bool MachineControlBackend::homePress()
{
    const QString operation = QStringLiteral("home");
    if (thcContinuousActive()) {
        beginThcV53Cancellation(QStringLiteral("THC_V53_HOME_REQUESTED"));
        // No deferred Home: the operator must request it after confirmed stop.
        return false;
    }
    if (m_pressConnectionState == ConnectionState::Resetting
        || m_pressConnectionState == ConnectionState::Disconnecting)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::Resetting);
    if (!m_pressConnected)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotConnected);
    if (m_pressConnectionState != ConnectionState::Ready || !m_pressTelemetryFresh)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    const bool approvedPreHomeState = m_pressMachineState == QStringLiteral("IDLE")
        || m_pressMachineState == QStringLiteral("STARTUP_HOMING_REQUIRED")
        || MachineProtocolParsers::pressStateIsAlarm(m_pressMachineState);
    if (!approvedPreHomeState)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    if (m_pressOperationActive || commandOperationActive() || m_thcTuningQueryPending || thcLiveTuningPending()
        || m_moduleHomeConcurrent)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::OperationInProgress);

    m_pressHomePending = true;
    m_pressHomeProgressObserved = false;
    m_pressHomeInitialState = m_pressMachineState;
    m_pressOperationActive = true;
    m_pressHomed = false;
    beginHomeOperation(QStringLiteral("press"));
    emit pressStateChanged();
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<$H>\n"))) {
        if (m_pressHomePending)
            failPressHoming(QStringLiteral("HOME_WRITE_FAILED"));
        return false;
    }
    m_pressHomingTimer.start();
    qInfo().noquote() << "MACHINE-HOME device=press state=SENT";
    return true;
}

bool MachineControlBackend::panelJogSupported() const
{
    return originalManualFirmware()
        || pressMotionFirmwareSupported(QStringLiteral("jog-panel-advance"));
}

bool MachineControlBackend::startAdvanceJog(double speed)
{
    return jogPress(-4.0, speed, originalManualFirmware()
        ? QStringLiteral("safety") : QStringLiteral("panel-advance"));
}

bool MachineControlBackend::startRetractJog(double speed)
{
    return jogPress(-0.05, speed, originalManualFirmware()
        ? QStringLiteral("retract") : QStringLiteral("panel-retract"));
}

bool MachineControlBackend::releasePanelJog()
{
    if (!panelJogSupported())
        return reject(QStringLiteral("press"), QStringLiteral("release-panel-jog"),
                      CommandRejectionReason::CommandDisabled);
    if (!m_pressOperationActive)
        return true;
    // Original has no HOLD contract. Its state-aware abort and echo/drain
    // barrier own release; never emulate a physical input or use panel types.
    return originalManualFirmware() ? abortPress() : holdPressMotion();
}

bool MachineControlBackend::holdPressMotion()
{
    if (thcContinuousActive()) return beginThcV53Cancellation(QStringLiteral("THC_V53_HOLD_REQUESTED"));
    if (m_thcV51Phase != ThcV51Phase::Inactive)
        return beginThcV51Cancellation(QStringLiteral("THC_V51_HOLD_REQUESTED"));
    const QString operation = QStringLiteral("hold-motion");
    if (m_pressConnected && !pressMotionFirmwareSupported(operation))
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::CommandDisabled);
    if (!m_pressConnected)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotConnected);
    if (m_pressConnectionState != ConnectionState::Ready)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    // A controller fault may revoke the homed latch before QML receives the
    // corresponding button-release event. The already-active safety STOP is
    // authoritative: release is idempotent and must neither raise a second
    // NOT_READY alarm nor replace the STOP transaction with HOLD.
    if (m_pressCommandPhase == PressCommandPhase::AwaitFailureStopIdle
        || m_pressCommandPhase == PressCommandPhase::AwaitHomeFailureStopIdle
        || m_pressCommandPhase == PressCommandPhase::AwaitHoldIdle)
        return true;
    if (!m_pressHomed || !m_pressOperationActive)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    if (commandOperationActive())
        finishCommandOperation(QStringLiteral("HOLD_REQUESTED"));
    beginCommandOperation(QStringLiteral("press"), operation);
    m_pressCommandPhase = PressCommandPhase::AwaitHoldIdle;
    m_pressOperationActive = true;
    emit pressStateChanged();
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<hold>\n"))) {
        failActiveCommand(QStringLiteral("HOLD_WRITE_FAILED"));
        return false;
    }
    m_commandDeadlineTimer.setInterval(10000);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::stopPressMotion()
{
    if (thcContinuousActive()) return beginThcV53Cancellation(QStringLiteral("THC_V53_STOP_REQUESTED"));
    if (m_thcV51Phase != ThcV51Phase::Inactive)
        return beginThcV51Cancellation(QStringLiteral("THC_V51_STOP_REQUESTED"));
    const QString operation = QStringLiteral("stop-motion");
    if (m_originalManualStop && commandOperationActive())
        return true;
    if (!m_pressConnected)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotConnected);
    if (m_pressConnectionState != ConnectionState::Ready)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    revokePrimingLatchPresentation();
    if (commandOperationActive())
        finishCommandOperation(QStringLiteral("CANCEL_REQUESTED"));
    beginCommandOperation(QStringLiteral("press"), operation);
    m_pressCommandPhase = PressCommandPhase::AwaitStopIdle;
    m_expectedPressStopState = QStringLiteral("IDLE");
    m_allowPressStopIdleRace = false;
    m_pressStopAcknowledged = false;
    m_pressOperationActive = true;
    const QByteArray stopFrame = prepareOriginalManualStop(false);
    emit pressStateChanged();
    if (!m_pressTransport->writeFrame(stopFrame)) {
        failActiveCommand(QStringLiteral("STOP_WRITE_FAILED"));
        return false;
    }
    m_commandDeadlineTimer.setInterval(m_originalManualStop ? 30000 : 10000);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::abortPress()
{
    if (thcContinuousActive()) return beginThcV53Cancellation(QStringLiteral("THC_V53_CANCEL_REQUESTED"));
    if (m_thcV51Phase != ThcV51Phase::Inactive)
        return beginThcV51Cancellation(QStringLiteral("THC_V51_CANCEL_REQUESTED"));
    const QString operation = QStringLiteral("abort");
    if (m_originalManualStop && commandOperationActive())
        return true;
    if (!m_pressConnected)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotConnected);
    if (m_pressConnectionState != ConnectionState::Ready)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    revokePrimingLatchPresentation();
    // A fault response already started the mandatory safety STOP transaction.
    // A subsequent QML button-release event must not cancel or replace that
    // transaction while the backend is waiting for [STOPPED] plus IDLE.
    if (m_pressCommandPhase == PressCommandPhase::AwaitFailureStopIdle
        || m_pressCommandPhase == PressCommandPhase::AwaitHomeFailureStopIdle)
        return true;
    const bool cancellingHome = m_pressHomePending;
    const bool cancellingHomeAfterProgress = cancellingHome && m_pressHomeProgressObserved;
    if (cancellingHome)
        finishHomeOperation(QStringLiteral("press"), QStringLiteral("FAILED"),
                            QStringLiteral("CANCEL_REQUESTED"));
    else if (commandOperationActive())
        finishCommandOperation(QStringLiteral("CANCEL_REQUESTED"));
    beginCommandOperation(QStringLiteral("press"), operation);
    m_pressCommandPhase = PressCommandPhase::AwaitStopIdle;
    m_expectedPressStopState = cancellingHome
        ? QStringLiteral("STARTUP_HOMING_REQUIRED") : QStringLiteral("IDLE");
    m_allowPressStopIdleRace = cancellingHomeAfterProgress;
    m_pressStopAcknowledged = false;
    m_pressOperationActive = true;
    // Home retains its independent STOP contract; never apply Manual CANCEL to Home.
    m_originalManualStop = false;
    const QByteArray abortFrame = cancellingHome ? QByteArrayLiteral("<stop>\n")
                                                : prepareOriginalManualStop(true);
    emit pressStateChanged();
    if (!m_pressTransport->writeFrame(abortFrame)) {
        failActiveCommand(QStringLiteral("ABORT_WRITE_FAILED"));
        return false;
    }
    m_commandDeadlineTimer.setInterval(m_originalManualStop ? 30000 : 10000);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::killHydraulics()
{
    const QString operation = QStringLiteral("kill-hydraulics");
    if (!m_pressConnected)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::NotConnected);
    if (m_pressConnectionState != ConnectionState::Ready)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::NotReady);
    revokePrimingLatchPresentation();
    if (commandOperationActive())
        finishCommandOperation(QStringLiteral("CANCEL_REQUESTED"));
    beginCommandOperation(QStringLiteral("press"), operation);
    m_pressCommandPhase = PressCommandPhase::AwaitHydraulicShutdown;
    m_pressOperationActive = true;
    emit pressStateChanged();
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<HydraulicShutdown>\n"))) {
        failActiveCommand(QStringLiteral("HYDRAULIC_STOP_WRITE_FAILED"));
        return false;
    }
    m_commandDeadlineTimer.setInterval(10000);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::startProgram()
{
    // A physical program is orchestrated by AppState using the typed operations below.
    // Never acknowledge a run here without owning and completing its physical phases.
    return reject(QStringLiteral("press"), QStringLiteral("run-program"),
                  CommandRejectionReason::CommandDisabled);
}

bool MachineControlBackend::beginProgramRun()
{
    const QString operation = QStringLiteral("run-program");
    if (m_programRunActive)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::OperationInProgress);
    if (!admitPressMotion(operation))
        return false;
    if (!m_moduleHomed)
        return reject(QStringLiteral("module"), operation,
                      CommandRejectionReason::NotHomed);
    if (m_moduleConnectionState != ConnectionState::Ready || !m_moduleReady
        || !m_moduleTelemetryFresh || m_moduleState != QStringLiteral("IDLE")
        || m_moduleOperationActive) {
        return reject(QStringLiteral("module"), operation,
                      CommandRejectionReason::NotReady);
    }
    m_programRunActive = true;
    return true;
}

void MachineControlBackend::endProgramRun()
{
    m_programRunActive = false;
}

bool MachineControlBackend::setRunPedalMode(int mode)
{
    const QString operation = QStringLiteral("run-pedal-mode");
    if (mode < 0 || mode > 4)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::InvalidArgument);
    if (!admitPressConfiguration(operation))
        return false;
    // Fire-and-forget config frame: no operation/deadline, so it cannot block
    // the beginProgramRun() that immediately follows.
    return m_pressTransport->writeFrame(QStringLiteral("<$PM=%1>\n").arg(mode).toLatin1());
}

bool MachineControlBackend::requestRemoteRun()
{
    const QString operation = QStringLiteral("remote-run");
    if (!m_remoteRunAllowed)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::CommandDisabled);
    if (m_programRunActive)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::OperationInProgress);
    emit remoteRunRequested();
    return true;
}

bool MachineControlBackend::startManualOperation(const QString &operation)
{
    const QString normalized = operation.trimmed();
    if (normalized.isEmpty())
        return reject(QStringLiteral("press"), QStringLiteral("manual"),
                      CommandRejectionReason::InvalidArgument);
    if (!m_pressConnected)
        return reject(QStringLiteral("press"), QStringLiteral("manual-") + normalized,
                      CommandRejectionReason::NotConnected);
    return reject(QStringLiteral("press"), QStringLiteral("manual-") + normalized,
                  CommandRejectionReason::InvalidArgument);
}

bool MachineControlBackend::jogPress(double targetPosition, double speed,
                                     const QString &jogType)
{
    const QString type = jogType.trimmed().toLower();
    static const QSet<QString> types = {QStringLiteral("safety"), QStringLiteral("retract"),
        QStringLiteral("move-retract"),
        QStringLiteral("clamp"), QStringLiteral("bend"), QStringLiteral("bump"),
        QStringLiteral("panel-retract"), QStringLiteral("panel-advance")};
    const QString operation = QStringLiteral("jog-") + type;
    if (!std::isfinite(targetPosition) || !std::isfinite(speed)
        || targetPosition < -4.0 || targetPosition > -0.05
        || speed < 0.5 || speed > 15.0 || !types.contains(type)) {
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::InvalidArgument);
    }
    if (!admitPressMotion(operation))
        return false;
    if ((type == QStringLiteral("safety") || type == QStringLiteral("retract"))
        && (m_safetyJogLeft || m_safetyJogRight)) {
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    }
    const bool admittedProgramBendContinuation = m_programRunActive
        && type == QStringLiteral("bend");
    if ((type == QStringLiteral("clamp") || type == QStringLiteral("bend"))
        && m_bendPedal && !admittedProgramBendContinuation) {
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    }
    beginCommandOperation(QStringLiteral("press"), operation);
    m_pressCommandPhase = PressCommandPhase::AwaitProgress;
    m_pressCommandJogType = type;
    m_pressCommandTarget = targetPosition;
    m_pressCommandProgressObserved = false;
    m_pressOperationActive = true;
    emit pressStateChanged();
    const QByteArray frame = QStringLiteral("<%1, %2, %3>\n")
        .arg(targetPosition, 0, 'f', 4).arg(speed, 0, 'f', 4).arg(type).toLatin1();
    return writePressCommand(frame, operation);
}

bool MachineControlBackend::startManualStroke(double retractPosition, double bendPosition,
                                              double jogSpeed, double bendSpeed)
{
    const QString operation = QStringLiteral("manual-stroke");
    if (!std::isfinite(retractPosition) || !std::isfinite(bendPosition)
        || !std::isfinite(jogSpeed) || !std::isfinite(bendSpeed)
        || retractPosition < -4.0 || retractPosition > -0.05
        || bendPosition < -4.0 || bendPosition > -0.05
        || bendPosition >= retractPosition || jogSpeed < 0.5 || jogSpeed > 15.0
        || bendSpeed < 0.5 || bendSpeed > 15.0) {
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::InvalidArgument);
    }
    if (!admitPressMotion(operation))
        return false;
    beginCommandOperation(QStringLiteral("press"), operation);
    m_pressStrokeRetractTarget = retractPosition;
    m_pressStrokeBendTarget = bendPosition;
    m_pressStrokeJogSpeed = jogSpeed;
    m_pressStrokeBendSpeed = bendSpeed;
    m_pressCommandPhase = PressCommandPhase::StrokeAwaitSetting;
    m_pressRetractEchoMismatch = std::numeric_limits<double>::quiet_NaN();
    m_pressOperationActive = true;
    emit pressStateChanged();
    const QByteArray frame = QStringLiteral("<$R=%1>\n").arg(retractPosition, 0, 'f', 4).toLatin1();
    if (!writePressCommand(frame, operation))
        return false;
    m_commandDeadlineTimer.setInterval(RetractPlaneAckTimeoutMs);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::setPressRetractPlane(double retractPosition)
{
    const QString operation = QStringLiteral("set-retract-plane");
    if (!std::isfinite(retractPosition) || retractPosition < -4.0
        || retractPosition > -0.05) {
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::InvalidArgument);
    }
    if (!admitPressMotion(operation))
        return false;
    beginCommandOperation(QStringLiteral("press"), operation);
    m_pressCommandPhase = PressCommandPhase::AwaitSettingAck;
    m_pressCommandTarget = retractPosition;
    m_pressRetractEchoMismatch = std::numeric_limits<double>::quiet_NaN();
    m_pressOperationActive = true;
    emit pressStateChanged();
    const QByteArray frame = QStringLiteral("<$R=%1>\n")
        .arg(retractPosition, 0, 'f', 4).toLatin1();
    if (!writePressCommand(frame, operation))
        return false;
    // Non-motion setting: never wait the generic 120 s. A controller that
    // ignores the plane (V53 before the original <= -0.05 parity fix echoed
    // 0.0000) must fail RUN visibly instead of parking it in STARTING.
    m_commandDeadlineTimer.setInterval(RetractPlaneAckTimeoutMs);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::setDeflectionCompensation(bool enabled)
{
    // Firmware-owned frame deflection (tonnage) compensation: the controller
    // adds tonnage/12.5*0.035 in per ram to the encoder feedback. The host
    // only toggles it ($1, EEPROM), exactly like the original Java app.
    if (!std::isfinite(m_ramToTableOpening) || m_ramToTableOpening < 7.950
        || m_ramToTableOpening > 8.750)
        return reject(QStringLiteral("press"), QStringLiteral("set-deflection-compensation"),
                      CommandRejectionReason::NotReady);
    m_deflectionAdmission = enabled ? 1 : 0;
    const bool ok = setRamToTableOpening(m_ramToTableOpening);
    m_deflectionAdmission = -1;
    return ok;
}

bool MachineControlBackend::setRamToTableOpening(double openingInches)
{
    const bool deflectionWrite = m_deflectionAdmission >= 0;
    if (thcLiveTuningPending())
        return reject(QStringLiteral("press"), QStringLiteral("ram-to-table-opening"), CommandRejectionReason::OperationInProgress);
    const QString operation = deflectionWrite
        ? QStringLiteral("set-deflection-compensation")
        : QStringLiteral("set-ram-to-table-opening");
    if (!std::isfinite(openingInches) || openingInches < 7.950
        || openingInches > 8.750) {
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::InvalidArgument);
    }
    if (!m_pressConnected)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotConnected);
    if (m_pressConnectionState != ConnectionState::Ready || !m_pressTelemetryFresh)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    const bool settingsAllowed = m_pressMachineState == QStringLiteral("IDLE")
        || m_pressMachineState == QStringLiteral("STARTUP_HOMING_REQUIRED")
        || m_pressMachineState == QStringLiteral("HYDRAULIC_SHUTDOWN");
    if (!settingsAllowed)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    if (m_pressOperationActive || commandOperationActive() || m_thcTuningQueryPending) {
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::OperationInProgress);
    }

    beginCommandOperation(QStringLiteral("press"), operation);
    m_requestedDeflectionCompensation = m_deflectionAdmission;
    m_requestedRamToTableOpening = openingInches;
    m_pressOperationActive = true;
    if (originalManualFirmware()) {
        m_pressCommandPhase = PressCommandPhase::AwaitRamToTableAck;
        emit pressStateChanged();
        return writeRamToTableOpeningFrame();
    }
    // Custom firmware admits EEPROM work only with the control loop fully at
    // rest (persistenceAccessAllowed: machineStopped, pidOutput/speedOutput
    // zero). A finished TH/THC can leave that loop non-zero and the write is
    // answered [EEPROM BUSY], so revoke it first with the non-motion STOP and
    // write $3 only after [STOPPED].
    m_pressCommandPhase = PressCommandPhase::AwaitRamToTableStop;
    emit pressStateChanged();
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<stop>\n"))) {
        failActiveCommand(QStringLiteral("RAM_TO_TABLE_STOP_WRITE_FAILED"));
        return false;
    }
    m_commandDeadlineTimer.setInterval(5000);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::writeRamToTableOpeningFrame()
{
    m_pressCommandPhase = PressCommandPhase::AwaitRamToTableAck;
    const QByteArray frame = m_requestedDeflectionCompensation >= 0
        ? QStringLiteral("<$1=%1>\n").arg(m_requestedDeflectionCompensation).toLatin1()
        : QStringLiteral("<$3=%1>\n")
              .arg(m_requestedRamToTableOpening, 0, 'f', 4).toLatin1();
    if (!m_pressTransport->writeFrame(frame)) {
        failActiveCommand(QStringLiteral("RAM_TO_TABLE_WRITE_FAILED"));
        return false;
    }
    m_commandDeadlineTimer.setInterval(10000);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::setManualModeEnabled(bool enabled)
{
    const QString operation = enabled ? QStringLiteral("manual-enable")
                                      : QStringLiteral("manual-disable");
    if (!admitPressConfiguration(operation))
        return false;
    // Disable is an idempotent safety command. A lost enable acknowledgement can
    // leave the controller enabled while the last confirmed host state is false,
    // so a compensating ManualDisable must still be admitted.
    if (enabled && m_manualModeEnabled == enabled)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::InvalidArgument);
    beginCommandOperation(QStringLiteral("press"), operation);
    m_expectedManualModeEnabled = enabled;
    m_pressCommandPhase = PressCommandPhase::AwaitManualModeStatus;
    m_pressOperationActive = true;
    emit pressStateChanged();
    if (!writePressCommand(enabled ? QByteArrayLiteral("<ManualEnable>\n")
                                   : QByteArrayLiteral("<ManualDisable>\n"), operation))
        return false;
    m_commandDeadlineTimer.setInterval(1000);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::setManualModeMaxTonnage(double maxTonnagePerRam)
{
    const QString operation = QStringLiteral("manual-max-tonnage");
    if (!std::isfinite(maxTonnagePerRam)
        || maxTonnagePerRam < 0.5 || maxTonnagePerRam > 12.5) {
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::InvalidArgument);
    }
    if (!admitPressConfiguration(operation))
        return false;
    beginCommandOperation(QStringLiteral("press"), operation);
    m_requestedManualMaxTonnage = maxTonnagePerRam;
    m_pressCommandPhase = PressCommandPhase::AwaitManualTonnageAck;
    m_pressOperationActive = true;
    emit pressStateChanged();
    const QByteArray frame = QStringLiteral("<$MT=%1>\n")
        .arg(maxTonnagePerRam, 0, 'f', 4).toLatin1();
    if (!writePressCommand(frame, operation))
        return false;
    m_commandDeadlineTimer.setInterval(3000);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::setPrimingEnabled(bool enabled)
{
    const QString operation = enabled ? QStringLiteral("priming-enable")
                                      : QStringLiteral("priming-disable");
    if (!admitPressConfiguration(operation))
        return false;
    if (m_primingModeEnabled == enabled)
        return true;
    const bool allowedState = m_pressMachineState == QStringLiteral("HYDRAULIC_SHUTDOWN")
        || m_pressMachineState == QStringLiteral("STARTUP_HOMING_REQUIRED")
        || (!enabled && m_pressMachineState == QStringLiteral("PRIMING_MODE"));
    if (!allowedState)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::NotReady);
    beginCommandOperation(QStringLiteral("press"), operation);
    m_expectedPrimingModeEnabled = enabled;
    if (!enabled)
        revokePrimingLatchPresentation();
    m_pressCommandPhase = PressCommandPhase::AwaitPrimingStatus;
    m_pressOperationActive = true;
    emit pressStateChanged();
    if (!writePressCommand(enabled ? QByteArrayLiteral("<PrimingEnable>\n")
                                   : QByteArrayLiteral("<PrimingDisable>\n"), operation))
        return false;
    m_commandDeadlineTimer.setInterval(5000);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::setRamLevelOffset(double inches)
{
    const QString operation = QStringLiteral("ram-level-offset");
    if (!std::isfinite(inches) || std::abs(inches) > 0.100)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::InvalidArgument);
    if (!m_pressConnected || !m_pressReady || m_pressOperationActive)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    // Firmware stores it only when idle and answers {LV:<current>} either way.
    return m_pressTransport->writeFrame(
        QStringLiteral("<$L=%1>\n").arg(inches, 0, 'f', 4).toLatin1());
}

bool MachineControlBackend::queryRamLevelOffset()
{
    if (!m_pressConnected)
        return false;
    return m_pressTransport->writeFrame(QByteArrayLiteral("<$L?>\n"));
}

bool MachineControlBackend::setPrimingLatch(const QString &axis, bool enabled)
{
    const QString normalized = axis.trimmed().toUpper();
    const QString operation = QStringLiteral("priming-") + (enabled ? QStringLiteral("latch-") : QStringLiteral("release-")) + normalized.toLower();
    if (normalized != QStringLiteral("Y1") && normalized != QStringLiteral("Y2"))
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::InvalidArgument);
    if (!m_primingLatchSupported)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::CommandDisabled);
    if (!m_pressConnected || !m_pressReady || !m_pressTelemetryFresh
        || !m_primingModeEnabled || m_pressMachineState != QStringLiteral("PRIMING_MODE"))
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    if (m_thcTuningQueryPending || thcLiveTuningPending())
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::OperationInProgress);
    const QByteArray frame = QStringLiteral("<Priming%1:%2>\n")
        .arg(enabled ? QStringLiteral("Latch") : QStringLiteral("Release"), normalized).toLatin1();
    if (!m_pressTransport->writeFrame(frame)) {
        failActiveCommand(QStringLiteral("PRIMING_LATCH_WRITE_FAILED"));
        return false;
    }
    // Never update latch state optimistically; only TEMP is authoritative.
    return true;
}

bool MachineControlBackend::startTonnageHold(double targetTonnage, double bendSpeed,
                                             double jogSpeed)
{
    const QString operation = QStringLiteral("tonnage-hold");
    if (!std::isfinite(targetTonnage) || !std::isfinite(bendSpeed) || !std::isfinite(jogSpeed)
        || targetTonnage < 0.5 || targetTonnage > 24.0
        || bendSpeed < 0.5 || bendSpeed > 15.0
        || jogSpeed < 0.5 || jogSpeed > 15.0) {
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::InvalidArgument);
    }
    if (!nativeTonnageHoldSupported())
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::CommandDisabled);
    if (!admitPressMotion(operation))
        return false;
    if (!m_manualModeEnabled)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);

    beginCommandOperation(QStringLiteral("press"), operation);
    m_tonnageHoldTarget = targetTonnage;
    m_tonnageHoldApproachSpeed = bendSpeed;
    m_tonnageHoldJogSpeed = jogSpeed;
    m_pressCommandProgressObserved = false;
    m_pressOperationActive = true;
    emit pressStateChanged();

    m_pressCommandPhase = PressCommandPhase::NativeTonnageHold;
    m_tonnageHoldDoneAcknowledged = false;
    const QByteArray frame = QStringLiteral("<TH:%1,%2,%3>\n")
        .arg(targetTonnage, 0, 'f', 3)
        .arg(bendSpeed, 0, 'f', 3)
        .arg(jogSpeed, 0, 'f', 3).toLatin1();
    if (!writePressCommand(frame, operation))
        return false;
    // Firmware expires this controller-owned lease unless exact TH heartbeat
    // acknowledgements arrive. Ordinary telemetry never renews it.
    m_tonnageHoldHeartbeatTimer.start();
    m_commandDeadlineTimer.setInterval(5000);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::startToolChangeTouch(double backoff, double floor)
{
    const QString operation = QStringLiteral("tool-change-touch");
    if (!toolChangeSupported())
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::CommandDisabled);
    const bool backoffOk = std::abs(backoff - 0.125) < 1e-9 || std::abs(backoff - 0.250) < 1e-9;
    if (!backoffOk || !std::isfinite(floor) || floor < -4.0 || floor > -0.05)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::InvalidArgument);
    if (!admitPressMotion(operation)) return false;
    beginCommandOperation(QStringLiteral("press"), operation);
    m_pressCommandPhase = PressCommandPhase::ThcCommissioning;
    m_pressOperationActive = true;
    // Contact-profile family: firmware owns approach, first contact and the
    // bounded backoff. The lease is renewed only while jog-down is held.
    m_thcContactProfileActive = true;
    m_thcContactProfileContactObserved = false;
    m_thcContactProfileAutomaticLifecycle = false;
    m_toolChangeMode = QStringLiteral("TOUCH");
    m_toolChangePhase = QStringLiteral("ARMING");
    m_thcCommissioningState = QStringLiteral("TOOL_CHANGE_ARMING");
    emit pressStateChanged();
    const QByteArray frame = QStringLiteral("<THC:TOUCH:%1,%2>\n")
        .arg(backoff, 0, 'f', 3).arg(floor, 0, 'f', 4).toLatin1();
    if (!writePressCommand(frame, operation)) return false;
    m_commandDeadlineTimer.setInterval(5000); m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::heartbeatToolChangeTouch()
{
    if (m_toolChangeMode != QStringLiteral("TOUCH")
        || m_pressCommandPhase != PressCommandPhase::ThcCommissioning
        || !m_pressConnected || !m_pressTransport->isOpen())
        return false;
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<THC:HB>\n"))) {
        failActiveCommand(QStringLiteral("THC_HEARTBEAT_WRITE_FAILED"));
        return false;
    }
    return true;
}

bool MachineControlBackend::startToolChangeMove(double target)
{
    const QString operation = QStringLiteral("tool-change-move");
    if (!toolChangeSupported())
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::CommandDisabled);
    if (!std::isfinite(target) || target < -3.99 - 1e-9 || target > -0.05 + 1e-9)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::InvalidArgument);
    if (!admitPressMotion(operation)) return false;
    beginCommandOperation(QStringLiteral("press"), operation);
    m_pressCommandPhase = PressCommandPhase::ThcCommissioning;
    m_pressOperationActive = true;
    m_thcContactProfileActive = true;
    m_thcContactProfileContactObserved = false;
    m_thcContactProfileAutomaticLifecycle = true; // host-renewed lease
    m_toolChangeMode = QStringLiteral("MOVE");
    m_toolChangePhase = QStringLiteral("ARMING");
    m_thcCommissioningState = QStringLiteral("TOOL_CHANGE_ARMING");
    emit pressStateChanged();
    const QByteArray frame = QStringLiteral("<THC:MOVE:%1>\n").arg(target, 0, 'f', 4).toLatin1();
    if (!writePressCommand(frame, operation)) return false;
    m_commandDeadlineTimer.setInterval(5000); m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::startToolChangeSeat(double bendSpeed, double jogSpeed,
                                                double retractPlane, bool equalForce)
{
    const QString operation = QStringLiteral("tool-change-seat");
    if (!toolChangeSupported())
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::CommandDisabled);
    if (!std::isfinite(bendSpeed) || !std::isfinite(jogSpeed) || !std::isfinite(retractPlane)
        || bendSpeed < 0.5 || bendSpeed > 15.0 || jogSpeed < 0.5 || jogSpeed > 15.0
        || retractPlane < -4.0 || retractPlane > 0.0)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::InvalidArgument);
    // RUN-owned: unlike plain TH, SEAT does not require Manual mode.
    if (!admitPressMotion(operation)) return false;
    beginCommandOperation(QStringLiteral("press"), operation);
    m_tonnageHoldTarget = 1.0;
    m_tonnageHoldApproachSpeed = bendSpeed;
    m_tonnageHoldJogSpeed = jogSpeed;
    m_pressCommandProgressObserved = false;
    m_pressOperationActive = true;
    m_toolChangeMode = QStringLiteral("SEAT");
    m_toolChangePhase = QStringLiteral("ARMING");
    emit pressStateChanged();
    m_pressCommandPhase = PressCommandPhase::NativeTonnageHold;
    m_tonnageHoldDoneAcknowledged = false;
    const QByteArray frame = QStringLiteral("<TH:%1:%2,%3,%4>\n")
        .arg(equalForce ? QStringLiteral("SEATEQ") : QStringLiteral("SEAT"))
        .arg(bendSpeed, 0, 'f', 3).arg(jogSpeed, 0, 'f', 3)
        .arg(retractPlane, 0, 'f', 4).toLatin1();
    if (!writePressCommand(frame, operation)) return false;
    m_tonnageHoldHeartbeatTimer.start();
    m_commandDeadlineTimer.setInterval(5000);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::handleToolChangeFrame(const QString &line)
{
    if (!line.startsWith(QStringLiteral("{TCH:")) || !line.endsWith(QLatin1Char('}')))
        return false;
    const QString body = line.mid(5, line.size() - 6).trimmed();
    if (body == QStringLiteral("CAP:1")) {
        if (!m_pressToolChangeSupported) {
            m_pressToolChangeSupported = true;
            qInfo().noquote() << "MACHINE-CAPABILITY device=press toolChange=1";
            emit pressStateChanged();
        }
        return true;
    }
    if (m_toolChangeMode.isEmpty())
        return true; // stray event without an owned tool change
    const int colon = body.indexOf(QLatin1Char(':'));
    const QString kind = colon < 0 ? body : body.left(colon);
    const QString arg = colon < 0 ? QString() : body.mid(colon + 1);
    double position = std::numeric_limits<double>::quiet_NaN();
    QString event;
    if (kind == QStringLiteral("PHASE")) {
        event = arg;
        if (arg == QStringLiteral("TOUCH") || arg == QStringLiteral("MOVE")) {
            acknowledgeCommandOperation();
            if (m_toolChangeMode == QStringLiteral("TOUCH")) {
                // Approach is untimed; the jog-held lease is the guard.
                m_commandDeadlineTimer.stop();
            } else {
                // Firmware deadline = 1.5 x ideal + 10 s (<= 190 s for 1 in).
                m_thcContactProfileHeartbeatTimer.start();
                m_commandDeadlineTimer.setInterval(200000);
                m_commandDeadlineTimer.start();
            }
        } else if (arg == QStringLiteral("BACKOFF")) {
            m_commandDeadlineTimer.setInterval(ThcReleaseHostObserverMs);
            m_commandDeadlineTimer.start();
        } else if (arg == QStringLiteral("SEAT_ARMED") || arg == QStringLiteral("SEAT_ARMED:EQ")) {
            event = QStringLiteral("SEAT_ARMED");
            acknowledgeCommandOperation();
        }
    } else if (kind == QStringLiteral("CONTACT")) {
        event = kind;
        bool ok = false;
        position = arg.section(QLatin1Char(','), 0, 0).toDouble(&ok);
        if (ok) m_toolChangeContactPosition = position;
    } else if (kind == QStringLiteral("BACKOFF_DONE") || kind == QStringLiteral("MOVE_DONE")
               || kind == QStringLiteral("SEAT_DONE")) {
        event = kind;
        bool ok = false;
        position = arg.toDouble(&ok);
        if (!ok) position = std::numeric_limits<double>::quiet_NaN();
    } else if (kind == QStringLiteral("SEAT_PAUSED") || kind == QStringLiteral("SEAT_RESUMED")
               || kind == QStringLiteral("SEAT_HOLDING")) {
        event = kind;
    } else if (kind == QStringLiteral("ERROR")) {
        m_toolChangePhase = QStringLiteral("ERROR");
        failActiveCommand(QStringLiteral("TOOL_CHANGE_") + arg);
        return true;
    } else {
        return true;
    }
    m_toolChangePhase = event;
    emit pressStateChanged();
    emit toolChangeEvent(event, position);
    return true;
}

bool MachineControlBackend::stopTonnageHold()
{
    const QString operation = QStringLiteral("tonnage-hold-stop");
    if (!m_pressConnected)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotConnected);
    if (!isTonnageHoldPhase())
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::InvalidArgument);
    m_tonnageHoldTimer.stop();
    m_tonnageHoldHeartbeatTimer.stop();
    m_pressCommandPhase = PressCommandPhase::TonnageHoldAwaitStopIdle;
    m_tonnageHoldDoneAcknowledged = false;
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<cancel>\n"))) {
        failActiveCommand(QStringLiteral("TONNAGE_HOLD_CANCEL_WRITE_FAILED"));
        return false;
    }
    m_commandDeadlineTimer.setInterval(10000);
    m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::armThcCommissioning(double targetTonnage, double speed, double floor)
{
    const QString operation = QStringLiteral("thc-arm");
    if (!std::isfinite(targetTonnage) || !std::isfinite(speed) || !std::isfinite(floor)
        || targetTonnage < 0.5 || targetTonnage > 1.0 || speed < 0.5 || speed > 1.0
        || std::abs(floor + 0.5) > 1e-9)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::InvalidArgument);
    if (!thcCommissioningSupported() || !m_manualModeEnabled)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::CommandDisabled);
    if (!admitPressMotion(operation)) return false;
    beginCommandOperation(QStringLiteral("press"), operation);
    m_pressCommandPhase = PressCommandPhase::ThcCommissioning;
    m_pressOperationActive = true;
    m_thcCommissioningState = QStringLiteral("ARMING");
    emit pressStateChanged();
    const QByteArray frame = QStringLiteral("<THC:ARM:%1,%2,%3>\n")
        .arg(targetTonnage, 0, 'f', 3).arg(speed, 0, 'f', 3).arg(floor, 0, 'f', 3).toLatin1();
    if (!writePressCommand(frame, operation)) return false;
    m_commandDeadlineTimer.setInterval(5000); m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::startThcCommissioning()
{
    if (m_pressCommandPhase != PressCommandPhase::ThcCommissioning
        || m_thcCommissioningState != QStringLiteral("ARMED"))
        return reject(QStringLiteral("press"), QStringLiteral("thc-start"), CommandRejectionReason::NotReady);
    return writePressCommand(QByteArrayLiteral("<THC:START>\n"), QStringLiteral("thc-start"));
}

bool MachineControlBackend::heartbeatThcCommissioning()
{
    if (thcContinuousActive()) {
        const auto owner = m_operationId;
        if (!checkThcV53Deadlines() || m_operationId != owner
            || m_thcV53Phase == ThcV53Phase::AwaitIdle) return false;
        m_thcV53ClientDeadlineMs = m_thcV53Clock.elapsed() + 2000;
        m_thcV53ClientLeaseTimer.start(2000);
        return true; // Only explicit owner renewal, never query/tune/serial HB.
    }
    if (m_thcV51Phase != ThcV51Phase::Inactive) {
        const auto owner = m_operationId;
        if (m_thcV51Phase == ThcV51Phase::AwaitIdle)
            return false;
        if (!checkThcV51Deadlines() || m_operationId != owner
            || m_thcV51Phase == ThcV51Phase::Inactive
            || m_thcV51Phase == ThcV51Phase::AwaitIdle
            || m_thcV51Phase == ThcV51Phase::AwaitCancel)
            return false;
        // Only this explicit external-owner call renews the client lease.
        // The automatic dual MCU heartbeat deliberately does not call here.
        m_thcV51ClientDeadlineMs = m_thcV51Clock.elapsed() + ThcV51ClientLeaseMs;
        m_thcV51ClientLeaseTimer.start(ThcV51ClientLeaseMs);
        return true;
    }
    if (m_pressCommandPhase != PressCommandPhase::ThcCommissioning)
        return reject(QStringLiteral("press"), QStringLiteral("thc-heartbeat"), CommandRejectionReason::NotReady);
    if (m_thcContactProfileActive) {
        if (!m_pressTransport->writeFrame(QByteArrayLiteral("<THC:HB>\n"))) {
            failActiveCommand(QStringLiteral("THC_HEARTBEAT_WRITE_FAILED"));
            return false;
        }
        return true;
    }
    return writePressCommand(QByteArrayLiteral("<THC:HB>\n"), QStringLiteral("thc-heartbeat"));
}

bool MachineControlBackend::releaseThcCommissioning()
{
    if (thcContinuousActive()) return releaseThcV53();
    if (m_thcV51Phase != ThcV51Phase::Inactive) {
        const auto owner = m_operationId;
        const bool wasHolding = m_thcV51Phase == ThcV51Phase::Holding;
        if (!checkThcV51Deadlines() || m_operationId != owner)
            return false;
        // Checking an expired HOLD dispatches RELEASE itself, possibly with a
        // synchronous terminal reply. Report that dispatch, never write twice.
        if (wasHolding && (m_thcV51Phase == ThcV51Phase::AwaitRelease
                           || m_thcV51Phase == ThcV51Phase::Releasing
                           || m_thcV51Phase == ThcV51Phase::AwaitIdle
                           || (m_thcV51Phase == ThcV51Phase::Inactive
                               && m_operationState == QStringLiteral("COMPLETED"))))
            return true;
        return releaseThcV51();
    }
    if (m_pressCommandPhase != PressCommandPhase::ThcCommissioning
        || (m_thcCommissioningState != QStringLiteral("CONTACT_PROFILE_RUNNING")
            && m_thcCommissioningState != QStringLiteral("RUNNING")
            && m_thcCommissioningState != QStringLiteral("HOLDING")))
        return reject(QStringLiteral("press"), QStringLiteral("thc-release"), CommandRejectionReason::NotReady);
    return writePressCommand(QByteArrayLiteral("<THC:RELEASE>\n"), QStringLiteral("thc-release"));
}

bool MachineControlBackend::cancelThcCommissioning()
{
    if (thcContinuousActive()) return beginThcV53Cancellation(QStringLiteral("THC_V53_CANCEL_REQUESTED"));
    if (m_thcV51Phase != ThcV51Phase::Inactive)
        return beginThcV51Cancellation(QStringLiteral("THC_V51_CANCEL_REQUESTED"));
    if (m_pressCommandPhase != PressCommandPhase::ThcCommissioning)
        return reject(QStringLiteral("press"), QStringLiteral("thc-cancel"), CommandRejectionReason::NotReady);
    return writePressCommand(QByteArrayLiteral("<THC:CANCEL>\n"), QStringLiteral("thc-cancel"));
}

bool MachineControlBackend::startThcContactProfileCommissioning(double targetTons, double approachIpm)
{
    const QString operation = QStringLiteral("thc-contact-profile");
    // This dedicated profile is the sole THC path that does not use Manual
    // mode. Firmware owns its exact approach/control settings; only the
    // target is host-selectable.
    if (!thcCommissioningSupported())
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::CommandDisabled);
    if (!std::isfinite(targetTons) || targetTons < ThcContactProfileMinTargetT - 1e-9
        || targetTons > ThcContactProfileMaxTargetT + 1e-9)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::InvalidArgument);
    if (approachIpm != 0.0 && (!std::isfinite(approachIpm) || approachIpm < 0.5 || approachIpm > 15.0))
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::InvalidArgument);
    const bool defaultTarget = std::abs(targetTons - ThcContactProfileDefaultTargetT) < 1e-9;
    // r33: the free approach uses the host Bend speed when supplied.
    const QByteArray frame = approachIpm > 0.0
        ? QStringLiteral("<THC:CONTACT_PROFILE:%1,%2>\n").arg(targetTons, 0, 'f', 3)
              .arg(approachIpm, 0, 'f', 3).toLatin1()
        : defaultTarget
        ? QByteArrayLiteral("<THC:CONTACT_PROFILE>\n")
        : QStringLiteral("<THC:CONTACT_PROFILE:%1>\n").arg(targetTons, 0, 'f', 3).toLatin1();
    if (!admitPressMotion(operation)) return false;
    beginCommandOperation(QStringLiteral("press"), operation);
    m_pressCommandPhase = PressCommandPhase::ThcCommissioning;
    m_pressOperationActive = true;
    m_thcContactProfileActive = true;
    m_thcContactProfileContactObserved = false;
    m_thcContactProfileAutomaticLifecycle = false;
    m_thcCommissioningState = QStringLiteral("CONTACT_PROFILE_ARMING");
    emit pressStateChanged();
    if (!writePressCommand(frame, operation)) return false;
    m_commandDeadlineTimer.setInterval(5000); m_commandDeadlineTimer.start();
    return true;
}

bool MachineControlBackend::startAutomaticThcContactProfile(double targetTons, double approachIpm)
{
    if (!startThcContactProfileCommissioning(targetTons, approachIpm))
        return false;
    m_operationName = QStringLiteral("automatic-thc-contact-profile");
    m_thcContactProfileAutomaticLifecycle = true;
    emit commandLifecycleChanged();
    return true;
}

bool MachineControlBackend::startThcContactProfileV51Commissioning(const QString &binarySha256)
{
    const QString operation = QStringLiteral("thc-contact-profile-v51");
    // Explicit, case-sensitive client selection; neither this hash nor the
    // shared v1.3 banner is device attestation. Never probe or fall back to AUTO.
    if (binarySha256 != QStringLiteral("a79f02982fdbec4f08bf494d08c22e05b2bb144d0fa3890b3cd537e4fadccd14"))
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::InvalidArgument);
    if (m_pressFirmwareVersion != QStringLiteral("1.3")
        || (m_pressFirmwareIdentity != QStringLiteral("[BENDCNC v1.3]")
            && m_pressFirmwareIdentity != QStringLiteral("[LS-BEND v1.3]")))
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::CommandDisabled);
    if (!admitPressMotion(operation))
        return false;
    if (m_programRunActive || m_primingModeEnabled || m_primingLatchY1 || m_primingLatchY2
        || m_antiBind || m_thcTuningQueryRecovery)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);

    // Establish the entire owner atomically before any notification. The
    // generic beginCommandOperation resets V51, so it cannot open this owner.
    resetThcV51Operation();
    m_thcV51CancellationConfirmed = false;
    const auto owner = m_operationId + 1;
    m_originalManualStop = false;
    m_operationId = owner;
    m_operationDevice = QStringLiteral("press");
    m_operationName = operation;
    m_operationState = QStringLiteral("SENT");
    m_operationError.clear();
    m_commandDeadlineTimer.stop();
    m_pressCommandPhase = PressCommandPhase::ThcV51;
    m_pressOperationActive = true;
    m_thcContactProfileContactObserved = false;
    m_thcV51Phase = ThcV51Phase::AwaitStart;
    m_thcCommissioningState = QStringLiteral("CONTACT_PROFILE_V51_ARMING");
    m_thcV51Clock.start();
    m_thcV51OverallDeadlineMs = ThcV51OverallMs;
    m_thcV51ClientDeadlineMs = ThcV51ClientLeaseMs;
    m_thcV51ClientLeaseTimer.start(ThcV51ClientLeaseMs);
    m_thcV51OverallTimer.start(ThcV51OverallMs);
    setThcV51PhaseDeadline(ThcV51AckMs);
    emit commandLifecycleChanged();
    if (m_operationId != owner || m_thcV51Phase != ThcV51Phase::AwaitStart)
        return false;
    emit pressStateChanged();
    if (m_operationId != owner || m_thcV51Phase != ThcV51Phase::AwaitStart)
        return false;
    if (!checkThcV51Deadlines() || m_operationId != owner
        || m_thcV51Phase != ThcV51Phase::AwaitStart)
        return false;
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<THC:CONTACT_PROFILE_V51>\n"))) {
        if (m_operationId == owner && m_thcV51Phase != ThcV51Phase::Inactive)
            beginThcV51Cancellation(QStringLiteral("THC_V51_START_WRITE_FAILED"));
        return false;
    }
    if (m_operationId != owner || m_thcV51Phase == ThcV51Phase::Inactive
        || m_thcV51Phase == ThcV51Phase::AwaitCancel)
        return false;
    m_thcV51HeartbeatTimer.start();
    return true;
}

void MachineControlBackend::stopThcV51Timers()
{
    m_thcV51HeartbeatTimer.stop();
    m_thcV51ClientLeaseTimer.stop();
    m_thcV51PhaseTimer.stop();
    m_thcV51OverallTimer.stop();
}

void MachineControlBackend::resetThcV51Operation()
{
    stopThcV51Timers();
    m_thcV51Phase = ThcV51Phase::Inactive;
    m_thcV51RunningAcknowledged = false;
    m_thcV51CancelAcknowledged = false;
    m_thcV51TerminalTelemetrySequence = 0;
    m_thcV51TerminalArrival = 0;
    m_thcV51Clock.invalidate();
    m_thcV51PhaseDeadlineMs = -1;
    m_thcV51OverallDeadlineMs = -1;
    m_thcV51ClientDeadlineMs = -1;
    m_thcV51ReleaseDeadlineMs = -1;
}

void MachineControlBackend::setThcV51PhaseDeadline(qint64 deadlineMs)
{
    m_thcV51PhaseDeadlineMs = deadlineMs;
    m_thcV51PhaseTimer.start(int(qMax(qint64(1), deadlineMs - m_thcV51Clock.elapsed())));
}

bool MachineControlBackend::checkThcV51Deadlines()
{
    // Queued timeouts from a former owner must never touch a recovery Home.
    if (m_thcV51Phase == ThcV51Phase::Inactive
        || m_pressCommandPhase != PressCommandPhase::ThcV51
        || !commandOperationActive() || !m_thcV51Clock.isValid())
        return false;
    const qint64 now = m_thcV51Clock.elapsed();
    if (m_thcV51Phase == ThcV51Phase::AwaitCancel) {
        if (now >= m_thcV51PhaseDeadlineMs)
            failActiveCommand(m_pendingThcFailure + QStringLiteral("_CANCEL_CONFIRMATION_TIMEOUT"));
        return false;
    }
    if (!m_pressConnected || !m_pressTransport->isOpen()) {
        beginThcV51Cancellation(QStringLiteral("THC_V51_TRANSPORT_CLOSED"));
        return false;
    }
    if (now >= m_thcV51OverallDeadlineMs) {
        beginThcV51Cancellation(QStringLiteral("THC_V51_OVERALL_TIMEOUT"));
        return false;
    }
    if (m_thcV51Phase != ThcV51Phase::AwaitIdle && now >= m_thcV51ClientDeadlineMs) {
        beginThcV51Cancellation(QStringLiteral("THC_V51_CLIENT_LEASE_EXPIRED"));
        return false;
    }
    if (!m_pressTelemetryFresh) {
        beginThcV51Cancellation(QStringLiteral("THC_V51_TELEMETRY_STALE"));
        return false;
    }
    if (now >= m_thcV51PhaseDeadlineMs) {
        if (m_thcV51Phase == ThcV51Phase::Holding)
            return releaseThcV51();
        const QString reason = m_thcV51Phase == ThcV51Phase::AwaitStart
            ? QStringLiteral("THC_V51_START_ACK_TIMEOUT")
            : m_thcV51Phase == ThcV51Phase::AwaitRelease
                ? QStringLiteral("THC_V51_RELEASE_ACK_TIMEOUT")
                : QStringLiteral("THC_V51_PHASE_TIMEOUT");
        beginThcV51Cancellation(reason);
        return false;
    }
    return true;
}

void MachineControlBackend::sendThcV51Heartbeat()
{
    const auto owner = m_operationId;
    if (!checkThcV51Deadlines() || m_operationId != owner
        || m_thcV51Phase == ThcV51Phase::AwaitIdle
        || m_thcV51Phase == ThcV51Phase::Inactive || m_thcV51Phase == ThcV51Phase::AwaitCancel)
        return;
    // THC's 2 s lease and the independent controller keepalive both renew at
    // 250 ms, but neither write renews the external client's 2 s lease.
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<THC:HB>\n"))) {
        if (m_operationId == owner && m_thcV51Phase != ThcV51Phase::Inactive)
            beginThcV51Cancellation(QStringLiteral("THC_V51_HEARTBEAT_WRITE_FAILED"));
        return;
    }
    if (m_operationId != owner || m_thcV51Phase == ThcV51Phase::Inactive
        || m_thcV51Phase == ThcV51Phase::AwaitCancel
        || m_thcV51Phase == ThcV51Phase::AwaitIdle)
        return;
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<?>\n"))
        && m_operationId == owner && m_thcV51Phase != ThcV51Phase::Inactive)
        beginThcV51Cancellation(QStringLiteral("THC_V51_KEEP_ALIVE_WRITE_FAILED"));
}

bool MachineControlBackend::beginThcV51Cancellation(const QString &error)
{
    if (m_thcV51Phase == ThcV51Phase::Inactive)
        return false;
    if (m_thcV51Phase == ThcV51Phase::AwaitCancel) {
        checkThcV51Deadlines(); // A repeated request must not mask an expired watchdog.
        return m_thcV51Phase == ThcV51Phase::AwaitCancel;
    }
    const auto owner = m_operationId;
    stopThcV51Timers();
    m_commandDeadlineTimer.stop();
    m_thcV51Phase = ThcV51Phase::AwaitCancel;
    m_thcV51RunningAcknowledged = false;
    m_thcV51CancelAcknowledged = false;
    m_thcCommissioningState = QStringLiteral("CANCELLING");
    m_pendingThcFailure = error;
    m_pressSafetyStopUnconfirmed = true;
    setThcV51PhaseDeadline(m_thcV51Clock.elapsed() + ThcV51AckMs);
    emit pressStateChanged();
    if (m_operationId != owner || m_thcV51Phase != ThcV51Phase::AwaitCancel)
        return false;
    if (!m_pressConnected || !m_pressTransport->isOpen()
        || !m_pressTransport->writeFrame(QByteArrayLiteral("<THC:CANCEL>\n"))) {
        if (m_operationId == owner && m_thcV51Phase == ThcV51Phase::AwaitCancel)
            failActiveCommand(error + QStringLiteral("_CANCEL_WRITE_FAILED"));
        return false;
    }
    // A write may synchronously deliver a transport fault, terminal telemetry,
    // or even start a different owner through a signal handler.
    return m_operationId == owner
        && (m_thcV51Phase == ThcV51Phase::AwaitCancel
            || (m_thcV51Phase == ThcV51Phase::Inactive && !m_pressSafetyStopUnconfirmed
                && m_operationState == QStringLiteral("FAILED")));
}

bool MachineControlBackend::releaseThcV51()
{
    if (!m_thcV51RunningAcknowledged
        || (m_thcV51Phase != ThcV51Phase::Holding && m_thcV51Phase != ThcV51Phase::Acquisition))
        return reject(QStringLiteral("press"), QStringLiteral("thc-release"), CommandRejectionReason::NotReady);
    const auto owner = m_operationId;
    const qint64 now = m_thcV51Clock.elapsed();
    m_thcV51Phase = ThcV51Phase::AwaitRelease; // Guard before any signal/write.
    m_thcCommissioningState = QStringLiteral("RELEASE_PENDING");
    m_thcV51ReleaseDeadlineMs = now + ThcV51ReleaseMs;
    setThcV51PhaseDeadline(now + ThcV51AckMs);
    emit pressStateChanged();
    if (m_operationId != owner || m_thcV51Phase != ThcV51Phase::AwaitRelease)
        return false;
    if (!checkThcV51Deadlines() || m_operationId != owner
        || m_thcV51Phase != ThcV51Phase::AwaitRelease)
        return false;
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<THC:RELEASE>\n"))) {
        if (m_operationId == owner && m_thcV51Phase != ThcV51Phase::Inactive)
            beginThcV51Cancellation(QStringLiteral("THC_V51_RELEASE_WRITE_FAILED"));
        return false;
    }
    return m_operationId == owner
        && (m_thcV51Phase == ThcV51Phase::AwaitRelease
            || m_thcV51Phase == ThcV51Phase::Releasing
            || m_thcV51Phase == ThcV51Phase::AwaitIdle
            || (m_thcV51Phase == ThcV51Phase::Inactive
                && m_operationState == QStringLiteral("COMPLETED")));
}

bool MachineControlBackend::handleThcV51Frame(const QByteArray &frame, qulonglong arrival)
{
    const QByteArray classified = frame.trimmed().toUpper();
    if (m_thcV51Phase == ThcV51Phase::Inactive) {
        // In particular, a legacy profile must not normalize/admit this marker.
        return classified.contains("CONTACT_PROFILE_V51");
    }
    const auto owner = m_operationId;
    checkThcV51Deadlines();
    if (m_operationId != owner || arrival != m_pressFrameArrival
        || m_thcV51Phase == ThcV51Phase::Inactive)
        return true;
    const bool protocolFrame = classified.startsWith("{THC:") || classified.startsWith("{TH:");
    if (!protocolFrame)
        return false;
    if (m_thcV51Phase == ThcV51Phase::AwaitCancel) {
        if (frame == QByteArrayLiteral("{THC:CANCELLED}") && !m_thcV51CancelAcknowledged) {
            m_thcV51CancelAcknowledged = true;
            m_thcV51TerminalTelemetrySequence = m_pressTelemetrySequence;
            m_thcV51TerminalArrival = arrival;
        }
        return true;
    }
    // Firmware failTonnageHold translates TH:ERROR to THC:ERROR; accept either
    // as failure evidence, never as successful completion authority.
    if (classified.startsWith("{THC:ERROR") || classified.startsWith("{TH:ERROR")
        || classified == "{TH:TIMEOUT}") {
        beginThcV51Cancellation(QStringLiteral("THC_V51_FIRMWARE_ERROR:") + QString::fromLatin1(classified));
        return true;
    }
    if (frame == QByteArrayLiteral("{THC:HB}"))
        return true;
    const qint64 now = m_thcV51Clock.elapsed();
    if (frame == QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}")) {
        if (m_thcV51Phase == ThcV51Phase::AwaitStart) {
            m_thcV51RunningAcknowledged = true;
            m_thcV51Phase = ThcV51Phase::Approach;
            m_thcCommissioningState = QStringLiteral("CONTACT_PROFILE_V51_RUNNING");
            setThcV51PhaseDeadline(ThcV51ApproachMs); // From admission, NOT ack.
            acknowledgeCommandOperation();
        } else if (!m_thcV51RunningAcknowledged) {
            beginThcV51Cancellation(QStringLiteral("THC_V51_UNEXPECTED_ACK"));
        }
    } else if (frame == QByteArrayLiteral("{THC:CONTACT}")) {
        if (m_thcV51Phase == ThcV51Phase::Approach) {
            m_thcContactProfileContactObserved = true;
            m_thcV51Phase = ThcV51Phase::Acquisition;
            m_thcCommissioningState = QStringLiteral("CONTACT");
            setThcV51PhaseDeadline(now + ThcV51AcquisitionMs);
        } else if (!m_thcContactProfileContactObserved) {
            beginThcV51Cancellation(QStringLiteral("THC_V51_UNEXPECTED_CONTACT"));
        }
    } else if (frame == QByteArrayLiteral("{THC:HOLDING}")) {
        if (m_thcV51Phase == ThcV51Phase::Acquisition) {
            m_thcV51Phase = ThcV51Phase::Holding;
            m_thcCommissioningState = QStringLiteral("HOLDING");
            setThcV51PhaseDeadline(now + ThcV51HoldMs);
        } else if (m_thcV51Phase != ThcV51Phase::Holding) {
            beginThcV51Cancellation(QStringLiteral("THC_V51_UNEXPECTED_HOLDING"));
        }
    } else if (frame == QByteArrayLiteral("{THC:RELEASING}")) {
        if (m_thcV51Phase == ThcV51Phase::AwaitRelease) {
            m_thcV51Phase = ThcV51Phase::Releasing;
            m_thcCommissioningState = QStringLiteral("RELEASING");
            setThcV51PhaseDeadline(m_thcV51ReleaseDeadlineMs);
        } else if (m_thcV51Phase != ThcV51Phase::Releasing) {
            beginThcV51Cancellation(QStringLiteral("THC_V51_UNEXPECTED_RELEASING"));
        }
    } else if (frame == QByteArrayLiteral("{THC:DONE}")) {
        if (m_thcV51Phase == ThcV51Phase::Releasing) {
            m_thcV51Phase = ThcV51Phase::AwaitIdle;
            m_thcV51TerminalTelemetrySequence = m_pressTelemetrySequence;
            m_thcV51TerminalArrival = arrival;
            m_thcCommissioningState = QStringLiteral("DONE");
            m_thcV51HeartbeatTimer.stop();
            m_thcV51ClientLeaseTimer.stop();
            setThcV51PhaseDeadline(qMin(m_thcV51ReleaseDeadlineMs, now + ThcV51AckMs));
        } else if (m_thcV51Phase != ThcV51Phase::AwaitIdle) {
            beginThcV51Cancellation(QStringLiteral("THC_V51_UNEXPECTED_DONE"));
        }
    } else {
        beginThcV51Cancellation(QStringLiteral("THC_V51_UNEXPECTED_ACK"));
    }
    emit pressStateChanged();
    return true;
}

void MachineControlBackend::handleThcV51Telemetry(bool exactIdleTelemetry, qulonglong arrival)
{
    const auto owner = m_operationId;
    checkThcV51Deadlines();
    if (m_operationId != owner || m_thcV51Phase == ThcV51Phase::Inactive)
        return;
    // Production field 4 is retained pidOutput, NOT measured ram velocity.
    // Firmware's typed CANCELLED/DONE plus a subsequent valid, exact IDLE is
    // the stop/completion contract. Do not rewrite either velocity property.
    const bool terminalIdle = exactIdleTelemetry && m_pressTelemetryFresh
        && arrival > m_thcV51TerminalArrival && arrival == m_pressFrameArrival
        && m_pressConnected && m_pressTransport->isOpen() && !m_antiBind
        && m_pressMachineState == QStringLiteral("IDLE")
        && m_pressTelemetrySequence > m_thcV51TerminalTelemetrySequence;
    if (m_thcV51Phase == ThcV51Phase::AwaitCancel) {
        if (m_thcV51CancelAcknowledged && terminalIdle) {
            const QString error = m_pendingThcFailure;
            resetThcV51Operation();
            m_pressSafetyStopUnconfirmed = false;
            emit pressStateChanged();
            m_thcV51CancellationConfirmed = true;
            failActiveCommand(error);
        }
        return;
    }
    if (m_antiBind || MachineProtocolParsers::pressStateIsAlarm(m_pressMachineState)) {
        beginThcV51Cancellation(QStringLiteral("THC_V51_CONTROLLER_ALARM"));
        return;
    }
    if (m_thcV51Phase == ThcV51Phase::AwaitIdle && m_thcV51RunningAcknowledged
        && terminalIdle) {
        resetThcV51Operation();
        completeActivePressCommand();
    }
}

bool MachineControlBackend::connectModule()
{
    m_moduleReconnectDesired = true;
    m_moduleReconnectAttempts = 0;
    m_moduleReconnectTimer.stop();
    return attemptModuleConnection(true);
}

bool MachineControlBackend::attemptModuleConnection(bool reportFailure)
{
    qInfo().noquote() << "MACHINE-CONNECT device=module state=" + moduleConnectionState()
                      << "available=" + QString::number(moduleTransportAvailable())
                      << "endpoint=" + moduleEndpointName();
    if (m_moduleConnectionState == ConnectionState::Faulted) {
        clearModuleState();
        emit moduleStateChanged();
    }
    if (!m_moduleTransport || !m_moduleTransport->isAvailable()) {
        const QString reason = rejectionReasonName(CommandRejectionReason::TransportUnavailable);
        if (reportFailure) {
            emit connectionFailed(QStringLiteral("module"), reason);
            return reject(QStringLiteral("module"), QStringLiteral("connect"),
                          CommandRejectionReason::TransportUnavailable);
        }
        return false;
    }
    if (m_moduleConnectionState != ConnectionState::Disconnected) {
        if (reportFailure)
            return reject(QStringLiteral("module"), QStringLiteral("connect"),
                          CommandRejectionReason::OperationInProgress);
        return false;
    }
    m_moduleConnectionState = ConnectionState::Connecting;
    emit moduleStateChanged();
    if (!m_moduleTransport->open()) {
        const bool transportReportedFailure =
            m_moduleConnectionState == ConnectionState::Faulted;
        clearModuleState();
        emit moduleStateChanged();
        const QString reason = rejectionReasonName(CommandRejectionReason::TransportUnavailable);
        if (reportFailure && !transportReportedFailure) {
            emit connectionFailed(QStringLiteral("module"), reason);
            return reject(QStringLiteral("module"), QStringLiteral("connect"),
                          CommandRejectionReason::TransportUnavailable);
        }
        if (!transportReportedFailure)
            scheduleModuleReconnect();
        return false;
    }
    m_moduleConnected = true;
    m_moduleConnectionState = ConnectionState::Initializing;
    emit moduleStateChanged();
    qInfo().noquote() << "MACHINE-STATE device=module state=INITIALIZING";
    startModuleHandshake();
    return true;
}

bool MachineControlBackend::disconnectModule()
{
    m_moduleReconnectDesired = false;
    m_moduleReconnectAttempts = 0;
    m_moduleReconnectTimer.stop();
    if (!m_moduleConnected)
        return reject(QStringLiteral("module"), QStringLiteral("disconnect"),
                      CommandRejectionReason::NotConnected);
    m_moduleConnectionState = ConnectionState::Disconnecting;
    emit moduleStateChanged();
    m_moduleTransport->close();
    if (m_moduleConnectionState != ConnectionState::Disconnected) {
        clearModuleState();
        emit moduleStateChanged();
    }
    return true;
}

bool MachineControlBackend::resetModule()
{
    return !rejectModuleOperation(QStringLiteral("reset"), true, false);
}

bool MachineControlBackend::moduleHomeBlocked(CommandRejectionReason &reason) const
{
    if (m_moduleConnectionState == ConnectionState::Resetting
        || m_moduleConnectionState == ConnectionState::Disconnecting)
        reason = CommandRejectionReason::Resetting;
    else if (!m_moduleConnected)
        reason = CommandRejectionReason::NotConnected;
    else if (m_moduleConnectionState != ConnectionState::Ready || !m_moduleReady
             || !m_moduleTelemetryFresh
             || (m_moduleState != QStringLiteral("ALARM") && m_moduleState != QStringLiteral("IDLE"))
             || m_moduleLimitX1 || m_moduleLimitX2 || m_moduleLimitR1 || m_moduleLimitR2)
        reason = CommandRejectionReason::NotReady;
    else if (m_moduleOperationActive || commandOperationActive() || m_moduleHomeConcurrent)
        reason = CommandRejectionReason::OperationInProgress;
    else
        return false;
    return true;
}

bool MachineControlBackend::homeAll()
{
    // Press and back gauge home simultaneously. The press owns the global
    // lifecycle; the module home reports with the same id and device "module".
    CommandRejectionReason reason;
    if (moduleHomeBlocked(reason))
        return reject(QStringLiteral("module"), QStringLiteral("home"), reason);
    if (!homePress())
        return false;
    return startModuleHome(true);
}

bool MachineControlBackend::homeModule()
{
    CommandRejectionReason reason;
    if (moduleHomeBlocked(reason))
        return reject(QStringLiteral("module"), QStringLiteral("home"), reason);
    return startModuleHome(false);
}

bool MachineControlBackend::startModuleHome(bool concurrent)
{
    const bool unlockFirst = m_moduleState == QStringLiteral("ALARM");
    m_moduleHomePhase = unlockFirst ? ModuleHomePhase::AwaitUnlockAck
                                    : ModuleHomePhase::AwaitHomeAck;
    m_moduleOperationActive = true;
    m_moduleHomed = false;
    m_moduleHomeConcurrent = concurrent;
    m_moduleConcurrentHomeId = m_operationId;
    if (!concurrent)
        beginHomeOperation(QStringLiteral("module"));
    emit moduleStateChanged();
    const QByteArray frame = unlockFirst ? QByteArrayLiteral("$X\n")
                                         : QByteArrayLiteral("$H\n");
    if (!m_moduleTransport->writeFrame(frame)) {
        if (m_moduleHomePhase != ModuleHomePhase::Idle)
            failModuleHoming(QStringLiteral("HOME_WRITE_FAILED"));
        return false;
    }
    m_moduleHomingTimer.start();
    qInfo().noquote() << "MACHINE-HOME device=module state=SENT phase="
                      << (unlockFirst ? "unlock" : "home");
    return true;
}

bool MachineControlBackend::jogModule(const QString &axis, int direction, double distance,
                                      double speed, bool continuous)
{
    const QString normalizedAxis = axis.trimmed().toUpper();
    if ((normalizedAxis != QStringLiteral("X") && normalizedAxis != QStringLiteral("R"))
        || (direction != -1 && direction != 1) || !std::isfinite(distance)
        || !std::isfinite(speed) || distance <= 0.0 || speed <= 0.0) {
        return reject(QStringLiteral("module"), QStringLiteral("jog"),
                      CommandRejectionReason::InvalidArgument);
    }
    if (distance > 500.0 || speed < 1.0 || speed > 2500.0)
        return reject(QStringLiteral("module"), QStringLiteral("jog"),
                      CommandRejectionReason::InvalidArgument);
    const QString physicalAxis = normalizedAxis == QStringLiteral("X")
        ? QStringLiteral("X") : QStringLiteral("Y");
    if (continuous) {
        const double maximumRate = normalizedAxis == QStringLiteral("X")
            ? m_moduleMaxRateX : m_moduleMaxRateR;
        const double acceleration = normalizedAxis == QStringLiteral("X")
            ? m_moduleAccelerationX : m_moduleAccelerationR;
        if (maximumRate <= 0.0 || acceleration <= 0.0)
            return reject(QStringLiteral("module"), QStringLiteral("jog"),
                          CommandRejectionReason::NotReady);
        const double boundedSpeed = std::min(speed, maximumRate);
        const double velocityPerSecond = boundedSpeed / 60.0;
        const double segmentTime = std::max(2.0 * velocityPerSecond / acceleration, 0.15);
        // ~40 ms segments, several queued (see kContinuousJogFramesInFlight):
        // the 0x85 cancel flushes the planner, so stop latency is unchanged
        // while serial/event-loop round trips no longer starve motion.
        distance = velocityPerSecond * segmentTime / 4.0;
        speed = boundedSpeed;
    }
    const QByteArray frame = QStringLiteral("$J=G20 G91 %1%2 F %3\n")
        .arg(physicalAxis).arg(direction * distance, 0, 'f', 4)
        .arg(qRound(speed)).toLatin1();
    if (continuous && m_moduleCommandPhase == ModuleCommandPhase::ContinuousJogging
        && m_operationDevice == QStringLiteral("module")
        && m_moduleContinuousAxis == normalizedAxis
        && m_moduleContinuousDirection == direction) {
        // Already streaming this hold; the ACK loop keeps the queue full.
        return true;
    }
    if (!admitModuleMotion(QStringLiteral("jog")))
        return false;
    beginCommandOperation(QStringLiteral("module"), continuous
                          ? QStringLiteral("continuous-jog") : QStringLiteral("jog"));
    m_moduleCommandFrames = {frame};
    m_moduleCommandFrameIndex = 0;
    m_moduleContinuousAxis = normalizedAxis;
    m_moduleContinuousDirection = direction;
    m_moduleTargetX = m_moduleWorkX + (normalizedAxis == QStringLiteral("X")
        ? direction * distance : 0.0);
    m_moduleTargetR = m_moduleWorkR + (normalizedAxis == QStringLiteral("R")
        ? direction * distance : 0.0);
    m_moduleTargetRequired = !continuous;
    m_moduleCommandPhase = continuous ? ModuleCommandPhase::ContinuousJogging
                                      : ModuleCommandPhase::AwaitFirstAck;
    m_moduleOperationActive = true;
    emit moduleStateChanged();
    m_commandDeadlineTimer.setInterval(continuous ? 300000 : 30000);
    m_commandDeadlineTimer.start();
    // 3 x ~32-byte frames stays inside GRBL's 128-byte RX buffer.
    constexpr int kContinuousJogFramesInFlight = 3;
    const int initialFrames = continuous ? kContinuousJogFramesInFlight : 1;
    m_moduleContinuousInFlight = 0;
    m_moduleJogCancelPending = false;
    for (int i = 0; i < initialFrames; ++i) {
        if (!m_moduleTransport->writeFrame(frame)) {
            failActiveCommand(QStringLiteral("JOG_WRITE_FAILED"));
            return false;
        }
        ++m_moduleContinuousInFlight;
    }
    return true;
}

bool MachineControlBackend::moveModule(double x, double r, double speed)
{
    if (!std::isfinite(x) || !std::isfinite(r) || !std::isfinite(speed) || speed <= 0.0)
        return reject(QStringLiteral("module"), QStringLiteral("move"),
                      CommandRejectionReason::InvalidArgument);
    if (speed < 1.0 || speed > 2500.0)
        return reject(QStringLiteral("module"), QStringLiteral("move"),
                      CommandRejectionReason::InvalidArgument);
    if (!admitModuleMotion(QStringLiteral("move")))
        return false;
    const QString system = m_moduleCoordinateSystem;
    const QByteArray xFrame = QStringLiteral("G20 G90 %1 G1 X%2 F%3\n")
        .arg(system).arg(x, 0, 'f', 4).arg(speed, 0, 'f', 2).toLatin1();
    const QByteArray rFrame = QStringLiteral("G20 G90 %1 G1 Y%2 F%3\n")
        .arg(system).arg(r, 0, 'f', 4).arg(speed, 0, 'f', 2).toLatin1();
    m_moduleCommandFrames = m_moduleWorkX > x ? QList<QByteArray>{rFrame, xFrame}
                                               : QList<QByteArray>{xFrame, rFrame};
    m_moduleCommandFrameIndex = 0;
    m_moduleTargetX = x;
    m_moduleTargetR = r;
    m_moduleTargetRequired = true;
    m_moduleCommandPhase = ModuleCommandPhase::AwaitFirstAck;
    m_moduleOperationActive = true;
    beginCommandOperation(QStringLiteral("module"), QStringLiteral("move"));
    emit moduleStateChanged();
    m_commandDeadlineTimer.setInterval(120000);
    m_commandDeadlineTimer.start();
    return writeNextModuleFrame();
}

bool MachineControlBackend::incrementModule(const QString &axis, double distance, double speed)
{
    const QString normalizedAxis = axis.trimmed().toUpper();
    const QString operation = QStringLiteral("increment");
    if ((normalizedAxis != QStringLiteral("X") && normalizedAxis != QStringLiteral("R"))
        || !std::isfinite(distance) || !std::isfinite(speed) || distance == 0.0
        || std::abs(distance) > 10.0 || speed < 1.0 || speed > 2500.0) {
        return reject(QStringLiteral("module"), operation,
                      CommandRejectionReason::InvalidArgument);
    }
    if (!admitModuleMotion(operation))
        return false;
    const QString physicalAxis = normalizedAxis == QStringLiteral("X")
        ? QStringLiteral("X") : QStringLiteral("Y");
    const QByteArray frame = QStringLiteral("G20 G91 %1 %2 %3 F %4\n")
        .arg(m_moduleCoordinateSystem).arg(physicalAxis)
        .arg(distance, 0, 'f', 4).arg(speed, 0, 'f', 2).toLatin1();
    beginCommandOperation(QStringLiteral("module"), operation);
    m_moduleCommandFrames = {frame};
    m_moduleCommandFrameIndex = 0;
    m_moduleTargetX = m_moduleWorkX
        + (normalizedAxis == QStringLiteral("X") ? distance : 0.0);
    m_moduleTargetR = m_moduleWorkR
        + (normalizedAxis == QStringLiteral("R") ? distance : 0.0);
    m_moduleTargetRequired = true;
    m_moduleCommandPhase = ModuleCommandPhase::AwaitFirstAck;
    m_moduleOperationActive = true;
    emit moduleStateChanged();
    m_commandDeadlineTimer.setInterval(30000);
    m_commandDeadlineTimer.start();
    return writeNextModuleFrame();
}

bool MachineControlBackend::selectModuleCoordinateSystem(const QString &system)
{
    const QString normalized = system.trimmed().toUpper();
    static const QRegularExpression pattern(QStringLiteral("^G5[4-9]$"));
    if (!pattern.match(normalized).hasMatch())
        return reject(QStringLiteral("module"), QStringLiteral("select-coordinate"),
                      CommandRejectionReason::InvalidArgument);
    if (!admitModuleMotion(QStringLiteral("select-coordinate")))
        return false;
    beginCommandOperation(QStringLiteral("module"), QStringLiteral("select-coordinate"));
    m_moduleCommandFrames = {normalized.toLatin1() + '\n'};
    m_moduleCommandFrameIndex = 0;
    m_moduleTargetRequired = false;
    m_moduleCoordinateSystem = normalized;
    m_moduleCommandPhase = ModuleCommandPhase::AwaitFirstAck;
    m_moduleOperationActive = true;
    emit moduleStateChanged();
    m_commandDeadlineTimer.setInterval(10000);
    m_commandDeadlineTimer.start();
    return writeNextModuleFrame();
}

bool MachineControlBackend::setModuleWorkPosition(const QString &system, const QString &axis,
                                                  double value)
{
    const QString normalizedSystem = system.trimmed().toUpper();
    const QString normalizedAxis = axis.trimmed().toUpper();
    static const QRegularExpression pattern(QStringLiteral("^G5([4-9])$"));
    const QRegularExpressionMatch match = pattern.match(normalizedSystem);
    if (!match.hasMatch() || (normalizedAxis != QStringLiteral("X")
        && normalizedAxis != QStringLiteral("R")) || !std::isfinite(value)) {
        return reject(QStringLiteral("module"), QStringLiteral("set-coordinate"),
                      CommandRejectionReason::InvalidArgument);
    }
    if (!admitModuleMotion(QStringLiteral("set-coordinate")))
        return false;
    const int coordinateIndex = match.captured(1).toInt() - 3;
    const QString physicalAxis = normalizedAxis == QStringLiteral("X")
        ? QStringLiteral("X") : QStringLiteral("Y");
    beginCommandOperation(QStringLiteral("module"), QStringLiteral("set-coordinate"));
    m_moduleCommandFrames = {QStringLiteral("G20 G10 P%1 L20 %2 %3\n")
        .arg(coordinateIndex).arg(physicalAxis).arg(value, 0, 'f', 4).toLatin1()};
    m_moduleCommandFrameIndex = 0;
    m_moduleTargetRequired = false;
    m_moduleCommandPhase = ModuleCommandPhase::AwaitFirstAck;
    m_moduleOperationActive = true;
    emit moduleStateChanged();
    m_commandDeadlineTimer.setInterval(10000);
    m_commandDeadlineTimer.start();
    return writeNextModuleFrame();
}

bool MachineControlBackend::stopModule()
{
    const QString operation = QStringLiteral("stop");
    if (!m_moduleConnected)
        return reject(QStringLiteral("module"), operation, CommandRejectionReason::NotConnected);
    if (m_moduleConnectionState != ConnectionState::Ready)
        return reject(QStringLiteral("module"), operation, CommandRejectionReason::NotReady);
    if (m_thcV51Phase != ThcV51Phase::Inactive || thcContinuousActive()) {
        const auto owner = m_operationId;
        const bool continuous = thcContinuousActive();
        // Urgent module feed-hold must not steal the THC global lifecycle or
        // reset its cancellation watchdog. No module reset is queued here.
        const bool held = (m_moduleTelemetryFresh && m_moduleState == QStringLiteral("IDLE"))
            || m_moduleTransport->writeFrame(QByteArrayLiteral("!"));
        // A transport error/close may be delivered reentrantly during write.
        // Its device-scoped handler must not fail the still-owned press cycle.
        const bool moduleAccepted = held && m_moduleConnected
            && m_moduleConnectionState == ConnectionState::Ready && m_moduleTransport->isOpen();
        if (m_operationId != owner) return false; // Never cancel a replacement owner/Home.
        const QString reason = (continuous ? QStringLiteral("THC_V53_MODULE_STOP")
                                           : QStringLiteral("THC_V51_MODULE_STOP"))
            + (moduleAccepted ? QString() : QStringLiteral("_FEED_HOLD_WRITE_FAILED"));
        const bool cancelAccepted = continuous ? beginThcV53Cancellation(reason)
                                               : beginThcV51Cancellation(reason);
        // True means the safety requests were accepted, not that either device
        // has stopped. Press ownership lasts through CANCELLED + fresh IDLE.
        return moduleAccepted && cancelAccepted;
    }
    if (m_moduleHomeConcurrent) {
        // Combined Home: the press owns the global lifecycle. Feed-hold the
        // module without stealing it; module homing reports its own failure.
        return m_moduleTransport->writeFrame(QByteArrayLiteral("!"));
    }
    if (m_moduleCommandPhase == ModuleCommandPhase::ContinuousJogging) {
        m_moduleCommandPhase = ModuleCommandPhase::AwaitJogIdle;
        m_moduleContinuousAxis.clear();
        m_moduleContinuousDirection = 0;
        m_commandDeadlineTimer.setInterval(10000);
        m_commandDeadlineTimer.start();
        // GRBL 1.1 jog-cancel flushes the planner but NOT $J lines still in
        // its serial RX buffer; those would run after the cancel (overshoot).
        // Stop refilling, wait for every queued line's ok/error, then cancel.
        if (m_moduleContinuousInFlight > 0) {
            m_moduleJogCancelPending = true;
            return true;
        }
        if (!m_moduleTransport->writeFrame(QByteArrayLiteral("\x85"))) {
            failActiveCommand(QStringLiteral("JOG_CANCEL_WRITE_FAILED"));
            return false;
        }
        m_commandDeadlineTimer.setInterval(10000);
        m_commandDeadlineTimer.start();
        return true;
    }
    if (commandOperationActive())
        finishCommandOperation(QStringLiteral("CANCEL_REQUESTED"));
    beginCommandOperation(QStringLiteral("module"), operation);
    m_moduleHomedBeforeStop = m_moduleHomed;
    const bool alreadyIdle = m_moduleState == QStringLiteral("IDLE");
    m_moduleCommandPhase = alreadyIdle ? ModuleCommandPhase::StopAwaitResetWelcome
                                       : ModuleCommandPhase::StopAwaitHold;
    m_moduleOperationActive = true;
    if (alreadyIdle) {
        m_moduleConnectionState = ConnectionState::Resetting;
        m_moduleReady = false;
    }
    emit moduleStateChanged();
    const QByteArray frame = alreadyIdle ? QByteArrayLiteral("\x18")
                                         : QByteArrayLiteral("!");
    if (!m_moduleTransport->writeFrame(frame)) {
        failActiveCommand(alreadyIdle ? QStringLiteral("RESET_WRITE_FAILED")
                                      : QStringLiteral("FEED_HOLD_WRITE_FAILED"));
        return false;
    }
    m_commandDeadlineTimer.setInterval(30000);
    m_commandDeadlineTimer.start();
    return true;
}

QString MachineControlBackend::connectionStateName(ConnectionState state)
{
    switch (state) {
    case ConnectionState::Disconnected: return QStringLiteral("DISCONNECTED");
    case ConnectionState::Connecting: return QStringLiteral("CONNECTING");
    case ConnectionState::Initializing: return QStringLiteral("INITIALIZING");
    case ConnectionState::Ready: return QStringLiteral("READY");
    case ConnectionState::Resetting: return QStringLiteral("RESETTING");
    case ConnectionState::Disconnecting: return QStringLiteral("DISCONNECTING");
    case ConnectionState::Faulted: return QStringLiteral("FAULTED");
    }
    return QStringLiteral("UNKNOWN");
}

QString MachineControlBackend::rejectionReasonName(CommandRejectionReason reason)
{
    switch (reason) {
    case CommandRejectionReason::None: return QString();
    case CommandRejectionReason::TransportUnavailable: return QStringLiteral("TRANSPORT_UNAVAILABLE");
    case CommandRejectionReason::NotConnected: return QStringLiteral("NOT_CONNECTED");
    case CommandRejectionReason::NotReady: return QStringLiteral("NOT_READY");
    case CommandRejectionReason::NotHomed: return QStringLiteral("NOT_HOMED");
    case CommandRejectionReason::OperationInProgress: return QStringLiteral("OPERATION_IN_PROGRESS");
    case CommandRejectionReason::Resetting: return QStringLiteral("RESETTING");
    case CommandRejectionReason::InvalidArgument: return QStringLiteral("INVALID_ARGUMENT");
    case CommandRejectionReason::CommandDisabled: return QStringLiteral("COMMAND_DISABLED");
    }
    return QStringLiteral("UNKNOWN");
}

bool MachineControlBackend::reject(const QString &device, const QString &operation,
                                   CommandRejectionReason reason)
{
    m_lastRejectedOperation = device + QLatin1Char(':') + operation;
    m_lastRejectReason = rejectionReasonName(reason);
    emit lastRejectChanged();
    emit operationRejected(device, operation, m_lastRejectReason);
    if (device == QStringLiteral("press")) {
        m_pressTelemetryRecorder->recordError(QStringLiteral("OPERATION_REJECTED"),
                                               operation + QLatin1Char(':') + m_lastRejectReason);
    }
    recordRejectedCommand(device, operation, reason);
    return false;
}

void MachineControlBackend::recordRejectedCommand(const QString &device,
                                                  const QString &operation,
                                                  CommandRejectionReason reason)
{
    // A rejected secondary action must not erase an accepted homing operation's
    // lifecycle authority while the controller is still moving.
    if (commandOperationActive())
        return;
    ++m_operationId;
    m_operationDevice = device;
    m_operationName = operation;
    m_operationState = QStringLiteral("REJECTED");
    m_operationError = rejectionReasonName(reason);
    emit commandLifecycleChanged();
    emit commandOperationFinished(m_operationId, m_operationDevice, m_operationName,
                                  m_operationState, m_operationError);
}

void MachineControlBackend::beginHomeOperation(const QString &device)
{
    if (device == QStringLiteral("press")) {
        invalidateThcLiveTuning(QStringLiteral("V53_QUERY_REQUIRED_AFTER_HOME"), false, false);
        // Finalize the Home owner before notifying property subscribers.
    }
    resetThcV51Operation();
    ++m_operationId;
    m_operationDevice = device;
    m_operationName = QStringLiteral("home");
    m_operationState = QStringLiteral("SENT");
    m_operationError.clear();
    emit commandLifecycleChanged();
    if (device == QStringLiteral("press")) {
        emit thcLiveTuningChanged();
        emit thcLiveDiagnosticsChanged();
    }
}

void MachineControlBackend::finishHomeOperation(const QString &device, const QString &state,
                                                const QString &error)
{
    if (device == QStringLiteral("press")) {
        m_pressHomingTimer.stop();
        m_pressHomePending = false;
        m_pressHomeProgressObserved = false;
        m_pressHomeInitialState.clear();
        m_pressOperationActive = false;
    } else {
        m_moduleHomingTimer.stop();
        m_moduleHomePhase = ModuleHomePhase::Idle;
        m_moduleOperationActive = false;
        if (m_moduleHomeConcurrent) {
            m_moduleHomeConcurrent = false;
            emit commandOperationFinished(m_moduleConcurrentHomeId, device,
                                          QStringLiteral("home"), state, error);
            return;
        }
    }
    if (m_operationDevice != device || m_operationName != QStringLiteral("home")
        || !commandOperationActive())
        return;
    m_operationState = state;
    m_operationError = error;
    emit commandLifecycleChanged();
    emit commandOperationFinished(m_operationId, m_operationDevice, m_operationName,
                                  m_operationState, m_operationError);
}

void MachineControlBackend::beginPressHomingSafetyFailure(const QString &reason)
{
    if (!m_pressHomePending
        || m_pressCommandPhase == PressCommandPhase::AwaitHomeFailureStopIdle)
        return;

    m_pressHomingTimer.stop();
    m_pendingPressHomeFailure = reason;
    m_pressCommandPhase = PressCommandPhase::AwaitHomeFailureStopIdle;
    m_pressStopAcknowledged = false;
    m_pressHomeProgressObserved = false;
    m_pressSafetyStopUnconfirmed = true;
    m_pressOperationActive = true;
    emit pressStateChanged();

    if (!m_pressTransport->isOpen()
        || !m_pressTransport->writeFrame(QByteArrayLiteral("<stop>\n"))) {
        m_pressCommandPhase = PressCommandPhase::Idle;
        failPressHoming(reason + QStringLiteral("_STOP_WRITE_FAILED"));
        return;
    }
    m_commandDeadlineTimer.setInterval(10000);
    m_commandDeadlineTimer.start();
}

void MachineControlBackend::tryCompletePressHomingSafetyFailure()
{
    if (m_pressCommandPhase != PressCommandPhase::AwaitHomeFailureStopIdle
        || !m_pressStopAcknowledged)
        return;

    const bool terminalTelemetry = m_pressHomeProgressObserved &&
        (m_pressMachineState == QStringLiteral("STARTUP_HOMING_REQUIRED")
         || m_pressMachineState == QStringLiteral("IDLE")
         || (MachineProtocolParsers::pressStateIsAlarm(m_pressMachineState)
             && m_ramVelocity == 0.0));
    if (!terminalTelemetry)
        return;

    const QString reason = m_pendingPressHomeFailure.isEmpty()
        ? QStringLiteral("HOMING_FAILED") : m_pendingPressHomeFailure;
    m_commandDeadlineTimer.stop();
    m_pressCommandPhase = PressCommandPhase::Idle;
    m_pendingPressHomeFailure.clear();
    m_pressSafetyStopUnconfirmed = false;
    emit pressStateChanged();
    // A Home timeout retains the existing fail-closed reconnect behavior.
    // A controller-reported alarm already arrived through a healthy link, so
    // preserve that transport after STOP + terminal telemetry are confirmed.
    failPressHoming(reason, reason == QStringLiteral("HOMING_TIMEOUT"));
}

void MachineControlBackend::failPressHoming(const QString &reason, bool closeTransport)
{
    if (!m_pressHomePending)
        return;
    qWarning().noquote() << "MACHINE-HOME device=press state=FAILED reason=" + reason;
    m_pressHomed = false;
    finishHomeOperation(QStringLiteral("press"), QStringLiteral("FAILED"), reason);
    emit pressStateChanged();
    if (closeTransport && m_pressTransport->isOpen())
        m_pressTransport->close();
}

void MachineControlBackend::failModuleHoming(const QString &reason, bool closeTransport)
{
    if (m_moduleHomePhase == ModuleHomePhase::Idle)
        return;
    qWarning().noquote() << "MACHINE-HOME device=module state=FAILED reason=" + reason;
    m_moduleHomed = false;
    finishHomeOperation(QStringLiteral("module"), QStringLiteral("FAILED"), reason);
    emit moduleStateChanged();
    if (closeTransport && m_moduleTransport->isOpen())
        m_moduleTransport->close();
}

bool MachineControlBackend::rejectPressOperation(const QString &operation, bool requireReady,
                                                 bool requireHomed)
{
    if (m_pressConnectionState == ConnectionState::Resetting
        || m_pressConnectionState == ConnectionState::Disconnecting) {
        reject(QStringLiteral("press"), operation, CommandRejectionReason::Resetting);
        return true;
    }
    if (!m_pressConnected) {
        reject(QStringLiteral("press"), operation, CommandRejectionReason::NotConnected);
        return true;
    }
    if (requireReady && !m_pressReady) {
        reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
        return true;
    }
    if (requireHomed && !m_pressHomed) {
        reject(QStringLiteral("press"), operation, CommandRejectionReason::NotHomed);
        return true;
    }
    if (m_pressOperationActive) {
        reject(QStringLiteral("press"), operation, CommandRejectionReason::OperationInProgress);
        return true;
    }
    // Deliberately fail closed. Read-only identity, telemetry, freshness, and
    // lifecycle authority are implemented, but production motion encoders and
    // ACK correlation have not yet been proven against replay fixtures.
    reject(QStringLiteral("press"), operation, CommandRejectionReason::CommandDisabled);
    return true;
}

bool MachineControlBackend::rejectModuleOperation(const QString &operation, bool requireReady,
                                                  bool requireHomed)
{
    if (m_moduleConnectionState == ConnectionState::Resetting
        || m_moduleConnectionState == ConnectionState::Disconnecting) {
        reject(QStringLiteral("module"), operation, CommandRejectionReason::Resetting);
        return true;
    }
    if (!m_moduleConnected) {
        reject(QStringLiteral("module"), operation, CommandRejectionReason::NotConnected);
        return true;
    }
    if (requireReady && !m_moduleReady) {
        reject(QStringLiteral("module"), operation, CommandRejectionReason::NotReady);
        return true;
    }
    if (requireHomed && !m_moduleHomed) {
        reject(QStringLiteral("module"), operation, CommandRejectionReason::NotHomed);
        return true;
    }
    if (m_moduleOperationActive) {
        reject(QStringLiteral("module"), operation, CommandRejectionReason::OperationInProgress);
        return true;
    }
    reject(QStringLiteral("module"), operation, CommandRejectionReason::CommandDisabled);
    return true;
}

bool MachineControlBackend::admitPressMotion(const QString &operation)
{
    if (thcLiveTuningPending())
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::OperationInProgress);
    if (m_pressConnected && m_pressConnectionState == ConnectionState::Ready
        && !pressMotionFirmwareSupported(operation))
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::CommandDisabled);
    if (m_pressSafetyStopUnconfirmed)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    if (m_pressConnectionState == ConnectionState::Resetting
        || m_pressConnectionState == ConnectionState::Disconnecting)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::Resetting);
    if (!m_pressConnected)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotConnected);
    if (m_pressConnectionState != ConnectionState::Ready || !m_pressReady
        || !m_pressTelemetryFresh || m_pressMachineState != QStringLiteral("IDLE"))
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    if (!m_pressHomed)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotHomed);
    if (m_pressOperationActive || commandOperationActive() || m_thcTuningQueryPending
        || m_moduleHomeConcurrent)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::OperationInProgress);
    return true;
}

bool MachineControlBackend::admitPressConfiguration(const QString &operation)
{
    if (thcLiveTuningPending())
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::OperationInProgress);
    if (m_pressSafetyStopUnconfirmed)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    if (m_pressConnectionState == ConnectionState::Resetting
        || m_pressConnectionState == ConnectionState::Disconnecting)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::Resetting);
    if (!m_pressConnected)
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotConnected);
    if (m_pressConnectionState != ConnectionState::Ready || !m_pressReady
        || !m_pressTelemetryFresh || m_pressMachineState == QStringLiteral("UNKNOWN"))
        return reject(QStringLiteral("press"), operation, CommandRejectionReason::NotReady);
    if (m_pressOperationActive || commandOperationActive() || m_thcTuningQueryPending)
        return reject(QStringLiteral("press"), operation,
                      CommandRejectionReason::OperationInProgress);
    return true;
}

bool MachineControlBackend::isTonnageHoldPhase() const
{
    return m_pressCommandPhase == PressCommandPhase::NativeTonnageHold
        || m_pressCommandPhase == PressCommandPhase::LegacyTonnageApproach
        || m_pressCommandPhase == PressCommandPhase::LegacyTonnageAwaitApproachIdle
        || m_pressCommandPhase == PressCommandPhase::LegacyTonnageFineJog
        || m_pressCommandPhase == PressCommandPhase::LegacyTonnageMonitoring
        || m_pressCommandPhase == PressCommandPhase::TonnageHoldAwaitStopIdle;
}

void MachineControlBackend::scheduleLegacyTonnageAdjustment(int delayMs)
{
    if (m_pressCommandPhase == PressCommandPhase::LegacyTonnageMonitoring) {
        m_commandDeadlineTimer.stop();
        m_tonnageHoldTimer.start(qMax(0, delayMs));
    }
}

void MachineControlBackend::evaluateLegacyTonnageHold()
{
    if (m_pressCommandPhase != PressCommandPhase::LegacyTonnageMonitoring)
        return;
    if (!m_pressConnected || !m_pressReady || !m_pressTelemetryFresh
        || !m_manualModeEnabled || m_pressMachineState != QStringLiteral("IDLE")) {
        beginPressSafetyFailure(QStringLiteral("TONNAGE_HOLD_NOT_READY"),
                                QByteArrayLiteral("<stop>\n"));
        return;
    }

    const double totalTonnage = m_ramLoadY1 + m_ramLoadY2;
    if (!std::isfinite(totalTonnage) || totalTonnage > 24.0) {
        beginPressSafetyFailure(QStringLiteral("TONNAGE_LIMIT_EXCEEDED"),
                                QByteArrayLiteral("<stop>\n"));
        return;
    }
    const double error = m_tonnageHoldTarget - totalTonnage;
    if (std::abs(error) <= 0.05) {
        scheduleLegacyTonnageAdjustment(200);
        return;
    }

    const double current = (m_ramPositionY1 + m_ramPositionY2) * 0.5;
    const double target = current + (error > 0.0 ? -0.001 : 0.001);
    if (target < -4.0 || target > -0.05) {
        beginPressSafetyFailure(QStringLiteral("TONNAGE_HOLD_TRAVEL_LIMIT"),
                                QByteArrayLiteral("<stop>\n"));
        return;
    }
    m_pressCommandPhase = PressCommandPhase::LegacyTonnageFineJog;
    m_pressCommandProgressObserved = false;
    const QString type = error > 0.0 ? QStringLiteral("safety") : QStringLiteral("retract");
    const QByteArray frame = QStringLiteral("<%1, 0.5000, %2>\n")
        .arg(target, 0, 'f', 4).arg(type).toLatin1();
    writePressCommand(frame, m_operationName);
}

bool MachineControlBackend::admitModuleMotion(const QString &operation)
{
    if (m_moduleConnectionState == ConnectionState::Resetting
        || m_moduleConnectionState == ConnectionState::Disconnecting)
        return reject(QStringLiteral("module"), operation, CommandRejectionReason::Resetting);
    if (!m_moduleConnected)
        return reject(QStringLiteral("module"), operation, CommandRejectionReason::NotConnected);
    if (m_moduleConnectionState != ConnectionState::Ready || !m_moduleReady
        || !m_moduleTelemetryFresh || m_moduleState != QStringLiteral("IDLE"))
        return reject(QStringLiteral("module"), operation, CommandRejectionReason::NotReady);
    if (!m_moduleHomed)
        return reject(QStringLiteral("module"), operation, CommandRejectionReason::NotHomed);
    if (m_moduleOperationActive || commandOperationActive())
        return reject(QStringLiteral("module"), operation,
                      CommandRejectionReason::OperationInProgress);
    return true;
}

void MachineControlBackend::beginCommandOperation(const QString &device,
                                                  const QString &operation)
{
    resetThcV51Operation();
    m_thcV51CancellationConfirmed = false;
    m_originalManualStop = false;
    ++m_operationId;
    m_operationDevice = device;
    m_operationName = operation;
    m_operationState = QStringLiteral("SENT");
    m_operationError.clear();
    emit commandLifecycleChanged();
}

void MachineControlBackend::acknowledgeCommandOperation()
{
    if (!commandOperationActive() || m_operationState == QStringLiteral("ACKNOWLEDGED"))
        return;
    m_operationState = QStringLiteral("ACKNOWLEDGED");
    emit commandLifecycleChanged();
}

void MachineControlBackend::finishCommandOperation(const QString &state,
                                                   const QString &error)
{
    if (!commandOperationActive())
        return;
    const bool stopWasUnconfirmed = m_pressSafetyStopUnconfirmed;
    const bool continuous = thcContinuousActive();
    if (continuous) {
        m_pressSafetyStopUnconfirmed = true;
        resetThcV53Operation();
        invalidateThcLiveTuning(QStringLiteral("V53_OWNER_LOST"), false, false);
    }
    if (m_thcV51Phase != ThcV51Phase::Inactive) {
        m_pressSafetyStopUnconfirmed = true;
        resetThcV51Operation();
    }
    if (m_operationDevice == QStringLiteral("press")
        && (state == QStringLiteral("FAILED") || state == QStringLiteral("REJECTED"))) {
        m_pressTelemetryRecorder->recordError(QStringLiteral("OPERATION"),
                                               m_operationName + QLatin1Char(':')
                                                   + state + QLatin1Char(':') + error);
    }
    m_commandDeadlineTimer.stop();
    m_operationState = state;
    m_operationError = error;
    if (m_operationDevice == QStringLiteral("press")
        && (m_operationName == QStringLiteral("thc-contact-profile-v51")
            || m_operationName == QStringLiteral("thc-contact-profile-v53"))
        && (state == QStringLiteral("FAILED") || state == QStringLiteral("REJECTED"))) {
        // Finalize presentation before lifecycle subscribers can inspect it or
        // start recovery Home. IDLE/NOT_ACTIVE alone never clears this latch.
        m_thcCommissioningState = m_pressSafetyStopUnconfirmed
            ? QStringLiteral("FAILED_STOP_UNCONFIRMED") : QStringLiteral("FAILED");
        if (m_pressSafetyStopUnconfirmed)
            m_thcV51CancellationConfirmed = false;
    }
    // Direct lifecycle subscribers may start a recovery operation. Terminal
    // evidence must always retain the owner and values finalized here.
    const auto id = m_operationId;
    const QString device = m_operationDevice;
    const QString name = m_operationName;
    const QString terminalState = m_operationState;
    const QString terminalError = m_operationError;
    if (stopWasUnconfirmed != m_pressSafetyStopUnconfirmed)
        emit pressStateChanged();
    emit commandLifecycleChanged();
    emit commandOperationFinished(id, device, name, terminalState, terminalError);
    if (continuous) {
        emit thcContinuousActiveChanged();
        emit thcLiveTuningChanged();
        emit thcLiveDiagnosticsChanged();
    }
}

void MachineControlBackend::failActiveCommand(const QString &error)
{
    QString failure = error;
    const bool stopWasUnconfirmed = m_pressSafetyStopUnconfirmed;
    const bool continuous = thcContinuousActive();
    if (continuous) {
        if (!m_thcV53Failure.isEmpty() && !failure.startsWith(m_thcV53Failure))
            failure = m_thcV53Failure + QLatin1Char('_') + failure;
        m_pressSafetyStopUnconfirmed = true;
        resetThcV53Operation();
        invalidateThcLiveTuning(m_thcLiveTuningError.isEmpty()
            ? QStringLiteral("V53_OPERATION_FAILED") : m_thcLiveTuningError, false, false);
    }
    if (m_thcV51Phase != ThcV51Phase::Inactive) {
        m_pressSafetyStopUnconfirmed = true;
        resetThcV51Operation();
    }
    const QString device = m_operationDevice;
    if (device == QStringLiteral("press")) {
        revokePrimingLatchPresentation();
        m_tonnageHoldTimer.stop();
        m_tonnageHoldHeartbeatTimer.stop();
        m_originalManualStop = false;
        m_pressCommandPhase = PressCommandPhase::Idle;
        m_allowPressStopIdleRace = false;
        m_pressStopAcknowledged = false;
        m_pressCommandProgressObserved = false;
        m_pendingPressFailure.clear();
        m_pendingThcFailure.clear();
        m_thcContactProfileActive = false;
        m_thcContactProfileAutomaticLifecycle = false;
        m_thcContactProfileHeartbeatTimer.stop();
        m_toolChangeMode.clear();
        m_pressOperationActive = false;
    } else if (device == QStringLiteral("module")) {
        m_moduleCommandPhase = ModuleCommandPhase::Idle;
        m_moduleCommandFrames.clear();
        m_moduleCommandFrameIndex = 0;
        m_moduleContinuousAxis.clear();
        m_moduleContinuousDirection = 0;
        m_moduleOperationActive = false;
    }
    // A physical Run admission cannot survive a failed constituent operation.
    // QML also calls endProgramRun(), but native cleanup must remain authoritative
    // when transport or timeout failures occur before QML can react.
    m_programRunActive = false;
    if (stopWasUnconfirmed != m_pressSafetyStopUnconfirmed)
        emit pressStateChanged();
    finishCommandOperation(QStringLiteral("FAILED"), failure);
    if (continuous) {
        emit thcContinuousActiveChanged();
        emit thcLiveTuningChanged();
        emit thcLiveDiagnosticsChanged();
    }
    if (device == QStringLiteral("press"))
        emit pressStateChanged();
    else if (device == QStringLiteral("module"))
        emit moduleStateChanged();
}

bool MachineControlBackend::pressPhaseRequiresSafetyStop() const
{
    return m_pressCommandPhase == PressCommandPhase::AwaitProgress
        || m_pressCommandPhase == PressCommandPhase::AwaitIdle
        || m_pressCommandPhase == PressCommandPhase::AwaitHoldIdle
        || m_pressCommandPhase == PressCommandPhase::StrokeAwaitRetract
        || m_pressCommandPhase == PressCommandPhase::StrokeAwaitBend
        || m_pressCommandPhase == PressCommandPhase::NativeTonnageHold
        || m_pressCommandPhase == PressCommandPhase::LegacyTonnageApproach
        || m_pressCommandPhase == PressCommandPhase::LegacyTonnageAwaitApproachIdle
        || m_pressCommandPhase == PressCommandPhase::LegacyTonnageFineJog
        || m_pressCommandPhase == PressCommandPhase::LegacyTonnageMonitoring;
}

void MachineControlBackend::beginPressSafetyFailure(const QString &error,
                                                     const QByteArray &frame)
{
    revokePrimingLatchPresentation();
    m_tonnageHoldTimer.stop();
    m_pendingPressFailure = error;
    m_pressCommandPhase = PressCommandPhase::AwaitFailureStopIdle;
    m_pressCommandProgressObserved = false;
    m_pressStopAcknowledged = false;
    m_pressOperationActive = true;
    m_pressSafetyStopUnconfirmed = true;
    emit pressStateChanged();
    const QByteArray safetyFrame = originalManualFirmware()
        ? prepareOriginalManualStop(false) : frame;
    if (!m_pressTransport->isOpen() || !m_pressTransport->writeFrame(safetyFrame)) {
        failActiveCommand(error + QStringLiteral("_SAFETY_WRITE_FAILED"));
        return;
    }
    m_commandDeadlineTimer.setInterval(m_originalManualStop ? 30000 : 10000);
    m_commandDeadlineTimer.start();
}

bool MachineControlBackend::writePressCommand(const QByteArray &frame,
                                              const QString &operation)
{
    if (originalManualFirmware()) {
        m_originalCommandEchoSeen = false;
        m_originalTelemetryDrainBytes = 0;
        m_originalExpectedEcho = "[RECEIVED STRING: " + frame.trimmed().mid(1);
        m_originalExpectedEcho.chop(1);
        m_originalExpectedEcho += ']';
    }
    if (!m_pressTransport->writeFrame(frame)) {
        failActiveCommand(operation.toUpper().replace(QLatin1Char('-'), QLatin1Char('_'))
                          + QStringLiteral("_WRITE_FAILED"));
        return false;
    }
    m_commandDeadlineTimer.setInterval(120000);
    m_commandDeadlineTimer.start();
    return true;
}

void MachineControlBackend::continueManualStrokeAfterSetting()
{
    const double current = (m_ramPositionY1 + m_ramPositionY2) * 0.5;
    if (std::abs(current - m_pressStrokeRetractTarget) <= 0.002) {
        m_pressCommandPhase = PressCommandPhase::StrokeAwaitBend;
        m_pressCommandProgressObserved = false;
        const QByteArray bendFrame = QStringLiteral("<%1, %2, bend>\n")
            .arg(m_pressStrokeBendTarget, 0, 'f', 4)
            .arg(m_pressStrokeBendSpeed, 0, 'f', 4).toLatin1();
        writePressCommand(bendFrame, m_operationName);
        return;
    }
    const QString type = current < m_pressStrokeRetractTarget
        ? QStringLiteral("retract") : QStringLiteral("safety");
    m_pressCommandPhase = PressCommandPhase::StrokeAwaitRetract;
    m_pressCommandProgressObserved = false;
    const QByteArray retractFrame = QStringLiteral("<%1, %2, %3>\n")
        .arg(m_pressStrokeRetractTarget, 0, 'f', 4)
        .arg(m_pressStrokeJogSpeed, 0, 'f', 4).arg(type).toLatin1();
    writePressCommand(retractFrame, m_operationName);
}

bool MachineControlBackend::writeNextModuleFrame()
{
    if (m_moduleCommandFrameIndex < 0
        || m_moduleCommandFrameIndex >= m_moduleCommandFrames.size()) {
        failActiveCommand(QStringLiteral("MODULE_FRAME_SEQUENCE_INVALID"));
        return false;
    }
    if (!m_moduleTransport->writeFrame(m_moduleCommandFrames.at(m_moduleCommandFrameIndex))) {
        failActiveCommand(QStringLiteral("MODULE_WRITE_FAILED"));
        return false;
    }
    return true;
}

void MachineControlBackend::completeActivePressCommand()
{
    const bool stopWasUnconfirmed = m_pressSafetyStopUnconfirmed;
    const bool confirmedSafetyStop =
        m_pressCommandPhase == PressCommandPhase::AwaitFailureStopIdle
        || (!originalManualFirmware() && m_pressCommandPhase == PressCommandPhase::AwaitStopIdle
            && m_pressStopAcknowledged)
        || (m_originalManualStop && !m_originalStopHadFault
            && m_pressCommandPhase == PressCommandPhase::AwaitStopIdle);
    m_originalManualStop = false;
    m_tonnageHoldTimer.stop();
    m_tonnageHoldHeartbeatTimer.stop();
    m_pressCommandPhase = PressCommandPhase::Idle;
    m_allowPressStopIdleRace = false;
    m_pressStopAcknowledged = false;
    m_tonnageHoldDoneAcknowledged = false;
    m_pressCommandProgressObserved = false;
    m_pressCommandJogType.clear();
    m_pendingPressFailure.clear();
    m_thcContactProfileActive = false;
    m_toolChangeMode.clear();
    if (confirmedSafetyStop)
        m_pressSafetyStopUnconfirmed = false;
    m_pressOperationActive = false;
    if (stopWasUnconfirmed != m_pressSafetyStopUnconfirmed)
        emit pressStateChanged();
    finishCommandOperation(QStringLiteral("COMPLETED"));
    emit pressStateChanged();
}

void MachineControlBackend::completeActiveModuleCommand()
{
    m_moduleCommandPhase = ModuleCommandPhase::Idle;
    m_moduleCommandFrames.clear();
    m_moduleCommandFrameIndex = 0;
    m_moduleTargetRequired = false;
    m_moduleContinuousAxis.clear();
    m_moduleContinuousDirection = 0;
    m_moduleOperationActive = false;
    finishCommandOperation(QStringLiteral("COMPLETED"));
    emit moduleStateChanged();
}

bool MachineControlBackend::pressStateIsMotion(const QString &state) const
{
    return state == QStringLiteral("SAFETY_JOG")
        || state == QStringLiteral("SAFETY_JOG_HOLD")
        || state == QStringLiteral("CLAMP_JOG")
        || state == QStringLiteral("CLAMP_JOG_HOLD")
        || state == QStringLiteral("BEND_JOG")
        || state == QStringLiteral("BEND_DEPTH_REACHED")
        || state == QStringLiteral("BEND_JOG_HOLD")
        || state == QStringLiteral("RETRACT_JOG")
        || state == QStringLiteral("RELEASE_LOAD_RETRACT");
}

bool MachineControlBackend::cancelCommandOperation()
{
    if (!commandOperationActive())
        return reject(QStringLiteral("command"), QStringLiteral("cancel"),
                      CommandRejectionReason::InvalidArgument);
    if (m_operationDevice == QStringLiteral("press"))
        return abortPress();
    if (m_operationDevice == QStringLiteral("module"))
        return stopModule();
    return reject(QStringLiteral("command"), QStringLiteral("cancel"),
                  CommandRejectionReason::InvalidArgument);
}

void MachineControlBackend::revokePrimingLatchPresentation()
{
    m_primingHeartbeatTimer.stop();
    m_primingLatchRevocationPending = true;
    if (!m_primingLatchY1 && !m_primingLatchY2)
        return;
    m_primingLatchY1 = false;
    m_primingLatchY2 = false;
    emit telemetryChanged();
}

void MachineControlBackend::clearPressState()
{
    if (thcContinuousActive()) failActiveCommand(QStringLiteral("THC_V53_TRANSPORT_CLOSED"));
    resetThcV53Operation();
    invalidateThcLiveTuning(QStringLiteral("V53_SESSION_LOST"), true, false);
    // A fault/reset of presentation may leave the underlying stream open.
    // Only actual stream retirement allows a new tokenless query after handshake.
    if (!m_pressTransport->isOpen()) m_thcLiveRecoveryRequired = false;
    if (m_thcV51Phase != ThcV51Phase::Inactive)
        failActiveCommand(QStringLiteral("THC_V51_TRANSPORT_CLOSED"));
    resetThcV51Operation();
    if (m_thcTuningQueryPending) {
        m_thcTuningQueryPending = false;
        m_thcTuningQueryTimer.stop();
        emit thcTuningQueryFinished(false, QString(),
                                    QStringLiteral("TRANSPORT_CLOSED"));
    }
    m_thcTuningQueryRecovery = false;
    m_thcTuningQueryTimer.stop();
    m_programRunActive = false;
    m_pressInitializationTimer.stop();
    m_pressKeepAliveTimer.stop();
    m_pressHandshakeState = PressHandshakeState::Idle;
    m_pressIdentityQueryRetriedAfterReset = false;
    m_pressConnectionState = ConnectionState::Disconnected;
    m_pressConnected = false;
    m_pressReady = false;
    m_pressHomed = false;
    m_pressOperationActive = false;
    // A transport lifecycle is not proof that a failed/unconfirmed safety
    // STOP reached the controller. Preserve this interlock across disconnect
    // and reconnect; only confirmed STOP terminal telemetry or a complete
    // observed Home lifecycle may clear it.
    m_pressHomingTimer.stop();
    m_pressHomePending = false;
    m_pressHomeProgressObserved = false;
    m_pressHomeInitialState.clear();
    m_pressCommandPhase = PressCommandPhase::Idle;
    m_pressCommandJogType.clear();
    m_pressCommandProgressObserved = false;
    m_pendingPressFailure.clear();
    m_pendingPressHomeFailure.clear();
    m_pendingThcFailure.clear();
    m_thcContactProfileActive = false;
    m_thcContactProfileContactObserved = false;
    m_thcContactProfileAutomaticLifecycle = false;
    m_thcContactProfileHeartbeatTimer.stop();
    m_pressToolChangeSupported = false;
    m_toolChangeMode.clear();
    m_pressMachineState = QStringLiteral("UNKNOWN");
    m_pressFirmwareIdentity.clear();
    m_pressFirmwareVersion.clear();
    m_pressTelemetryFreshnessTimer.stop();
    m_pressTelemetryFresh = false;
    m_manualModeEnabled = false;
    m_manualModeMaxTonnagePerRam = 0.0;
    m_primingModeEnabled = false;
    m_primingLatchSupported = false;
    m_primingLatchY1 = false;
    m_primingLatchY2 = false;
    m_primingLatchRevocationPending = false;
    m_primingHeartbeatTimer.stop();
    m_tonnageHoldTimer.stop();
    m_tonnageHoldHeartbeatTimer.stop();
    m_tonnageHoldDoneAcknowledged = false;
    m_independentRamTelemetryAvailable = false;
    m_safetyJogLeft = false;
    m_safetyJogRight = false;
    m_bendPedal = false;
    m_physicalPedal = false;
    m_physicalPedalAvailable = false;
    m_antiBind = false;
    m_ramPositionY1 = 0.0;
    m_ramPositionY2 = 0.0;
    m_ramLoadY1 = 0.0;
    m_ramLoadY2 = 0.0;
    m_ramVelocity = 0.0;
    m_measuredRamVelocityAvailable = false;
    m_measuredRamVelocity = 0.0;
    m_motorRpmAvailable = false;
    m_motorRpmY1 = 0.0;
    m_motorRpmY2 = 0.0;
    m_ramTargetPosition = 0.0;
    m_ramCommandedJogPosition = 0.0;
    m_ramJogSpeed = 0.0;
    m_ramDistanceToGo = 0.0;
    m_ramToTableOpening = 0.0;
    emit thcLiveTuningChanged();
    emit thcLiveDiagnosticsChanged();
}

void MachineControlBackend::clearModuleState()
{
    m_programRunActive = false;
    m_moduleInitializationTimer.stop();
    m_moduleStatusPollTimer.stop();
    m_moduleHandshakeState = ModuleHandshakeState::Idle;
    m_moduleSettingsSeen = false;
    m_moduleModalSeen = false;
    m_moduleConnectionState = ConnectionState::Disconnected;
    m_moduleConnected = false;
    m_moduleReady = false;
    m_moduleHomed = false;
    m_moduleOperationActive = false;
    m_moduleHomingTimer.stop();
    m_moduleHomePhase = ModuleHomePhase::Idle;
    m_moduleHomeConcurrent = false;
    m_moduleCommandPhase = ModuleCommandPhase::Idle;
    m_moduleCommandFrames.clear();
    m_moduleCommandFrameIndex = 0;
    m_moduleTargetRequired = false;
    m_moduleContinuousAxis.clear();
    m_moduleContinuousDirection = 0;
    m_moduleState = QStringLiteral("UNKNOWN");
    m_moduleFirmwareVersion.clear();
    m_moduleTelemetryFreshnessTimer.stop();
    m_moduleTelemetryFresh = false;
    m_moduleInches = true;
    m_moduleUnitSettingSeen = false;
    m_moduleWcoAvailable = false;
    m_moduleWcoX = 0.0;
    m_moduleWcoR = 0.0;
    m_moduleWorkX = 0.0;
    m_moduleWorkR = 0.0;
    m_moduleMachineX = 0.0;
    m_moduleMachineR = 0.0;
    m_moduleLimitX1 = false;
    m_moduleLimitX2 = false;
    m_moduleLimitR1 = false;
    m_moduleLimitR2 = false;
}

void MachineControlBackend::handlePressTransportClosed()
{
    if (!m_pressTransport->isOpen()) m_thcLiveRecoveryRequired = false;
    if (m_pressConnectionState == ConnectionState::Faulted && !m_pressConnected) {
        schedulePressReconnect();
        return;
    }
    if (m_pressConnectionState == ConnectionState::Disconnected && !m_pressConnected)
        return;
    if (m_pressHomePending)
        failPressHoming(QStringLiteral("TRANSPORT_CLOSED"), false);
    else if (m_operationDevice == QStringLiteral("press") && commandOperationActive())
        failActiveCommand(QStringLiteral("TRANSPORT_CLOSED"));
    clearPressState();
    emit pressStateChanged();
    emit telemetryChanged();
    schedulePressReconnect();
}

void MachineControlBackend::handleModuleTransportClosed()
{
    if (m_moduleConnectionState == ConnectionState::Faulted && !m_moduleConnected) {
        scheduleModuleReconnect();
        return;
    }
    if (m_moduleConnectionState == ConnectionState::Disconnected && !m_moduleConnected)
        return;
    if (m_moduleHomePhase != ModuleHomePhase::Idle)
        failModuleHoming(QStringLiteral("TRANSPORT_CLOSED"), false);
    else if (m_operationDevice == QStringLiteral("module") && commandOperationActive())
        failActiveCommand(QStringLiteral("TRANSPORT_CLOSED"));
    clearModuleState();
    emit moduleStateChanged();
    scheduleModuleReconnect();
}

void MachineControlBackend::handlePressTransportError(const QString &message)
{
    if (thcContinuousActive() && m_thcV53Phase != ThcV53Phase::AwaitCancel)
        beginThcV53Cancellation(QStringLiteral("THC_V53_TRANSPORT_ERROR:") + message);
    if (m_thcV51Phase != ThcV51Phase::Inactive && m_thcV51Phase != ThcV51Phase::AwaitCancel)
        beginThcV51Cancellation(QStringLiteral("THC_V51_TRANSPORT_ERROR:") + message);
    if (m_pressHomePending)
        failPressHoming(message, false);
    else if (m_operationDevice == QStringLiteral("press") && commandOperationActive())
        failActiveCommand(message);
    if (m_pressConnected || m_pressConnectionState != ConnectionState::Disconnected) {
        clearPressState();
        m_pressConnectionState = ConnectionState::Faulted;
        emit pressStateChanged();
        emit telemetryChanged();
    }
    emit connectionFailed(QStringLiteral("press"), message);
    schedulePressReconnect();
}

void MachineControlBackend::handleModuleTransportError(const QString &message)
{
    if (m_moduleHomePhase != ModuleHomePhase::Idle)
        failModuleHoming(message, false);
    else if (m_operationDevice == QStringLiteral("module") && commandOperationActive())
        failActiveCommand(message);
    if (m_moduleConnected || m_moduleConnectionState != ConnectionState::Disconnected) {
        clearModuleState();
        m_moduleConnectionState = ConnectionState::Faulted;
        emit moduleStateChanged();
    }
    emit connectionFailed(QStringLiteral("module"), message);
    scheduleModuleReconnect();
}

void MachineControlBackend::handlePressAvailabilityChanged()
{
    emit transportAvailabilityChanged();
    if (pressTransportAvailable())
        schedulePressReconnect(true);
}

void MachineControlBackend::handleModuleAvailabilityChanged()
{
    emit transportAvailabilityChanged();
    if (moduleTransportAvailable())
        scheduleModuleReconnect(true);
}

void MachineControlBackend::schedulePressReconnect(bool endpointRediscovered)
{
    if (!m_pressReconnectDesired || m_pressConnected
        || m_pressConnectionState == ConnectionState::Connecting
        || m_pressConnectionState == ConnectionState::Initializing
        || m_pressConnectionState == ConnectionState::Ready
        || m_pressConnectionState == ConnectionState::Disconnecting)
        return;
    if (!pressTransportAvailable())
        return;
    if (endpointRediscovered)
        m_pressReconnectAttempts = 0;
    if (m_pressReconnectAttempts >= MaximumReconnectAttempts) {
        qWarning().noquote() << "MACHINE-RECONNECT device=press result=suspended attempts="
                             + QString::number(m_pressReconnectAttempts);
        return;
    }
    const int exponent = qMin(m_pressReconnectAttempts, 4);
    const int delayMs = endpointRediscovered ? 0 : m_reconnectBaseDelayMs * (1 << exponent);
    if (!m_pressReconnectTimer.isActive()
        || delayMs < m_pressReconnectTimer.remainingTime()) {
        qInfo().noquote() << "MACHINE-RECONNECT device=press state=scheduled delayMs="
                          + QString::number(delayMs)
                          << "attempt=" + QString::number(m_pressReconnectAttempts + 1);
        m_pressReconnectTimer.start(delayMs);
    }
}

void MachineControlBackend::scheduleModuleReconnect(bool endpointRediscovered)
{
    if (!m_moduleReconnectDesired || m_moduleConnected
        || m_moduleConnectionState == ConnectionState::Connecting
        || m_moduleConnectionState == ConnectionState::Initializing
        || m_moduleConnectionState == ConnectionState::Ready
        || m_moduleConnectionState == ConnectionState::Disconnecting)
        return;
    if (!moduleTransportAvailable())
        return;
    if (endpointRediscovered)
        m_moduleReconnectAttempts = 0;
    if (m_moduleReconnectAttempts >= MaximumReconnectAttempts) {
        qWarning().noquote() << "MACHINE-RECONNECT device=module result=suspended attempts="
                             + QString::number(m_moduleReconnectAttempts);
        return;
    }
    const int exponent = qMin(m_moduleReconnectAttempts, 4);
    const int delayMs = endpointRediscovered ? 0 : m_reconnectBaseDelayMs * (1 << exponent);
    if (!m_moduleReconnectTimer.isActive()
        || delayMs < m_moduleReconnectTimer.remainingTime()) {
        qInfo().noquote() << "MACHINE-RECONNECT device=module state=scheduled delayMs="
                          + QString::number(delayMs)
                          << "attempt=" + QString::number(m_moduleReconnectAttempts + 1);
        m_moduleReconnectTimer.start(delayMs);
    }
}

void MachineControlBackend::attemptPressReconnect()
{
    if (!m_pressReconnectDesired || !pressTransportAvailable())
        return;
    ++m_pressReconnectAttempts;
    qInfo().noquote() << "MACHINE-RECONNECT device=press state=attempting attempt="
                      + QString::number(m_pressReconnectAttempts);
    if (!attemptPressConnection(false))
        schedulePressReconnect();
}

void MachineControlBackend::attemptModuleReconnect()
{
    if (!m_moduleReconnectDesired || !moduleTransportAvailable())
        return;
    ++m_moduleReconnectAttempts;
    qInfo().noquote() << "MACHINE-RECONNECT device=module state=attempting attempt="
                      + QString::number(m_moduleReconnectAttempts);
    if (!attemptModuleConnection(false))
        scheduleModuleReconnect();
}

bool MachineControlBackend::startPressHandshake()
{
    m_pressHandshakeState = PressHandshakeState::AwaitWelcome;
    m_pressIdentityQueryRetriedAfterReset = false;
    m_pressInitializationTimer.start();
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<!?>\n"))
        || !m_pressTransport->writeFrame(QByteArrayLiteral("<?>\n"))) {
        failPressInitialization(QStringLiteral("HANDSHAKE_WRITE_FAILED"));
        return false;
    }
    return true;
}

void MachineControlBackend::startModuleHandshake()
{
    m_moduleHandshakeState = ModuleHandshakeState::AwaitWelcome;
    m_moduleInitializationTimer.start();
    if (!m_moduleTransport->writeFrame(QByteArrayLiteral("\x18")))
        failModuleInitialization(QStringLiteral("HANDSHAKE_WRITE_FAILED"));
}

void MachineControlBackend::handlePressFrame(const QByteArray &frame)
{
    // Arrival order survives synchronous nested transport replies; parse order
    // cannot prove that an IDLE actually arrived after a terminal marker.
    const auto arrival = ++m_pressFrameArrival;
    const auto owner = m_operationId;
    const auto currentFrame = [this, owner, arrival] {
        return m_operationId == owner && m_pressFrameArrival == arrival;
    };
    if (handleThcLiveFrame(frame, arrival) || !currentFrame())
        return;
    if (handleThcV53Frame(frame, arrival) || !currentFrame())
        return;
    if (handleThcV51Frame(frame, arrival) || !currentFrame())
        return;
    static const QRegularExpression welcomePattern(
        QStringLiteral("^\\[(?:BENDCNC|LS-BEND) v(\\d+(?:\\.\\d+)?(?:[a-zA-Z]+)?)\\]$"));
    const QString line = QString::fromLatin1(frame).trimmed();
    static const QRegularExpression tuningResponsePattern(
        QStringLiteral("^\\{THC:TUNE:v=1,cq=\\d+\\.\\d{4},fs=\\d+\\.\\d{4},rate=\\d+\\.\\d{4},auth=\\d+\\.\\d{4},brake=(?:clear|freeze|grow),safe=(?:clear|freeze|grow)\\}$"));
    if (m_thcTuningQueryPending && tuningResponsePattern.match(line).hasMatch()) {
        m_thcTuningQueryPending = false;
        m_thcTuningQueryTimer.stop();
        emit thcTuningQueryFinished(true, line, QString());
        return;
    }
    if (line.startsWith(QStringLiteral("{LV:")) && line.endsWith(QLatin1Char('}'))) {
        bool ok = false;
        const double value = line.mid(4, line.size() - 5).toDouble(&ok);
        if (ok) emit ramLevelOffsetReported(value);
        return;
    }
    if (handleToolChangeFrame(line))
        return;
    if (m_thcTuningQueryPending
        && (line == QStringLiteral("{THC:TUNE:ERROR:BUSY}")
            || line == QStringLiteral("{THC:TUNE:ERROR:ARGUMENT}"))) {
        m_thcTuningQueryPending = false;
        m_thcTuningQueryTimer.stop();
        emit thcTuningQueryFinished(false, QString(), line.mid(16, line.size() - 17));
        return;
    }
    if (originalManualFirmware() && m_pressCommandPhase != PressCommandPhase::Idle) {
        if (!m_originalCommandEchoSeen && line.toLatin1() == m_originalExpectedEcho) {
            m_originalCommandEchoSeen = true;
            m_originalTelemetryDrainBytes = 1279; // 1023-byte ring + 256-byte staging
            if (m_originalManualStop && !m_originalManualCancel
                && m_pressCommandPhase == PressCommandPhase::AwaitStopIdle)
                m_pressStopAcknowledged = true; // controller release request, NOT standstill
        }
        if (line == QStringLiteral("[JOG COMPLETED]")) {
            if (!m_originalCommandEchoSeen)
                return;
            if (m_originalManualStop && m_originalManualCancel
                && m_pressCommandPhase == PressCommandPhase::AwaitStopIdle)
                m_pressStopAcknowledged = true;
            else if (m_pressCommandPhase == PressCommandPhase::AwaitProgress) {
                m_pressCommandProgressObserved = true;
                m_pressCommandPhase = PressCommandPhase::AwaitIdle;
            }
        }
    }
    const QRegularExpressionMatch match = welcomePattern.match(line);
    // Historical v1.2 can consume the immediately queued <?> before it has
    // finished processing a reset, then emit the acknowledgement last. Re-query only
    // after that explicit reset acknowledgement so the controller emits its
    // exact identity banner; telemetry alone must never authenticate it.
    if (m_pressHandshakeState == PressHandshakeState::AwaitWelcome
        && !m_pressIdentityQueryRetriedAfterReset
        && (line == QStringLiteral("[SOFT RESET]")
            || line == QStringLiteral("[HARD RESET]"))) {
        m_pressIdentityQueryRetriedAfterReset = true;
        if (!m_pressTransport->writeFrame(QByteArrayLiteral("<?>\n")))
            failPressInitialization(QStringLiteral("HANDSHAKE_WRITE_FAILED"));
        return;
    }
    if ((m_pressHandshakeState == PressHandshakeState::AwaitTelemetry
         || m_pressHandshakeState == PressHandshakeState::Ready)
        && (line == QStringLiteral("[SOFT RESET]")
            || line == QStringLiteral("[HARD RESET]"))) {
        failPressInitialization(QStringLiteral("CONTROLLER_RESET_DETECTED"));
        return;
    }
    if (const auto eeprom = MachineProtocolParsers::parsePressEepromSettings(frame)) {
        m_ramToTableOpening = eeprom->ramToTableOpening;
        m_deflectionCompensation = eeprom->deflectionCompEnabled ? 1 : 0;
        qInfo().noquote() << "MACHINE-SETTINGS device=press source=EEPROM ramToTableOpening="
                          + QString::number(m_ramToTableOpening, 'f', 4)
                          + " deflectionComp=" + QString::number(m_deflectionCompensation);
        emit telemetryChanged();
        if (!currentFrame()) return;
        if (m_pressCommandPhase == PressCommandPhase::AwaitRamToTableAck
            && m_requestedDeflectionCompensation >= 0) {
            const bool match = m_deflectionCompensation == m_requestedDeflectionCompensation;
            m_requestedDeflectionCompensation = -1;
            if (!match)
                failActiveCommand(QStringLiteral("DEFLECTION_COMP_ACK_MISMATCH"));
            else {
                acknowledgeCommandOperation();
                if (!currentFrame()) return;
                completeActivePressCommand();
            }
        } else if (m_pressCommandPhase == PressCommandPhase::AwaitRamToTableAck) {
            // The firmware stores the full double. Its {EEPROM:...} echo has
            // 4 decimals (v53 AUTO-target and later) or 3 (older images), so
            // match within half of the echo's last printed digit. A coarser
            // echo never widens the band beyond the 3-decimal one.
            const int echoDecimals = eeprom->ramToTableOpeningDecimals < 3
                ? 3 : eeprom->ramToTableOpeningDecimals;
            const double echoTolerance = 0.5 * std::pow(10.0, -echoDecimals) + 1e-9;
            if (std::abs(m_ramToTableOpening - m_requestedRamToTableOpening) > echoTolerance)
                failActiveCommand(QStringLiteral("RAM_TO_TABLE_ACK_MISMATCH"));
            else {
                acknowledgeCommandOperation();
                if (!currentFrame()) return;
                completeActivePressCommand();
            }
        }
        return;
    }
    if (const auto temporaryStatus = MachineProtocolParsers::parsePressTemporaryStatus(frame)) {
        m_manualModeEnabled = temporaryStatus->manualModeEnabled;
        m_manualModeMaxTonnagePerRam = temporaryStatus->manualModeMaxTonnagePerRam;
        m_primingModeEnabled = temporaryStatus->primingModeEnabled;
        m_primingLatchSupported = temporaryStatus->primingLatchSupported;
        const bool reportedLatchY1 = temporaryStatus->primingLatchY1;
        const bool reportedLatchY2 = temporaryStatus->primingLatchY2;
        if (m_primingLatchRevocationPending && !reportedLatchY1 && !reportedLatchY2)
            m_primingLatchRevocationPending = false;
        m_primingLatchY1 = !m_primingLatchRevocationPending && reportedLatchY1;
        m_primingLatchY2 = !m_primingLatchRevocationPending && reportedLatchY2;
        if (m_primingModeEnabled && m_primingLatchSupported
            && (m_primingLatchY1 || m_primingLatchY2))
            m_primingHeartbeatTimer.start();
        else
            m_primingHeartbeatTimer.stop();
        if (thcContinuousActive()) {
            checkThcV53Deadlines();
            if (!currentFrame()) return;
        }
        emit telemetryChanged();
        if (!currentFrame()) return;
        if (m_pressCommandPhase == PressCommandPhase::AwaitManualModeStatus
            && m_manualModeEnabled == m_expectedManualModeEnabled) {
            acknowledgeCommandOperation();
            if (!currentFrame()) return;
            completeActivePressCommand();
        } else if (m_pressCommandPhase == PressCommandPhase::AwaitSettingAck
                   && std::abs(temporaryStatus->safetyRetract
                               - m_pressCommandTarget) <= 0.0001) {
            acknowledgeCommandOperation();
            if (!currentFrame()) return;
            completeActivePressCommand();
        } else if (m_pressCommandPhase == PressCommandPhase::StrokeAwaitSetting
                   && std::abs(temporaryStatus->safetyRetract
                               - m_pressStrokeRetractTarget) <= 0.0001) {
            acknowledgeCommandOperation();
            if (!currentFrame()) return;
            continueManualStrokeAfterSetting();
        } else if (m_pressCommandPhase == PressCommandPhase::AwaitSettingAck
                   || m_pressCommandPhase == PressCommandPhase::StrokeAwaitSetting) {
            // A TEMP echo with another plane may still be a stale reply, so
            // keep waiting for the bounded deadline but name the cause.
            m_pressRetractEchoMismatch = temporaryStatus->safetyRetract;
            qWarning().noquote() << QStringLiteral("[PRESS-RETRACT-PLANE] echo=%1 requested=%2")
                .arg(temporaryStatus->safetyRetract, 0, 'f', 4)
                .arg(m_pressCommandPhase == PressCommandPhase::AwaitSettingAck
                         ? m_pressCommandTarget : m_pressStrokeRetractTarget, 0, 'f', 4);
        } else if (m_pressCommandPhase == PressCommandPhase::AwaitManualTonnageAck
                   && std::abs(m_manualModeMaxTonnagePerRam
                               - m_requestedManualMaxTonnage) <= 0.0001) {
            acknowledgeCommandOperation();
            if (!currentFrame()) return;
            completeActivePressCommand();
        } else if (m_pressCommandPhase == PressCommandPhase::AwaitPrimingStatus
                   && m_primingModeEnabled == m_expectedPrimingModeEnabled
                   && (!m_expectedPrimingModeEnabled
                       || m_pressMachineState == QStringLiteral("PRIMING_MODE"))) {
            acknowledgeCommandOperation();
            if (!currentFrame()) return;
            completeActivePressCommand();
        }
        return;
    }
    if (m_pressCommandPhase != PressCommandPhase::Idle) {
        static const QSet<QString> commandFailures = {
            QStringLiteral("[MACHINE NOT IDLE]"), QStringLiteral("[INVALID COMMAND]"),
            QStringLiteral("[INVALID JOGTYPE]"), QStringLiteral("[PEDAL RELEASED]"),
            QStringLiteral("[BEND REACH FAIL]"), QStringLiteral("[RETRACT DIRECTION FAIL]"),
            QStringLiteral("[RETRACT PLANE ERROR]"), QStringLiteral("[LOAD RETRACT ERROR]")
        };
        if (commandFailures.contains(line)) {
            const QString error = line.mid(1, line.size() - 2)
                                      .replace(QLatin1Char(' '), QLatin1Char('_'));
            if (thcContinuousActive()) {
                beginThcV53Cancellation(error);
                return;
            }
            if (m_thcV51Phase != ThcV51Phase::Inactive) {
                beginThcV51Cancellation(error);
                return;
            }
            if (m_pressCommandPhase == PressCommandPhase::AwaitFailureStopIdle)
                return;
            if (pressPhaseRequiresSafetyStop())
                beginPressSafetyFailure(error, QByteArrayLiteral("<stop>\n"));
            else
                failActiveCommand(error);
            return;
        }
        if (m_pressCommandPhase != PressCommandPhase::ThcV51
            && m_pressCommandPhase != PressCommandPhase::ThcV53
            && m_pressCommandPhase != PressCommandPhase::AwaitHoldIdle
            && (line == QStringLiteral("[JOG COMPLETED]")
            || line == QStringLiteral("[BEND COMPLETED]")
            || line == QStringLiteral("[RECEIVED STRING: stop]"))) {
            acknowledgeCommandOperation();
            if (!currentFrame()) return;
            // A jog already at its endpoint completes before any motion
            // telemetry exists: endpoint-idempotent panel commands, and the
            // firmware trajectory check (target == trajectory -> stopMotion).
            // 2026-11-01 v1.3 RUN: <-2.5986, 10, retract> answered
            // [JOG COMPLETED] at once and the step waited for motion until
            // CANCEL / COMMAND_TIMEOUT. The frame is emitted only after the
            // parser admitted this jog, so it is progress for every jog type
            // (as the original-firmware echo path above already treats it);
            // the following IDLE frame closes the operation.
            if (line == QStringLiteral("[JOG COMPLETED]")
                && m_pressCommandPhase == PressCommandPhase::AwaitProgress) {
                m_pressCommandProgressObserved = true;
                m_pressCommandPhase = PressCommandPhase::AwaitIdle;
            }
        }
        if (m_pressCommandPhase == PressCommandPhase::AwaitManualModeStatus
            && ((m_expectedManualModeEnabled && line == QStringLiteral("[MANUAL ENABLED]"))
                || (!m_expectedManualModeEnabled
                    && line == QStringLiteral("[MANUAL DISABLED]"))
                || line == (QStringLiteral("[CMD:Manual")
                    + (m_expectedManualModeEnabled ? QStringLiteral("Enable]")
                                                   : QStringLiteral("Disable]"))))) {
            m_manualModeEnabled = m_expectedManualModeEnabled;
            emit telemetryChanged();
            if (!currentFrame()) return;
            acknowledgeCommandOperation();
            if (!currentFrame()) return;
            completeActivePressCommand();
            return;
        }
        if (m_pressCommandPhase == PressCommandPhase::AwaitPrimingStatus
            && ((m_expectedPrimingModeEnabled
                 && (line == QStringLiteral("[CMD:PrimingEnable]")
                     || line == QStringLiteral("[PRIMING ENABLED]")))
                || (!m_expectedPrimingModeEnabled
                    && (line == QStringLiteral("[CMD:PrimingDisable]")
                        || line == QStringLiteral("[PRIMING DISABLED]"))))) {
            acknowledgeCommandOperation();
            if (!currentFrame()) return;
        }
        if (m_pressCommandPhase == PressCommandPhase::AwaitManualTonnageAck
            && (line.startsWith(QStringLiteral("[RECEIVED STRING: $MT="))
                || line.startsWith(QStringLiteral("[CMD:$MT=")))) {
            static const QRegularExpression maxTonnageEchoPattern(
                QStringLiteral("^\\[(?:RECEIVED STRING: |CMD:)\\$MT=([-+]?(?:\\d+(?:\\.\\d*)?|\\.\\d+))\\]$"));
            const QRegularExpressionMatch maxTonnageMatch =
                maxTonnageEchoPattern.match(line);
            bool valueOk = false;
            const double echoedValue = maxTonnageMatch.hasMatch()
                ? maxTonnageMatch.captured(1).toDouble(&valueOk) : 0.0;
            if (!valueOk || std::abs(echoedValue - m_requestedManualMaxTonnage) > 0.0001) {
                failActiveCommand(QStringLiteral("MANUAL_MAX_TONNAGE_ACK_MISMATCH"));
                return;
            }
            m_manualModeMaxTonnagePerRam = m_requestedManualMaxTonnage;
            emit telemetryChanged();
            if (!currentFrame()) return;
            acknowledgeCommandOperation();
            if (!currentFrame()) return;
            completeActivePressCommand();
            return;
        }
        if ((m_pressCommandPhase == PressCommandPhase::ThcCommissioning
             || m_pressCommandPhase == PressCommandPhase::ThcAwaitCancel)
            && line.startsWith(QStringLiteral("{THC:")) && line.endsWith(QLatin1Char('}'))) {
            const QString status = line.mid(5, line.size() - 6).trimmed().toUpper();
            const bool heartbeat = status == QStringLiteral("HB");
            const auto phase = m_pressCommandPhase;
            if (!heartbeat) {
                m_thcCommissioningState = status;
                emit pressStateChanged();
                if (!currentFrame() || m_pressCommandPhase != phase) return;
            }
            if (m_pressCommandPhase == PressCommandPhase::ThcAwaitCancel) {
                if (status == QStringLiteral("CANCELLED")) {
                    failActiveCommand(m_pendingThcFailure.isEmpty()
                        ? QStringLiteral("THC_COMMAND_TIMEOUT") : m_pendingThcFailure);
                } else if (status.startsWith(QStringLiteral("ERROR:"))) {
                    failActiveCommand(QStringLiteral("THC_") + status.mid(6));
                }
                return;
            }
            if (status == QStringLiteral("CONTACT") && m_thcContactProfileActive) {
                m_thcContactProfileContactObserved = true;
                // Firmware owns the exact 60-second force-acquisition limit.
                // Keep a delivery margin so its typed FORCE_TIMEOUT wins over
                // a less useful host-side cancellation race.
                m_commandDeadlineTimer.setInterval(ThcAcquisitionHostObserverMs);
                m_commandDeadlineTimer.start();
                return;
            }
            if (status == QStringLiteral("ARMED") || status == QStringLiteral("RUNNING")
                || status == QStringLiteral("CONTACT_PROFILE_RUNNING")
                || status == QStringLiteral("HOLDING") || status == QStringLiteral("RELEASING")) {
                acknowledgeCommandOperation();
                if (!currentFrame() || m_pressCommandPhase != phase) return;
                if (status == QStringLiteral("CONTACT_PROFILE_RUNNING")) {
                    // The approach is intentionally not time-limited. Fresh
                    // contact telemetry starts the fixed host observation
                    // budget; firmware physical and lease guards own approach.
                    m_commandDeadlineTimer.stop();
                    if (m_thcContactProfileAutomaticLifecycle)
                        m_thcContactProfileHeartbeatTimer.start();
                } else if (status == QStringLiteral("HOLDING")
                           && m_thcContactProfileActive) {
                    // Five fresh in-band samples start a new observation
                    // epoch. AUTO 1 T keeps regulating for a full minute;
                    // expiry above sends the typed release. Commissioning
                    // clients remain free to own release explicitly.
                    if (m_thcContactProfileAutomaticLifecycle && !m_pressToolChangeSupported) {
                        // Legacy images: 60 s observation, then release.
                        // TCH images have no AUTO HOLD cap; HOLD ends by
                        // explicit RELEASE/CANCEL under lease and guards.
                        m_commandDeadlineTimer.setInterval(ThcHoldingObservationMs);
                        m_commandDeadlineTimer.start();
                    } else {
                        m_commandDeadlineTimer.stop();
                    }
                } else if (status == QStringLiteral("RELEASING")
                           && m_thcContactProfileActive) {
                    // Firmware owns a finite 40-second typed release. Keep a
                    // bounded host observer with protocol/settling margin.
                    m_commandDeadlineTimer.setInterval(ThcReleaseHostObserverMs);
                    m_commandDeadlineTimer.start();
                } else if (!(m_thcContactProfileActive &&
                             m_thcContactProfileContactObserved)) {
                    m_commandDeadlineTimer.setInterval(5000);
                    m_commandDeadlineTimer.start();
                }
            } else if (heartbeat) {
                // Heartbeat is an acknowledgement, not a persistent phase.
                // It must not replace CONTACT_PROFILE_RUNNING or start a
                // pre-contact deadline. Legacy THC retains its 5-second ack.
                if (!m_thcContactProfileActive) {
                    m_commandDeadlineTimer.setInterval(5000);
                    m_commandDeadlineTimer.start();
                }
            } else if (status == QStringLiteral("DONE")) {
                m_thcContactProfileHeartbeatTimer.stop();
                m_thcContactProfileAutomaticLifecycle = false;
                m_thcCommissioningState = QStringLiteral("DONE");
                m_pressCommandPhase = PressCommandPhase::TonnageHoldAwaitStopIdle;
                m_tonnageHoldDoneAcknowledged = true;
                m_commandDeadlineTimer.setInterval(5000);
                m_commandDeadlineTimer.start();
            } else if (status == QStringLiteral("CANCELLED") || status.startsWith(QStringLiteral("ERROR:"))) {
                m_thcCommissioningState = status;
                m_pressCommandPhase = PressCommandPhase::Idle;
                QString failure = status;
                failure.replace(QLatin1Char(':'), QLatin1Char('_'));
                failActiveCommand(QStringLiteral("THC_") + failure);
            }
            return;
        }
        if ((m_pressCommandPhase == PressCommandPhase::NativeTonnageHold
               || m_pressCommandPhase == PressCommandPhase::TonnageHoldAwaitStopIdle
               || m_pressCommandPhase == PressCommandPhase::AwaitFailureStopIdle)
            && line.startsWith(QStringLiteral("{TH:")) && line.endsWith(QLatin1Char('}'))) {
            const QString status = line.mid(4, line.size() - 5).trimmed().toUpper();
            if (status == QStringLiteral("ARMED") || status == QStringLiteral("RUNNING")
                       || status == QStringLiteral("HOLDING")) {
                if (m_pressCommandPhase == PressCommandPhase::NativeTonnageHold)
                    acknowledgeCommandOperation();
            } else if (status == QStringLiteral("HB")) {
                // Only an explicit firmware acknowledgement validates a host
                // lease renewal. Telemetry and malformed TH frames cannot.
                if (m_pressCommandPhase == PressCommandPhase::NativeTonnageHold) {
                    m_commandDeadlineTimer.setInterval(5000);
                    m_commandDeadlineTimer.start();
                }
            } else if (status == QStringLiteral("DONE")) {
                // A terminal frame is not sufficient proof that both axes are
                // idle; wait for the ordinary controller status confirmation.
                if (m_pressCommandPhase != PressCommandPhase::AwaitFailureStopIdle) {
                    m_tonnageHoldDoneAcknowledged = true;
                    m_tonnageHoldHeartbeatTimer.stop();
                    m_pressCommandPhase = PressCommandPhase::TonnageHoldAwaitStopIdle;
                    m_commandDeadlineTimer.setInterval(5000);
                    m_commandDeadlineTimer.start();
                }
            } else if (status == QStringLiteral("TIMEOUT")
                       || status == QStringLiteral("ERROR")
                       || status.startsWith(QStringLiteral("ERROR:"))) {
                if (m_pressCommandPhase != PressCommandPhase::AwaitFailureStopIdle)
                    beginPressSafetyFailure(QStringLiteral("TONNAGE_HOLD_")
                                            + (status.startsWith(QStringLiteral("ERROR:"))
                                                ? status.mid(6) : status),
                                            QByteArrayLiteral("<stop>\n"));
            }
            return;
        }
        if (m_pressCommandPhase == PressCommandPhase::AwaitSettingAck
            && (line.startsWith(QStringLiteral("R set to:"))
                || line.startsWith(QStringLiteral("[CMD:$R=")))) {
            acknowledgeCommandOperation();
            if (!currentFrame()) return;
            completeActivePressCommand();
            return;
        }
        if (m_pressCommandPhase == PressCommandPhase::StrokeAwaitSetting
            && (line.startsWith(QStringLiteral("R set to:"))
                || line.startsWith(QStringLiteral("[CMD:$R=")))) {
            acknowledgeCommandOperation();
            if (!currentFrame()) return;
            continueManualStrokeAfterSetting();
            return;
        }
    }
    if (m_pressHomePending
        && (line == QStringLiteral("[HOMING TONNAGE FAIL]")
            || line == QStringLiteral("[HOMING DIRECTION FAIL]")
            || line == QStringLiteral("[HOMING TIMEOUT]")
            || line == QStringLiteral("[HOMING PRIMING FAIL]")
            || line == QStringLiteral("[HOMING RETRACT TIMEOUT]")
            || line == QStringLiteral("[CONTROLLER ALARM ACTIVE]")
            || line == QStringLiteral("[HOME RECOVERY NOT SETTLED]")
            || line == QStringLiteral("[RETRACT PLANE ERROR]"))) {
        const QString reason = line.mid(1, line.size() - 2)
                                   .replace(QLatin1Char(' '), QLatin1Char('_'));
        beginPressHomingSafetyFailure(reason);
        return;
    }
    if (m_originalManualStop && originalManualFirmware()
        && (m_pressCommandPhase == PressCommandPhase::AwaitStopIdle
            || m_pressCommandPhase == PressCommandPhase::AwaitFailureStopIdle)) {
        // Original has no [STOPPED] response. Normal completion is handled
        // above; fault-stop recovery deliberately remains unconfirmed.
        if (line == QStringLiteral("[STOPPED]")
            || line == QStringLiteral("[JOG COMPLETED]"))
            return;
    }
    if (line == QStringLiteral("[STOPPED]")
        && m_pressCommandPhase == PressCommandPhase::AwaitRamToTableStop) {
        writeRamToTableOpeningFrame();
        return;
    }
    if (line == QStringLiteral("[EEPROM BUSY]")
        && m_pressCommandPhase == PressCommandPhase::AwaitRamToTableAck) {
        failActiveCommand(QStringLiteral("RAM_TO_TABLE_EEPROM_BUSY"));
        return;
    }
    if (line == QStringLiteral("[STOPPED]")
        && m_pressCommandPhase == PressCommandPhase::AwaitStopIdle) {
        m_pressStopAcknowledged = true;
        return;
    }
    if (line == QStringLiteral("[STOPPED]")
        && m_pressCommandPhase == PressCommandPhase::AwaitFailureStopIdle) {
        m_pressStopAcknowledged = true;
        return;
    }
    if (line == QStringLiteral("[STOPPED]")
        && m_pressCommandPhase == PressCommandPhase::AwaitHomeFailureStopIdle) {
        m_pressStopAcknowledged = true;
        return;
    }
    if (line == QStringLiteral("[HELD]")
        && m_pressCommandPhase == PressCommandPhase::AwaitHoldIdle) {
        acknowledgeCommandOperation();
        return;
    }
    if ((m_pressHandshakeState == PressHandshakeState::AwaitTelemetry
         || m_pressHandshakeState == PressHandshakeState::Ready)
        && match.hasMatch()) {
        failPressInitialization(QStringLiteral("CONTROLLER_RESET_DETECTED"));
        return;
    }
    if (m_pressHandshakeState == PressHandshakeState::AwaitTelemetry
        || m_pressHandshakeState == PressHandshakeState::Ready) {
        const auto telemetry = MachineProtocolParsers::parsePressTelemetry(frame);
        if (!telemetry)
            return;
        bool admitCompletion = true;
        if (originalManualFirmware()
            && (m_originalManualStop || m_pressCommandPhase == PressCommandPhase::AwaitProgress
                || m_pressCommandPhase == PressCommandPhase::AwaitIdle)
            && !m_originalCommandEchoSeen) {
            admitCompletion = false;
        }
        if (originalManualFirmware() && m_pressCommandPhase != PressCommandPhase::Idle
            && m_originalCommandEchoSeen && m_originalTelemetryDrainBytes > 0) {
            // Count only payload bytes (excluding framing delimiters): conservative
            // bound even when transport strips whitespace. Still inspect alarms below.
            m_originalTelemetryDrainBytes -= qMax(qsizetype(0), frame.trimmed().size() - 2);
            admitCompletion = false; // crossing frame may still contain queued bytes
        }
        m_pressMachineState = telemetry->state;
        m_ramPositionY1 = telemetry->y1Position;
        m_ramPositionY2 = telemetry->y2Position;
        m_ramVelocity = telemetry->velocity;
        m_measuredRamVelocityAvailable = telemetry->y1MeasuredVelocity.has_value()
            && telemetry->y2MeasuredVelocity.has_value();
        m_measuredRamVelocity = m_measuredRamVelocityAvailable
            ? (*telemetry->y1MeasuredVelocity + *telemetry->y2MeasuredVelocity) * 0.5
            : 0.0;
        m_motorRpmAvailable = telemetry->y1MotorRpm.has_value()
            && telemetry->y2MotorRpm.has_value();
        m_motorRpmY1 = m_motorRpmAvailable ? *telemetry->y1MotorRpm : 0.0;
        m_motorRpmY2 = m_motorRpmAvailable ? *telemetry->y2MotorRpm : 0.0;
        m_ramTargetPosition = telemetry->targetPosition;
        m_ramCommandedJogPosition = telemetry->commandedJogPosition;
        m_ramJogSpeed = telemetry->jogSpeed;
        m_safetyJogLeft = telemetry->safetyJogLeft;
        m_safetyJogRight = telemetry->safetyJogRight;
        m_bendPedal = telemetry->bendPedal;
        m_physicalPedal = telemetry->physicalPedal;
        m_physicalPedalAvailable = telemetry->physicalPedalAvailable;
        m_ramDistanceToGo = telemetry->distanceToGo;
        m_ramLoadY1 = telemetry->y1Tonnage;
        m_ramLoadY2 = telemetry->y2Tonnage;
        m_antiBind = telemetry->antiBind;
        ++m_pressTelemetrySequence;
        m_pressTelemetryFresh = true;
        m_independentRamTelemetryAvailable = true;
        m_pressTelemetryFreshnessTimer.start();
        const bool telemetryOperationActive = telemetry->state != QStringLiteral("IDLE")
            && telemetry->state != QStringLiteral("STARTUP_HOMING_REQUIRED")
            && telemetry->state != QStringLiteral("HYDRAULIC_SHUTDOWN")
            && telemetry->state != QStringLiteral("PRIMING_MODE")
            && telemetry->state != QStringLiteral("UNKNOWN")
            && !MachineProtocolParsers::pressStateIsAlarm(telemetry->state);
        m_pressOperationActive = m_pressHomePending
            || m_pressCommandPhase != PressCommandPhase::Idle || telemetryOperationActive;
        m_pressHomed = telemetry->state != QStringLiteral("STARTUP_HOMING_REQUIRED")
            && telemetry->state != QStringLiteral("HOMING")
            && telemetry->state != QStringLiteral("HOMING_BUMP")
            && telemetry->state != QStringLiteral("UNKNOWN")
            && !MachineProtocolParsers::pressStateIsAlarm(telemetry->state);
        if (m_pressHomePending) {
            if (m_pressCommandPhase == PressCommandPhase::AwaitHomeFailureStopIdle) {
                if (m_pressStopAcknowledged
                    && (telemetry->state == QStringLiteral("STARTUP_HOMING_REQUIRED")
                        || telemetry->state == QStringLiteral("IDLE")
                        || (MachineProtocolParsers::pressStateIsAlarm(telemetry->state)
                            && telemetry->velocity == 0.0))) {
                    m_pressHomeProgressObserved = true;
                    tryCompletePressHomingSafetyFailure();
                }
                // Retained alarm telemetry must neither become Home success
                // nor fall through to the ordinary command-failure handler.
                return;
            }
            if (telemetry->state == QStringLiteral("HOMING")
                || telemetry->state == QStringLiteral("HOMING_BUMP")) {
                m_pressHomeProgressObserved = true;
                if (m_operationState == QStringLiteral("SENT")) {
                    m_operationState = QStringLiteral("ACKNOWLEDGED");
                    emit commandLifecycleChanged();
                    if (!currentFrame()) return;
                }
            } else if (telemetry->state == QStringLiteral("IDLE")
                       && m_pressHomeProgressObserved) {
                qInfo().noquote() << "MACHINE-HOME device=press state=COMPLETED";
                // A complete Home lifecycle (observed Home motion followed
                // by fresh IDLE telemetry) is the only in-band recovery that
                // may clear an earlier unconfirmed safety-STOP latch. Do not
                // clear it merely because <$H> was accepted or transmitted.
                m_pressSafetyStopUnconfirmed = false;
                emit pressStateChanged();
                finishHomeOperation(QStringLiteral("press"), QStringLiteral("COMPLETED"));
                if (!currentFrame()) return;
            } else if (MachineProtocolParsers::pressStateIsHomingCalibrationFailure(
                           telemetry->state)
                       && (m_pressHomeProgressObserved
                           || telemetry->state != m_pressHomeInitialState)) {
                m_pressReady = false;
                beginPressHomingSafetyFailure(telemetry->state);
                return;
            } else if (MachineProtocolParsers::pressStateIsAlarm(telemetry->state)
                       && (m_pressHomeProgressObserved
                           || telemetry->state != m_pressHomeInitialState)) {
                beginPressHomingSafetyFailure(QStringLiteral("CONTROLLER_ALARM"));
                return;
            }
        }
        if (m_pressCommandPhase != PressCommandPhase::Idle) {
            if (m_pressCommandPhase == PressCommandPhase::ThcV53) {
                m_pressReady = !MachineProtocolParsers::pressStateIsAlarm(telemetry->state)
                    && telemetry->state != QStringLiteral("UNKNOWN");
                handleThcV53Telemetry(frame.startsWith(QByteArrayLiteral("<IDLE|")) && frame.endsWith('>'), arrival);
                emit pressStateChanged();
                emit telemetryChanged();
                return;
            }
            if (m_pressCommandPhase == PressCommandPhase::ThcV51) {
                m_pressReady = !MachineProtocolParsers::pressStateIsAlarm(telemetry->state)
                    && telemetry->state != QStringLiteral("UNKNOWN");
                handleThcV51Telemetry(frame.startsWith(QByteArrayLiteral("<IDLE|"))
                                      && frame.endsWith('>'), arrival);
                emit pressStateChanged();
                emit telemetryChanged();
                return;
            }
            const bool expectedHydraulicShutdown =
                m_pressCommandPhase == PressCommandPhase::AwaitHydraulicShutdown
                && telemetry->state == QStringLiteral("HYDRAULIC_SHUTDOWN");
            if (MachineProtocolParsers::pressStateIsAlarm(telemetry->state)
                && !expectedHydraulicShutdown
                && m_pressCommandPhase != PressCommandPhase::AwaitFailureStopIdle) {
                if (pressPhaseRequiresSafetyStop())
                    beginPressSafetyFailure(QStringLiteral("CONTROLLER_ALARM"),
                                            QByteArrayLiteral("<stop>\n"));
                else
                    failActiveCommand(QStringLiteral("CONTROLLER_ALARM"));
                return;
            }
            // Motion is safety evidence even before echo / while draining queued
            // telemetry. It must not grant original-protocol completion authority.
            if (pressStateIsMotion(telemetry->state)
                && (m_pressCommandPhase == PressCommandPhase::AwaitProgress
                    || m_pressCommandPhase == PressCommandPhase::AwaitIdle
                    || m_pressCommandPhase == PressCommandPhase::LegacyTonnageApproach
                    || m_pressCommandPhase == PressCommandPhase::LegacyTonnageFineJog
                    || m_pressCommandPhase == PressCommandPhase::StrokeAwaitRetract
                    || m_pressCommandPhase == PressCommandPhase::StrokeAwaitBend))
                m_pressCommandProgressObserved = true;
            if (!admitCompletion) {
                // Publish positions, pedal and safety below; alarms above remain live.
            } else if (m_pressCommandPhase == PressCommandPhase::AwaitFailureStopIdle) {
                const bool stoppedTerminalTelemetry =
                    telemetry->state == QStringLiteral("IDLE")
                    || (!m_originalManualStop
                        && MachineProtocolParsers::pressStateIsAlarm(telemetry->state));
                if (m_pressStopAcknowledged && stoppedTerminalTelemetry) {
                    const QString error = m_pendingPressFailure;
                    m_pressSafetyStopUnconfirmed = false;
                    emit pressStateChanged();
                    failActiveCommand(error.isEmpty()
                        ? QStringLiteral("SAFETY_STOP_REQUESTED") : error);
                }
            } else if (m_pressCommandPhase == PressCommandPhase::AwaitHomeFailureStopIdle) {
                tryCompletePressHomingSafetyFailure();
            } else if (m_pressCommandPhase == PressCommandPhase::AwaitHoldIdle) {
                if (m_operationState == QStringLiteral("ACKNOWLEDGED")
                    && telemetry->state == QStringLiteral("IDLE"))
                    completeActivePressCommand();
            } else if (m_pressCommandPhase == PressCommandPhase::AwaitStopIdle) {
                const bool cancelledHomeStopped =
                    m_expectedPressStopState == QStringLiteral("STARTUP_HOMING_REQUIRED")
                    && m_pressStopAcknowledged
                    && m_allowPressStopIdleRace
                    && telemetry->state == QStringLiteral("IDLE");
                const bool expectedStopped = m_pressStopAcknowledged
                    && telemetry->state == m_expectedPressStopState;
                if (expectedStopped || cancelledHomeStopped)
                    completeActivePressCommand();
            } else if (m_pressCommandPhase == PressCommandPhase::AwaitHydraulicShutdown) {
                if (telemetry->state == QStringLiteral("HYDRAULIC_SHUTDOWN")
                    || telemetry->state == QStringLiteral("STARTUP_HOMING_REQUIRED"))
                    completeActivePressCommand();
            } else if (m_pressCommandPhase == PressCommandPhase::AwaitPrimingStatus) {
                if (m_expectedPrimingModeEnabled
                    && m_primingModeEnabled
                    && telemetry->state == QStringLiteral("PRIMING_MODE")) {
                    acknowledgeCommandOperation();
                    if (!currentFrame()) return;
                    completeActivePressCommand();
                }
            } else if (m_pressCommandPhase == PressCommandPhase::TonnageHoldAwaitStopIdle) {
                // IDLE can be queued before parser cancellation takes effect.
                // TH:DONE is the cancellation correlation; require a fresh
                // IDLE after it before reopening admission.
                if (m_tonnageHoldDoneAcknowledged && telemetry->state == QStringLiteral("IDLE"))
                    completeActivePressCommand();
            } else if (m_pressCommandPhase == PressCommandPhase::NativeTonnageHold) {
                const double totalTonnage = m_ramLoadY1 + m_ramLoadY2;
                if (!std::isfinite(totalTonnage) || totalTonnage > 24.0) {
                    beginPressSafetyFailure(QStringLiteral("TONNAGE_LIMIT_EXCEEDED"),
                                            QByteArrayLiteral("<stop>\n"));
                    return;
                }
                if (telemetry->state != QStringLiteral("IDLE"))
                    acknowledgeCommandOperation();
            } else if (m_pressCommandPhase == PressCommandPhase::LegacyTonnageApproach) {
                if (pressStateIsMotion(telemetry->state)) {
                    m_pressCommandProgressObserved = true;
                    acknowledgeCommandOperation();
                    if (!currentFrame()) return;
                    const double totalTonnage = m_ramLoadY1 + m_ramLoadY2;
                    if (totalTonnage > 24.0) {
                        beginPressSafetyFailure(QStringLiteral("TONNAGE_LIMIT_EXCEEDED"),
                                                QByteArrayLiteral("<stop>\n"));
                        return;
                    }
                    if (totalTonnage >= 0.6) {
                        m_pressCommandPhase = PressCommandPhase::LegacyTonnageAwaitApproachIdle;
                        if (!m_pressTransport->writeFrame(QByteArrayLiteral("<cancel>\n"))) {
                            failActiveCommand(QStringLiteral("TONNAGE_APPROACH_CANCEL_WRITE_FAILED"));
                            return;
                        }
                    }
                }
            } else if (m_pressCommandPhase == PressCommandPhase::LegacyTonnageAwaitApproachIdle) {
                if (telemetry->state == QStringLiteral("IDLE")) {
                    m_pressCommandPhase = PressCommandPhase::LegacyTonnageMonitoring;
                    scheduleLegacyTonnageAdjustment(0);
                }
            } else if (m_pressCommandPhase == PressCommandPhase::LegacyTonnageFineJog) {
                if (pressStateIsMotion(telemetry->state)) {
                    m_pressCommandProgressObserved = true;
                    acknowledgeCommandOperation();
                } else if (telemetry->state == QStringLiteral("IDLE")
                           && m_pressCommandProgressObserved) {
                    m_pressCommandPhase = PressCommandPhase::LegacyTonnageMonitoring;
                    m_pressCommandProgressObserved = false;
                    scheduleLegacyTonnageAdjustment(0);
                }
            } else if (m_pressCommandPhase == PressCommandPhase::AwaitProgress
                       || m_pressCommandPhase == PressCommandPhase::AwaitIdle) {
                if (pressStateIsMotion(telemetry->state)) {
                    if (!originalManualFirmware())
                        m_pressCommandPhase = PressCommandPhase::AwaitIdle;
                    acknowledgeCommandOperation();
                } else if (telemetry->state == QStringLiteral("IDLE")
                           && m_pressCommandProgressObserved
                           && (!originalManualFirmware()
                               || m_pressCommandPhase == PressCommandPhase::AwaitIdle)) {
                    completeActivePressCommand();
                }
            } else if (m_pressCommandPhase == PressCommandPhase::StrokeAwaitRetract) {
                if (pressStateIsMotion(telemetry->state)) {
                    m_pressCommandProgressObserved = true;
                    acknowledgeCommandOperation();
                } else if (telemetry->state == QStringLiteral("IDLE")
                           && m_pressCommandProgressObserved) {
                    m_pressCommandPhase = PressCommandPhase::StrokeAwaitBend;
                    m_pressCommandProgressObserved = false;
                    const QByteArray bendFrame = QStringLiteral("<%1, %2, bend>\n")
                        .arg(m_pressStrokeBendTarget, 0, 'f', 4)
                        .arg(m_pressStrokeBendSpeed, 0, 'f', 4).toLatin1();
                    if (!writePressCommand(bendFrame, m_operationName))
                        return;
                }
            } else if (m_pressCommandPhase == PressCommandPhase::StrokeAwaitBend) {
                if (pressStateIsMotion(telemetry->state)) {
                    m_pressCommandProgressObserved = true;
                    acknowledgeCommandOperation();
                } else if (telemetry->state == QStringLiteral("IDLE")
                           && m_pressCommandProgressObserved) {
                    completeActivePressCommand();
                }
            }
        }
        if (!currentFrame()) return;
        if (m_pressHandshakeState == PressHandshakeState::AwaitTelemetry) {
            m_pressHandshakeState = PressHandshakeState::Ready;
            m_pressInitializationTimer.stop();
            m_pressReconnectTimer.stop();
            m_pressReconnectAttempts = 0;
            m_pressConnectionState = ConnectionState::Ready;
            m_pressReady = (!MachineProtocolParsers::pressStateIsAlarm(telemetry->state)
                || telemetry->state == QStringLiteral("HYDRAULIC_SHUTDOWN"))
                && telemetry->state != QStringLiteral("UNKNOWN");
            qInfo().noquote() << "MACHINE-HANDSHAKE device=press result=ready"
                              << "firmware=" + m_pressFirmwareVersion
                              << "machineState=" + m_pressMachineState
                              << "toolChange=" + QString::number(m_pressToolChangeSupported ? 1 : 0);
            // The <TCH?> sent right after <VER> can be lost while the
            // firmware is still printing its banner: re-probe once ready.
            if (!m_pressToolChangeSupported && nativeTonnageHoldSupported())
                m_pressTransport->writeFrame(QByteArrayLiteral("<TCH?>\n"));
        } else {
            m_pressReady = (!MachineProtocolParsers::pressStateIsAlarm(telemetry->state)
                || telemetry->state == QStringLiteral("HYDRAULIC_SHUTDOWN"))
                && telemetry->state != QStringLiteral("UNKNOWN");
        }
        // Idle (no active press command): identical telemetry carries nothing
        // new for QML. Active commands keep per-frame publication because
        // samplers (manual measurement) consume each telemetry sequence.
        if (m_pressCommandPhase == PressCommandPhase::Idle
            && pressObservableSnapshot() == m_publishedPressSnapshot)
            return;
        emit pressStateChanged();
        emit telemetryChanged();
        return;
    }
    if (m_pressHandshakeState != PressHandshakeState::AwaitWelcome)
        return;
    if (!match.hasMatch())
        return;
    m_pressFirmwareIdentity = match.captured(0);
    m_pressFirmwareVersion = match.captured(1);
    qInfo().noquote() << "MACHINE-HANDSHAKE device=press phase=welcome"
                      << "firmware=" + m_pressFirmwareVersion;
    m_pressHandshakeState = PressHandshakeState::AwaitTelemetry;
    m_pressInitializationTimer.start();
    m_pressConnectionState = ConnectionState::Initializing;
    m_pressReady = false;
    m_pressMachineState = QStringLiteral("UNKNOWN");
    emit pressStateChanged();
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<VER>\n"))) {
        failPressInitialization(QStringLiteral("HANDSHAKE_WRITE_FAILED"));
        return;
    }
    // Optional capability probe; older images ignore it and stay unsupported.
    m_pressToolChangeSupported = false;
    if (nativeTonnageHoldSupported())
        m_pressTransport->writeFrame(QByteArrayLiteral("<TCH?>\n"));
    if (m_pressHandshakeState == PressHandshakeState::AwaitTelemetry
        || m_pressHandshakeState == PressHandshakeState::Ready)
        m_pressKeepAliveTimer.start();
}

void MachineControlBackend::handleModuleFrame(const QByteArray &frame)
{
    static const QRegularExpression welcomePattern(
        QStringLiteral("^Grbl ([^\\s]+) \\['\\$' for help\\]$"));
    const QString line = QString::fromLatin1(frame).trimmed();
    const QRegularExpressionMatch welcomeMatch = welcomePattern.match(line);
    if (m_moduleCommandPhase == ModuleCommandPhase::StopAwaitResetWelcome
        && welcomeMatch.hasMatch()) {
        m_moduleFirmwareVersion = welcomeMatch.captured(1);
        m_moduleHandshakeState = ModuleHandshakeState::AwaitSettingsOk;
        m_moduleCommandPhase = ModuleCommandPhase::StopReinitializing;
        m_moduleSettingsSeen = false;
        m_moduleModalSeen = false;
        m_moduleUnitSettingSeen = false;
        m_moduleWcoAvailable = false;
        m_moduleReady = false;
        m_moduleConnectionState = ConnectionState::Initializing;
        m_moduleInitializationTimer.start();
        emit moduleStateChanged();
        if (!m_moduleTransport->writeFrame(QByteArrayLiteral("$$\n")))
            failActiveCommand(QStringLiteral("REINITIALIZE_WRITE_FAILED"));
        return;
    }
    if (m_moduleHandshakeState != ModuleHandshakeState::Idle
        && m_moduleHandshakeState != ModuleHandshakeState::AwaitWelcome
        && welcomeMatch.hasMatch()) {
        failModuleInitialization(QStringLiteral("CONTROLLER_RESET_DETECTED"));
        return;
    }
    if (m_moduleHomePhase == ModuleHomePhase::AwaitUnlockAck) {
        if (line == QStringLiteral("ok")) {
            if (!m_moduleTransport->writeFrame(QByteArrayLiteral("$H\n"))) {
                if (m_moduleHomePhase != ModuleHomePhase::Idle)
                    failModuleHoming(QStringLiteral("HOME_WRITE_FAILED"));
                return;
            }
            m_moduleHomePhase = ModuleHomePhase::AwaitHomeAck;
            m_moduleHomingTimer.start();
            qInfo().noquote() << "MACHINE-HOME device=module phase=home state=SENT";
            return;
        }
        if (line.startsWith(QStringLiteral("error:"))
            || line.startsWith(QStringLiteral("ALARM:"))) {
            failModuleHoming(QStringLiteral("UNLOCK_REJECTED"));
            return;
        }
    } else if (m_moduleHomePhase == ModuleHomePhase::AwaitHomeAck) {
        if (line == QStringLiteral("ok")) {
            m_moduleHomePhase = ModuleHomePhase::AwaitIdleTelemetry;
            if (!m_moduleHomeConcurrent) {
                m_operationState = QStringLiteral("ACKNOWLEDGED");
                emit commandLifecycleChanged();
            }
            m_moduleHomingTimer.start();
            return;
        }
        if (line.startsWith(QStringLiteral("error:"))
            || line.startsWith(QStringLiteral("ALARM:"))) {
            failModuleHoming(QStringLiteral("HOME_REJECTED"));
            return;
        }
    }
    if (m_moduleCommandPhase != ModuleCommandPhase::Idle
        && m_moduleCommandPhase != ModuleCommandPhase::StopAwaitResetWelcome
        && m_moduleCommandPhase != ModuleCommandPhase::StopReinitializing) {
        if (m_moduleCommandPhase == ModuleCommandPhase::AwaitJogIdle
            && (line == QStringLiteral("ok") || line.startsWith(QStringLiteral("error:")))) {
            // Responses for segments queued before the 0x85 cancel. GRBL may
            // reject them (error:8) while the cancel decelerates; harmless.
            if (m_moduleContinuousInFlight > 0)
                --m_moduleContinuousInFlight;
            if (line == QStringLiteral("ok"))
                acknowledgeCommandOperation();
            if (m_moduleJogCancelPending && m_moduleContinuousInFlight == 0) {
                m_moduleJogCancelPending = false;
                if (!m_moduleTransport->writeFrame(QByteArrayLiteral("\x85")))
                    failActiveCommand(QStringLiteral("JOG_CANCEL_WRITE_FAILED"));
            }
            return;
        }
        if (line.startsWith(QStringLiteral("error:"))) {
            failActiveCommand(QStringLiteral("GRBL_") + line.toUpper()
                              .replace(QLatin1Char(':'), QLatin1Char('_')));
            return;
        }
        if (line.startsWith(QStringLiteral("ALARM:"))) {
            m_moduleHomed = false;
            failActiveCommand(QStringLiteral("GRBL_") + line.toUpper()
                              .replace(QLatin1Char(':'), QLatin1Char('_')));
            return;
        }
        if (line == QStringLiteral("ok")) {
            acknowledgeCommandOperation();
            if (m_moduleCommandPhase == ModuleCommandPhase::ContinuousJogging) {
                // Match Java ContinuousJogOperation: one native lifecycle owns
                // the hold and queues the next bounded segment only after GRBL
                // acknowledges the prior segment. QML must not race a timer
                // against command admission or cancellation.
                if (m_moduleContinuousInFlight > 0)
                    --m_moduleContinuousInFlight;
                if (!m_moduleTransport->writeFrame(m_moduleCommandFrames.first()))
                    failActiveCommand(QStringLiteral("JOG_WRITE_FAILED"));
                else
                    ++m_moduleContinuousInFlight;
                return;
            }
            if (m_moduleCommandPhase == ModuleCommandPhase::AwaitFirstAck) {
                if (m_moduleCommandFrameIndex + 1 < m_moduleCommandFrames.size()) {
                    ++m_moduleCommandFrameIndex;
                    m_moduleCommandPhase = ModuleCommandPhase::AwaitSecondAck;
                    writeNextModuleFrame();
                } else if (m_moduleTargetRequired) {
                    m_moduleCommandPhase = ModuleCommandPhase::AwaitIdleTelemetry;
                } else {
                    completeActiveModuleCommand();
                }
                return;
            }
            if (m_moduleCommandPhase == ModuleCommandPhase::AwaitSecondAck) {
                m_moduleCommandPhase = ModuleCommandPhase::AwaitIdleTelemetry;
                return;
            }
        }
    }
    switch (m_moduleHandshakeState) {
    case ModuleHandshakeState::AwaitWelcome: {
        if (!welcomeMatch.hasMatch())
            return;
        m_moduleFirmwareVersion = welcomeMatch.captured(1);
        qInfo().noquote() << "MACHINE-HANDSHAKE device=module phase=welcome"
                  << "firmware=" + m_moduleFirmwareVersion;
        m_moduleHandshakeState = ModuleHandshakeState::AwaitSettingsOk;
        m_moduleSettingsSeen = false;
        m_moduleInitializationTimer.start();
        if (!m_moduleTransport->writeFrame(QByteArrayLiteral("$$\n")))
            failModuleInitialization(QStringLiteral("HANDSHAKE_WRITE_FAILED"));
        return;
    }
    case ModuleHandshakeState::AwaitSettingsOk:
        if (line.startsWith(QLatin1Char('$')) && line.contains(QLatin1Char('='))) {
            m_moduleSettingsSeen = true;
            bool settingOk = false;
            const double settingValue = line.section(QLatin1Char('='), 1, 1)
                                            .toDouble(&settingOk);
            if (settingOk) {
                if (line.startsWith(QStringLiteral("$110=")))
                    m_moduleMaxRateX = settingValue / 25.4;
                else if (line.startsWith(QStringLiteral("$111=")))
                    m_moduleMaxRateR = settingValue / 25.4;
                else if (line.startsWith(QStringLiteral("$120=")))
                    m_moduleAccelerationX = settingValue / 25.4;
                else if (line.startsWith(QStringLiteral("$121=")))
                    m_moduleAccelerationR = settingValue / 25.4;
            }
            if (line.startsWith(QStringLiteral("$13="))) {
                bool ok = false;
                const int value = line.section(QLatin1Char('='), 1, 1).toInt(&ok);
                if (ok && (value == 0 || value == 1)) {
                    m_moduleInches = value == 1;
                    m_moduleUnitSettingSeen = true;
                    qInfo().noquote() << "MACHINE-HANDSHAKE device=module phase=units"
                                      << "value=" + QString::number(value);
                }
            }
            return;
        }
        if (line == QStringLiteral("ok") && m_moduleSettingsSeen) {
            if (!m_moduleUnitSettingSeen) {
                failModuleInitialization(QStringLiteral("UNIT_SETTING_MISSING"));
                return;
            }
            m_moduleHandshakeState = ModuleHandshakeState::AwaitModalOk;
            m_moduleModalSeen = false;
            m_moduleInitializationTimer.start();
            if (!m_moduleTransport->writeFrame(QByteArrayLiteral("$G\n")))
                failModuleInitialization(QStringLiteral("HANDSHAKE_WRITE_FAILED"));
            else
                qInfo().noquote() << "MACHINE-HANDSHAKE device=module phase=settings-ready";
        }
        return;
    case ModuleHandshakeState::AwaitModalOk:
        if (line.startsWith(QStringLiteral("[GC:")) && line.endsWith(QLatin1Char(']'))) {
            m_moduleModalSeen = true;
            return;
        }
        if (line == QStringLiteral("ok") && m_moduleModalSeen) {
            m_moduleHandshakeState = ModuleHandshakeState::AwaitStatus;
            m_moduleInitializationTimer.start();
            m_moduleStatusPollTimer.start();
            pollModuleStatus();
            qInfo().noquote() << "MACHINE-HANDSHAKE device=module phase=modal-ready";
        }
        return;
    case ModuleHandshakeState::AwaitStatus:
    case ModuleHandshakeState::Ready:
        {
            const auto telemetry = MachineProtocolParsers::parseGrblTelemetry(frame);
            if (!telemetry)
                return;
            // The 200 ms status poll repeats identical frames while idle; only
            // notify QML when observable state changes, otherwise every poll
            // re-evaluates bindings and forces a full scene-graph frame.
            const auto observableModuleState = [this]() {
                return std::make_tuple(m_moduleWorkX, m_moduleWorkR,
                    m_moduleMachineX, m_moduleMachineR,
                    m_moduleLimitX1, m_moduleLimitX2, m_moduleLimitR1, m_moduleLimitR2,
                    m_moduleState, m_moduleOperationActive, m_moduleHomed,
                    m_moduleTelemetryFresh, m_moduleReady,
                    m_moduleHandshakeState, m_moduleConnectionState,
                    m_moduleWcoAvailable, m_moduleHomePhase, m_moduleCommandPhase);
            };
            const auto stateBefore = observableModuleState();
            if (telemetry->workCoordinateOffset) {
                m_moduleWcoX = telemetry->workCoordinateOffset->x;
                m_moduleWcoR = telemetry->workCoordinateOffset->y;
                m_moduleWcoAvailable = true;
            }
            if (!m_moduleWcoAvailable)
                return;
            constexpr double millimetersPerInch = 25.4;
            const double scale = m_moduleInches ? 1.0 : 1.0 / millimetersPerInch;
            if (telemetry->machinePosition) {
                m_moduleMachineX = telemetry->machinePosition->x * scale;
                m_moduleMachineR = telemetry->machinePosition->y * scale;
                m_moduleWorkX = (telemetry->machinePosition->x - m_moduleWcoX) * scale;
                m_moduleWorkR = (telemetry->machinePosition->y - m_moduleWcoR) * scale;
            } else if (telemetry->workPosition) {
                m_moduleWorkX = telemetry->workPosition->x * scale;
                m_moduleWorkR = telemetry->workPosition->y * scale;
                m_moduleMachineX = (telemetry->workPosition->x + m_moduleWcoX) * scale;
                m_moduleMachineR = (telemetry->workPosition->y + m_moduleWcoR) * scale;
            }
            m_moduleLimitX1 = telemetry->activePins.contains(QStringLiteral("X1"));
            m_moduleLimitX2 = telemetry->activePins.contains(QStringLiteral("X2"));
            m_moduleLimitR1 = telemetry->activePins.contains(QStringLiteral("Y1"));
            m_moduleLimitR2 = telemetry->activePins.contains(QStringLiteral("Y2"));
            m_moduleState = telemetry->state;
            const bool telemetryOperationActive = telemetry->state == QStringLiteral("RUN")
                || telemetry->state == QStringLiteral("JOG")
                || telemetry->state == QStringLiteral("HOME")
                || telemetry->state.startsWith(QStringLiteral("HOLD_"));
            m_moduleOperationActive = m_moduleHomePhase != ModuleHomePhase::Idle
                || m_moduleCommandPhase != ModuleCommandPhase::Idle
                || telemetryOperationActive;
            if (telemetry->state == QStringLiteral("HOME")
                && m_moduleHomePhase != ModuleHomePhase::Idle)
                m_moduleHomed = false;
            else if (telemetry->state == QStringLiteral("IDLE")
                     && (m_moduleLimitX1 || m_moduleLimitX2
                         || m_moduleLimitR1 || m_moduleLimitR2))
                m_moduleHomed = true;
            m_moduleTelemetryFresh = true;
            m_moduleTelemetryFreshnessTimer.start();
            if (m_moduleHandshakeState == ModuleHandshakeState::Ready)
                m_moduleReady = true;
            if (m_moduleHomePhase == ModuleHomePhase::AwaitHomeAck
                && telemetry->state == QStringLiteral("HOME")) {
                m_moduleHomePhase = ModuleHomePhase::AwaitIdleTelemetry;
                if (!m_moduleHomeConcurrent) {
                    m_operationState = QStringLiteral("ACKNOWLEDGED");
                    emit commandLifecycleChanged();
                }
                m_moduleHomingTimer.start();
            }
            if (m_moduleHomePhase == ModuleHomePhase::AwaitIdleTelemetry
                && telemetry->state == QStringLiteral("IDLE")) {
                m_moduleHomed = true;
                qInfo().noquote() << "MACHINE-HOME device=module state=COMPLETED";
                finishHomeOperation(QStringLiteral("module"), QStringLiteral("COMPLETED"));
            } else if ((m_moduleHomePhase == ModuleHomePhase::AwaitHomeAck
                        || m_moduleHomePhase == ModuleHomePhase::AwaitIdleTelemetry)
                       && telemetry->state == QStringLiteral("ALARM")) {
                failModuleHoming(QStringLiteral("CONTROLLER_ALARM"));
                return;
            }
            if (m_moduleCommandPhase != ModuleCommandPhase::Idle) {
                if (telemetry->state == QStringLiteral("ALARM")) {
                    m_moduleHomed = false;
                    failActiveCommand(QStringLiteral("CONTROLLER_ALARM"));
                    return;
                }
                if (m_moduleCommandPhase == ModuleCommandPhase::AwaitJogIdle
                    && !m_moduleJogCancelPending && m_moduleContinuousInFlight == 0
                    && telemetry->state != QStringLiteral("JOG")) {
                    completeActiveModuleCommand();
                } else if (m_moduleCommandPhase == ModuleCommandPhase::AwaitIdleTelemetry
                           && telemetry->state == QStringLiteral("IDLE")) {
                    constexpr double targetToleranceInches = 0.003;
                    if (!m_moduleTargetRequired
                        || (std::abs(m_moduleWorkX - m_moduleTargetX) <= targetToleranceInches
                            && std::abs(m_moduleWorkR - m_moduleTargetR)
                                <= targetToleranceInches)) {
                        completeActiveModuleCommand();
                    }
                } else if (m_moduleCommandPhase == ModuleCommandPhase::StopAwaitHold
                           && telemetry->state == QStringLiteral("HOLD_0")) {
                    acknowledgeCommandOperation();
                    m_moduleCommandPhase = ModuleCommandPhase::StopAwaitResetWelcome;
                    m_moduleConnectionState = ConnectionState::Resetting;
                    m_moduleReady = false;
                    if (!m_moduleTransport->writeFrame(QByteArrayLiteral("\x18"))) {
                        failActiveCommand(QStringLiteral("RESET_WRITE_FAILED"));
                        return;
                    }
                }
            }
        if (m_moduleHandshakeState == ModuleHandshakeState::AwaitStatus) {
            m_moduleHandshakeState = ModuleHandshakeState::Ready;
            m_moduleInitializationTimer.stop();
            m_moduleReconnectTimer.stop();
            m_moduleReconnectAttempts = 0;
            m_moduleConnectionState = ConnectionState::Ready;
            m_moduleReady = true;
            qInfo().noquote() << "MACHINE-HANDSHAKE device=module result=ready"
                              << "firmware=" + m_moduleFirmwareVersion
                              << "machineState=" + m_moduleState;
        }
        if (m_moduleCommandPhase == ModuleCommandPhase::StopReinitializing
            && m_moduleHandshakeState == ModuleHandshakeState::Ready
            && m_moduleState == QStringLiteral("IDLE")) {
            m_moduleHomed = m_moduleHomedBeforeStop;
            completeActiveModuleCommand();
        }
        if (observableModuleState() != stateBefore)
            emit moduleStateChanged();
        return;
        }
    case ModuleHandshakeState::Idle:
        return;
    }
}

void MachineControlBackend::failPressInitialization(const QString &reason)
{
    if (thcContinuousActive()) beginThcV53Cancellation(reason);
    if (m_thcV51Phase != ThcV51Phase::Inactive)
        beginThcV51Cancellation(reason);
    if (m_pressHandshakeState == PressHandshakeState::Idle)
        return;
    qWarning().noquote() << "MACHINE-HANDSHAKE device=press result=failed reason=" + reason;
    if (m_pressTransport->isOpen())
        m_pressTransport->close();
    else {
        clearPressState();
        emit pressStateChanged();
    }
    emit connectionFailed(QStringLiteral("press"), reason);
}

void MachineControlBackend::failModuleInitialization(const QString &reason)
{
    if (m_moduleHandshakeState == ModuleHandshakeState::Idle)
        return;
    qWarning().noquote() << "MACHINE-HANDSHAKE device=module result=failed reason=" + reason;
    if (m_moduleTransport->isOpen())
        m_moduleTransport->close();
    else {
        clearModuleState();
        emit moduleStateChanged();
    }
    emit connectionFailed(QStringLiteral("module"), reason);
}

void MachineControlBackend::pollModuleStatus()
{
    if (m_moduleHandshakeState == ModuleHandshakeState::AwaitStatus
        || m_moduleHandshakeState == ModuleHandshakeState::Ready) {
        if (!m_moduleTransport->writeFrame(QByteArrayLiteral("?")))
            failModuleInitialization(QStringLiteral("STATUS_POLL_WRITE_FAILED"));
    }
}

void MachineControlBackend::sendPressKeepAlive()
{
    if ((m_pressHandshakeState == PressHandshakeState::AwaitTelemetry
         || m_pressHandshakeState == PressHandshakeState::Ready)
        && !m_pressTransport->writeFrame(QByteArrayLiteral("<?>\n"))) {
        if (thcContinuousActive()) {
            beginThcV53Cancellation(QStringLiteral("THC_V53_KEEP_ALIVE_WRITE_FAILED"));
            return;
        }
        if (m_thcV51Phase != ThcV51Phase::Inactive) {
            beginThcV51Cancellation(QStringLiteral("THC_V51_KEEP_ALIVE_WRITE_FAILED"));
            return;
        }
        failPressInitialization(QStringLiteral("KEEP_ALIVE_WRITE_FAILED"));
    }
}

void MachineControlBackend::sendTonnageHoldHeartbeat()
{
    if (m_pressCommandPhase != PressCommandPhase::NativeTonnageHold
        || !m_pressConnected || !m_pressTransport->isOpen()) {
        m_tonnageHoldHeartbeatTimer.stop();
        return;
    }
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<TH:HB>\n"))) {
        m_tonnageHoldHeartbeatTimer.stop();
        beginPressSafetyFailure(QStringLiteral("TONNAGE_HOLD_HEARTBEAT_WRITE_FAILED"),
                                QByteArrayLiteral("<stop>\n"));
    }
}

void MachineControlBackend::sendPrimingHeartbeat()
{
    if (!m_pressConnected || !m_pressTransport->isOpen() || !m_pressReady
        || !m_primingModeEnabled || !m_primingLatchSupported
        || (!m_primingLatchY1 && !m_primingLatchY2)) {
        m_primingHeartbeatTimer.stop();
        return;
    }
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<PrimingHeartbeat>\n"))) {
        // A failed renewal must not leave a UI that implies authority. The
        // firmware lease independently expires within one second.
        m_primingHeartbeatTimer.stop();
        m_primingLatchY1 = false;
        m_primingLatchY2 = false;
        emit telemetryChanged();
    }
}

void MachineControlBackend::sendThcContactProfileHeartbeat()
{
    if (m_pressCommandPhase != PressCommandPhase::ThcCommissioning
        || !m_thcContactProfileActive || !m_thcContactProfileAutomaticLifecycle
        || !m_pressConnected || !m_pressTransport->isOpen()) {
        m_thcContactProfileHeartbeatTimer.stop();
        return;
    }
    if (!m_pressTransport->writeFrame(QByteArrayLiteral("<THC:HB>\n"))) {
        m_thcContactProfileHeartbeatTimer.stop();
        failActiveCommand(QStringLiteral("THC_HEARTBEAT_WRITE_FAILED"));
    }
}

void MachineControlBackend::expirePressTelemetry()
{
    if (!m_pressTelemetryFresh)
        return;
    if (m_pressHomePending) {
        failPressHoming(QStringLiteral("TELEMETRY_STALE"));
        return;
    }
    const bool activePressCommand = m_operationDevice == QStringLiteral("press")
        && commandOperationActive();
    const bool safetyStopPending = activePressCommand && pressPhaseRequiresSafetyStop();
    if (thcContinuousActive())
        beginThcV53Cancellation(QStringLiteral("THC_V53_TELEMETRY_STALE"));
    else if (m_thcV51Phase != ThcV51Phase::Inactive)
        beginThcV51Cancellation(QStringLiteral("THC_V51_TELEMETRY_STALE"));
    else if (safetyStopPending)
        beginPressSafetyFailure(QStringLiteral("TELEMETRY_STALE"),
                                QByteArrayLiteral("<stop>\n"));
    else if (activePressCommand
             && m_pressCommandPhase != PressCommandPhase::AwaitFailureStopIdle)
        failActiveCommand(QStringLiteral("TELEMETRY_STALE"));
    revokePrimingLatchPresentation();
    m_programRunActive = false;
    m_pressTelemetryFresh = false;
    m_independentRamTelemetryAvailable = false;
    m_pressReady = false;
    m_pressHomed = false;
    m_pressOperationActive = m_pressCommandPhase == PressCommandPhase::AwaitFailureStopIdle
        || m_pressCommandPhase == PressCommandPhase::ThcV51 || m_pressCommandPhase == PressCommandPhase::ThcV53;
    invalidateThcLiveTuning(QStringLiteral("V53_TELEMETRY_STALE"), true);
    m_pressMachineState = QStringLiteral("UNKNOWN");
    m_safetyJogLeft = false;
    m_safetyJogRight = false;
    m_bendPedal = false;
    m_physicalPedal = false;
    m_physicalPedalAvailable = false;
    m_antiBind = false;
    emit pressStateChanged();
    emit telemetryChanged();
}

void MachineControlBackend::expireModuleTelemetry()
{
    if (!m_moduleTelemetryFresh)
        return;
    if (m_moduleHomePhase != ModuleHomePhase::Idle)
        return;
    if (m_operationDevice == QStringLiteral("module") && commandOperationActive())
        failActiveCommand(QStringLiteral("TELEMETRY_STALE"));
    m_programRunActive = false;
    m_moduleTelemetryFresh = false;
    m_moduleReady = false;
    m_moduleOperationActive = false;
    m_moduleState = QStringLiteral("UNKNOWN");
    m_moduleLimitX1 = false;
    m_moduleLimitX2 = false;
    m_moduleLimitR1 = false;
    m_moduleLimitR2 = false;
    emit moduleStateChanged();
}

QVariantList MachineControlBackend::pressObservableSnapshot() const
{
    static const QList<int> propertyIndexes = [] {
        QList<int> indexes;
        const QMetaObject &meta = MachineControlBackend::staticMetaObject;
        const QMetaMethod pressSignal =
            QMetaMethod::fromSignal(&MachineControlBackend::pressStateChanged);
        const QMetaMethod telemetrySignal =
            QMetaMethod::fromSignal(&MachineControlBackend::telemetryChanged);
        for (int i = meta.propertyOffset(); i < meta.propertyCount(); ++i) {
            const QMetaProperty property = meta.property(i);
            const QMetaMethod notify = property.notifySignal();
            if ((notify == pressSignal || notify == telemetrySignal)
                && qstrcmp(property.name(), "pressTelemetrySequence") != 0)
                indexes.append(i);
        }
        return indexes;
    }();
    QVariantList values;
    values.reserve(propertyIndexes.size());
    for (int index : propertyIndexes)
        values.append(staticMetaObject.property(index).read(this));
    return values;
}
