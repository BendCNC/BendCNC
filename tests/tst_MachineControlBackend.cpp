#include <QSignalSpy>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaProperty>
#include <QTemporaryDir>
#include <QtTest>
#include <algorithm>
#include <array>
#include <functional>
#include <limits>

#include "MachineControlBackend.h"
#include "MachineProtocolParsers.h"
#include "MachineTransport.h"
#include "SerialDeviceDiscovery.h"
#include "SerialMachineTransport.h"
#include "ThcV53RemoteTuning.h"

class ScriptedMachineTransport final : public MachineTransport
{
public:
    explicit ScriptedMachineTransport(bool available, QObject *parent = nullptr)
        : MachineTransport(parent), m_available(available)
    {
    }

    bool isAvailable() const override { return m_available; }
    bool isOpen() const override { return m_open; }
    QString endpointId() const override { return m_available ? QStringLiteral("scripted:1") : QString(); }
    QString endpointDisplayName() const override { return m_available ? QStringLiteral("Scripted endpoint") : QString(); }
    bool open() override
    {
        if (!m_available)
            return false;
        if (!m_openSucceeds) {
            if (!m_openError.isEmpty())
                emit transportError(m_openError);
            return false;
        }
        m_open = true;
        emit opened();
        return true;
    }
    void close() override
    {
        if (!m_open)
            return;
        m_open = false;
        emit closed();
    }
    bool writeFrame(const QByteArray &frame) override
    {
        emit frameWriteAttempted(frame);
        m_writes.push_back(frame);
        const auto hook = m_writeHook;
        if (hook)
            hook(frame);
        const bool written = m_writeSucceeds && frame != m_failedFrame;
        if (written)
            emit frameWritten(SerialMachineTransport::machineLogContent(frame));
        return written;
    }
    void setDiagnosticLoggingEnabled(bool enabled) override
    {
        m_diagnosticLoggingEnabled = enabled;
    }
    bool diagnosticLoggingEnabled() const override
    {
        return m_diagnosticLoggingEnabled;
    }
    void setAvailable(bool available)
    {
        if (m_available == available)
            return;
        m_available = available;
        emit availabilityChanged();
    }
    void fail(const QString &message) { emit transportError(message); }
    void receive(const QByteArray &frame) { emit frameReceived(frame); }
    void drop()
    {
        m_open = false;
        emit closed();
    }
    qsizetype writeCount() const { return m_writes.size(); }
    QByteArray writeAt(qsizetype index) const { return m_writes.at(index); }
    void setWriteSucceeds(bool succeeds) { m_writeSucceeds = succeeds; }
    void setFailedFrame(const QByteArray &frame) { m_failedFrame = frame; }
    void setWriteHook(std::function<void(const QByteArray &)> hook) { m_writeHook = std::move(hook); }
    void setOpenSucceeds(bool succeeds) { m_openSucceeds = succeeds; }
    void setOpenError(QString message) { m_openError = std::move(message); }
    bool diagnosticLoggingWasEnabled() const { return m_diagnosticLoggingEnabled; }

private:
    bool m_available = false;
    bool m_open = false;
    bool m_openSucceeds = true;
    QString m_openError;
    bool m_writeSucceeds = true;
    QByteArray m_failedFrame;
    std::function<void(const QByteArray &)> m_writeHook;
    QList<QByteArray> m_writes;
    bool m_diagnosticLoggingEnabled = false;
};

class EnvironmentVariableGuard final
{
public:
    explicit EnvironmentVariableGuard(const char *name)
        : m_name(name), m_wasSet(qEnvironmentVariableIsSet(name)), m_value(qgetenv(name))
    {
    }

    ~EnvironmentVariableGuard()
    {
        if (m_wasSet)
            qputenv(m_name, m_value);
        else
            qunsetenv(m_name);
    }

private:
    const char *m_name;
    bool m_wasSet;
    QByteArray m_value;
};

class MachineControlBackendTests final : public QObject
{
    Q_OBJECT

    static QString v51Hash()
    {
        return QStringLiteral("a79f02982fdbec4f08bf494d08c22e05b2bb144d0fa3890b3cd537e4fadccd14");
    }

    static QByteArray v51Idle()
    {
        return QByteArrayLiteral("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
    }

    static QByteArray v51ProductionTelemetry(const QByteArray &state = QByteArrayLiteral("IDLE"),
                                            const QByteArray &pidOutput = QByteArrayLiteral("-7.25"))
    {
        // 20-field production layout: retained pidOutput at 4, independently
        // reported measured velocities/RPM at 15..18, physical pedal at 19.
        return '<' + state + "|-0.2|-0.2|0|" + pidOutput
            + "|-0.2|-0.2|1|1|1|0|0|0.4|0.5|0|0|0|0|0|0>";
    }

    static bool v51ModuleReady(MachineControlBackend &backend, ScriptedMachineTransport *raw)
    {
        if (!backend.connectModule())
            return false;
        raw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        raw->receive(QByteArrayLiteral("$13=1"));
        raw->receive(QByteArrayLiteral("ok"));
        raw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        raw->receive(QByteArrayLiteral("ok"));
        raw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        return backend.moduleReady();
    }

    static bool v51Ready(MachineControlBackend &backend, ScriptedMachineTransport *raw,
                         const QByteArray &identity = QByteArrayLiteral("[LS-BEND v1.3]"))
    {
        if (!backend.connectPress())
            return false;
        raw->receive(identity);
        raw->receive(v51Idle());
        return backend.pressReady() && backend.pressHomed();
    }

    static qsizetype countWrites(ScriptedMachineTransport *raw, const QByteArray &frame)
    {
        qsizetype count = 0;
        for (qsizetype n = 0; n < raw->writeCount(); ++n)
            count += raw->writeAt(n) == frame;
        return count;
    }

    static void v51Contact(ScriptedMachineTransport *raw)
    {
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        raw->receive(QByteArrayLiteral("{THC:CONTACT}"));
    }

    static QByteArray v53Reply(const QByteArray &revision = "0", const QByteArray &kp = "0.150000",
                               int version = 1)
    {
        return "{THC:V53:v=" + QByteArray::number(version) + ",kp=" + kp
            + ",ki=0.020000,kd=0.030000,rate=0.010000,cq=0.010000,fs=0.050000,revision=" + revision + '}';
    }

    static QVariantMap v53Settings(double kp = 0.15)
    {
        return {{QStringLiteral("kp"), kp}, {QStringLiteral("ki"), 0.02},
            {QStringLiteral("kd"), 0.03}, {QStringLiteral("rate"), 0.01},
            {QStringLiteral("cq"), 0.01}, {QStringLiteral("fs"), 0.05}};
    }

    static bool v53Ready(MachineControlBackend &backend, ScriptedMachineTransport *raw,
                         int version = 1)
    {
        if (!v51Ready(backend, raw)) return false;
        raw->receive(v51ProductionTelemetry()); // fresh physical-pedal evidence
        if (!backend.queryThcLiveTuning()) return false;
        raw->receive(v53Reply("0", "0.150000", version));
        return backend.thcLiveTuningSupported();
    }

    static void v53Hold(ScriptedMachineTransport *raw)
    {
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V53_RUNNING}"));
        raw->receive(QByteArrayLiteral("{THC:CONTACT}"));
        raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
    }

    static QByteArray v53Control(quint32 ms, quint32 seq, quint32 age = 5,
                                  const QByteArray &f1 = "0.45001")
    {
        return "[TH_CTRL ms=" + QByteArray::number(ms) + " age=" + QByteArray::number(age)
            + " ph=2 f1=" + f1 + " f2=0.55002 req=0.01300 v=0.01200 p=0.00100 i=0.00200 d=-0.00300"
            " ev1=0.000 ev2=0.000 ap1=0.000 ap2=0.000 clamp=0 hr=1 hn=2 hl=1 ha=0.010 fr=0"
            " profile=V46_LIVE_V53 seq=" + QByteArray::number(seq) + ']';
    }

private slots:
    void pressSafetyStopPropertyHomeRecovery_data()
    {
        QTest::addColumn<bool>("reconnect");
        QTest::newRow("same-session") << false;
        QTest::newRow("reconnected-idle-is-not-proof") << true;
    }

    void pressSafetyStopPropertyHomeRecovery()
    {
        QFETCH(bool, reconnect);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        const int index = backend.metaObject()->indexOfProperty("pressSafetyStopUnconfirmed");
        QVERIFY(index >= 0);
        const QMetaProperty property = backend.metaObject()->property(index);
        QCOMPARE(property.metaType(), QMetaType::fromType<bool>());
        QVERIFY(property.isReadable());
        QVERIFY(!property.isWritable());
        QVERIFY(property.isFinal());
        QVERIFY(property.hasNotifySignal());
        QCOMPARE(property.notifySignal().name(), QByteArrayLiteral("pressStateChanged"));
        QSignalSpy notify(&backend, property.notifySignal());
        QVERIFY(notify.isValid());
        QList<bool> transitions;
        bool observedLatch = property.read(&backend).toBool();
        connect(&backend, &MachineControlBackend::pressStateChanged, &backend, [&] {
            const bool value = property.read(&backend).toBool();
            if (value != observedLatch) {
                transitions.push_back(value);
                observedLatch = value;
            }
        });
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        const auto owner = backend.operationId();
        notify.clear();
        QVERIFY(backend.cancelThcCommissioning());
        QVERIFY(!notify.isEmpty());
        QCOMPARE(transitions, QList<bool>({true}));
        backend.m_thcV53PhaseDeadlineMs = backend.m_thcV53Clock.elapsed();
        QVERIFY(!backend.cancelThcCommissioning());
        QCOMPARE(backend.operationId(), owner);
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.thcCommissioningState(), QStringLiteral("FAILED_STOP_UNCONFIRMED"));
        QVERIFY(property.read(&backend).toBool());
        raw->receive(v51ProductionTelemetry());
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}")); // Late, retired owner cannot prove stop.
        QVERIFY(property.read(&backend).toBool());
        QVERIFY(!backend.queryThcLiveTuning());
        if (reconnect) {
            QVERIFY(backend.disconnectPress());
            QVERIFY(v51Ready(backend, raw));
            raw->receive(v51ProductionTelemetry());
            QVERIFY(property.read(&backend).toBool());
            QVERIFY(!backend.queryThcLiveTuning());
        }
        QVERIFY(backend.homePress());
        const auto homeId = backend.operationId();
        QVERIFY(property.read(&backend).toBool()); // Acceptance/transmission is not recovery.
        raw->receive(v51ProductionTelemetry()); // IDLE without Home progress is not recovery.
        QVERIFY(property.read(&backend).toBool());
        QVERIFY(backend.commandOperationActive());
        QVERIFY(!backend.queryThcLiveTuning());
        for (QTimer *timer : {&backend.m_thcV53HeartbeatTimer, &backend.m_thcV53ClientLeaseTimer,
                             &backend.m_thcV53PhaseTimer})
            QVERIFY(QMetaObject::invokeMethod(timer, "timeout", Qt::DirectConnection));
        QCOMPARE(backend.operationId(), homeId);
        QCOMPARE(backend.operationName(), QStringLiteral("home"));
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<$H>\n")), qsizetype(1));
        raw->receive(v51ProductionTelemetry("HOMING"));
        QVERIFY(property.read(&backend).toBool());
        QVERIFY(!backend.queryThcLiveTuning());
        notify.clear();
        raw->receive(v51ProductionTelemetry());
        QVERIFY(!property.read(&backend).toBool());
        QVERIFY(!notify.isEmpty());
        QCOMPARE(transitions, QList<bool>({true, false}));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(backend.thcCommissioningState(), QStringLiteral("FAILED_STOP_UNCONFIRMED"));
        QVERIFY(backend.pressHomed());
        QVERIFY(backend.queryThcLiveTuning());
        raw->receive(v53Reply());
        QVERIFY(backend.thcLiveTuningSupported());
        QCOMPARE(backend.operationId(), homeId);
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<$H>\n")), qsizetype(1));
    }

    void pressSafetyStopPropertyNotifiesOwnerRetirement()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        QSignalSpy notify(&backend, &MachineControlBackend::pressStateChanged);
        backend.finishCommandOperation(QStringLiteral("CANCEL_REQUESTED"));
        QVERIFY(backend.property("pressSafetyStopUnconfirmed").toBool());
        QCOMPARE(notify.size(), 1);
        QVERIFY(!backend.thcContinuousActive());
    }

    void pressSafetyStopPropertyNotifiesBeforeReentrantCancellationProof()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        QList<bool> transitions;
        bool observedLatch = false;
        connect(&backend, &MachineControlBackend::pressStateChanged, &backend, [&] {
            const bool value = backend.property("pressSafetyStopUnconfirmed").toBool();
            if (value != observedLatch) {
                transitions.push_back(value);
                observedLatch = value;
            }
        });
        bool deliveredProof = false;
        connect(&backend, &MachineControlBackend::thcLiveTuningChanged, &backend, [&] {
            if (deliveredProof || backend.thcCommissioningState() != QStringLiteral("CANCELLING")) return;
            deliveredProof = true;
            raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
            raw->receive(v51ProductionTelemetry());
        }, Qt::DirectConnection);
        QVERIFY(!backend.cancelThcCommissioning()); // Owner retired inside the notification.
        QVERIFY(deliveredProof);
        QCOMPARE(transitions, QList<bool>({true, false}));
        QVERIFY(!backend.pressSafetyStopUnconfirmed());
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.thcCommissioningState(), QStringLiteral("FAILED"));
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(0));
    }

    void pressSafetyStopPropertyNotifiesLegacyStop_data()
    {
        QTest::addColumn<bool>("abort");
        QTest::newRow("stop") << false;
        QTest::newRow("abort") << true;
    }

    void pressSafetyStopPropertyNotifiesLegacyStop()
    {
        QFETCH(bool, abort);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw, QByteArrayLiteral("[LS-BEND v1.1]")));
        bool notifiedLatch = false;
        connect(&backend, &MachineControlBackend::pressStateChanged, &backend, [&] {
            notifiedLatch |= backend.property("pressSafetyStopUnconfirmed").toBool();
        });
        QVERIFY(abort ? backend.abortPress() : backend.stopPressMotion());
        QVERIFY(backend.pressSafetyStopUnconfirmed());
        QVERIFY(notifiedLatch);
    }

    void thcV53CapabilityFailClosed_data()
    {
        QTest::addColumn<QByteArray>("reply");
        QTest::addColumn<bool>("accepted");
        QTest::newRow("exact") << v53Reply() << true;
        QTest::newRow("legacy-padding") << v53Reply("0", "000.150000") << true;
        const QByteArray maxLegacy = v53Reply("0", QByteArray(160 - v53Reply().size(), '0') + "0.150000");
        QTest::newRow("legacy-160-byte-reply") << maxLegacy << true;
        auto oversizedLegacy = maxLegacy;
        oversizedLegacy.insert(oversizedLegacy.indexOf("kp=") + 3, '0');
        QTest::newRow("legacy-161-byte-reply") << oversizedLegacy << false;
        QTest::newRow("v2") << v53Reply("0", "1.250000", 2) << true;
        for (const QByteArray &reply : {QByteArray("[LS-BEND v1.3]"),
             QByteArray("{THC:TUNE:v=1,cq=0.0100,fs=0.0500,rate=0.0100,auth=0.0200,brake=freeze,safe=freeze}"),
             QByteArray("{THC:ERROR:ARGUMENT}"), v53Reply("4294967296"), v53Reply("-1"),
             v53Reply("00"), v53Reply("0", "0.300001"), v53Reply("0", "nan"),
             v53Reply("0", "0.1500"), ' ' + v53Reply(), v53Reply() + ' ',
             v53Reply() + "\r\n", v53Reply().toLower(), v53Reply("0", "0.150000", 0),
             v53Reply("0", "0.150000", 3)})
            QTest::newRow(reply.constData()) << reply << false;
    }

    void thcV53CapabilityFailClosed()
    {
        QFETCH(QByteArray, reply);
        QFETCH(bool, accepted);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(!backend.thcLiveTuningSupported());
        raw->receive(v53Reply()); // unsolicited exact reply is not capability
        QVERIFY(!backend.thcLiveTuningSupported());
        QVERIFY(!backend.startContinuousThcContactProfile());
        const auto id = backend.operationId();
        QVERIFY(backend.queryThcLiveTuning());
        raw->receive(reply);
        if (backend.thcLiveTuningPending())
            QVERIFY(QMetaObject::invokeMethod(&backend.m_thcLiveRequestTimer, "timeout", Qt::DirectConnection));
        QCOMPARE(backend.thcLiveTuningSupported(), accepted);
        QCOMPARE(backend.operationId(), id);
        QVERIFY(!backend.thcLiveTuningPending());
        QVERIFY(!backend.thcContinuousActive());
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CONTACT_PROFILE_V53>\n")), qsizetype(0));
    }

    void thcV53Admission_data()
    {
        QTest::addColumn<QString>("gate");
        for (const char *gate : {"good", "no-query", "capability-expired", "not-homed", "stale",
                                "priming", "latch", "anti-bind", "physical-pedal", "pedal",
                                "no-physical-bit", "stop-unconfirmed", "program", "other-owner", "pending"})
            QTest::newRow(gate) << QString::fromLatin1(gate);
    }

    void thcV53Admission()
    {
        QFETCH(QString, gate);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        if (gate == "no-query") backend.m_thcLiveTuningSupported = false;
        if (gate == "capability-expired") backend.m_thcLiveCapabilityClock.invalidate();
        if (gate == "not-homed") backend.m_pressHomed = false;
        if (gate == "stale") backend.m_pressTelemetryFresh = false;
        if (gate == "priming") backend.m_primingModeEnabled = true;
        if (gate == "latch") backend.m_primingLatchY1 = true;
        if (gate == "anti-bind") backend.m_antiBind = true;
        if (gate == "physical-pedal") backend.m_physicalPedal = true;
        if (gate == "pedal") backend.m_bendPedal = true;
        if (gate == "no-physical-bit") backend.m_physicalPedalAvailable = false;
        if (gate == "stop-unconfirmed") backend.m_pressSafetyStopUnconfirmed = true;
        if (gate == "program") backend.m_programRunActive = true;
        if (gate == "other-owner") backend.m_pressOperationActive = true;
        if (gate == "pending") QVERIFY(backend.queryThcLiveTuning());
        const auto before = raw->writeCount();
        QCOMPARE(backend.startContinuousThcContactProfile(), gate == "good");
        QCOMPARE(raw->writeCount(), before + (gate == "good" ? 1 : 0));
        QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcContactProfileHeartbeatTimer.isActive());
        if (gate == "good") {
            QCOMPARE(raw->writeAt(before), QByteArrayLiteral("<THC:CONTACT_PROFILE_V53>\n"));
            QCOMPARE(backend.operationName(), QStringLiteral("thc-contact-profile-v53"));
            QVERIFY(backend.thcContinuousActive());
            QVERIFY(!backend.m_commandDeadlineTimer.isActive());
        }
    }

    void thcV53StartAck_data()
    {
        QTest::addColumn<QByteArray>("ack");
        QTest::addColumn<bool>("accepted");
        QTest::newRow("exact") << QByteArray("{THC:CONTACT_PROFILE_V53_RUNNING}") << true;
        for (const QByteArray &ack : {QByteArray("{THC:CONTACT_PROFILE_RUNNING}"),
             QByteArray("{THC:CONTACT_PROFILE_V51_RUNNING}"), QByteArray("{THC:RUNNING}"),
             QByteArray("{thc:contact_profile_v53_running}"), QByteArray(" {THC:CONTACT_PROFILE_V53_RUNNING}"),
             QByteArray("{THC:CONTACT_PROFILE_V53_RUNNING} "), QByteArray("{THC:CONTACT}"),
             QByteArray("{THC:HOLDING}"), QByteArray("{THC:DONE}")})
            QTest::newRow(ack.constData()) << ack << false;
    }

    void thcV53StartAck()
    {
        QFETCH(QByteArray, ack);
        QFETCH(bool, accepted);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        raw->receive(QByteArrayLiteral("[JOG COMPLETED]"));
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        raw->receive(ack);
        QCOMPARE(backend.m_thcV53RunningAcknowledged, accepted);
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(accepted ? 0 : 1));
        if (accepted) QCOMPARE(backend.m_thcV53PhaseDeadlineMs, qint64(45000));
        else {
            QVERIFY(!backend.m_thcV53HeartbeatTimer.isActive());
            QVERIFY(backend.pressSafetyStopUnconfirmed());
        }
    }

    void thcV53LiveTunePreservesOwnerAndDemand()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        raw->receive(v51ProductionTelemetry());
        const auto id = backend.operationId();
        const auto epoch = backend.m_thcV53Clock.msecsSinceReference();
        const auto lease = backend.m_thcV53ClientDeadlineMs;
        const double demand = backend.ramVelocity();
        QVERIFY(backend.applyThcLiveTuning(v53Settings(0.16)));
        QCOMPARE(raw->writeAt(raw->writeCount() - 1), QByteArrayLiteral("<THC:V53:TUNE:1,0.160000,0.020000,0.030000,0.010000,0.010000,0.050000>\n"));
        QVERIFY(!backend.applyThcLiveTuning(v53Settings(0.17)));
        QVERIFY(!backend.queryThcLiveTuning());
        QCOMPARE(backend.thcLiveTuning().value("kp").toDouble(), 0.15);
        raw->receive(v53Reply("1", "0.160000"));
        QCOMPARE(backend.thcLiveTuning().value("kp").toDouble(), 0.16);
        QCOMPARE(backend.thcLiveTuning().value("revision").toULongLong(), 1ULL);
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        QCOMPARE(backend.m_thcV53Clock.msecsSinceReference(), epoch);
        QCOMPARE(backend.m_thcV53ClientDeadlineMs, lease);
        QCOMPARE(backend.m_thcV53PhaseDeadlineMs, qint64(-1));
        QCOMPARE(backend.ramVelocity(), demand);
        QVERIFY(backend.queryThcLiveTuning());
        raw->receive(v53Reply("1", "0.160000"));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.m_thcV53ClientDeadlineMs, lease);
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CONTACT_PROFILE_V53>\n")), qsizetype(1));
        QVERIFY(!backend.m_thcV51Clock.isValid());
    }

    void thcV53TuneBounds_data()
    {
        QTest::addColumn<QString>("field");
        QTest::addColumn<QVariant>("value");
        for (const auto &item : QList<QPair<QString, QVariant>>{
             {"kp", -0.000001}, {"kp", 0.300001}, {"ki", 0.040001}, {"kd", 0.060001},
             {"rate", 0.001999}, {"rate", 0.010001}, {"cq", 0.004999}, {"cq", 0.020001},
             {"fs", 0.019999}, {"fs", 0.100001}, {"kp", QStringLiteral("0.15")},
             {"kp", true}, {"kp", std::numeric_limits<double>::quiet_NaN()},
             {"kp", std::numeric_limits<double>::infinity()}, {"extra", 0.1}}) {
            const auto name = (item.first + ':' + item.second.toString()).toLatin1();
            QTest::newRow(name.constData()) << item.first << item.second;
        }
    }

    void thcV53TuneBounds()
    {
        QFETCH(QString, field);
        QFETCH(QVariant, value);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        auto settings = v53Settings();
        settings.insert(field, value);
        const auto before = raw->writeCount();
        QVERIFY(!backend.applyThcLiveTuning(settings));
        QCOMPARE(raw->writeCount(), before);
        QVERIFY(backend.thcLiveTuningSupported());
        settings = v53Settings();
        settings["cq"] = 0.02;
        settings["fs"] = 0.02;
        QVERIFY(!backend.applyThcLiveTuning(settings));
        settings.remove("kp");
        QVERIFY(!backend.applyThcLiveTuning(settings));
    }

    void thcV53IdleTuneCanonicalBoundsAndNoMotionOwner()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        const auto id = backend.operationId();
        const auto state = backend.operationState();
        auto low = v53Settings();
        low["kp"] = 0.0;
        low["ki"] = 0.0;
        low["kd"] = 0.0;
        low["rate"] = 0.002;
        low["cq"] = 0.005;
        low["fs"] = 0.020;
        QVERIFY(backend.applyThcLiveTuning(low));
        raw->receive(QByteArrayLiteral("{THC:V53:v=1,kp=0.000000,ki=0.000000,kd=0.000000,rate=0.002000,cq=0.005000,fs=0.020000,revision=1}"));
        QVERIFY(backend.thcLiveTuningSupported());
        auto high = v53Settings();
        high["kp"] = 0.30;
        high["ki"] = 0.04;
        high["kd"] = 0.06;
        high["rate"] = 0.010;
        high["cq"] = 0.020;
        high["fs"] = 0.100;
        QVERIFY(backend.applyThcLiveTuning(high));
        raw->receive(QByteArrayLiteral("{THC:V53:v=1,kp=0.300000,ki=0.040000,kd=0.060000,rate=0.010000,cq=0.020000,fs=0.100000,revision=2}"));
        QCOMPARE(backend.thcLiveTuning().value("revision").toULongLong(), 2ULL);
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationState(), state);
        QVERIFY(!backend.pressOperationActive());
        QVERIFY(!backend.m_thcV53HeartbeatTimer.isActive());
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:HB>\n")), qsizetype(0));
    }

    void thcV53ExtendedCapabilityPropertyAndRenegotiation()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        const int index = backend.metaObject()->indexOfProperty("thcLiveTuningExtended");
        QVERIFY(index >= 0);
        const QMetaProperty property = backend.metaObject()->property(index);
        QCOMPARE(property.metaType(), QMetaType::fromType<bool>());
        QVERIFY(property.isReadable());
        QVERIFY(!property.isWritable());
        QCOMPARE(property.notifySignal().name(), QByteArray("thcLiveTuningChanged"));
        QVERIFY(!property.read(&backend).toBool());
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(!backend.thcLiveTuningExtended());
        const auto legacy = backend.thcLiveTuning();
        QCOMPARE(legacy.size(), 7);
        QCOMPARE(legacy.value("revision").metaType(), QMetaType::fromType<qulonglong>());
        QVERIFY(!legacy.contains("version"));
        QVERIFY(!legacy.contains("v"));
        QSignalSpy changed(&backend, &MachineControlBackend::thcLiveTuningChanged);
        QVERIFY(backend.queryThcLiveTuning());
        QVERIFY(!backend.thcLiveTuningSupported());
        QVERIFY(!backend.thcLiveTuningExtended());
        raw->receive(v53Reply("0", "0.150000", 2));
        QVERIFY(backend.thcLiveTuningSupported());
        QVERIFY(property.read(&backend).toBool());
        QCOMPARE(backend.thcLiveTuning(), legacy); // Version is not an ACK-map key.
        QVERIFY(changed.size() >= 2);
        backend.m_thcLiveTuningSupported = false;
        QVERIFY(!backend.thcLiveTuningExtended()); // Always gated by support.
        backend.m_thcLiveTuningSupported = true;
        QVERIFY(backend.queryThcLiveTuning());
        QVERIFY(!backend.thcLiveTuningExtended());
        QCOMPARE(backend.m_thcLiveTuningVersion, 0);
        raw->receive(v53Reply());
        QVERIFY(!backend.thcLiveTuningExtended());
        const auto before = raw->writeCount();
        QVERIFY(!backend.applyThcLiveTuning(v53Settings(0.300001))); // v1 remains narrow.
        QCOMPARE(backend.thcLiveTuningError(), QStringLiteral("V53_ARGUMENT"));
        QCOMPARE(raw->writeCount(), before);
        backend.invalidateThcLiveTuning(QStringLiteral("TEST_INVALIDATION"));
        QVERIFY(!backend.thcLiveTuningExtended());
        QCOMPARE(backend.m_thcLiveTuningVersion, 0);
    }

    void thcV53ExtendedReplyGrammar_data()
    {
        QTest::addColumn<QByteArray>("reply");
        QTest::addColumn<bool>("accepted");
        QTest::newRow("expanded") << v53Reply("0", "0.300001", 2) << true;
        QTest::newRow("technical-ceiling") << v53Reply("0", "999999999.999999", 2) << true;
        QTest::newRow("zero-gain") << v53Reply("0", "0.000000", 2) << true;
        for (const QByteArray &token : {QByteArray("00.150000"), QByteArray("0000000000.150000"),
             QByteArray("1000000000.000000"), QByteArray("+0.150000"), QByteArray("-0.000000"),
             QByteArray("0.15"), QByteArray("0.1500000"), QByteArray("1e-6"), QByteArray("nan"),
             QByteArray("inf"), QByteArray(" 0.150000"), QByteArray("0,150000")})
            QTest::newRow(token.constData()) << v53Reply("0", token, 2) << false;
        for (const QByteArray &revision : {QByteArray("00"), QByteArray("4294967296"), QByteArray("-1")})
            QTest::newRow(("revision-" + revision).constData()) << v53Reply(revision, "0.150000", 2) << false;
        for (const QByteArray &token : {QByteArray("0.000000"), QByteArray("0.010000"),
                                      QByteArray("0.0000009")}) {
            auto reply = v53Reply("0", "0.150000", 2);
            reply.replace("fs=0.050000", "fs=" + token);
            QTest::newRow(("fs-" + token).constData()) << reply << false;
        }
        auto oversized = v53Reply("0", "0.150000", 2);
        oversized.replace("kp=0.150000", "kp=" + QByteArray(160, '0') + ".150000");
        QTest::newRow("reply-over-160") << oversized << false;
        auto unknown = v53Reply("0", "0.150000", 2);
        unknown.replace("v=2", "v=02");
        QTest::newRow("padded-version") << unknown << false;
    }

    void thcV53ExtendedReplyGrammar()
    {
        QFETCH(QByteArray, reply);
        QFETCH(bool, accepted);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        raw->receive(reply); // No unsolicited negotiation.
        QVERIFY(!backend.thcLiveTuningExtended());
        QVERIFY(backend.queryThcLiveTuning());
        raw->receive(reply);
        QCOMPARE(backend.thcLiveTuningSupported(), accepted);
        QCOMPARE(backend.thcLiveTuningExtended(), accepted);
        QVERIFY(!backend.thcLiveTuningPending());
        QCOMPARE(backend.m_thcLiveTuningVersion, accepted ? 2 : 0);
        QCOMPARE(backend.thcLiveTuning().size(), accepted ? 7 : 0);
        QCOMPARE(backend.m_thcLiveRecoveryRequired, !accepted);
    }

    void thcV53ExtendedZeroAndMaximumFrames()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw, 2));
        const auto id = backend.operationId();
        const auto state = backend.operationState();
        const QVariantMap zero = {{"kp", -0.0}, {"ki", 0}, {"kd", 0U}, {"rate", 0.0},
                                  {"cq", 0.0}, {"fs", 0.000001}};
        QVERIFY(backend.applyThcLiveTuning(zero));
        const QByteArray zeroFrame("<THC:V53:TUNE:1,0.000000,0.000000,0.000000,0.000000,0.000000,0.000001>\n");
        QCOMPARE(raw->writeAt(raw->writeCount() - 1), zeroFrame);
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(SerialDeviceDiscovery::DeviceRole::Press, zeroFrame));
        raw->receive(QByteArrayLiteral("{THC:V53:v=2,kp=0.000000,ki=0.000000,kd=0.000000,rate=0.000000,cq=0.000000,fs=0.000001,revision=1}"));
        QVERIFY(backend.thcLiveTuningExtended());
        QCOMPARE(backend.thcLiveTuning().value("fs").toDouble(), 0.000001);
        QVERIFY(backend.queryThcLiveTuning());
        raw->receive(v53Reply("4294967294", "0.150000", 2));
        const double maximum = 999999999.999999;
        const QVariantMap high = {{"kp", maximum}, {"ki", maximum}, {"kd", maximum},
                                  {"rate", maximum}, {"cq", 999999999.999998}, {"fs", maximum}};
        QVERIFY(backend.applyThcLiveTuning(high));
        const QByteArray maxFrame("<THC:V53:TUNE:4294967295,999999999.999999,999999999.999999,999999999.999999,999999999.999999,999999999.999998,999999999.999999>\n");
        QCOMPARE(raw->writeAt(raw->writeCount() - 1), maxFrame);
        QCOMPARE(maxFrame.size() - 3, qsizetype(125)); // Largest canonical payload, <=128.
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(SerialDeviceDiscovery::DeviceRole::Press, maxFrame));
        const QByteArray maxReply("{THC:V53:v=2,kp=999999999.999999,ki=999999999.999999,kd=999999999.999999,rate=999999999.999999,cq=999999999.999998,fs=999999999.999999,revision=4294967295}");
        QCOMPARE(maxReply.size(), qsizetype(155));
        QVERIFY(maxReply.size() <= 160);
        raw->receive(maxReply);
        QVERIFY(backend.thcLiveTuningExtended());
        QVERIFY(!backend.thcLiveTuningPending());
        QCOMPARE(backend.thcLiveTuning().size(), 7);
        QCOMPARE(backend.thcLiveTuning().value("revision").toULongLong(), 4294967295ULL);
        const auto before = raw->writeCount();
        QVERIFY(!backend.applyThcLiveTuning(high));
        QCOMPARE(backend.thcLiveTuningError(), QStringLiteral("V53_REVISION_EXHAUSTED"));
        QCOMPARE(raw->writeCount(), before);
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationState(), state);
        QVERIFY(!backend.pressOperationActive());
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:HB>\n")), qsizetype(0));
    }

    void thcV53ExtendedTuneBoundsAndRounding_data()
    {
        QTest::addColumn<QString>("field");
        QTest::addColumn<QVariant>("value");
        for (const auto &item : QList<QPair<QString, QVariant>>{
             {"kp", -0.000001}, {"ki", -1.0}, {"kd", 1000000000.0}, {"rate", -0.000001},
             {"cq", -0.000001}, {"fs", 0.0}, {"fs", 0.0000009}, {"fs", 0.01},
             {"kp", std::numeric_limits<double>::max()}, {"rate", std::numeric_limits<double>::infinity()},
             {"cq", std::numeric_limits<double>::quiet_NaN()}, {"kp", true}, {"ki", QVariant()},
             {"kp", QStringLiteral("0.400000")}, {"extra", 0.1}}) {
            const auto name = (item.first + ':' + item.second.toString()).toLatin1();
            QTest::newRow(name.constData()) << item.first << item.second;
        }
    }

    void thcV53ExtendedTuneBoundsAndRounding()
    {
        QFETCH(QString, field);
        QFETCH(QVariant, value);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw, 2));
        const auto confirmed = backend.thcLiveTuning();
        auto settings = v53Settings();
        settings.insert(field, value);
        const auto before = raw->writeCount();
        QVERIFY(!backend.applyThcLiveTuning(settings));
        QCOMPARE(backend.thcLiveTuningError(), QStringLiteral("V53_ARGUMENT"));
        settings = v53Settings();
        settings.remove("kp");
        settings.insert("other", 0.15); // Exactly six, but not the six allowed keys.
        QVERIFY(!backend.applyThcLiveTuning(settings));
        settings = v53Settings();
        settings["cq"] = 0.0000011;
        settings["fs"] = 0.0000012; // Distinct before rounding, identical six-decimal wire.
        QVERIFY(!backend.applyThcLiveTuning(settings));
        QCOMPARE(backend.thcLiveTuningError(), QStringLiteral("V53_ARGUMENT_PRECISION"));
        QCOMPARE(raw->writeCount(), before);
        QCOMPARE(backend.thcLiveTuning(), confirmed);
        QVERIFY(backend.thcLiveTuningExtended());
        QVERIFY(!backend.thcLiveTuningPending());
        QCOMPARE(backend.m_thcLiveExpectedVersion, 0);
    }

    void thcV53ExtendedLiveTunePreservesOwnerAndLease()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw, 2));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        raw->receive(v51ProductionTelemetry());
        const auto confirmed = backend.thcLiveTuning();
        const auto id = backend.operationId();
        const auto epoch = backend.m_thcV53Clock.msecsSinceReference();
        const auto lease = backend.m_thcV53ClientDeadlineMs;
        const auto demand = backend.ramVelocity();
        QVERIFY(backend.applyThcLiveTuning(v53Settings(1.25)));
        QCOMPARE(backend.m_thcLiveExpectedVersion, 2);
        QCOMPARE(backend.thcLiveTuning(), confirmed);
        QCOMPARE(raw->writeAt(raw->writeCount() - 1), QByteArrayLiteral("<THC:V53:TUNE:1,1.250000,0.020000,0.030000,0.010000,0.010000,0.050000>\n"));
        raw->receive(v53Reply("1", "1.250000", 2));
        QVERIFY(backend.thcLiveTuningExtended());
        QCOMPARE(backend.thcLiveTuning().value("kp").toDouble(), 1.25);
        QCOMPARE(backend.thcLiveTuning().value("revision").toULongLong(), 1ULL);
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.m_thcV53Clock.msecsSinceReference(), epoch);
        QCOMPARE(backend.m_thcV53ClientDeadlineMs, lease);
        QCOMPARE(backend.m_thcV53PhaseDeadlineMs, qint64(-1));
        QCOMPARE(backend.ramVelocity(), demand);
        QVERIFY(backend.m_thcV53HeartbeatTimer.isActive());
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(0));
    }

    void thcV53ExtendedSynchronousTuneAck()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw, 2));
        const auto id = backend.operationId();
        raw->setWriteHook([&](const QByteArray &frame) {
            if (!frame.startsWith("<THC:V53:TUNE:")) return;
            QCOMPARE(backend.m_thcLiveExpectedVersion, 2);
            raw->receive(v53Reply("1", "1.250000", 2));
        });
        QVERIFY(backend.applyThcLiveTuning(v53Settings(1.25)));
        raw->setWriteHook({});
        QVERIFY(backend.thcLiveTuningExtended());
        QVERIFY(!backend.thcLiveTuningPending());
        QVERIFY(!backend.m_thcLiveRequestTimer.isActive());
        QCOMPARE(backend.m_thcLiveTuningVersion, 2);
        QCOMPARE(backend.m_thcLiveExpectedVersion, 0);
        QCOMPARE(backend.thcLiveTuning().value("kp").toDouble(), 1.25);
        QCOMPARE(backend.operationId(), id);
    }

    void thcV53MutationVersionChangeFailsClosed_data()
    {
        QTest::addColumn<int>("version");
        QTest::addColumn<bool>("live");
        QTest::newRow("idle-downgrade") << 2 << false;
        QTest::newRow("holding-downgrade") << 2 << true;
        QTest::newRow("idle-upgrade") << 1 << false;
        QTest::newRow("holding-upgrade") << 1 << true;
    }

    void thcV53MutationVersionChangeFailsClosed()
    {
        QFETCH(int, version);
        QFETCH(bool, live);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw, version));
        if (live) {
            QVERIFY(backend.startContinuousThcContactProfile());
            v53Hold(raw);
        }
        const auto id = backend.operationId();
        QVERIFY(backend.applyThcLiveTuning(v53Settings(0.16)));
        raw->receive(v53Reply("1", "0.160000", version == 2 ? 1 : 2)); // Map identical, version wrong.
        QCOMPARE(backend.thcLiveTuningError(), QStringLiteral("V53_ACK_MISMATCH"));
        QVERIFY(!backend.thcLiveTuningSupported());
        QVERIFY(!backend.thcLiveTuningExtended());
        QVERIFY(!backend.thcLiveTuningPending());
        QVERIFY(backend.m_thcLiveRecoveryRequired);
        QCOMPARE(backend.m_thcLiveTuningVersion, 0);
        QCOMPARE(backend.m_thcLiveExpectedVersion, 0);
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(live ? 1 : 0));
        if (live) {
            QCOMPARE(backend.m_thcV53Phase, MachineControlBackend::ThcV53Phase::AwaitCancel);
            QVERIFY(backend.pressSafetyStopUnconfirmed());
            QVERIFY(!backend.m_thcV53HeartbeatTimer.isActive());
            QVERIFY(!backend.m_thcV53ClientLeaseTimer.isActive());
        }
        raw->receive(v53Reply("1", "0.160000", version)); // Late correct ACK has no authority.
        QVERIFY(!backend.thcLiveTuningSupported());
    }

    void thcV53ExtendedCapabilitySessionReset_data()
    {
        QTest::addColumn<QString>("pending");
        QTest::addColumn<bool>("disconnect");
        for (const QString &pending : {QStringLiteral("none"), QStringLiteral("query"), QStringLiteral("tune")}) {
            QTest::newRow((pending + "-drop").toLatin1().constData()) << pending << false;
            QTest::newRow((pending + "-disconnect").toLatin1().constData()) << pending << true;
        }
    }

    void thcV53ExtendedCapabilitySessionReset()
    {
        QFETCH(QString, pending);
        QFETCH(bool, disconnect);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw, 2));
        QVERIFY(backend.thcLiveTuningExtended());
        if (pending == "query") {
            QVERIFY(backend.queryThcLiveTuning());
            QVERIFY(!backend.thcLiveTuningExtended());
        }
        if (pending == "tune") QVERIFY(backend.applyThcLiveTuning(v53Settings(1.25)));
        if (disconnect) QVERIFY(backend.disconnectPress());
        else raw->drop();
        QVERIFY(!backend.thcLiveTuningSupported());
        QVERIFY(!backend.thcLiveTuningExtended());
        QVERIFY(!backend.thcLiveTuningPending());
        QVERIFY(backend.thcLiveTuning().isEmpty());
        QCOMPARE(backend.m_thcLiveTuningVersion, 0);
        QCOMPARE(backend.m_thcLiveExpectedVersion, 0);
        QVERIFY(v51Ready(backend, raw));
        raw->receive(v51ProductionTelemetry());
        raw->receive(v53Reply("1", "1.250000", 2));
        QVERIFY(!backend.thcLiveTuningExtended());
        QVERIFY(backend.queryThcLiveTuning());
        raw->receive(v53Reply());
        QVERIFY(backend.thcLiveTuningSupported());
        QVERIFY(!backend.thcLiveTuningExtended());
        QVERIFY(!backend.applyThcLiveTuning(v53Settings(0.300001)));
    }

    void thcV53ExtendedReentrantWriteKeepsSuccessorVersion()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw, 2));
        const QByteArray original("<THC:V53:TUNE:1,1.250000,0.020000,0.030000,0.010000,0.010000,0.050000>\n");
        bool replaced = false;
        raw->setFailedFrame(original);
        raw->setWriteHook([&](const QByteArray &frame) {
            if (frame != original || replaced) return;
            replaced = true;
            QCOMPARE(backend.m_thcLiveExpectedVersion, 2);
            raw->receive(v53Reply("1", "1.250000", 2)); // Synchronous ACK before write returns false.
            QVERIFY(backend.thcLiveTuningExtended());
            QVERIFY(backend.queryThcLiveTuning());
            QVERIFY(!backend.thcLiveTuningExtended());
            raw->receive(v53Reply("1", "0.150000", 1));
            QVERIFY(backend.thcLiveTuningSupported());
            QVERIFY(!backend.thcLiveTuningExtended());
            QVERIFY(backend.applyThcLiveTuning(v53Settings(0.17)));
        });
        QVERIFY(!backend.applyThcLiveTuning(v53Settings(1.25)));
        raw->setWriteHook({});
        QVERIFY(replaced);
        QVERIFY(backend.thcLiveTuningPending());
        QCOMPARE(backend.m_thcLiveTuningVersion, 1);
        QCOMPARE(backend.m_thcLiveExpectedVersion, 1);
        QVERIFY(!backend.m_thcLiveRecoveryRequired);
        QVERIFY(backend.thcLiveTuningError().isEmpty());
        raw->receive(v53Reply("2", "0.170000", 1));
        QVERIFY(backend.thcLiveTuningSupported());
        QVERIFY(!backend.thcLiveTuningExtended());
        QVERIFY(!backend.thcLiveTuningPending());
        QCOMPARE(backend.thcLiveTuning().value("revision").toULongLong(), 2ULL);
        QCOMPARE(backend.m_thcLiveExpectedVersion, 0);
    }

    void thcV53ExtendedDiagnosticsVersionGate_data()
    {
        QTest::addColumn<int>("version");
        QTest::newRow("legacy") << 1;
        QTest::newRow("extended") << 2;
    }

    void thcV53ExtendedDiagnosticsVersionGate()
    {
        QFETCH(int, version);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw, version));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        const auto lease = backend.m_thcV53ClientDeadlineMs;
        const auto sequence = backend.pressTelemetrySequence();
        const auto writes = raw->writeCount();
        raw->receive(v53Control(1000, 1));
        QCOMPARE(backend.thcLiveDiagnostics().value("p").toDouble(), 0.001);
        const QByteArray effective("[TH_V53 revision=0 effectiveRevision=0 rampMs=50 hold=1 kp=999999999.999999 ki=0.000000 kd=0.000000 rate=0.000000 cq=0.000000 fs=0.000001 seq=2]");
        raw->receive(effective);
        QCOMPARE(backend.thcLiveDiagnostics().contains("effective"), version == 2);
        const auto diagnostics = backend.thcLiveDiagnostics();
        if (version == 2) QCOMPARE(diagnostics.value("effective").toMap().value("kp").toDouble(), 999999999.999999);
        for (const QByteArray &token : {QByteArray("00.400000"), QByteArray("1000000000.000000"),
             QByteArray("-0.000000"), QByteArray("0.4000000"), QByteArray("nan")}) {
            auto invalid = effective;
            invalid.replace("kp=999999999.999999", "kp=" + token);
            raw->receive(invalid);
            QCOMPARE(backend.thcLiveDiagnostics(), diagnostics);
        }
        auto invalidControl = v53Control(1010, 3);
        invalidControl.replace("ph=2", "ph=5");
        raw->receive(invalidControl);
        QCOMPARE(backend.thcLiveDiagnostics(), diagnostics); // TH_CTRL guards unchanged.
        QCOMPARE(backend.m_thcV53ClientDeadlineMs, lease);
        QCOMPARE(backend.pressTelemetrySequence(), sequence);
        QCOMPARE(raw->writeCount(), writes);
        QVERIFY(backend.queryThcLiveTuning());
        QVERIFY(!backend.thcLiveTuningExtended());
        raw->receive(effective); // Query clears expanded diagnostic capability too.
        QCOMPARE(backend.thcLiveDiagnostics(), diagnostics);
    }

    void thcV53PendingReplyCannotSurviveSessionLoss_data()
    {
        QTest::addColumn<bool>("tune");
        QTest::newRow("query") << false;
        QTest::newRow("tune") << true;
    }

    void thcV53PendingReplyCannotSurviveSessionLoss()
    {
        QFETCH(bool, tune);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(tune ? backend.applyThcLiveTuning(v53Settings(0.16)) : backend.queryThcLiveTuning());
        raw->drop();
        QVERIFY(!backend.thcLiveTuningPending());
        QVERIFY(!backend.thcLiveTuningSupported());
        QVERIFY(backend.thcLiveTuning().isEmpty());
        raw->receive(v53Reply(tune ? QByteArray("1") : QByteArray("0"), tune ? QByteArray("0.160000") : QByteArray("0.150000")));
        QVERIFY(!backend.thcLiveTuningSupported());
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(!backend.thcLiveTuningSupported());
    }

    void thcV53IdleAmbiguityRequiresStreamRetirement_data()
    {
        QTest::addColumn<bool>("tune");
        QTest::addColumn<QString>("loss");
        for (const char *loss : {"stale", "clear-confirmed", "fault-open-stream"}) {
            QTest::newRow(qPrintable(QStringLiteral("query-") + loss)) << false << QString::fromLatin1(loss);
            QTest::newRow(qPrintable(QStringLiteral("tune-") + loss)) << true << QString::fromLatin1(loss);
        }
    }

    void thcV53IdleAmbiguityRequiresStreamRetirement()
    {
        QFETCH(bool, tune);
        QFETCH(QString, loss);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        const auto id = backend.operationId();
        QVERIFY(tune ? backend.applyThcLiveTuning(v53Settings(0.16)) : backend.queryThcLiveTuning());
        if (loss == "stale") backend.expirePressTelemetry();
        if (loss == "clear-confirmed") backend.invalidateThcLiveTuning(QStringLiteral("TEST_CACHE_LOSS"), true);
        if (loss == "fault-open-stream") raw->fail(QStringLiteral("TEST_FAULT_WITHOUT_CLOSE"));
        QVERIFY(raw->isOpen()); // None of these events retires the receive stream.
        QVERIFY(backend.m_thcLiveRecoveryRequired);
        QVERIFY(!backend.thcLiveTuningPending());
        QVERIFY(!backend.m_thcLiveRequestTimer.isActive());
        QVERIFY(backend.thcLiveTuning().isEmpty());
        QVERIFY(!backend.thcLiveTuningSupported());
        if (loss == "fault-open-stream") QVERIFY(v51Ready(backend, raw));
        raw->receive(v51ProductionTelemetry());
        QVERIFY(backend.pressReady());
        QVERIFY(backend.m_thcLiveRecoveryRequired);
        const auto before = countWrites(raw, QByteArrayLiteral("<THC:V53?>\n"));
        QVERIFY(!backend.queryThcLiveTuning()); // Fresh IDLE cannot authorize a tokenless successor.
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:V53?>\n")), before);
        QVERIFY(!raw->isOpen());
        QVERIFY(!backend.pressConnected());
        raw->receive(v53Reply(tune ? QByteArray("1") : QByteArray("0"),
                              tune ? QByteArray("0.160000") : QByteArray("0.150000")));
        QVERIFY(!backend.thcLiveTuningSupported());
        QVERIFY(!backend.thcLiveTuningPending());
        QVERIFY(v51Ready(backend, raw));
        raw->receive(v51ProductionTelemetry());
        QVERIFY(!backend.m_thcLiveRecoveryRequired);
        QVERIFY(backend.queryThcLiveTuning());
        raw->receive(v53Reply());
        QVERIFY(backend.thcLiveTuningSupported());
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(0));
    }

    void thcV53ConfirmedCacheLossDoesNotFenceNewQuery()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        backend.expirePressTelemetry();
        QVERIFY(!backend.m_thcLiveRecoveryRequired);
        QVERIFY(backend.thcLiveTuning().isEmpty());
        raw->receive(v51ProductionTelemetry());
        QVERIFY(backend.queryThcLiveTuning());
        raw->receive(v53Reply());
        QVERIFY(backend.thcLiveTuningSupported());
        QVERIFY(raw->isOpen());
    }

    void thcV53ReentrantWritePreservesReplacementRequest_data()
    {
        QTest::addColumn<bool>("tune");
        QTest::addColumn<bool>("replacementTune");
        QTest::addColumn<QString>("notification");
        for (bool tune : {false, true}) {
            for (bool replacementTune : {false, true}) {
                for (const char *notification : {"attempted-failure", "hook-failure", "written"}) {
                    const QString row = QStringLiteral("%1-to-%2-%3")
                        .arg(tune ? "tune" : "query", replacementTune ? "tune" : "query", notification);
                    QTest::newRow(qPrintable(row)) << tune << replacementTune << QString::fromLatin1(notification);
                }
            }
        }
    }

    void thcV53ReentrantWritePreservesReplacementRequest()
    {
        QFETCH(bool, tune);
        QFETCH(bool, replacementTune);
        QFETCH(QString, notification);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        const auto owner = backend.operationId();
        bool replaced = false;
        const auto replace = [&](const QByteArray &frame) {
            const bool selected = tune ? frame.startsWith("<THC:V53:TUNE:")
                : frame == "<THC:V53?>" || frame == "<THC:V53?>\n";
            if (replaced || !selected)
                return;
            replaced = true;
            raw->receive(v53Reply(tune ? QByteArray("1") : QByteArray("0"),
                                  tune ? QByteArray("0.160000") : QByteArray("0.150000")));
            QVERIFY(backend.thcLiveTuningSupported());
            QVERIFY(replacementTune ? backend.applyThcLiveTuning(v53Settings(0.17)) : backend.queryThcLiveTuning());
            if (notification != "written") raw->setFailedFrame(frame);
        };
        if (notification == "attempted-failure")
            connect(raw, &MachineTransport::frameWriteAttempted, &backend, replace, Qt::DirectConnection);
        else if (notification == "written")
            connect(raw, &MachineTransport::frameWritten, &backend, replace, Qt::DirectConnection);
        else raw->setWriteHook(replace);
        QVERIFY(!(tune ? backend.applyThcLiveTuning(v53Settings(0.16)) : backend.queryThcLiveTuning()));
        QVERIFY(replaced);
        QCOMPARE(backend.operationId(), owner);
        QVERIFY(backend.thcLiveTuningPending());
        QCOMPARE(backend.m_thcLiveRequest, replacementTune ? MachineControlBackend::ThcLiveRequest::Tune
                                                         : MachineControlBackend::ThcLiveRequest::Query);
        QVERIFY(backend.m_thcLiveRequestTimer.isActive());
        QVERIFY(backend.m_thcLiveRequestClock.isValid());
        QVERIFY(!backend.m_thcLiveRecoveryRequired);
        QVERIFY(backend.thcLiveTuningError().isEmpty());
        raw->setFailedFrame({});
        raw->receive(v53Reply(QByteArray::number(int(tune) + int(replacementTune)),
                              replacementTune ? QByteArray("0.170000")
                                              : tune ? QByteArray("0.160000") : QByteArray("0.150000")));
        QVERIFY(!backend.thcLiveTuningPending());
        QVERIFY(backend.thcLiveTuningSupported());
        QVERIFY(!backend.m_thcLiveRequestTimer.isActive());
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(0));
    }

    void thcV53ReentrantWriteFailureDoesNotCancelReplacementOwner_data()
    {
        QTest::addColumn<bool>("tune");
        QTest::newRow("query") << false;
        QTest::newRow("tune") << true;
    }

    void thcV53ReentrantWriteFailureDoesNotCancelReplacementOwner()
    {
        QFETCH(bool, tune);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        const auto owner = backend.operationId();
        bool replaced = false;
        raw->setWriteHook([&](const QByteArray &frame) {
            if (replaced || (tune ? !frame.startsWith("<THC:V53:TUNE:") : frame != "<THC:V53?>\n")) return;
            replaced = true;
            raw->receive(v53Reply(tune ? QByteArray("1") : QByteArray("0"),
                                  tune ? QByteArray("0.160000") : QByteArray("0.150000")));
            QVERIFY(backend.startContinuousThcContactProfile());
            v53Hold(raw);
            raw->setFailedFrame(frame);
        });
        QVERIFY(!(tune ? backend.applyThcLiveTuning(v53Settings(0.16)) : backend.queryThcLiveTuning()));
        QVERIFY(replaced);
        QCOMPARE(backend.operationId(), owner + 1);
        QCOMPARE(backend.operationName(), QStringLiteral("thc-contact-profile-v53"));
        QCOMPARE(backend.m_thcV53Phase, MachineControlBackend::ThcV53Phase::Holding);
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.m_thcV53HeartbeatTimer.isActive());
        QVERIFY(backend.m_thcV53ClientLeaseTimer.isActive());
        QVERIFY(!backend.m_thcLiveRecoveryRequired);
        QVERIFY(backend.thcLiveTuningSupported());
        QVERIFY(!backend.pressSafetyStopUnconfirmed());
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(0));
    }

    void thcV53LiveWriteFailureFencesOriginalRequest_data()
    {
        QTest::addColumn<bool>("tune");
        QTest::addColumn<bool>("active");
        QTest::newRow("idle-query") << false << false;
        QTest::newRow("idle-tune") << true << false;
        QTest::newRow("owned-query") << false << true;
        QTest::newRow("owned-tune") << true << true;
    }

    void thcV53LiveWriteFailureFencesOriginalRequest()
    {
        QFETCH(bool, tune);
        QFETCH(bool, active);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        if (active) {
            QVERIFY(backend.startContinuousThcContactProfile());
            v53Hold(raw);
        }
        const auto owner = backend.operationId();
        raw->setFailedFrame(tune ? QByteArrayLiteral("<THC:V53:TUNE:1,0.160000,0.020000,0.030000,0.010000,0.010000,0.050000>\n")
                                : QByteArrayLiteral("<THC:V53?>\n"));
        QVERIFY(!(tune ? backend.applyThcLiveTuning(v53Settings(0.16)) : backend.queryThcLiveTuning()));
        QCOMPARE(backend.operationId(), owner);
        QVERIFY(backend.m_thcLiveRecoveryRequired);
        QVERIFY(!backend.thcLiveTuningPending());
        QVERIFY(!backend.thcLiveTuningSupported());
        QVERIFY(!backend.m_thcLiveRequestTimer.isActive());
        QCOMPARE(backend.thcLiveTuningError(), tune ? QStringLiteral("V53_TUNE_WRITE_FAILED")
                                                   : QStringLiteral("V53_QUERY_WRITE_FAILED"));
        raw->receive(v53Reply("1", "0.160000"));
        QVERIFY(!backend.thcLiveTuningSupported());
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(active ? 1 : 0));
        if (active) {
            QCOMPARE(backend.m_thcV53Phase, MachineControlBackend::ThcV53Phase::AwaitCancel);
            QVERIFY(backend.pressSafetyStopUnconfirmed());
            raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
            raw->receive(v51ProductionTelemetry());
            QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
            QVERIFY(!backend.pressSafetyStopUnconfirmed());
        }
        raw->setFailedFrame({});
        QVERIFY(!backend.queryThcLiveTuning());
        QVERIFY(!raw->isOpen());
    }

    void thcV53TuneMismatchAndRevisionExhaustion_data()
    {
        QTest::addColumn<QByteArray>("reply");
        QTest::newRow("old-revision") << v53Reply("0", "0.160000");
        QTest::newRow("future-revision") << v53Reply("2", "0.160000");
        QTest::newRow("wrong-values") << v53Reply("1", "0.150000");
        QTest::newRow("busy") << QByteArray("{THC:V53:ERROR:BUSY}");
        QTest::newRow("lease") << QByteArray("{THC:V53:ERROR:LEASE_EXPIRED}");
    }

    void thcV53TuneMismatchAndRevisionExhaustion()
    {
        QFETCH(QByteArray, reply);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.applyThcLiveTuning(v53Settings(0.16)));
        raw->receive(reply);
        QVERIFY(!backend.thcLiveTuningSupported());
        QVERIFY(!backend.thcLiveTuningPending());
        QVERIFY(!backend.applyThcLiveTuning(v53Settings(0.16)));
        raw->receive(v53Reply("1", "0.160000"));
        QVERIFY(!backend.thcLiveTuningSupported());
        QVERIFY(!backend.queryThcLiveTuning()); // closes ambiguous stream, no retry
        QVERIFY(!backend.pressConnected());
        QVERIFY(v51Ready(backend, raw));
        raw->receive(v51ProductionTelemetry());
        QVERIFY(backend.queryThcLiveTuning());
        raw->receive(v53Reply("4294967295"));
        const auto before = raw->writeCount();
        QVERIFY(!backend.applyThcLiveTuning(v53Settings()));
        QCOMPARE(backend.thcLiveTuningError(), QStringLiteral("V53_REVISION_EXHAUSTED"));
        QCOMPARE(raw->writeCount(), before);
    }

    void thcV53ContinuousOnlyRemovesHoldObservation()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V53_RUNNING}"));
        QCOMPARE(backend.m_thcV53PhaseDeadlineMs, qint64(45000));
        raw->receive(QByteArrayLiteral("{THC:CONTACT}"));
        QVERIFY(backend.m_thcV53PhaseDeadlineMs >= 60000);
        const auto acquisition = backend.m_thcV53PhaseDeadlineMs;
        raw->receive(QByteArrayLiteral("{THC:CONTACT}"));
        QCOMPARE(backend.m_thcV53PhaseDeadlineMs, acquisition);
        QVERIFY(!backend.applyThcLiveTuning(v53Settings()));
        raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        QCOMPARE(backend.m_thcV53PhaseDeadlineMs, qint64(-1));
        QVERIFY(!backend.m_thcV53PhaseTimer.isActive());
        QVERIFY(!backend.m_commandDeadlineTimer.isActive());
        // Structural timer injection: there is no HOLD phase/overall observer
        // to expire at 60 s. Lease checks remain independently authoritative.
        backend.m_thcV53ClientDeadlineMs = 120000;
        for (int i = 0; i < 3; ++i) {
            QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV53PhaseTimer, "timeout", Qt::DirectConnection));
            QVERIFY(QMetaObject::invokeMethod(&backend.m_commandDeadlineTimer, "timeout", Qt::DirectConnection));
            backend.sendThcV53Heartbeat();
            raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
            QCOMPARE(backend.m_thcV53ClientDeadlineMs, qint64(120000));
        }
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:RELEASE>\n")), qsizetype(0));
        QVERIFY(backend.heartbeatThcCommissioning());
        QVERIFY(backend.m_thcV53ClientDeadlineMs <= backend.m_thcV53Clock.elapsed() + 2000);
        const auto before = backend.m_thcV53Clock.elapsed();
        QVERIFY(backend.releaseThcCommissioning());
        const auto end = backend.m_thcV53ReleaseDeadlineMs;
        QVERIFY(end >= before + 40000);
        QVERIFY(end <= backend.m_thcV53Clock.elapsed() + 40000);
        raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        QCOMPARE(backend.m_thcV53PhaseDeadlineMs, end);
        raw->receive(QByteArrayLiteral("{THC:DONE}"));
        raw->receive(v51ProductionTelemetry());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.thcContinuousActive());
    }

    void thcV53CancellationProof_data()
    {
        QTest::addColumn<bool>("release");
        QTest::newRow("cancel") << false;
        QTest::newRow("release") << true;
    }

    void thcV53CancellationProof()
    {
        QFETCH(bool, release);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        const auto id = backend.operationId();
        QVERIFY(release ? backend.releaseThcCommissioning() : backend.cancelThcCommissioning());
        raw->receive(v51ProductionTelemetry());
        QVERIFY(backend.commandOperationActive());
        if (release) raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        else raw->receive(QByteArrayLiteral("{THC:ERROR:NOT_ACTIVE}"));
        raw->receive(v51ProductionTelemetry());
        QVERIFY(backend.commandOperationActive());
        const auto marker = release ? QByteArrayLiteral("{THC:DONE}") : QByteArrayLiteral("{THC:CANCELLED}");
        raw->receive(marker);
        raw->receive(marker);
        raw->receive(v51ProductionTelemetry("IDLE", "nan"));
        raw->receive(v51ProductionTelemetry("idle"));
        QVERIFY(backend.commandOperationActive());
        raw->receive(v51ProductionTelemetry());
        QCOMPARE(backend.operationState(), release ? QStringLiteral("COMPLETED") : QStringLiteral("FAILED"));
        QCOMPARE(backend.operationId(), id);
        QVERIFY(!backend.pressSafetyStopUnconfirmed());
        QVERIFY(!backend.thcContinuousActive());
        QCOMPARE(backend.ramVelocity(), -7.25); // retained demand is not measured velocity
        QCOMPARE(backend.thcCommissioningState(), release ? QStringLiteral("DONE") : QStringLiteral("FAILED"));
    }

    void thcV53FailureStopsLeaseAndRetainsReason_data()
    {
        QTest::addColumn<QString>("failure");
        for (const char *failure : {"firmware", "lease", "phase", "stale", "disconnect", "drop",
                                   "release-write", "release-timeout", "tune-timeout", "home", "reset", "pedal"})
            QTest::newRow(failure) << QString::fromLatin1(failure);
    }

    void thcV53FailureStopsLeaseAndRetainsReason()
    {
        QFETCH(QString, failure);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        const auto id = backend.operationId();
        if (failure == "firmware") raw->receive(QByteArrayLiteral("{THC:ERROR:V53_APPROACH_TIMEOUT}"));
        if (failure == "lease") {
            backend.m_thcV53ClientDeadlineMs = backend.m_thcV53Clock.elapsed();
            QVERIFY(!backend.heartbeatThcCommissioning());
        }
        if (failure == "phase") {
            backend.m_thcV53PhaseDeadlineMs = backend.m_thcV53Clock.elapsed();
            QVERIFY(!backend.checkThcV53Deadlines());
        }
        if (failure == "stale") backend.expirePressTelemetry();
        if (failure == "disconnect") QVERIFY(backend.disconnectPress());
        if (failure == "drop") raw->drop();
        if (failure == "release-write") {
            raw->setFailedFrame(QByteArrayLiteral("<THC:RELEASE>\n"));
            QVERIFY(!backend.releaseThcCommissioning());
        }
        if (failure == "release-timeout") {
            QVERIFY(backend.releaseThcCommissioning());
            backend.m_thcV53PhaseDeadlineMs = backend.m_thcV53Clock.elapsed();
            QVERIFY(!backend.checkThcV53Deadlines());
        }
        if (failure == "tune-timeout") {
            QVERIFY(backend.applyThcLiveTuning(v53Settings(0.16)));
            QVERIFY(QMetaObject::invokeMethod(&backend.m_thcLiveRequestTimer, "timeout", Qt::DirectConnection));
        }
        if (failure == "home") QVERIFY(!backend.homePress());
        if (failure == "reset") raw->receive(QByteArrayLiteral("[SOFT RESET]"));
        if (failure == "pedal") {
            auto fields = v51ProductionTelemetry().split('|');
            fields[19] = "1>";
            raw->receive(fields.join('|'));
        }
        QCOMPARE(backend.operationId(), id);
        QVERIFY(!backend.m_thcV53HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV53ClientLeaseTimer.isActive());
        QVERIFY(backend.pressSafetyStopUnconfirmed());
        QVERIFY(!backend.thcLiveTuningSupported());
        if (backend.thcContinuousActive()) QVERIFY(!backend.heartbeatThcCommissioning());
        const QString reason = backend.thcContinuousActive() ? backend.m_thcV53Failure : backend.operationError();
        QVERIFY(!reason.isEmpty());
        if (backend.thcContinuousActive()) {
            raw->receive(QByteArrayLiteral("{THC:ERROR:NOT_ACTIVE}"));
            raw->receive(v51ProductionTelemetry());
            QVERIFY(backend.commandOperationActive());
            backend.m_thcV53PhaseDeadlineMs = backend.m_thcV53Clock.elapsed();
            QVERIFY(!backend.checkThcV53Deadlines());
        }
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QVERIFY(backend.operationError().startsWith(reason));
        QCOMPARE(backend.thcCommissioningState(), QStringLiteral("FAILED_STOP_UNCONFIRMED"));
        QVERIFY(!backend.thcContinuousActive());
        raw->receive(v51ProductionTelemetry());
        QVERIFY(backend.pressSafetyStopUnconfirmed());
        QVERIFY(!backend.startContinuousThcContactProfile());
    }

    void thcV53ModuleStopPreservesCancellationOwner_data()
    {
        QTest::addColumn<QString>("scenario");
        for (const char *scenario : {"idle", "moving", "stale-idle", "write-failure",
             "error-on-write", "close-on-write", "cancel-write-failure", "cancel-error-on-write",
             "cancel-close-on-write", "synchronous-cancel", "confirmation-timeout", "repeat-stop"})
            QTest::newRow(scenario) << QString::fromLatin1(scenario);
    }

    void thcV53ModuleStopPreservesCancellationOwner()
    {
        QFETCH(QString, scenario);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(v51ModuleReady(backend, moduleRaw));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        const auto id = backend.operationId();
        if (scenario != "idle" && scenario != "stale-idle")
            moduleRaw->receive(QByteArrayLiteral("<Run|MPos:0,0,0|WCO:0,0,0>"));
        if (scenario == "stale-idle") backend.m_moduleTelemetryFresh = false;
        if (scenario == "write-failure") moduleRaw->setFailedFrame(QByteArrayLiteral("!"));
        if (scenario == "cancel-write-failure") raw->setFailedFrame(QByteArrayLiteral("<THC:CANCEL>\n"));
        moduleRaw->setWriteHook([&](const QByteArray &frame) {
            if (frame != "!") return;
            QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(0));
            if (scenario == "error-on-write") moduleRaw->fail(QStringLiteral("TEST_MODULE_WRITE_ERROR"));
            if (scenario == "close-on-write") moduleRaw->drop();
        });
        raw->setWriteHook([&](const QByteArray &frame) {
            if (frame != "<THC:CANCEL>\n") return;
            if (scenario == "cancel-error-on-write") raw->fail(QStringLiteral("TEST_CANCEL_WRITE_ERROR"));
            if (scenario == "cancel-close-on-write") raw->drop();
            if (scenario == "synchronous-cancel") {
                raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
                raw->receive(v51ProductionTelemetry());
            }
        });
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        const auto moduleWrites = moduleRaw->writeCount();
        const bool moduleFailed = scenario == "write-failure" || scenario == "error-on-write" || scenario == "close-on-write";
        const bool cancelFailed = scenario == "cancel-write-failure" || scenario == "cancel-error-on-write"
            || scenario == "cancel-close-on-write";
        QCOMPARE(backend.stopModule(), !moduleFailed && !cancelFailed);
        moduleRaw->setWriteHook({});
        raw->setWriteHook({});
        QCOMPARE(moduleRaw->writeCount(), moduleWrites + (scenario == "idle" ? 0 : 1));
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationDevice(), QStringLiteral("press"));
        QCOMPARE(backend.operationName(), QStringLiteral("thc-contact-profile-v53"));
        QVERIFY(!backend.m_commandDeadlineTimer.isActive());
        QVERIFY(!backend.m_thcV53HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV53ClientLeaseTimer.isActive());
        if (!cancelFailed && scenario != "synchronous-cancel") {
            QCOMPARE(finished.size(), 0);
            QVERIFY(backend.commandOperationActive());
            QVERIFY(backend.pressOperationActive());
            QVERIFY(backend.pressSafetyStopUnconfirmed());
            QVERIFY(backend.m_thcV53PhaseTimer.isActive());
            QCOMPARE(backend.m_thcV53Phase, MachineControlBackend::ThcV53Phase::AwaitCancel);
            QCOMPARE(backend.m_pressCommandPhase, MachineControlBackend::PressCommandPhase::ThcV53);
            QCOMPARE(backend.m_moduleCommandPhase, MachineControlBackend::ModuleCommandPhase::Idle);
            const auto deadline = backend.m_thcV53PhaseDeadlineMs;
            moduleRaw->receive(QByteArrayLiteral("<Hold:0|MPos:0,0,0|WCO:0,0,0>"));
            moduleRaw->receive(QByteArrayLiteral("ok"));
            QCOMPARE(moduleRaw->writeCount(), moduleWrites + (scenario == "idle" ? 0 : 1)); // Never reset module.
            QVERIFY(!backend.homePress());
            QVERIFY(backend.cancelThcCommissioning());
            QCOMPARE(backend.m_thcV53PhaseDeadlineMs, deadline);
            if (scenario == "repeat-stop") {
                QVERIFY(backend.stopModule());
                QCOMPARE(backend.m_thcV53PhaseDeadlineMs, deadline);
                QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
                QCOMPARE(backend.operationId(), id);
            }
            raw->receive(v51ProductionTelemetry());
            raw->receive(QByteArrayLiteral("{THC:ERROR:NOT_ACTIVE}"));
            QVERIFY(backend.commandOperationActive());
            if (scenario == "confirmation-timeout") {
                backend.m_thcV53PhaseDeadlineMs = backend.m_thcV53Clock.elapsed();
                QVERIFY(!backend.cancelThcCommissioning());
            } else {
                raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
                raw->receive(v51ProductionTelemetry("idle"));
                QVERIFY(backend.commandOperationActive());
                raw->receive(v51ProductionTelemetry());
            }
        }
        QCOMPARE(finished.size(), 1);
        QCOMPARE(finished.at(0).at(0).toULongLong(), id);
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        if (scenario == "confirmation-timeout")
            QCOMPARE(backend.operationError(), QStringLiteral("THC_V53_MODULE_STOP_CANCEL_CONFIRMATION_TIMEOUT"));
        else if (!cancelFailed)
            QCOMPARE(backend.operationError(), moduleFailed
                ? QStringLiteral("THC_V53_MODULE_STOP_FEED_HOLD_WRITE_FAILED") : QStringLiteral("THC_V53_MODULE_STOP"));
        QVERIFY(!backend.pressOperationActive());
        QVERIFY(!backend.thcContinuousActive());
        QCOMPARE(backend.m_pressCommandPhase, MachineControlBackend::PressCommandPhase::Idle);
        QVERIFY(!backend.m_thcV53PhaseTimer.isActive());
        QCOMPARE(backend.pressSafetyStopUnconfirmed(), cancelFailed || scenario == "confirmation-timeout");
        QCOMPARE(backend.thcCommissioningState(), backend.pressSafetyStopUnconfirmed()
            ? QStringLiteral("FAILED_STOP_UNCONFIRMED") : QStringLiteral("FAILED"));
        raw->setFailedFrame({});
        if (!backend.pressConnected()) QVERIFY(v51Ready(backend, raw));
        raw->receive(v51ProductionTelemetry());
        const auto cancels = countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n"));
        QVERIFY(backend.homePress());
        const auto homeId = backend.operationId();
        const auto writes = raw->writeCount();
        for (QTimer *timer : {&backend.m_thcV53HeartbeatTimer, &backend.m_thcV53ClientLeaseTimer, &backend.m_thcV53PhaseTimer})
            QVERIFY(QMetaObject::invokeMethod(timer, "timeout", Qt::DirectConnection));
        QCOMPARE(backend.operationId(), homeId);
        QCOMPARE(backend.operationName(), QStringLiteral("home"));
        QCOMPARE(raw->writeCount(), writes);
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), cancels);
        raw->receive(v51ProductionTelemetry("HOMING"));
        raw->receive(v51ProductionTelemetry());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.pressSafetyStopUnconfirmed());
    }

    void thcV53ModuleStopReentrantHomeIsNotInterrupted_data()
    {
        QTest::addColumn<QString>("notification");
        QTest::newRow("attempted-failure") << QStringLiteral("attempted-failure");
        QTest::newRow("hook-failure") << QStringLiteral("hook-failure");
        QTest::newRow("written") << QStringLiteral("written");
    }

    void thcV53ModuleStopReentrantHomeIsNotInterrupted()
    {
        QFETCH(QString, notification);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(v51ModuleReady(backend, moduleRaw));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        moduleRaw->receive(QByteArrayLiteral("<Run|MPos:0,0,0|WCO:0,0,0>"));
        const auto owner = backend.operationId();
        bool replaced = false;
        const auto replace = [&](const QByteArray &frame) {
            if (replaced || frame != "!") return;
            replaced = true;
            QVERIFY(backend.cancelThcCommissioning());
            raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
            raw->receive(v51ProductionTelemetry());
            QVERIFY(backend.homePress());
            if (notification != "written") moduleRaw->setFailedFrame(frame);
        };
        if (notification == "attempted-failure")
            connect(moduleRaw, &MachineTransport::frameWriteAttempted, &backend, replace, Qt::DirectConnection);
        else if (notification == "written")
            connect(moduleRaw, &MachineTransport::frameWritten, &backend, replace, Qt::DirectConnection);
        else moduleRaw->setWriteHook(replace);
        QVERIFY(!backend.stopModule());
        QVERIFY(replaced);
        QCOMPARE(backend.operationId(), owner + 1);
        QCOMPARE(backend.operationName(), QStringLiteral("home"));
        QVERIFY(backend.m_pressHomePending);
        QVERIFY(backend.commandOperationActive());
        QVERIFY(!backend.thcContinuousActive());
        QVERIFY(!backend.pressSafetyStopUnconfirmed());
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<$H>\n")), qsizetype(1));
        raw->receive(v51ProductionTelemetry("HOMING"));
        raw->receive(v51ProductionTelemetry());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void thcV53ModuleCancelWriteFailureDoesNotFailNewHome()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(v51ModuleReady(backend, moduleRaw));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        const auto owner = backend.operationId();
        bool recovered = false;
        connect(&backend, &MachineControlBackend::commandOperationFinished, &backend,
                [&](qulonglong id, const QString &, const QString &, const QString &state, const QString &) {
            if (id != owner || recovered) return;
            recovered = true;
            QCOMPARE(state, QStringLiteral("FAILED"));
            QVERIFY(!backend.pressSafetyStopUnconfirmed());
            QVERIFY(backend.homePress());
        }, Qt::DirectConnection);
        raw->setFailedFrame(QByteArrayLiteral("<THC:CANCEL>\n"));
        raw->setWriteHook([&](const QByteArray &frame) {
            if (frame != "<THC:CANCEL>\n") return;
            raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
            raw->receive(v51ProductionTelemetry());
        });
        QVERIFY(!backend.stopModule()); // Stale false result returns after proof + new Home.
        QVERIFY(recovered);
        QCOMPARE(backend.operationId(), owner + 1);
        QCOMPARE(backend.operationName(), QStringLiteral("home"));
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.m_pressHomePending);
        QVERIFY(backend.m_pressHomingTimer.isActive());
        QVERIFY(!backend.pressSafetyStopUnconfirmed());
        QVERIFY(!backend.m_thcV53PhaseTimer.isActive());
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        raw->receive(v51ProductionTelemetry("HOMING"));
        raw->receive(v51ProductionTelemetry());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void thcV53ReleaseRechecksAfterDirectNotification_data()
    {
        QTest::addColumn<QString>("guard");
        for (const char *guard : {"elapsed-lease", "phase", "stale", "physical-pedal", "anti-bind", "not-homed"})
            QTest::newRow(guard) << QString::fromLatin1(guard);
    }

    void thcV53ReleaseRechecksAfterDirectNotification()
    {
        QFETCH(QString, guard);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        const auto owner = backend.operationId();
        bool notified = false;
        connect(&backend, &MachineControlBackend::pressStateChanged, &backend, [&] {
            if (backend.m_thcV53Phase != MachineControlBackend::ThcV53Phase::AwaitRelease || notified) return;
            notified = true;
            if (guard == "elapsed-lease") {
                // No event loop/timer callback: elapsed time itself expires the
                // real 2 s operator lease while a direct UI subscriber runs.
                const auto remaining = backend.m_thcV53ClientDeadlineMs - backend.m_thcV53Clock.elapsed();
                QTest::qSleep(int(qMax(qint64(0), remaining)) + 10);
                QVERIFY(backend.m_thcV53Clock.elapsed() >= backend.m_thcV53ClientDeadlineMs);
            }
            if (guard == "phase") backend.m_thcV53PhaseDeadlineMs = backend.m_thcV53Clock.elapsed();
            if (guard == "stale") backend.m_pressTelemetryFresh = false;
            if (guard == "physical-pedal") backend.m_physicalPedal = true;
            if (guard == "anti-bind") backend.m_antiBind = true;
            if (guard == "not-homed") backend.m_pressHomed = false;
        }, Qt::DirectConnection);
        QVERIFY(!backend.releaseThcCommissioning());
        QVERIFY(notified);
        QCOMPARE(backend.operationId(), owner);
        QCOMPARE(backend.m_thcV53Phase, MachineControlBackend::ThcV53Phase::AwaitCancel);
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:RELEASE>\n")), qsizetype(0));
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QVERIFY(backend.pressSafetyStopUnconfirmed());
        QVERIFY(backend.commandOperationActive());
        QVERIFY(!backend.m_thcV53HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV53ClientLeaseTimer.isActive());
        QVERIFY(backend.m_thcV53PhaseTimer.isActive());
        QCOMPARE(backend.m_thcV53Failure, guard == "elapsed-lease" ? QStringLiteral("THC_V53_CLIENT_LEASE_EXPIRED")
            : guard == "phase" ? QStringLiteral("THC_V53_PHASE_TIMEOUT")
            : guard == "stale" ? QStringLiteral("THC_V53_TELEMETRY_STALE") : QStringLiteral("THC_V53_CONTROLLER_GUARD"));
    }

    void thcV53DiagnosticsAreBoundedAndNotAuthority()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        const QByteArray control("[TH_CTRL ms=100 age=5 ph=2 f1=0.45000 f2=0.50000 req=0.01300 v=0.01200 p=0.00100 i=0.00200 d=-0.00300 ev1=0.000 ev2=0.000 ap1=0.000 ap2=0.000 clamp=0 hr=1 hn=2 hl=1 ha=0.010 fr=0 profile=V46_LIVE_V53]");
        const QByteArray effective("[TH_V53 revision=1 effectiveRevision=0 rampMs=50 hold=1 kp=0.151000 ki=0.020000 kd=0.030000 rate=0.010000 cq=0.010000 fs=0.050000]");
        raw->receive(control);
        QVERIFY(backend.thcLiveDiagnostics().isEmpty());
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        const auto lease = backend.m_thcV53ClientDeadlineMs;
        raw->receive(control);
        raw->receive(effective);
        QCOMPARE(backend.thcLiveDiagnostics().value("force").toDouble(), 0.95);
        QCOMPARE(backend.thcLiveDiagnostics().value("request").toDouble(), 0.013);
        QCOMPARE(backend.thcLiveDiagnostics().value("effective").toMap().value("kp").toDouble(), 0.151);
        QCOMPARE(backend.thcLiveTuning().value("revision").toULongLong(), 0ULL);
        const auto good = backend.thcLiveDiagnostics();
        auto bad = control;
        bad.replace("f1=0.45000", "f1=nan");
        raw->receive(bad);
        bad = control;
        bad.replace("V46_LIVE_V53", "OWNED_INTERVAL_V49");
        raw->receive(bad);
        raw->receive(control + " ");
        QCOMPARE(backend.thcLiveDiagnostics(), good);
        QCOMPARE(backend.m_thcV53ClientDeadlineMs, lease);
        backend.expirePressTelemetry();
        QVERIFY(backend.thcLiveDiagnostics().isEmpty());
    }

    void thcV53FineLoadIsSequencedFreshAndDisplayOnly()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        raw->receive(v53Control(1000, 0));
        QVERIFY(backend.thcFineLoad().isEmpty());
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        const auto generalSequence = backend.pressTelemetrySequence();
        const auto y1 = backend.ramLoadY1();
        const auto y2 = backend.ramLoadY2();
        const auto velocity = backend.ramVelocity();
        const auto lease = backend.m_thcV53ClientDeadlineMs;
        const auto writes = raw->writeCount();
        QElapsedTimer clock;
        clock.start();
        raw->receive(v53Control(1000, 0)); // seq zero is valid; first row anchors only
        QVERIFY(backend.thcFineLoad().isEmpty());
        QTest::qSleep(100);
        raw->receive(v53Control(1000 + quint32(clock.elapsed()), 1));
        QTest::qSleep(100);
        raw->receive(v53Control(1000 + quint32(clock.elapsed()), 2));
        QTest::qSleep(100);
        raw->receive(v53Control(1000 + quint32(clock.elapsed()), 3));
        QTest::qSleep(470); // real monotonic time, no fake production clock
        const quint32 ms = 1000 + quint32(clock.elapsed());
        raw->receive(v53Control(ms, 4)); // queue sequence is shared across diagnostics
        auto fine = backend.thcFineLoad();
        QVERIFY(!fine.isEmpty());
        QSignalSpy fineChanged(&backend, &MachineControlBackend::thcFineLoadChanged);
        QCOMPARE(fine.value("f1").toDouble(), 0.45001);
        QCOMPARE(fine.value("f2").toDouble(), 0.55002);
        QCOMPARE(fine.value("ownerId").toString(), QString::number(backend.operationId()));
        QCOMPARE(fine.value("source").toString(), QStringLiteral("TH_CTRL_FILTERED_PRE_DEADZONE"));
        QCOMPARE(fine.value("sampleMs").toUInt(), ms - 5);
        QVERIFY(fine.value("receivedMs").toLongLong() >= 770);
        QVERIFY(fine.value("breakBefore").toBool());
        raw->receive(v53Control(ms, 4, 5, "0.99999")); // duplicate, no refresh or changed value
        raw->receive(v53Control(ms - 1, 3)); // replay
        raw->receive(v53Control(ms + 1, 5, 999)); // stale ADC
        auto shortPrecision = v53Control(ms + 1, 5);
        shortPrecision.replace("f1=0.45001", "f1=0.4");
        raw->receive(shortPrecision);
        auto wrongPhase = v53Control(ms + 1, 5);
        wrongPhase.replace("ph=2", "ph=1");
        raw->receive(wrongPhase);
        auto invalidSequence = v53Control(ms + 1, 5);
        invalidSequence.replace("seq=5", "seq=5.0");
        raw->receive(invalidSequence);
        auto noSequence = v53Control(ms + 1, 5);
        noSequence.replace(" seq=5", "");
        raw->receive(noSequence); // historical diagnostic has no fine authority
        QVERIFY(backend.thcLiveDiagnostics().contains("f1"));
        QCOMPARE(backend.thcFineLoad(), fine);
        QCOMPARE(fineChanged.size(), 0); // rejected/diagnostic rows do not fan out fine
        raw->receive(v53Control(ms + 10, 5, 5, "0.46001"));
        fine = backend.thcFineLoad();
        QCOMPARE(fineChanged.size(), 1); // actual parsed frame emits once, not diagnostics twice
        QCOMPARE(fine.value("sequence").toULongLong(), 2ULL);
        QCOMPARE(fine.value("f1").toDouble(), 0.46001);
        raw->receive(v53Control(ms + 20, 6, 15)); // same ADC timestamp
        QCOMPARE(backend.thcFineLoad(), fine);
        auto effective = QByteArrayLiteral("[TH_V53 revision=1 effectiveRevision=0 rampMs=50 hold=1 kp=0.151000 ki=0.020000 kd=0.030000 rate=0.010000 cq=0.010000 fs=0.050000 seq=8]");
        raw->receive(effective);
        QCOMPARE(backend.thcLiveDiagnostics().value("effective").toMap().value("seq").toUInt(), 8U);
        QCOMPARE(backend.thcFineLoad(), fine); // effective frame cannot refresh force
        QCOMPARE(fineChanged.size(), 1);
        QCOMPARE(backend.pressTelemetrySequence(), generalSequence);
        QCOMPARE(backend.ramLoadY1(), y1);
        QCOMPARE(backend.ramLoadY2(), y2);
        QCOMPARE(backend.ramVelocity(), velocity);
        QCOMPARE(backend.m_thcV53ClientDeadlineMs, lease);
        QCOMPARE(raw->writeCount(), writes);
        QTest::qSleep(760); // getter expires even without event loop dispatch
        QVERIFY(backend.thcFineLoad().isEmpty());
        QCOMPARE(raw->writeCount(), writes);
        QVERIFY(QMetaObject::invokeMethod(&backend.m_thcFineExpiryTimer, "timeout", Qt::DirectConnection));
        QVERIFY(backend.m_thcFineLoad.isEmpty());
        raw->receive(v53Control(ms + 780, 10)); // after timeout, anchor not sample
        QVERIFY(backend.thcFineLoad().isEmpty());
    }

    void thcV53FineLoadBreaksOnPublicationOrAdcGap_data()
    {
        QTest::addColumn<quint32>("firstMs");
        QTest::addColumn<quint32>("firstAge");
        QTest::addColumn<quint32>("nextAge");
        QTest::addColumn<quint32>("publicationDt");
        QTest::addColumn<bool>("expectedBreak");
        QTest::newRow("adc-age-250-to-zero") << 1000U << 250U << 0U << 100U << true;
        QTest::newRow("adc-gap-with-publication-and-sample-rollover")
            << 0xffffffceU << 250U << 0U << 100U << true;
        QTest::newRow("adc-gap-from-underflowed-sample") << 50U << 250U << 0U << 100U << true;
        QTest::newRow("initial-negative-adc-time") << 770U << 250U << 0U << 100U << true;
        QTest::newRow("adc-at-250-is-continuous") << 1000U << 150U << 0U << 100U << false;
        QTest::newRow("continuous-publication-and-sample-rollover")
            << 0xffffffceU << 0U << 0U << 100U << false;
        QTest::newRow("publication-gap-with-close-adc") << 1000U << 0U << 201U << 301U << true;
    }

    void thcV53FineLoadBreaksOnPublicationOrAdcGap()
    {
        QFETCH(quint32, firstMs);
        QFETCH(quint32, firstAge);
        QFETCH(quint32, nextAge);
        QFETCH(quint32, publicationDt);
        QFETCH(bool, expectedBreak);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        const auto writes = raw->writeCount();
        const auto lease = backend.m_thcV53ClientDeadlineMs;
        QElapsedTimer clock;
        clock.start();
        const quint32 startMs = firstMs - 770U;
        raw->receive(v53Control(startMs, 10, firstAge));
        QVERIFY(backend.thcFineLoad().isEmpty()); // includes ms=0, age=250 underflow
        for (quint32 n = 1; n <= 3; ++n) {
            QTest::qSleep(100);
            raw->receive(v53Control(startMs + quint32(clock.elapsed()), 10 + n, firstAge));
        }
        QTest::qSleep(470); // real warm-up; fixed MCU pair gives exact 100/350 ms deltas
        raw->receive(v53Control(firstMs, 14, firstAge));
        const auto first = backend.thcFineLoad();
        QVERIFY(!first.isEmpty());
        QCOMPARE(first.value("mcuMs").toUInt(), firstMs);
        QCOMPARE(first.value("sampleMs").toUInt(), quint32(firstMs - firstAge));
        QCOMPARE(first.value("sampleAgeMs").toUInt(), firstAge);
        QVERIFY(first.value("breakBefore").toBool());
        QTest::qSleep(int(publicationDt));
        const quint32 nextMs = firstMs + publicationDt;
        raw->receive(v53Control(nextMs, 15, nextAge));
        const auto next = backend.thcFineLoad();
        QVERIFY(!next.isEmpty());
        QCOMPARE(next.value("sequence").toULongLong(), first.value("sequence").toULongLong() + 1);
        QCOMPARE(next.value("generation"), first.value("generation"));
        QCOMPARE(next.value("mcuMs").toUInt() - first.value("mcuMs").toUInt(), publicationDt);
        QCOMPARE(next.value("sampleMs").toUInt() - first.value("sampleMs").toUInt(),
                 quint32(publicationDt + firstAge - nextAge));
        QCOMPARE(next.value("sampleAgeMs").toUInt(), nextAge);
        QCOMPARE(next.value("breakBefore").toBool(), expectedBreak);
        QTest::qSleep(100);
        raw->receive(v53Control(nextMs + 100U, 16, nextAge));
        const auto continuous = backend.thcFineLoad();
        QVERIFY(!continuous.isEmpty());
        QCOMPARE(continuous.value("sequence").toULongLong(), next.value("sequence").toULongLong() + 1);
        QVERIFY(!continuous.value("breakBefore").toBool()); // a gap is not latched
        QCOMPARE(backend.m_thcV53ClientDeadlineMs, lease);
        QCOMPARE(raw->writeCount(), writes);
    }

    void thcV53FineLongStreamTimingAndNotifications_data()
    {
        QTest::addColumn<bool>("drifting");
        QTest::newRow("90s-stable-jitter-fill-to-hold") << false;
        QTest::newRow("90s-accumulated-drift-reanchors-not-control") << true;
    }

    void thcV53FineLongStreamTimingAndNotifications()
    {
        QFETCH(bool, drifting);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V53_RUNNING}"));
        raw->receive(QByteArrayLiteral("{THC:CONTACT}")); // Fill/acquisition, ph=1
        QSignalSpy changed(&backend, &MachineControlBackend::thcFineLoadChanged);
        const auto writes = raw->writeCount();
        const auto lease = backend.m_thcV53ClientDeadlineMs;
        const auto generalSequence = backend.pressTelemetrySequence();
        // The first row changes owner and establishes the initial generation.
        const auto initialGeneration = backend.m_thcFineGeneration
            + (backend.m_thcFineOwner != backend.operationId() ? 1 : 0);
        int firstInvalidationMs = -1;
        int published = 0;
        for (int n = 0; n <= 900; ++n) {
            if (n == 600) backend.m_thcV53Phase = MachineControlBackend::ThcV53Phase::Holding;
            // Private display observer only: no alternate production clock or
            // bypass of the control owner/lease/phase admission is installed.
            const qint64 hostMs = n * 100;
            const quint32 mcuMs = 1000 + quint32(drifting ? n * 985 / 10 : n * 100);
            const quint32 age = n % 3 == 0 ? 5 : 15;
            QVariantMap values = {{"finePrecision", true}, {"ms", mcuMs}, {"seq", quint32(n * 4)},
                {"age", age}, {"ph", n < 600 ? 1 : 2}, {"f1", 0.45001 + (n % 7) * 0.00001},
                {"f2", 0.55002}};
            changed.clear();
            backend.observeThcFineLoadAt(values, ++backend.m_pressFrameArrival, hostMs);
            QVERIFY(changed.size() <= 1);
            if (firstInvalidationMs < 0 && backend.m_thcFineGeneration != initialGeneration)
                firstInvalidationMs = int(hostMs);
            const auto fine = backend.m_thcFineLoad;
            if (!fine.isEmpty()) {
                ++published;
                QCOMPARE(fine.value("ownerId").toString(), QString::number(backend.operationId()));
                QCOMPARE(fine.value("f1"), values.value("f1"));
                QCOMPARE(fine.value("f2"), values.value("f2"));
                // Shared diagnostics/effective publications do not notify fine.
                changed.clear();
                emit backend.thcLiveDiagnosticsChanged();
                QCOMPARE(changed.size(), 0);
                backend.observeThcFineLoadAt(values, ++backend.m_pressFrameArrival, hostMs);
                QCOMPARE(backend.m_thcFineLoad, fine);
                QCOMPARE(changed.size(), 0);
            }
        }
        QVERIFY(published > 800);
        if (drifting) {
            // 1.5 ms/100 ms cumulative divergence crosses the *unchanged*
            // 250 ms uncertainty fence at 16.7 s. It is a display gap, not reset.
            QCOMPARE(firstInvalidationMs, 16700);
            QVERIFY(backend.m_thcFineGeneration > initialGeneration);
        } else {
            QCOMPARE(firstInvalidationMs, -1);
            QCOMPARE(backend.m_thcFineGeneration, initialGeneration);
        }
        QCOMPARE(raw->writeCount(), writes);
        QCOMPARE(backend.m_thcV53ClientDeadlineMs, lease);
        QCOMPARE(backend.pressTelemetrySequence(), generalSequence);
        QVERIFY(backend.thcContinuousActive());
        QCOMPARE(backend.ramLoadY1(), 0.4);
        QCOMPARE(backend.ramLoadY2(), 0.5);
    }

    void thcV53FineBoundaries_data()
    {
        QTest::addColumn<QString>("boundary");
        for (const char *name : {"owner", "disconnect", "status-stale", "cancel", "release", "backlog", "rollover"})
            QTest::newRow(name) << QString::fromLatin1(name);
    }

    void thcV53FineBoundaries()
    {
        QFETCH(QString, boundary);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        QElapsedTimer clock;
        clock.start();
        const quint32 start = boundary == "rollover" ? 0xffffff00U : 1000U;
        const quint32 seq = boundary == "rollover" ? 0xfffffffeU : 10U;
        raw->receive(v53Control(start, seq));
        for (quint32 n = 1; n <= 3; ++n) {
            QTest::qSleep(100);
            raw->receive(v53Control(start + quint32(clock.elapsed()), seq + n));
        }
        QTest::qSleep(470);
        raw->receive(v53Control(start + quint32(clock.elapsed()), seq + 4));
        QVERIFY(!backend.thcFineLoad().isEmpty());
        const auto generation = backend.thcFineLoad().value("generation").toString();
        if (boundary == "rollover") {
            QVERIFY(backend.thcFineLoad().value("mcuMs").toUInt() < start);
            return;
        }
        if (boundary == "owner") backend.beginCommandOperation(QStringLiteral("module"), QStringLiteral("other-owner"));
        if (boundary == "disconnect") raw->drop();
        if (boundary == "status-stale") backend.expirePressTelemetry();
        if (boundary == "cancel") QVERIFY(backend.cancelThcCommissioning());
        if (boundary == "release") QVERIFY(backend.releaseThcCommissioning());
        if (boundary == "backlog") raw->receive(v53Control(start + 5000, seq + 10));
        QVERIFY(backend.thcFineLoad().isEmpty());
        const auto writes = raw->writeCount();
        raw->receive(v53Control(start + 5010, seq + 11));
        QVERIFY(backend.thcFineLoad().isEmpty());
        QCOMPARE(raw->writeCount(), writes); // observation never cancels/queries
        QVERIFY(QString::number(backend.m_thcFineGeneration) != generation);
    }

    void thcV53HomeRecoveryDoesNotCancelNewHomeOwner()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        QVERIFY(!backend.homePress());
        const auto cancels = countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n"));
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        raw->receive(v51ProductionTelemetry());
        QVERIFY(!backend.thcContinuousActive());
        QVERIFY(backend.homePress());
        const auto homeId = backend.operationId();
        QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV53PhaseTimer, "timeout", Qt::DirectConnection));
        backend.sendThcV53Heartbeat();
        QCOMPARE(backend.operationId(), homeId);
        QCOMPARE(backend.operationName(), QStringLiteral("home"));
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), cancels);
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<$H>\n")), qsizetype(1));
        QVERIFY(!backend.queryThcLiveTuning());
        raw->receive(v51ProductionTelemetry("HOMING"));
        raw->receive(v51ProductionTelemetry());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void thcV53SynchronousReplyAndFailureAreAtomic()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        raw->setWriteHook([raw](const QByteArray &frame) {
            if (frame == QByteArrayLiteral("<THC:CONTACT_PROFILE_V53>\n")) v53Hold(raw);
            if (frame.startsWith("<THC:V53:TUNE:")) raw->receive(v53Reply("1", "0.160000"));
            if (frame == QByteArrayLiteral("<THC:CANCEL>\n")) {
                raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
                raw->receive(v51ProductionTelemetry());
            }
        });
        QVERIFY(backend.startContinuousThcContactProfile());
        const auto id = backend.operationId();
        QVERIFY(backend.applyThcLiveTuning(v53Settings(0.16)));
        QVERIFY(!backend.thcLiveTuningPending());
        QVERIFY(backend.thcLiveTuningSupported());
        QCOMPARE(backend.operationId(), id);
        QVERIFY(backend.cancelThcCommissioning());
        QVERIFY(!backend.thcContinuousActive());
        QVERIFY(!backend.m_thcV53HeartbeatTimer.isActive());
        QVERIFY(!backend.pressSafetyStopUnconfirmed());
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
    }

    void thcV53InvalidLiveAckCancelsSameOwner()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        const auto id = backend.operationId();
        const auto demand = backend.ramVelocity();
        QVERIFY(backend.applyThcLiveTuning(v53Settings(0.16)));
        raw->receive(v53Reply("2", "0.160000"));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.m_thcV53Phase, MachineControlBackend::ThcV53Phase::AwaitCancel);
        QVERIFY(backend.m_thcV53Failure.contains(QStringLiteral("V53_ACK_MISMATCH")));
        QCOMPARE(backend.ramVelocity(), demand);
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QVERIFY(!backend.m_thcV53HeartbeatTimer.isActive());
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        raw->receive(v51ProductionTelemetry());
        QVERIFY(!backend.pressSafetyStopUnconfirmed());
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QVERIFY(backend.operationError().contains(QStringLiteral("V53_ACK_MISMATCH")));
        QVERIFY(!backend.queryThcLiveTuning());
        QVERIFY(!backend.pressConnected());
        QVERIFY(v51Ready(backend, raw));
        raw->receive(v51ProductionTelemetry());
        QVERIFY(backend.queryThcLiveTuning());
        raw->receive(v53Reply());
        QVERIFY(backend.thcLiveTuningSupported());
    }

    void thcV53LegacyAndV51OwnershipRemainIsolated()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(backend.queryThcTuning());
        const auto before = raw->writeCount();
        QVERIFY(!backend.queryThcLiveTuning());
        QCOMPARE(raw->writeCount(), before);
        raw->receive(QByteArrayLiteral("{THC:TUNE:v=1,cq=0.0100,fs=0.0500,rate=0.0100,auth=0.0200,brake=freeze,safe=freeze}"));
        QVERIFY(!backend.m_thcTuningQueryPending);
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        const auto id = backend.operationId();
        QVERIFY(!backend.queryThcLiveTuning());
        QVERIFY(!backend.applyThcLiveTuning(v53Settings()));
        QVERIFY(!backend.startContinuousThcContactProfile());
        raw->receive(v53Reply());
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationName(), QStringLiteral("thc-contact-profile-v51"));
        QVERIFY(backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV53HeartbeatTimer.isActive());
    }

    void thcV53SerialAllowlist_data()
    {
        QTest::addColumn<QByteArray>("frame");
        QTest::addColumn<bool>("accepted");
        QTest::newRow("query") << QByteArray("<THC:V53?>\n") << true;
        QTest::newRow("start") << QByteArray("<THC:CONTACT_PROFILE_V53>\n") << true;
        // AUTO contact-profile target suffix (backend 3-decimal form, 0.5-20 T).
        QTest::newRow("contact-default") << QByteArray("<THC:CONTACT_PROFILE>\n") << true;
        for (const QByteArray &tons : {QByteArray("0.500"), QByteArray("0.750"),
             QByteArray("2.500"), QByteArray("20.000")})
            QTest::newRow(("contact-target-" + tons).constData())
                << QByteArray("<THC:CONTACT_PROFILE:") + tons + ">\n" << true;
        for (const QByteArray &tons : {QByteArray("0.499"), QByteArray("20.001"),
             QByteArray("0.5"), QByteArray("1"), QByteArray("00.500"), QByteArray("-1.000"),
             QByteArray("+1.000"), QByteArray("nan"), QByteArray("1e1"), QByteArray(" 1.000"),
             QByteArray("100.000"), QByteArray("")})
            QTest::newRow(("contact-reject-" + tons).constData())
                << QByteArray("<THC:CONTACT_PROFILE:") + tons + ">\n" << false;
        QTest::newRow("contact-target-injection")
            << QByteArray("<THC:CONTACT_PROFILE:0.500>\n<$H>\n") << false;
        const QByteArray values(",0.150000,0.020000,0.030000,0.010000,0.010000,0.050000>\n");
        QTest::newRow("tune") << QByteArray("<THC:V53:TUNE:1") + values << true;
        QTest::newRow("uint32-max") << QByteArray("<THC:V53:TUNE:4294967295") + values << true;
        QTest::newRow("legacy-padding") << QByteArray("<THC:V53:TUNE:1,000.150000,0.020000,0.030000,0.010000,0.010000,0.050000>\n") << true;
        QTest::newRow("extended-coefficient") << QByteArray("<THC:V53:TUNE:1,0.300002,0.020000,0.030000,0.010000,0.010000,0.050000>\n") << true;
        QTest::newRow("extended-zero-fields") << QByteArray("<THC:V53:TUNE:1,0.000000,0.000000,0.000000,0.000000,0.000000,0.000001>\n") << true;
        QTest::newRow("extended-largest-canonical") << QByteArray("<THC:V53:TUNE:4294967295,999999999.999999,999999999.999999,999999999.999999,999999999.999999,999999999.999998,999999999.999999>\n") << true;
        QByteArray maximumLegacy = QByteArray("<THC:V53:TUNE:4294967295") + values;
        maximumLegacy.insert(maximumLegacy.indexOf(",0.150000") + 1,
                     QByteArray(128 - (maximumLegacy.size() - 3), '0'));
        QTest::newRow("legacy-128-byte-payload") << maximumLegacy << true;
        maximumLegacy.insert(maximumLegacy.indexOf(',') + 1, '0');
        QTest::newRow("legacy-129-byte-payload") << maximumLegacy << false;
        for (const QByteArray &revision : {QByteArray("0"), QByteArray("01"), QByteArray("-1"),
             QByteArray("+1"), QByteArray("1.0"), QByteArray("4294967296"), QByteArray(" 1")})
            QTest::newRow(revision.constData()) << QByteArray("<THC:V53:TUNE:") + revision + values << false;
        QTest::newRow("nan") << QByteArray("<THC:V53:TUNE:1,nan,0.020000,0.030000,0.010000,0.010000,0.050000>\n") << false;
        // Expanded canonical frames are legal structurally; v1 rejection is
        // tested at backend admission, which alone knows the negotiated version.
        for (const QByteArray &token : {QByteArray("00.400000"), QByteArray("1000000000.000000"),
             QByteArray("+0.400000"), QByteArray("-0.000000"), QByteArray("0.4000000"),
             QByteArray("1e-6"), QByteArray("inf"), QByteArray(" 0.400000")})
            QTest::newRow(("extended-structure-" + token).constData())
            << QByteArray("<THC:V53:TUNE:1,") + token + ",0.020000,0.030000,0.010000,0.010000,0.050000>\n" << false;
        QTest::newRow("zero-fs") << QByteArray("<THC:V53:TUNE:1,0.000000,0.000000,0.000000,0.000000,0.000000,0.000000>\n") << false;
        QTest::newRow("sub-quantum-fs") << QByteArray("<THC:V53:TUNE:1,0.000000,0.000000,0.000000,0.000000,0.000000,0.0000009>\n") << false;
        QTest::newRow("equal-fs-cq") << QByteArray("<THC:V53:TUNE:1,0.150000,0.020000,0.030000,0.010000,0.020000,0.020000>\n") << false;
        QTest::newRow("overflow-payload") << QByteArray("<THC:V53:TUNE:1,") + QByteArray(130, '0') + ".150000,0.020000,0.030000,0.010000,0.010000,0.050000>\n" << false;
        QTest::newRow("extra-newline") << QByteArray("<THC:V53:TUNE:1") + values + '\n' << false;
        QTest::newRow("injection") << QByteArray("<THC:V53?>\n<$H>\n") << false;
    }

    void thcV53SerialAllowlist()
    {
        QFETCH(QByteArray, frame);
        QFETCH(bool, accepted);
        QCOMPARE(SerialMachineTransport::isWriteFrameAllowed(SerialDeviceDiscovery::DeviceRole::Press, frame), accepted);
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(SerialDeviceDiscovery::DeviceRole::Module, frame));
    }

    void thcV51Admission_data()
    {
        QTest::addColumn<QString>("gate");
        for (const char *gate : {"good", "empty-hash", "wrong-hash", "uppercase-hash",
                                "padded-hash", "v11", "v12", "v14", "v13-suffix",
                                "not-connected", "not-homed", "stale", "not-idle",
                                "other-operation", "safety-lock", "program", "priming",
                                "anti-bind", "tuning-pending", "tuning-recovery"})
            QTest::newRow(gate) << QString::fromLatin1(gate);
    }

    void thcV51Admission()
    {
        QFETCH(QString, gate);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QByteArray identity("[LS-BEND v1.3]");
        if (gate == "v11") identity = "[LS-BEND v1.1]";
        if (gate == "v12") identity = "[LS-BEND v1.2]";
        if (gate == "v14") identity = "[LS-BEND v1.4]";
        if (gate == "v13-suffix") identity = "[LS-BEND v1.3a]";
        if (gate != "not-connected") QVERIFY(v51Ready(backend, raw, identity));
        QString hash = v51Hash();
        if (gate == "empty-hash") hash.clear();
        if (gate == "wrong-hash") hash[0] = QLatin1Char('0');
        if (gate == "uppercase-hash") hash = hash.toUpper();
        if (gate == "padded-hash") hash += QLatin1Char(' ');
        if (gate == "not-homed") backend.m_pressHomed = false;
        if (gate == "stale") backend.m_pressTelemetryFresh = false;
        if (gate == "not-idle") backend.m_pressMachineState = QStringLiteral("HOMING");
        if (gate == "other-operation") backend.m_pressOperationActive = true;
        if (gate == "safety-lock") backend.m_pressSafetyStopUnconfirmed = true;
        if (gate == "program") backend.m_programRunActive = true;
        if (gate == "priming") backend.m_primingModeEnabled = true;
        if (gate == "anti-bind") backend.m_antiBind = true;
        if (gate == "tuning-pending") backend.m_thcTuningQueryPending = true;
        if (gate == "tuning-recovery") backend.m_thcTuningQueryRecovery = true;
        const auto before = raw->writeCount();
        QCOMPARE(backend.startThcContactProfileV51Commissioning(hash), gate == "good");
        QVERIFY(!backend.thcV51RunningAcknowledged());
        if (gate == "good") {
            QCOMPARE(raw->writeCount(), before + 1);
            QCOMPARE(raw->writeAt(before), QByteArrayLiteral("<THC:CONTACT_PROFILE_V51>\n"));
            QCOMPARE(backend.operationName(), QStringLiteral("thc-contact-profile-v51"));
            QVERIFY(backend.m_thcV51HeartbeatTimer.isActive());
            QVERIFY(!backend.m_thcContactProfileHeartbeatTimer.isActive());
            QVERIFY(!backend.m_commandDeadlineTimer.isActive());
            QCOMPARE(backend.m_thcV51OverallDeadlineMs, qint64(330000));
            QCOMPARE(backend.m_thcV51PhaseDeadlineMs, qint64(5000));
            const auto id = backend.operationId();
            raw->receive(v51Idle()); // queued pre-start IDLE cannot clear ownership
            QVERIFY(backend.commandOperationActive());
            QVERIFY(!backend.startThcContactProfileV51Commissioning(hash));
            QCOMPARE(backend.operationId(), id);
            QCOMPARE(raw->writeCount(), before + 1);
        } else {
            QCOMPARE(raw->writeCount(), before);
            QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
        }
    }

    void thcV51ExactStartAck_data()
    {
        QTest::addColumn<QByteArray>("ack");
        QTest::addColumn<bool>("accepted");
        QTest::newRow("exact") << QByteArray("{THC:CONTACT_PROFILE_V51_RUNNING}") << true;
        for (const QByteArray &ack : {QByteArray("{THC:CONTACT_PROFILE_RUNNING}"),
             QByteArray("{thc:contact_profile_v51_running}"),
             QByteArray(" {THC:CONTACT_PROFILE_V51_RUNNING}"),
             QByteArray("{THC:CONTACT_PROFILE_V51_RUNNING} "),
             QByteArray("{THC: CONTACT_PROFILE_V51_RUNNING}"),
             QByteArray("{THC:CONTACT_PROFILE_V51_RUNNING}\r\n"),
             QByteArray("{THC:RUNNING}"), QByteArray("{THC:ARMED}"),
             QByteArray("{THC:CONTACT}"), QByteArray("{THC:HOLDING}"),
             QByteArray("{THC:RELEASING}"), QByteArray("{THC:DONE}"),
             QByteArray("{TH:DONE}"), QByteArray("{THC:CANCELLED}")})
            QTest::newRow(ack.constData()) << ack << false;
    }

    void thcV51ExactStartAck()
    {
        QFETCH(QByteArray, ack);
        QFETCH(bool, accepted);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        raw->receive(QByteArrayLiteral("[JOG COMPLETED]"));
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        raw->receive(ack);
        QCOMPARE(backend.thcV51RunningAcknowledged(), accepted);
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(accepted ? 0 : 1));
        if (accepted) {
            QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
            QCOMPARE(backend.m_thcV51PhaseDeadlineMs, qint64(50000));
        } else {
            QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
            QVERIFY(!backend.m_thcV51ClientLeaseTimer.isActive());
            QVERIFY(!backend.m_thcV51OverallTimer.isActive());
            QVERIFY(backend.m_pressSafetyStopUnconfirmed);
            raw->receive(v51Idle());
            QVERIFY(backend.commandOperationActive());
        }
    }

    void thcV51UnsolicitedMarkerCannotAdmitLegacyAuto()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        QVERIFY(!backend.commandOperationActive());
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QVERIFY(backend.startAutomaticThcContactProfile());
        const QString state = backend.thcCommissioningState();
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        raw->receive(QByteArrayLiteral(" {thc:contact_profile_v51_running} "));
        QCOMPARE(backend.thcCommissioningState(), state);
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        QVERIFY(!backend.m_thcContactProfileHeartbeatTimer.isActive());
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_RUNNING}"));
        QVERIFY(backend.m_thcContactProfileHeartbeatTimer.isActive());
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QCOMPARE(backend.operationName(), QStringLiteral("automatic-thc-contact-profile"));
    }

    void thcV51DualHeartbeatDoesNotRenewOwnerOrPhase()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        QCOMPARE(backend.m_thcV51HeartbeatTimer.interval(), 250);
        QCOMPARE(backend.m_thcV51ClientLeaseTimer.interval(), 2000);
        const qint64 client = backend.m_thcV51Clock.elapsed() + 60000;
        backend.m_thcV51ClientDeadlineMs = client;
        backend.m_thcV51PhaseDeadlineMs = client;
        const auto before = raw->writeCount();
        const auto phase = backend.m_thcV51PhaseDeadlineMs;
        const auto overall = backend.m_thcV51OverallDeadlineMs;
        for (int n = 0; n < 3; ++n) {
            QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51HeartbeatTimer, "timeout", Qt::DirectConnection));
            QCOMPARE(raw->writeAt(before + n * 2), QByteArrayLiteral("<THC:HB>\n"));
            QCOMPARE(raw->writeAt(before + n * 2 + 1), QByteArrayLiteral("<?>\n"));
            raw->receive(QByteArrayLiteral("{THC:HB}"));
            QCOMPARE(backend.m_thcV51ClientDeadlineMs, client);
            QCOMPARE(backend.m_thcV51PhaseDeadlineMs, phase);
            QCOMPARE(backend.m_thcV51OverallDeadlineMs, overall);
            QVERIFY(!backend.thcV51RunningAcknowledged());
        }
        const auto writes = raw->writeCount();
        const auto renewalBefore = backend.m_thcV51Clock.elapsed();
        QVERIFY(backend.heartbeatThcCommissioning());
        const auto renewalAfter = backend.m_thcV51Clock.elapsed();
        QCOMPARE(raw->writeCount(), writes); // client renewal is not a serial command
        QVERIFY(backend.m_thcV51ClientDeadlineMs >= renewalBefore + 2000);
        QVERIFY(backend.m_thcV51ClientDeadlineMs <= renewalAfter + 2000);
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, phase);
        backend.m_thcV51ClientDeadlineMs = backend.m_thcV51Clock.elapsed();
        backend.sendThcV51Heartbeat();
        QCOMPARE(raw->writeCount(), writes + 1);
        QCOMPARE(raw->writeAt(writes), QByteArrayLiteral("<THC:CANCEL>\n"));
        QVERIFY(!backend.heartbeatThcCommissioning());
        QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
    }

    void thcV51AutomaticCycleHasImmutableDeadlinesAndNewCycleReset()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        const auto id = backend.operationId();
        const auto epoch = backend.m_thcV51Clock.msecsSinceReference();
        const auto overall = backend.m_thcV51OverallDeadlineMs;
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, qint64(50000));
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, qint64(50000));
        raw->receive(QByteArrayLiteral("{THC:CONTACT}"));
        QVERIFY(backend.thcContactObserved());
        const auto acquisition = backend.m_thcV51PhaseDeadlineMs;
        QVERIFY(acquisition >= 185000);
        raw->receive(QByteArrayLiteral("{THC:CONTACT}"));
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, acquisition);
        const auto holdBefore = backend.m_thcV51Clock.elapsed();
        raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        const auto holdAfter = backend.m_thcV51Clock.elapsed();
        const auto hold = backend.m_thcV51PhaseDeadlineMs;
        QVERIFY(hold >= holdBefore + 60000);
        QVERIFY(hold <= holdAfter + 60000);
        raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        raw->receive(QByteArrayLiteral("{THC:CONTACT}"));
        raw->receive(QByteArrayLiteral("{THC:HB}"));
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, hold);
        QCOMPARE(backend.m_thcV51OverallDeadlineMs, overall);
        QCOMPARE(backend.m_thcV51Clock.msecsSinceReference(), epoch);
        backend.m_thcV51PhaseDeadlineMs = backend.m_thcV51Clock.elapsed();
        const auto releaseBefore = backend.m_thcV51Clock.elapsed();
        QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51PhaseTimer, "timeout", Qt::DirectConnection));
        const auto releaseAfter = backend.m_thcV51Clock.elapsed();
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:RELEASE>\n")), qsizetype(1));
        QVERIFY(backend.heartbeatThcCommissioning()); // owner survives AwaitRelease
        QVERIFY(!backend.releaseThcCommissioning());
        const auto releaseEnd = backend.m_thcV51ReleaseDeadlineMs;
        QVERIFY(releaseEnd >= releaseBefore + 45000);
        QVERIFY(releaseEnd <= releaseAfter + 45000);
        raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, releaseEnd);
        raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, releaseEnd);
        raw->receive(v51Idle());
        QVERIFY(backend.commandOperationActive());
        raw->receive(QByteArrayLiteral("{THC:DONE}"));
        const auto idleDeadline = backend.m_thcV51PhaseDeadlineMs;
        raw->receive(QByteArrayLiteral("{THC:DONE}"));
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, idleDeadline);
        QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV51ClientLeaseTimer.isActive());
        raw->receive(v51Idle());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(backend.operationId(), id);
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QVERIFY(!backend.m_thcV51PhaseTimer.isActive());
        QVERIFY(!backend.m_thcV51OverallTimer.isActive());
        QVERIFY(!backend.m_pressSafetyStopUnconfirmed);
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        QCOMPARE(backend.operationId(), id + 1);
        QVERIFY(!backend.thcContactObserved());
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, qint64(5000));
    }

    void thcV51ExplicitRelease_data()
    {
        QTest::addColumn<int>("stage");
        QTest::newRow("arming-rejected") << 0;
        QTest::newRow("approach-rejected") << 1;
        QTest::newRow("acquisition-accepted") << 2;
        QTest::newRow("holding-accepted") << 3;
    }

    void thcV51ExplicitRelease()
    {
        QFETCH(int, stage);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        if (stage >= 1) raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        if (stage >= 2) raw->receive(QByteArrayLiteral("{THC:CONTACT}"));
        if (stage >= 3) raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        const auto writes = raw->writeCount();
        QCOMPARE(backend.releaseThcCommissioning(), stage >= 2);
        QCOMPARE(raw->writeCount(), writes + (stage >= 2 ? 1 : 0));
        if (stage < 2) return;
        const auto releaseDeadline = backend.m_thcV51ReleaseDeadlineMs;
        QVERIFY(!backend.releaseThcCommissioning());
        QCOMPARE(backend.m_thcV51ReleaseDeadlineMs, releaseDeadline);
        QCOMPARE(raw->writeCount(), writes + 1);
        raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        raw->receive(QByteArrayLiteral("{THC:DONE}"));
        raw->receive(v51Idle());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void thcV51ExpiredHoldReleaseReportsSingleDispatch_data()
    {
        QTest::addColumn<QString>("reply");
        for (const char *reply : {"deferred", "releasing", "write-failure", "transport-error"})
            QTest::newRow(reply) << QString::fromLatin1(reply);
    }

    void thcV51ExpiredHoldReleaseReportsSingleDispatch()
    {
        QFETCH(QString, reply);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        v51Contact(raw);
        raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        backend.m_thcV51ClientDeadlineMs = backend.m_thcV51Clock.elapsed() + 60000;
        backend.m_thcV51PhaseDeadlineMs = backend.m_thcV51Clock.elapsed();
        if (reply == "write-failure") raw->setFailedFrame(QByteArrayLiteral("<THC:RELEASE>\n"));
        raw->setWriteHook([raw, reply](const QByteArray &frame) {
            if (frame != QByteArrayLiteral("<THC:RELEASE>\n")) return;
            if (reply == "releasing") raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
            if (reply == "transport-error") raw->fail(QStringLiteral("TEST_RELEASE_ERROR"));
        });
        QSignalSpy rejected(&backend, &MachineControlBackend::operationRejected);
        const auto before = backend.m_thcV51Clock.elapsed();
        const bool accepted = reply == "deferred" || reply == "releasing";
        QCOMPARE(backend.releaseThcCommissioning(), accepted);
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:RELEASE>\n")), qsizetype(1));
        QCOMPARE(rejected.count(), 0);
        if (!accepted) {
            QVERIFY(backend.m_pressSafetyStopUnconfirmed);
            QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
            return;
        }
        QVERIFY(backend.m_thcV51Clock.isValid());
        const auto after = backend.m_thcV51Clock.elapsed();
        const auto deadline = backend.m_thcV51ReleaseDeadlineMs;
        QVERIFY(deadline >= before + 45000);
        QVERIFY(deadline <= after + 45000);
        QCOMPARE(backend.m_thcV51Phase, reply == "releasing"
            ? MachineControlBackend::ThcV51Phase::Releasing : MachineControlBackend::ThcV51Phase::AwaitRelease);
        QVERIFY(!backend.releaseThcCommissioning()); // later duplicate retains existing rejection contract
        QCOMPARE(backend.m_thcV51ReleaseDeadlineMs, deadline);
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:RELEASE>\n")), qsizetype(1));
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(0));
    }

    void thcV51ProductionTerminalRequiresAckThenValidIdle_data()
    {
        QTest::addColumn<bool>("cancelled");
        QTest::newRow("cancel-retains-pid-output") << true;
        QTest::newRow("done-retains-pid-output") << false;
    }

    void thcV51ProductionTerminalRequiresAckThenValidIdle()
    {
        QFETCH(bool, cancelled);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        backend.m_thcV51ClientDeadlineMs = backend.m_thcV51Clock.elapsed() + 60000;
        v51Contact(raw);
        if (cancelled) QVERIFY(backend.cancelThcCommissioning());
        else {
            QVERIFY(backend.releaseThcCommissioning());
            raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        }
        const auto idle = v51ProductionTelemetry();
        QCOMPARE(idle.count('|'), 19);
        raw->receive(idle);
        QVERIFY(backend.commandOperationActive()); // IDLE alone has no terminal authority
        QCOMPARE(backend.ramVelocity(), -7.25);
        QVERIFY(backend.measuredRamVelocityAvailable());
        QCOMPARE(backend.measuredRamVelocity(), 0.0);
        QVERIFY(backend.motorRpmAvailable());
        QVERIFY(backend.physicalPedalAvailable());
        const auto sequence = backend.pressTelemetrySequence();
        const auto marker = cancelled ? QByteArrayLiteral("{THC:CANCELLED}") : QByteArrayLiteral("{THC:DONE}");
        raw->receive(marker);
        raw->receive(marker); // duplicates do not change the corroboration barrier
        QCOMPARE(backend.m_thcV51TerminalTelemetrySequence, sequence);
        backend.handleThcV51Telemetry(true); // cached valid IDLE is not a new frame
        QVERIFY(backend.commandOperationActive());
        raw->receive(v51ProductionTelemetry(QByteArrayLiteral("IDLE"), QByteArrayLiteral("nan")));
        QCOMPARE(backend.pressTelemetrySequence(), sequence);
        QVERIFY(backend.commandOperationActive());
        for (const QByteArray &state : {QByteArray("idle"), QByteArray(" IDLE"), QByteArray("IDLE ")}) {
            raw->receive(v51ProductionTelemetry(state));
            QVERIFY(backend.commandOperationActive()); // normalized spelling cannot corroborate V51
        }
        raw->receive(idle);
        QCOMPARE(backend.operationState(), cancelled ? QStringLiteral("FAILED") : QStringLiteral("COMPLETED"));
        QVERIFY(!backend.commandOperationActive());
        QVERIFY(!backend.pressOperationActive());
        QVERIFY(!backend.m_pressSafetyStopUnconfirmed);
        QCOMPARE(backend.ramVelocity(), -7.25); // never zero the retained PID command
        QCOMPARE(backend.measuredRamVelocity(), 0.0);
        QVERIFY(!backend.m_thcV51PhaseTimer.isActive());
    }

    void thcV51TerminalSafetyEvidence_data()
    {
        QTest::addColumn<bool>("cancelled");
        QTest::addColumn<QString>("evidence");
        for (bool cancelled : {false, true}) {
            for (const char *evidence : {"stale", "anti-bind", "non-idle", "invalid-measured-velocity", "deadline"}) {
                const QByteArray name = QByteArray(cancelled ? "cancel-" : "done-") + evidence;
                QTest::newRow(name.constData()) << cancelled << QString::fromLatin1(evidence);
            }
        }
    }

    void thcV51TerminalSafetyEvidence()
    {
        QFETCH(bool, cancelled);
        QFETCH(QString, evidence);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        backend.m_thcV51ClientDeadlineMs = backend.m_thcV51Clock.elapsed() + 60000;
        v51Contact(raw);
        if (cancelled) {
            QVERIFY(backend.cancelThcCommissioning());
            raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        } else {
            QVERIFY(backend.releaseThcCommissioning());
            raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
            raw->receive(QByteArrayLiteral("{THC:DONE}"));
        }
        auto fields = v51ProductionTelemetry().split('|');
        if (evidence == "stale") {
            backend.m_pressTelemetryFresh = false;
            backend.handleThcV51Telemetry(true);
        } else if (evidence == "deadline") {
            backend.m_thcV51PhaseDeadlineMs = backend.m_thcV51Clock.elapsed();
            raw->receive(v51ProductionTelemetry());
        } else {
            if (evidence == "anti-bind") fields[14] = "1";
            if (evidence == "non-idle") fields[0] = "<RETRACT_JOG";
            if (evidence == "invalid-measured-velocity") fields[15] = "nan";
            raw->receive(fields.join('|'));
        }
        QVERIFY(backend.operationState() != QStringLiteral("COMPLETED"));
        if (cancelled && evidence == "deadline") {
            QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
            QVERIFY(backend.m_pressSafetyStopUnconfirmed);
            QVERIFY(!backend.pressOperationActive());
            return;
        }
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.pressOperationActive());
        const bool cancelling = backend.m_thcV51Phase == MachineControlBackend::ThcV51Phase::AwaitCancel;
        if (cancelling) raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        raw->receive(v51ProductionTelemetry());
        QCOMPARE(backend.operationState(), cancelling ? QStringLiteral("FAILED") : QStringLiteral("COMPLETED"));
        QVERIFY(!backend.m_pressSafetyStopUnconfirmed);
    }

    void thcV51ProductionDonePreservesReportedMeasurements()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        v51Contact(raw);
        QVERIFY(backend.releaseThcCommissioning());
        raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        raw->receive(QByteArrayLiteral("{THC:DONE}"));
        const auto idle = QByteArrayLiteral("<IDLE|-0.2|-0.2|0|-7.25|-0.2|-0.2|1|1|1|0|0|0.4|0.5|0|0.125|0.375|4|8|0>");
        QCOMPARE(idle.count('|'), 19);
        raw->receive(idle);
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(backend.ramVelocity(), -7.25);
        QVERIFY(backend.measuredRamVelocityAvailable());
        QCOMPARE(backend.measuredRamVelocity(), 0.25);
        QCOMPARE(backend.motorRpmY1(), 4.0);
        QCOMPARE(backend.motorRpmY2(), 8.0);
        QVERIFY(!backend.m_pressSafetyStopUnconfirmed);
        QVERIFY(!backend.pressOperationActive());
    }

    void thcV51ModuleStopPreservesCancellationOwner_data()
    {
        QTest::addColumn<QString>("scenario");
        for (const char *scenario : {"idle", "moving", "stale-idle", "write-failure",
             "error-on-write", "close-on-write", "cancel-write-failure", "cancel-error-on-write",
               "cancel-close-on-write", "synchronous-cancel", "confirmation-timeout", "repeat-stop"})
            QTest::newRow(scenario) << QString::fromLatin1(scenario);
    }

    void thcV51ModuleStopPreservesCancellationOwner()
    {
        QFETCH(QString, scenario);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(v51ModuleReady(backend, moduleRaw));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        v51Contact(raw);
        const auto id = backend.operationId();
        if (scenario != "idle" && scenario != "stale-idle")
            moduleRaw->receive(QByteArrayLiteral("<Run|MPos:0,0,0|WCO:0,0,0>"));
        if (scenario == "stale-idle") backend.m_moduleTelemetryFresh = false;
        if (scenario == "write-failure") moduleRaw->setFailedFrame(QByteArrayLiteral("!"));
        if (scenario == "cancel-write-failure") raw->setFailedFrame(QByteArrayLiteral("<THC:CANCEL>\n"));
        moduleRaw->setWriteHook([&, scenario](const QByteArray &frame) {
            if (frame != QByteArrayLiteral("!")) return;
            QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(0));
            if (scenario == "error-on-write") moduleRaw->fail(QStringLiteral("TEST_MODULE_WRITE_ERROR"));
            if (scenario == "close-on-write") moduleRaw->drop();
        });
        raw->setWriteHook([&, scenario](const QByteArray &frame) {
            if (frame != QByteArrayLiteral("<THC:CANCEL>\n")) return;
            if (scenario == "cancel-error-on-write") raw->fail(QStringLiteral("TEST_CANCEL_WRITE_ERROR"));
            if (scenario == "cancel-close-on-write") raw->drop();
            if (scenario == "synchronous-cancel") {
                raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
                raw->receive(v51ProductionTelemetry());
            }
        });
        const auto moduleWrites = moduleRaw->writeCount();
        const bool moduleFailed = scenario == "write-failure" || scenario == "error-on-write" || scenario == "close-on-write";
        const bool cancelFailed = scenario == "cancel-write-failure" || scenario == "cancel-error-on-write"
            || scenario == "cancel-close-on-write";
        QCOMPARE(backend.stopModule(), !moduleFailed && !cancelFailed);
        moduleRaw->setWriteHook({});
        raw->setWriteHook({});
        QCOMPARE(moduleRaw->writeCount(), moduleWrites + (scenario == "idle" ? 0 : 1));
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationDevice(), QStringLiteral("press"));
        QCOMPARE(backend.operationName(), QStringLiteral("thc-contact-profile-v51"));
        QVERIFY(!backend.m_commandDeadlineTimer.isActive());
        QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV51ClientLeaseTimer.isActive());
        QVERIFY(!backend.m_thcV51OverallTimer.isActive());
        if (!cancelFailed && scenario != "synchronous-cancel") {
            QVERIFY(backend.commandOperationActive());
            QVERIFY(backend.pressOperationActive());
            QVERIFY(backend.m_pressSafetyStopUnconfirmed);
            QVERIFY(backend.m_thcV51PhaseTimer.isActive());
            QCOMPARE(backend.m_pressCommandPhase, MachineControlBackend::PressCommandPhase::ThcV51);
            QCOMPARE(backend.m_moduleCommandPhase, MachineControlBackend::ModuleCommandPhase::Idle);
            const auto deadline = backend.m_thcV51PhaseDeadlineMs;
            moduleRaw->receive(QByteArrayLiteral("<Hold:0|MPos:0,0,0|WCO:0,0,0>"));
            moduleRaw->receive(QByteArrayLiteral("ok"));
            QCOMPARE(moduleRaw->writeCount(), moduleWrites + (scenario == "idle" ? 0 : 1)); // no reset
            QVERIFY(!backend.homePress());
            QVERIFY(backend.cancelThcCommissioning());
            QCOMPARE(backend.m_thcV51PhaseDeadlineMs, deadline);
            if (scenario == "repeat-stop") {
                QVERIFY(backend.stopModule());
                QCOMPARE(backend.m_thcV51PhaseDeadlineMs, deadline);
                QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
                QCOMPARE(backend.operationId(), id);
            }
            raw->receive(v51ProductionTelemetry());
            QVERIFY(backend.commandOperationActive());
            if (scenario == "confirmation-timeout") {
                backend.m_thcV51PhaseDeadlineMs = backend.m_thcV51Clock.elapsed();
                QVERIFY(!backend.cancelThcCommissioning());
            } else {
                raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
                raw->receive(v51ProductionTelemetry());
            }
        }
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        if (scenario == "confirmation-timeout")
            QCOMPARE(backend.operationError(), QStringLiteral("THC_V51_MODULE_STOP_CANCEL_CONFIRMATION_TIMEOUT"));
        else if (!cancelFailed)
            QCOMPARE(backend.operationError(), moduleFailed
                ? QStringLiteral("THC_V51_MODULE_STOP_FEED_HOLD_WRITE_FAILED") : QStringLiteral("THC_V51_MODULE_STOP"));
        QVERIFY(!backend.pressOperationActive());
        QCOMPARE(backend.m_pressCommandPhase, MachineControlBackend::PressCommandPhase::Idle);
        QVERIFY(!backend.m_thcV51PhaseTimer.isActive());
        QCOMPARE(backend.m_pressSafetyStopUnconfirmed, cancelFailed || scenario == "confirmation-timeout");
        raw->setFailedFrame({});
        if (!backend.pressConnected()) QVERIFY(v51Ready(backend, raw));
        raw->receive(v51Idle());
        QVERIFY(backend.homePress()); // no orphaned V51 pressOperationActive latch
        const auto homeId = backend.operationId();
        const auto writes = raw->writeCount();
        for (QTimer *timer : {&backend.m_thcV51HeartbeatTimer, &backend.m_thcV51ClientLeaseTimer,
                             &backend.m_thcV51PhaseTimer, &backend.m_thcV51OverallTimer})
            QVERIFY(QMetaObject::invokeMethod(timer, "timeout", Qt::DirectConnection));
        QCOMPARE(backend.operationId(), homeId);
        QCOMPARE(raw->writeCount(), writes);
        raw->receive(v51ProductionTelemetry(QByteArrayLiteral("HOMING")));
        raw->receive(v51Idle());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
    }

    void thcV51ModuleLifecycleDoesNotStealOwnership_data()
    {
        QTest::addColumn<QString>("event");
        for (const char *event : {"disconnect", "drop", "error", "stale", "controller-reset", "poll-failure", "reconnect"})
            QTest::newRow(event) << QString::fromLatin1(event);
    }

    void thcV51ModuleLifecycleDoesNotStealOwnership()
    {
        QFETCH(QString, event);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(v51ModuleReady(backend, moduleRaw));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        v51Contact(raw);
        backend.m_thcV51ClientDeadlineMs = backend.m_thcV51Clock.elapsed() + 60000;
        const auto id = backend.operationId();
        const auto deadline = backend.m_thcV51PhaseDeadlineMs;
        const auto writes = raw->writeCount();
        if (event == "disconnect") QVERIFY(backend.disconnectModule());
        if (event == "drop" || event == "reconnect") moduleRaw->drop();
        if (event == "error") moduleRaw->fail(QStringLiteral("TEST_MODULE_ERROR"));
        if (event == "stale") backend.expireModuleTelemetry();
        if (event == "controller-reset") moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        if (event == "poll-failure") {
            moduleRaw->setFailedFrame(QByteArrayLiteral("?"));
            backend.pollModuleStatus();
        }
        if (event == "reconnect") QVERIFY(v51ModuleReady(backend, moduleRaw));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationDevice(), QStringLiteral("press"));
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::Acquisition);
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, deadline);
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.pressOperationActive());
        QVERIFY(backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(backend.m_thcV51ClientLeaseTimer.isActive());
        QVERIFY(backend.m_thcV51PhaseTimer.isActive());
        QVERIFY(backend.m_thcV51OverallTimer.isActive());
        QCOMPARE(raw->writeCount(), writes);
        QVERIFY(backend.cancelThcCommissioning());
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        raw->receive(v51ProductionTelemetry());
        QVERIFY(!backend.commandOperationActive());
        QVERIFY(!backend.pressOperationActive());
    }

    void thcV51Faults_data()
    {
        QTest::addColumn<QString>("fault");
        for (const char *fault : {"start-ack-timeout", "approach-timeout", "late-contact",
             "acquisition-timeout", "late-holding", "release-ack-timeout", "release-timeout",
             "idle-timeout", "overall-timeout", "owner-timer", "owner-call",
             "stale", "hb-write", "keepalive-write", "ordinary-keepalive-write",
             "start-write", "release-write", "th-error", "thc-error", "th-timeout",
             "holding-before-contact", "unsolicited-releasing", "done-before-release-ack",
             "regressive-holding", "invalid-command", "alarm", "anti-bind"})
            QTest::newRow(fault) << QString::fromLatin1(fault);
    }

    void thcV51Faults()
    {
        QFETCH(QString, fault);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        if (fault == "start-write") raw->setFailedFrame(QByteArrayLiteral("<THC:CONTACT_PROFILE_V51>\n"));
        QCOMPARE(backend.startThcContactProfileV51Commissioning(v51Hash()), fault != "start-write");
        if (fault != "start-write" && fault != "start-ack-timeout")
            raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        const bool acquisition = fault == "acquisition-timeout" || fault == "late-holding"
            || fault.startsWith("release-") || fault == "idle-timeout"
            || fault == "done-before-release-ack" || fault == "regressive-holding";
        if (acquisition) raw->receive(QByteArrayLiteral("{THC:CONTACT}"));
        const bool release = fault == "release-ack-timeout" || fault == "release-timeout"
            || fault == "idle-timeout" || fault == "done-before-release-ack"
            || fault == "regressive-holding";
        if (release) QVERIFY(backend.releaseThcCommissioning());
        if (fault == "release-timeout" || fault == "idle-timeout" || fault == "regressive-holding")
            raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        if (fault == "idle-timeout") raw->receive(QByteArrayLiteral("{THC:DONE}"));
        if (fault == "overall-timeout") {
            backend.m_thcV51OverallDeadlineMs = backend.m_thcV51Clock.elapsed();
            QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51OverallTimer, "timeout", Qt::DirectConnection));
        } else if (fault.endsWith("-timeout") && fault != "th-timeout") {
            backend.m_thcV51PhaseDeadlineMs = backend.m_thcV51Clock.elapsed();
            QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51PhaseTimer, "timeout", Qt::DirectConnection));
        } else if (fault == "late-contact" || fault == "late-holding") {
            backend.m_thcV51PhaseDeadlineMs = backend.m_thcV51Clock.elapsed();
            raw->receive(fault == "late-contact" ? QByteArrayLiteral("{THC:CONTACT}")
                                                  : QByteArrayLiteral("{THC:HOLDING}"));
        } else if (fault == "owner-timer" || fault == "owner-call") {
            backend.m_thcV51ClientDeadlineMs = backend.m_thcV51Clock.elapsed();
            if (fault == "owner-call") QVERIFY(!backend.heartbeatThcCommissioning());
            else QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51ClientLeaseTimer, "timeout", Qt::DirectConnection));
        } else if (fault == "stale") {
            backend.expirePressTelemetry();
        } else if (fault == "hb-write" || fault == "keepalive-write" || fault == "ordinary-keepalive-write") {
            raw->setFailedFrame(fault == "hb-write" ? QByteArrayLiteral("<THC:HB>\n") : QByteArrayLiteral("<?>\n"));
            if (fault == "ordinary-keepalive-write") backend.sendPressKeepAlive();
            else backend.sendThcV51Heartbeat();
        } else if (fault == "release-write") {
            raw->setFailedFrame(QByteArrayLiteral("<THC:RELEASE>\n"));
            QVERIFY(!backend.releaseThcCommissioning());
        } else if (fault == "th-error") raw->receive(QByteArrayLiteral("{TH:ERROR:NO_PROGRESS}"));
        else if (fault == "thc-error") raw->receive(QByteArrayLiteral("{THC:ERROR:FORCE_TIMEOUT}"));
        else if (fault == "th-timeout") raw->receive(QByteArrayLiteral("{TH:TIMEOUT}"));
        else if (fault == "holding-before-contact" || fault == "regressive-holding") raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        else if (fault == "unsolicited-releasing") raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        else if (fault == "done-before-release-ack") raw->receive(QByteArrayLiteral("{THC:DONE}"));
        else if (fault == "invalid-command") raw->receive(QByteArrayLiteral("[INVALID COMMAND]"));
        else if (fault == "alarm" || fault == "anti-bind") {
            if (fault == "alarm") backend.m_pressMachineState = QStringLiteral("ANTIBIND_TRIGGERED");
            else backend.m_antiBind = true;
            backend.handleThcV51Telemetry();
        }
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<stop>\n")), qsizetype(0));
        QCOMPARE(countWrites(raw, QByteArrayLiteral("<THC:CONTACT_PROFILE>\n")), qsizetype(0));
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.m_pressSafetyStopUnconfirmed);
        QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV51ClientLeaseTimer.isActive());
        QVERIFY(!backend.m_thcV51OverallTimer.isActive());
        const auto deadline = backend.m_thcV51PhaseDeadlineMs;
        const auto writes = raw->writeCount();
        QVERIFY(backend.cancelThcCommissioning());
        QVERIFY(backend.cancelCommandOperation());
        backend.sendThcV51Heartbeat();
        QVERIFY(!backend.heartbeatThcCommissioning());
        QCOMPARE(raw->writeCount(), writes);
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, deadline);
        raw->receive(v51Idle());
        QVERIFY(backend.commandOperationActive());
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        QVERIFY(backend.commandOperationActive());
        raw->receive(v51Idle());
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QVERIFY(!backend.m_pressSafetyStopUnconfirmed);
        QVERIFY(!backend.m_thcV51PhaseTimer.isActive());
    }

    void thcV51CancellationRecovery_data()
    {
        QTest::addColumn<QString>("failure");
        for (const char *failure : {"missing-confirmation", "nonexact-confirmation", "cancel-write",
                                    "disconnect", "drop", "transport-error", "clear-state"})
            QTest::newRow(failure) << QString::fromLatin1(failure);
    }

    void thcV51CancellationRecovery()
    {
        QFETCH(QString, failure);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        v51Contact(raw);
        if (failure == "cancel-write") raw->setFailedFrame(QByteArrayLiteral("<THC:CANCEL>\n"));
        if (failure == "disconnect") QVERIFY(backend.disconnectPress());
        else if (failure == "drop") raw->drop();
        else if (failure == "transport-error") raw->fail(QStringLiteral("TEST_WRITE_ERROR"));
        else if (failure == "clear-state") backend.clearPressState();
        else {
            QCOMPARE(backend.cancelThcCommissioning(), failure != "cancel-write");
            if (failure != "cancel-write") {
                if (failure == "nonexact-confirmation") {
                    raw->receive(QByteArrayLiteral(" {THC:CANCELLED}"));
                    raw->receive(QByteArrayLiteral("{thc:cancelled}"));
                    raw->receive(v51Idle());
                    QVERIFY(backend.commandOperationActive());
                }
                backend.m_thcV51PhaseDeadlineMs = backend.m_thcV51Clock.elapsed();
                QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51PhaseTimer, "timeout", Qt::DirectConnection));
            }
        }
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QVERIFY(backend.m_pressSafetyStopUnconfirmed);
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV51ClientLeaseTimer.isActive());
        QVERIFY(!backend.m_thcV51PhaseTimer.isActive());
        QVERIFY(!backend.m_thcV51OverallTimer.isActive());
        raw->setFailedFrame(QByteArray());
        if (!backend.pressConnected()) QVERIFY(v51Ready(backend, raw));
        raw->receive(v51Idle());
        QVERIFY(!backend.startThcContactProfileV51Commissioning(v51Hash()));
        QVERIFY(!backend.startAutomaticThcContactProfile());
        QVERIFY(backend.homePress());
        const auto homeId = backend.operationId();
        const auto writes = raw->writeCount();
        // Explicitly dispatch old queued V51 timer callbacks into recovery Home.
        for (QTimer *timer : {&backend.m_thcV51HeartbeatTimer, &backend.m_thcV51ClientLeaseTimer,
                             &backend.m_thcV51PhaseTimer, &backend.m_thcV51OverallTimer})
            QVERIFY(QMetaObject::invokeMethod(timer, "timeout", Qt::DirectConnection));
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        QCOMPARE(raw->writeCount(), writes);
        QCOMPARE(backend.operationId(), homeId);
        QCOMPARE(backend.operationName(), QStringLiteral("home"));
        QVERIFY(backend.m_pressHomePending);
        raw->receive(QByteArrayLiteral("<HOMING|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>"));
        raw->receive(v51Idle());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.m_pressSafetyStopUnconfirmed);
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QVERIFY(!backend.thcContactObserved());
    }

    void thcV51UnconfirmedCancelAllowsConfirmedSafetyStopRecovery()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v51Ready(backend, raw));
        QVERIFY(backend.startThcContactProfileV51Commissioning(v51Hash()));
        QVERIFY(backend.cancelThcCommissioning());
        backend.m_thcV51PhaseDeadlineMs = backend.m_thcV51Clock.elapsed();
        backend.checkThcV51Deadlines();
        QVERIFY(backend.m_pressSafetyStopUnconfirmed);
        QVERIFY(backend.stopPressMotion());
        raw->receive(v51Idle());
        QVERIFY(backend.m_pressSafetyStopUnconfirmed);
        raw->receive(QByteArrayLiteral("[STOPPED]"));
        raw->receive(v51Idle());
        QVERIFY(!backend.m_pressSafetyStopUnconfirmed);
        QVERIFY(backend.startAutomaticThcContactProfile());
    }

    void serialDiagnosticLoggingCanBeChangedAtRuntime()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *pressRaw = press.get();
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QSignalSpy changed(&backend, &MachineControlBackend::serialDiagnosticLogsEnabledChanged);

        backend.setSerialDiagnosticLogsEnabled(true);
        QVERIFY(backend.serialDiagnosticLogsEnabled());
        QVERIFY(pressRaw->diagnosticLoggingWasEnabled());
        QVERIFY(moduleRaw->diagnosticLoggingWasEnabled());
        QCOMPARE(changed.count(), 1);

        backend.setSerialDiagnosticLogsEnabled(false);
        QVERIFY(!backend.serialDiagnosticLogsEnabled());
        QVERIFY(!pressRaw->diagnosticLoggingWasEnabled());
        QVERIFY(!moduleRaw->diagnosticLoggingWasEnabled());
        QCOMPARE(changed.count(), 2);
    }

    void ths1RxPersistsThroughBackendWiringWithoutChangingControlState()
    {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        EnvironmentVariableGuard homeGuard("BENDCNC_QT_HOME");
        QVERIFY(qputenv("BENDCNC_QT_HOME", directory.path().toLocal8Bit()));
        const QByteArray payload = QByteArrayLiteral(
            "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
            "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100");
        const QByteArray ths1 = QByteArrayLiteral("[THS1 ") + payload + QByteArrayLiteral("]\r\n");
        QCOMPARE(ths1.size(), 137);

        QString logPath;
        {
            auto press = std::make_unique<ScriptedMachineTransport>(true);
            auto *raw = press.get();
            MachineControlBackend backend(std::move(press),
                std::make_unique<ScriptedMachineTransport>(false));
            QVERIFY(backend.connectPress());
            raw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
            raw->receive(QByteArrayLiteral(
                "<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>"));
            QVERIFY(backend.pressReady());
            QVERIFY(backend.pressHomed());
            const QString stateBefore = backend.pressMachineState();
            const QString operationBefore = backend.operationState();
            const double y1Before = backend.ramPositionY1();
            const double y2Before = backend.ramPositionY2();
            logPath = backend.pressTelemetryLogPath();

            raw->receive(ths1);

            QCOMPARE(backend.pressMachineState(), stateBefore);
            QCOMPARE(backend.operationState(), operationBefore);
            QCOMPARE(backend.ramPositionY1(), y1Before);
            QCOMPARE(backend.ramPositionY2(), y2Before);
            QVERIFY(backend.pressReady());
            QVERIFY(backend.pressHomed());
        }

        QFile file(logPath);
        QVERIFY(file.open(QIODevice::ReadOnly));
        bool foundThs1 = false;
        while (!file.atEnd()) {
            const QJsonObject row = QJsonDocument::fromJson(file.readLine()).object();
            if (row.value(QStringLiteral("event")).toString() != QStringLiteral("RX"))
                continue;
            if (QByteArray::fromBase64(
                    row.value(QStringLiteral("frameBase64")).toString().toLatin1()) == ths1) {
                foundThs1 = true;
                break;
            }
        }
        QVERIFY(foundThs1);
    }

    void semanticPanel_data()
    {
        QTest::addColumn<QByteArray>("identity");
        QTest::addColumn<bool>("original");
        QTest::addColumn<bool>("supported");
        QTest::addColumn<bool>("advance");
        for (bool advance : {false, true}) {
            const QByteArray suffix = advance ? "-advance" : "-retract";
            QTest::newRow(("original" + suffix).constData()) << QByteArray("[LS-BEND v1.1]") << true << true << advance;
            QTest::newRow(("modern" + suffix).constData()) << QByteArray("[LS-BEND v1.3]") << false << true << advance;
            QTest::newRow(("v12" + suffix).constData()) << QByteArray("[LS-BEND v1.2]") << false << true << advance;
            QTest::newRow(("unknown" + suffix).constData()) << QByteArray("[LS-BEND v1.4]") << false << false << advance;
            QTest::newRow(("near-match" + suffix).constData()) << QByteArray("[LS-BEND v1.10]") << false << false << advance;
        }
    }

    void semanticPanel()
    {
        QFETCH(QByteArray, identity);
        QFETCH(bool, original);
        QFETCH(bool, supported);
        QFETCH(bool, advance);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        const QByteArray idle("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        QVERIFY(backend.connectPress());
        raw->receive(identity);
        raw->receive(idle);
        QCOMPARE(backend.panelJogSupported(), supported);
        QCOMPARE(backend.panelJogRequiresPhysicalInputs(), original);
        const auto before = raw->writeCount();
        QCOMPARE(advance ? backend.startAdvanceJog(5) : backend.startRetractJog(5), supported);
        if (!supported) {
            QVERIFY(!backend.releasePanelJog());
            QCOMPARE(raw->writeCount(), before);
            return;
        }
        const QByteArray type = original ? (advance ? "safety" : "retract")
                                         : (advance ? "panel-advance" : "panel-retract");
        QCOMPARE(raw->writeAt(before), QByteArray(advance ? "<-4.0000, 5.0000, " : "<-0.0500, 5.0000, ") + type + ">\n");
        QVERIFY(!backend.startAdvanceJog(5));
        QVERIFY(!backend.startRetractJog(5));
        raw->receive(QByteArray(advance ? "<SAFETY JOG" : "<RETRACT JOG") + "|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        QVERIFY(backend.releasePanelJog());
        const QByteArray release = original ? (advance ? "stop" : "cancel") : "hold";
        QCOMPARE(raw->writeAt(raw->writeCount() - 1), "<" + release + ">\n");
        const auto writes = raw->writeCount();
        QVERIFY(backend.releasePanelJog());
        QCOMPARE(raw->writeCount(), writes);
        raw->receive("[JOG COMPLETED]");
        raw->receive(idle);
        QVERIFY(backend.commandOperationActive());
        if (original) {
            raw->receive("[HELD]");
            raw->receive("[STOPPED]");
            raw->receive(idle);
            QVERIFY(backend.commandOperationActive());
            raw->receive("[RECEIVED STRING: " + release + "]");
            if (!advance)
                raw->receive("[JOG COMPLETED]");
            for (int n = 0; n < 40; ++n)
                raw->receive(idle);
        } else {
            raw->receive("[HELD]");
            raw->receive(idle);
        }
        QVERIFY(!backend.commandOperationActive());
        QVERIFY(backend.releasePanelJog());
        QCOMPARE(raw->writeCount(), writes);
    }

    void originalObservedMotionWithoutCompletionFaultStops_data()
    {
        QTest::addColumn<bool>("echoBeforeMotion");
        QTest::newRow("pre-echo") << false;
        QTest::newRow("during-drain") << true;
    }

    void originalObservedMotionWithoutCompletionFaultStops()
    {
        QFETCH(bool, echoBeforeMotion);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press),
            std::make_unique<ScriptedMachineTransport>(false));
        const QByteArray idle("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        const QByteArray echo("[RECEIVED STRING: -0.2000, 5.0000, safety]");
        QVERIFY(backend.connectPress());
        raw->receive("[LS-BEND v1.1]");
        raw->receive(idle);
        QVERIFY(backend.jogPress(-0.2, 5, "safety"));
        const auto writes = raw->writeCount();
        if (echoBeforeMotion)
            raw->receive(echo);
        raw->receive("<SAFETY JOG|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>");
        if (!echoBeforeMotion)
            raw->receive(echo);
        // Exhaust the queue, then keep genuinely admitted IDLE fresh. There is
        // deliberately no JOG COMPLETED: motion is not completion authority.
        for (int n = 0; n < 40; ++n)
            raw->receive(idle);
        QVERIFY(backend.commandOperationActive());
        QCOMPARE(raw->writeCount(), writes);
        QTimer fresh;
        connect(&fresh, &QTimer::timeout, &backend, [raw, idle] { raw->receive(idle); });
        fresh.start(100);
        const auto stopCount = [raw, writes] {
            int count = 0;
            for (auto n = writes; n < raw->writeCount(); ++n)
                count += raw->writeAt(n) == QByteArray("<stop>\n");
            return count;
        };
        QTRY_COMPARE_WITH_TIMEOUT(stopCount(), 1, 122000);
        QVERIFY(backend.commandOperationActive());
        QTRY_COMPARE_WITH_TIMEOUT(backend.operationState(), QStringLiteral("FAILED"), 32000);
        QCOMPARE(backend.operationError(),
                 QStringLiteral("COMMAND_TIMEOUT_STOP_CONFIRMATION_TIMEOUT"));
        QVERIFY(!backend.jogPress(-0.2, 5, "safety"));
    }

    void originalBacklogKeepsLiveTelemetry()
    {
        for (bool echo : {false, true}) {
            auto press = std::make_unique<ScriptedMachineTransport>(true);
            auto *raw = press.get();
            MachineControlBackend backend(std::move(press),
                std::make_unique<ScriptedMachineTransport>(false));
            QVERIFY(backend.connectPress());
            raw->receive("[LS-BEND v1.1]");
            raw->receive("<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>");
            QVERIFY(backend.jogPress(-1, 5, "safety"));
            if (echo)
                raw->receive("[RECEIVED STRING: -1.0000, 5.0000, safety]");
            QSignalSpy updates(&backend, &MachineControlBackend::telemetryChanged);
            raw->receive("<SAFETY JOG|-0.1|-0.2|0|0|0|0|0|1|0|0|0|0|0|0>");
            QCOMPARE(backend.ramPositionY1(), -0.1);
            QCOMPARE(backend.ramPositionY2(), -0.2);
            QVERIFY(!backend.bendPedal());
            QVERIFY(!backend.safetyJogLeft());
            QVERIFY(updates.count() > 0);
            QVERIFY(backend.commandOperationActive());
            QVERIFY(backend.abortPress());
            QCOMPARE(raw->writeAt(raw->writeCount() - 1), QByteArray("<stop>\n"));
        }
    }

    void originalCompactPacedDrainSurvivesModernDeadline()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press),
            std::make_unique<ScriptedMachineTransport>(false));
        const QByteArray idle("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        QVERIFY(backend.connectPress());
        raw->receive("[LS-BEND v1.1]");
        raw->receive(idle);
        QVERIFY(backend.stopPressMotion());
        raw->receive("[RECEIVED STRING: stop]");
        for (int n = 0; n < 34; ++n) {
            QTest::qWait(300);
            raw->receive(idle);
            QVERIFY(backend.commandOperationActive());
        }
        for (int n = 0; n < 6 && backend.commandOperationActive(); ++n) {
            QTest::qWait(300);
            raw->receive(idle);
        }
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void originalStaleStopPermutations()
    {
        for (bool cancel : {false, true}) {
            std::array<int, 4> order{0, 1, 2, 3};
            do {
                auto press = std::make_unique<ScriptedMachineTransport>(true);
                auto *raw = press.get();
                MachineControlBackend backend(std::move(press),
                    std::make_unique<ScriptedMachineTransport>(false));
                const QByteArray idle("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
                QVERIFY(backend.connectPress());
                raw->receive("[LS-BEND v1.1]");
                raw->receive(idle);
                QVERIFY(cancel ? backend.abortPress() : backend.stopPressMotion());
                const QList<QByteArray> stale = {
                    cancel ? QByteArray("[RECEIVED STRING: cancel]") : QByteArray("[RECEIVED STRING: stop]"),
                    "<RETRACT JOG|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>",
                    "[JOG COMPLETED]", idle};
                for (int i : order)
                    raw->receive(stale[i]);
                raw->receive("<SAFETY JOG HOLD|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
                raw->receive("[STOPPED]");
                raw->receive("[JOG COMPLETED]");
                raw->receive(idle);
                QVERIFY(backend.commandOperationActive()); // bounded drain not yet exhausted
                for (int n = 0; n < 40; ++n)
                    raw->receive(idle);
                QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
            } while (std::next_permutation(order.begin(), order.end()));
        }
    }

    void originalShortJogDeadlineDoesNotRetract_data()
    {
        QTest::addColumn<QString>("type");
        QTest::newRow("safety") << QStringLiteral("safety");
        QTest::newRow("retract") << QStringLiteral("retract");
    }

    void originalShortJogDeadlineDoesNotRetract()
    {
        QFETCH(QString, type);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press),
            std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(backend.connectPress());
        raw->receive("[LS-BEND v1.1]");
        const QByteArray idle("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        raw->receive(idle);
        QVERIFY(backend.jogPress(-0.2, 5, type));
        const auto writes = raw->writeCount();
        raw->receive("[JOG COMPLETED]");
        raw->receive(idle);
        QVERIFY(backend.commandOperationActive()); // pre-echo completion ignored
        raw->receive("[RECEIVED STRING: -0.2000, 5.0000, " + type.toLatin1() + "]");
        raw->receive("[JOG COMPLETED]");
        for (int n = 0; n < 40; ++n)
            raw->receive(idle);
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(raw->writeCount(), writes);
    }

    void originalManualCancel_data()
    {
        QTest::addColumn<QByteArray>("state");
        QTest::addColumn<bool>("cancel");
        QTest::newRow("retract") << QByteArray("RETRACT JOG") << true;
        QTest::newRow("safety-hold") << QByteArray("SAFETY JOG HOLD") << true;
        QTest::newRow("clamp-hold") << QByteArray("CLAMP JOG HOLD") << true;
        QTest::newRow("bend-hold") << QByteArray("BEND JOG HOLD") << true;
        QTest::newRow("idle") << QByteArray("IDLE") << true;
        QTest::newRow("safety-moving") << QByteArray("SAFETY JOG") << false;
        QTest::newRow("bend-moving") << QByteArray("BEND JOG") << false;
    }

    void originalManualCancel()
    {
        QFETCH(QByteArray, state);
        QFETCH(bool, cancel);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press),
            std::make_unique<ScriptedMachineTransport>(false));
        const auto telemetry = [raw](const QByteArray &s) {
            raw->receive("<" + s + "|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        };
        QVERIFY(backend.connectPress());
        raw->receive("[LS-BEND v1.1]");
        telemetry("IDLE");
        QVERIFY(!backend.holdPressMotion());
        QVERIFY(!backend.jogPress(-1, 5, "panel-advance"));
        QVERIFY(!backend.jogPress(-1, 5, "panel-retract"));
        telemetry(state);
        QVERIFY(backend.abortPress());
        QCOMPARE(raw->writeAt(raw->writeCount() - 1),
                 cancel ? QByteArray("<cancel>\n") : QByteArray("<stop>\n"));
        const auto stopWrites = raw->writeCount();
        QVERIFY(backend.abortPress());
        QVERIFY(backend.stopPressMotion());
        QCOMPARE(raw->writeCount(), stopWrites);
        telemetry("IDLE"); // cached/request-adjacent IDLE cannot complete
        raw->receive("[RECEIVED STRING: unrelated]");
        raw->receive("[STOPPED]"); // not an original acknowledgement
        telemetry("IDLE");
        QVERIFY(backend.commandOperationActive());
        if (!cancel) {
            raw->receive("[JOG COMPLETED]"); // delayed prior completion
            telemetry("IDLE");
            QVERIFY(backend.commandOperationActive());
            telemetry("RETRACT JOG");
        }
        raw->receive("[JOG COMPLETED]");
        QVERIFY(backend.commandOperationActive());
        telemetry("IDLE");
        QVERIFY(backend.commandOperationActive());
        raw->receive(cancel ? "[RECEIVED STRING: cancel]" : "[RECEIVED STRING: stop]");
        for (int n = 0; n < 40; ++n)
            telemetry("IDLE");
        if (cancel) {
            QVERIFY(backend.commandOperationActive()); // IDLE is not cancel completion
            raw->receive("[JOG COMPLETED]");
            telemetry("IDLE");
        }
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(backend.jogPress(-1, 5, "safety"));
    }

    void originalManualStopTimeoutRetainsLock()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press),
            std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(backend.connectPress());
        raw->receive("[LS-BEND v1.1]");
        const QByteArray idle("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        raw->receive(idle);
        QVERIFY(backend.abortPress());
        QTimer fresh;
        connect(&fresh, &QTimer::timeout, &backend, [raw, idle] { raw->receive(idle); });
        fresh.start(100);
        QTest::qWait(29000);
        QVERIFY(backend.commandOperationActive());
        QTRY_COMPARE_WITH_TIMEOUT(backend.operationState(), QStringLiteral("FAILED"), 3000);
        QCOMPARE(backend.operationError(), QStringLiteral("STOP_CONFIRMATION_TIMEOUT"));
        raw->receive("[JOG COMPLETED]");
        raw->receive(idle);
        QVERIFY(!backend.jogPress(-1, 5, "safety"));
    }

    void originalManualStopDisconnectRetainsLock()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press),
            std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(backend.connectPress());
        raw->receive("[LS-BEND v1.1]");
        const QByteArray idle("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        raw->receive(idle);
        QVERIFY(backend.stopPressMotion());
        raw->receive("[JOG COMPLETED]");
        raw->receive(idle);
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.disconnectPress());
        QVERIFY(backend.connectPress());
        raw->receive("[LS-BEND v1.1]");
        raw->receive(idle);
        QVERIFY(!backend.jogPress(-1, 5, "safety"));
    }

    void originalManualAlarmDoesNotConfirmStop()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press),
            std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(backend.connectPress());
        raw->receive("[LS-BEND v1.1]");
        raw->receive("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        QVERIFY(backend.jogPress(-1, 5, "safety"));
        raw->receive("[RETRACT DIRECTION FAIL]");
        QCOMPARE(raw->writeAt(raw->writeCount() - 1), QByteArray("<stop>\n"));
        raw->receive("[RECEIVED STRING: stop]");
        for (int n = 0; n < 40; ++n)
            raw->receive("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        raw->receive("[STOPPED]");
        raw->receive("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        QVERIFY(backend.commandOperationActive());
        raw->receive("<RETRACT JOG|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        raw->receive("[JOG COMPLETED]");
        raw->receive("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        QVERIFY(backend.commandOperationActive());
    }

    void unexpectedFirmwareCannotJog_data()
    {
        QTest::addColumn<QByteArray>("version");
        QTest::newRow("suffix") << QByteArray("1.1a");
        QTest::newRow("future") << QByteArray("1.4");
    }

    void unexpectedFirmwareCannotJog()
    {
        QFETCH(QByteArray, version);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press),
            std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(backend.connectPress());
        raw->receive("[LS-BEND v" + version + "]");
        raw->receive("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        const auto writes = raw->writeCount();
        QVERIFY(!backend.jogPress(-1, 5, "safety"));
        QVERIFY(!backend.startManualStroke(-0.2, -1, 5, 5));
        QVERIFY(!backend.startTonnageHold(3, 5, 5));
        QVERIFY(!backend.beginProgramRun());
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("COMMAND_DISABLED"));
        QCOMPARE(raw->writeCount(), writes);
    }

    void startsFailClosed()
    {
        MachineControlBackend backend;

        QVERIFY(!backend.transportAvailable());
        QVERIFY(!backend.discoveryAvailable());
        QVERIFY(!backend.pressConnected());
        QVERIFY(!backend.pressReady());
        QVERIFY(!backend.pressHomed());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("DISCONNECTED"));
        QCOMPARE(backend.pressMachineState(), QStringLiteral("UNKNOWN"));
        QVERIFY(!backend.moduleConnected());
        QVERIFY(!backend.moduleReady());
        QVERIFY(!backend.moduleHomed());
        QCOMPARE(backend.moduleConnectionState(), QStringLiteral("DISCONNECTED"));
        QCOMPARE(backend.moduleState(), QStringLiteral("UNKNOWN"));
        QVERIFY(!backend.independentRamTelemetryAvailable());
        QCOMPARE(backend.ramLoadY1(), 0.0);
        QCOMPARE(backend.ramLoadY2(), 0.0);
    }

    void unavailableConnectionsRemainDisconnected()
    {
        MachineControlBackend backend;
        QSignalSpy rejected(&backend, &MachineControlBackend::operationRejected);
        QSignalSpy connectionFailed(&backend, &MachineControlBackend::connectionFailed);

        QVERIFY(!backend.connectPress());
        QVERIFY(!backend.connectModule());
        QCOMPARE(connectionFailed.count(), 2);
        QCOMPARE(rejected.count(), 2);
        QVERIFY(!backend.pressConnected());
        QVERIFY(!backend.moduleConnected());
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("TRANSPORT_UNAVAILABLE"));
        QCOMPARE(backend.lastRejectedOperation(), QStringLiteral("module:connect"));
    }

    void disconnectedPressCommandsAreRejectedWithoutMutation()
    {
        MachineControlBackend backend;
        QSignalSpy rejected(&backend, &MachineControlBackend::operationRejected);

        QVERIFY(!backend.homePress());
        QVERIFY(!backend.startRetractJog());
        QVERIFY(!backend.holdPressMotion());
        QVERIFY(!backend.stopPressMotion());
        QVERIFY(!backend.abortPress());
        QVERIFY(!backend.killHydraulics());
        QVERIFY(!backend.startProgram());
        QVERIFY(!backend.startManualOperation(QStringLiteral("jog-up")));

        QCOMPARE(rejected.count(), 8);
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("NOT_CONNECTED"));
        QVERIFY(!backend.pressOperationActive());
        QCOMPARE(backend.pressMachineState(), QStringLiteral("UNKNOWN"));
        QCOMPARE(backend.ramPositionY1(), 0.0);
        QCOMPARE(backend.ramPositionY2(), 0.0);
    }

    void disconnectedModuleCommandsAreRejectedWithoutMutation()
    {
        MachineControlBackend backend;
        QSignalSpy rejected(&backend, &MachineControlBackend::operationRejected);

        QVERIFY(!backend.homeModule());
        QVERIFY(!backend.jogModule(QStringLiteral("X"), 1, 0.1, 100.0, false));
        QVERIFY(!backend.moveModule(-1.0, 0.0, 100.0));
        QVERIFY(!backend.stopModule());

        QCOMPARE(rejected.count(), 4);
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("NOT_CONNECTED"));
        QVERIFY(!backend.moduleOperationActive());
        QCOMPARE(backend.moduleState(), QStringLiteral("UNKNOWN"));
    }

    void invalidArgumentsRejectBeforeConnectionChecks()
    {
        MachineControlBackend backend;

        QVERIFY(!backend.startManualOperation(QString()));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("INVALID_ARGUMENT"));
        QVERIFY(!backend.jogModule(QStringLiteral("Z"), 1, 0.1, 100.0, false));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("INVALID_ARGUMENT"));
        QVERIFY(!backend.jogModule(QStringLiteral("X"), 0, 0.1, 100.0, false));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("INVALID_ARGUMENT"));
        QVERIFY(!backend.moveModule(0.0, 0.0, 0.0));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("INVALID_ARGUMENT"));
    }

    void rejectedCommandsHaveAuditableLifecycleIds()
    {
        MachineControlBackend backend;
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);

        QCOMPARE(backend.operationId(), qulonglong(0));
        QCOMPARE(backend.operationState(), QStringLiteral("IDLE"));
        QVERIFY(!backend.homePress());
        QCOMPARE(backend.operationId(), qulonglong(1));
        QCOMPARE(backend.operationDevice(), QStringLiteral("press"));
        QCOMPARE(backend.operationName(), QStringLiteral("home"));
        QCOMPARE(backend.operationState(), QStringLiteral("REJECTED"));
        QCOMPARE(backend.operationError(), QStringLiteral("NOT_CONNECTED"));
        QVERIFY(!backend.commandOperationActive());
        QCOMPARE(finished.size(), 1);

        QVERIFY(!backend.moveModule(0.0, 0.0, 0.0));
        QCOMPARE(backend.operationId(), qulonglong(2));
        QCOMPARE(backend.operationError(), QStringLiteral("INVALID_ARGUMENT"));
        QCOMPARE(finished.size(), 2);
    }

    void typedPressJogWritesExactFrameAndRequiresProgressThenIdle()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressReady());
        QVERIFY(backend.pressHomed());
        const qsizetype handshakeWriteCount = pressRaw->writeCount();

        QVERIFY(backend.jogPress(-0.1000, 5.0, QStringLiteral("retract")));
        QCOMPARE(pressRaw->writeCount(), handshakeWriteCount + 1);
        QCOMPARE(pressRaw->writeAt(handshakeWriteCount),
                 QByteArrayLiteral("<-0.1000, 5.0000, retract>\n"));
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.commandOperationActive());
        pressRaw->receive(QByteArrayLiteral(
            "<RETRACT JOG|-0.05|-0.05|0|1|-0.1|-0.1|5|1|1|0|0.05|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        pressRaw->receive(QByteArrayLiteral("[JOG COMPLETED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|-0.1|-0.1|5|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.pressOperationActive());
    }

    void moveToRetractWritesDedicatedAutomaticFrame()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1.0|-1.0|0|0|-1.0|-1.0|5|1|1|0|0|0|0|0>"));
        const qsizetype beforeMove = pressRaw->writeCount();

        QVERIFY(backend.jogPress(-0.0500, 5.0, QStringLiteral("move-retract")));
        QCOMPARE(pressRaw->writeAt(beforeMove),
                 QByteArrayLiteral("<-0.0500, 5.0000, move-retract>\n"));
    }

    void rightPanelJogTypesWriteDedicatedUngatedFrames()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.5|-0.5|0|0|-0.5|-0.5|15|1|1|0|0|0|0|0>"));
        const qsizetype beforeAdvance = pressRaw->writeCount();

        QVERIFY(backend.jogPress(-4.0, 15.0, QStringLiteral("panel-advance")));
        QCOMPARE(pressRaw->writeAt(beforeAdvance),
                 QByteArrayLiteral("<-4.0000, 15.0000, panel-advance>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "<SAFETY JOG|-0.6|-0.6|0|15|-0.7|-4|15|1|1|0|-3.3|0|0|0>"));
        pressRaw->receive(QByteArrayLiteral("[JOG COMPLETED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.7|-0.7|0|0|-0.7|-0.7|15|1|1|0|0|0|0|0>"));

        const qsizetype beforeRetract = pressRaw->writeCount();
        QVERIFY(backend.jogPress(-0.05, 15.0, QStringLiteral("panel-retract")));
        QCOMPARE(pressRaw->writeAt(beforeRetract),
                 QByteArrayLiteral("<-0.0500, 15.0000, panel-retract>\n"));
    }

    void rightPanelEndpointNoOpCompletesWithoutMotionTelemetry()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|-0.05|-0.05|5|1|1|0|0|0|0|0>"));

        QVERIFY(backend.jogPress(-0.05, 5.0, QStringLiteral("panel-retract")));
        pressRaw->receive(QByteArrayLiteral("[JOG COMPLETED]"));
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|-0.05|-0.05|0|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.pressOperationActive());
    }

    void programJogAtEndpointCompletesWithoutMotionTelemetry_data()
    {
        QTest::addColumn<QString>("type");
        QTest::newRow("retract") << QStringLiteral("retract");
        QTest::newRow("safety") << QStringLiteral("safety");
        QTest::newRow("clamp") << QStringLiteral("clamp");
    }

    // 2026-11-01 v1.3 RUN: <-2.5986, 10.0000, retract> at the trajectory
    // endpoint answered [JOG COMPLETED] at once, then only IDLE frames; the
    // SAFETY_CLEARANCE step waited until CANCEL / COMMAND_TIMEOUT.
    void programJogAtEndpointCompletesWithoutMotionTelemetry()
    {
        QFETCH(QString, type);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        const QByteArray idle(
            "<IDLE|-2.5779|-2.5903|0|0|-2.5986|-2.5986|0|1|1|0|0|0|0|0>");
        pressRaw->receive(idle);
        const qsizetype writes = pressRaw->writeCount();

        QVERIFY(backend.jogPress(-2.5986, 10.0, type));
        pressRaw->receive(idle);  // queued before the parser admitted the jog
        QVERIFY(backend.commandOperationActive());
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        pressRaw->receive(QByteArrayLiteral("[JOG COMPLETED]"));
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        QVERIFY(backend.commandOperationActive());
        pressRaw->receive(idle);
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.pressOperationActive());
        QCOMPARE(pressRaw->writeCount(), writes + 1);  // no STOP or retry
    }

    void admittedProgramBendAllowsHeldPedalContinuation()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *pressRaw = press.get();
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-2.6598|-2.6598|0|0|-2.6598|-2.6598|0|1|1|1|0|0|0|0>"));
        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.homeModule());
        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));

        QVERIFY(!backend.jogPress(-2.7806, 5.0, QStringLiteral("bend")));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("NOT_READY"));
        QVERIFY(backend.beginProgramRun());
        const qsizetype beforeBend = pressRaw->writeCount();
        QVERIFY(backend.jogPress(-2.7806, 5.0, QStringLiteral("bend")));
        QCOMPARE(pressRaw->writeAt(beforeBend),
                 QByteArrayLiteral("<-2.7806, 5.0000, bend>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "<BEND JOG|-2.6598|-2.6598|0|1|-2.7806|-2.7806|5|1|1|1|0.1208|0|0|0>"));
        pressRaw->receive(QByteArrayLiteral("[JOG COMPLETED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-2.7806|-2.7806|0|0|-2.7806|-2.7806|5|1|1|1|0|0|0|0>"));
        QVERIFY(!backend.pressOperationActive());
        backend.endProgramRun();

        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-2.7806|-2.7806|0|0|-2.7806|-2.7806|0|1|1|1|0|0|0|0>"));
        QVERIFY(!backend.jogPress(-2.7806, 5.0, QStringLiteral("bend")));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("NOT_READY"));
    }

    void typedModuleMoveWritesSafeAxisOrderAndRequiresTargetIdle()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(false);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$0=10"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.moduleReady());
        QVERIFY(backend.homeModule());
        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.moduleHomed());
        const qsizetype beforeMove = moduleRaw->writeCount();

        QVERIFY(backend.moveModule(1.0, 0.5, 100.0));
        QCOMPARE(moduleRaw->writeAt(beforeMove),
             QByteArrayLiteral("G20 G90 G54 G1 X1.0000 F100.00\n"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        QCOMPARE(moduleRaw->writeAt(beforeMove + 1),
             QByteArrayLiteral("G20 G90 G54 G1 Y0.5000 F100.00\n"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0.5,0.25,0|WCO:0,0,0>"));
        QVERIFY(backend.commandOperationActive());
        moduleRaw->receive(QByteArrayLiteral("<Run|MPos:0.75,0.4,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:1,0.5,0|WCO:0,0,0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.moduleOperationActive());
    }

    void incrementalModuleMoveUsesExactProductionFrameAndTargetConvergence()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(false);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:1,0,0|WCO:0,0,0>"));
        QVERIFY(backend.homeModule());
        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:1,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:1,0,0|WCO:0,0,0>"));
        const qsizetype beforeMove = moduleRaw->writeCount();

        QVERIFY(backend.incrementModule(QStringLiteral("X"), 0.25, 100.0));
        QCOMPARE(moduleRaw->writeAt(beforeMove),
                 QByteArrayLiteral("G20 G91 G54 X 0.2500 F 100.00\n"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:1.1,0,0|WCO:0,0,0>"));
        QVERIFY(backend.commandOperationActive());
        moduleRaw->receive(QByteArrayLiteral("<Run|MPos:1.2,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:1.25,0,0|WCO:0,0,0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void pressRetractPlaneRequiresVerifiedControllerAcknowledgement()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        const qsizetype beforeSetting = pressRaw->writeCount();

        QVERIFY(backend.setPressRetractPlane(-0.25));
        QCOMPARE(pressRaw->writeAt(beforeSetting), QByteArrayLiteral("<$R=-0.2500>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.commandOperationActive());
        pressRaw->receive(QByteArrayLiteral("R set to: -0.2500"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        QVERIFY(backend.setPressRetractPlane(-0.30));
        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.3000|0|12.5000|0}"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        // 2026-11-01 field failure: V53 ignored a negative plane and echoed
        // 0.0000, so RUN waited in STARTING. The non-motion setting is now
        // bounded and fails with a named cause, never advancing on timeout.
        const qsizetype beforeIgnored = pressRaw->writeCount();
        QVERIFY(backend.setPressRetractPlane(-2.6208));
        QCOMPARE(pressRaw->writeAt(beforeIgnored), QByteArrayLiteral("<$R=-2.6208>\n"));
        QVERIFY(backend.m_commandDeadlineTimer.isActive());
        QVERIFY(backend.m_commandDeadlineTimer.interval() <= 3000);
        pressRaw->receive(QByteArrayLiteral("{TEMP:0.0000|0|12.5000|0}"));
        QVERIFY(backend.commandOperationActive());
        QVERIFY(QMetaObject::invokeMethod(&backend.m_commandDeadlineTimer, "timeout",
                                          Qt::DirectConnection));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("RETRACT_PLANE_NOT_ACCEPTED"));
        QCOMPARE(pressRaw->writeCount(), beforeIgnored + 1);

        // No reply at all: a distinct timeout cause, still no extra write.
        const qsizetype beforeSilent = pressRaw->writeCount();
        QVERIFY(backend.setPressRetractPlane(-1.0));
        QVERIFY(QMetaObject::invokeMethod(&backend.m_commandDeadlineTimer, "timeout",
                                          Qt::DirectConnection));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("RETRACT_PLANE_ACK_TIMEOUT"));
        QCOMPARE(pressRaw->writeCount(), beforeSilent + 1);

        // A late matching echo after a mismatched one still acknowledges.
        QVERIFY(backend.setPressRetractPlane(-1.5));
        pressRaw->receive(QByteArrayLiteral("{TEMP:-1.0000|0|12.5000|0}"));
        pressRaw->receive(QByteArrayLiteral("{TEMP:-1.5000|0|12.5000|0}"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void pressEepromPublishesRamToTableOpeningAndDisconnectClearsIt()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QCOMPARE(backend.ramToTableOpening(), 0.0);
        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "{EEPROM:12.5|1|1|8.300|90000|90000|0|300000|300000|0}"));
        QCOMPARE(backend.ramToTableOpening(), 8.3);

        pressRaw->receive(QByteArrayLiteral(
            "{EEPROM:12.5|1|1|-8.300|90000|90000|0|300000|300000|0}"));
        QCOMPARE(backend.ramToTableOpening(), 8.3);

        backend.disconnectPress();
        QCOMPARE(backend.ramToTableOpening(), 0.0);
    }

    void ramToTableWriteUsesJavaFrameAndRequiresMatchingEeprom()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<HYDRAULIC SHUTDOWN|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        const qsizetype beforeSetting = pressRaw->writeCount();

        // Custom firmware: STOP first so the persistence gate admits the write.
        QVERIFY(backend.setRamToTableOpening(8.3));
        QCOMPARE(pressRaw->writeCount(), beforeSetting + 1);
        QCOMPARE(pressRaw->writeAt(beforeSetting), QByteArrayLiteral("<stop>\n"));
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        QCOMPARE(pressRaw->writeAt(beforeSetting + 1), QByteArrayLiteral("<$3=8.3000>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "{EEPROM:12.5|1|1|8.250|90000|90000|0|300000|300000|0}"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));

        const qsizetype beforeRetry = pressRaw->writeCount();
        QVERIFY(backend.setRamToTableOpening(8.3));
        QCOMPARE(pressRaw->writeAt(beforeRetry), QByteArrayLiteral("<stop>\n"));
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        QCOMPARE(pressRaw->writeAt(beforeRetry + 1), QByteArrayLiteral("<$3=8.3000>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "{EEPROM:12.5|1|1|8.300|90000|90000|0|300000|300000|0}"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(backend.ramToTableOpening(), 8.3);

        // Firmware echoes 3 decimals: 8.2915 is saved and read back as 8.291.
        const qsizetype beforeEcho = pressRaw->writeCount();
        QVERIFY(backend.setRamToTableOpening(8.2915));
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        QCOMPARE(pressRaw->writeAt(beforeEcho + 1), QByteArrayLiteral("<$3=8.2915>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "{EEPROM:12.5|1|1|8.291|90000|90000|0|300000|300000|0}"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        // A stale echo one display digit away is still a mismatch.
        const qsizetype beforeStale = pressRaw->writeCount();
        QVERIFY(backend.setRamToTableOpening(8.2915));
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        QCOMPARE(pressRaw->writeAt(beforeStale + 1), QByteArrayLiteral("<$3=8.2915>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "{EEPROM:12.5|1|1|8.290|90000|90000|0|300000|300000|0}"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("RAM_TO_TABLE_ACK_MISMATCH"));

        // A 4-decimal echo (v53 AUTO-target firmware) is verified exactly.
        const qsizetype beforeExact = pressRaw->writeCount();
        QVERIFY(backend.setRamToTableOpening(8.2937));
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        QCOMPARE(pressRaw->writeAt(beforeExact + 1), QByteArrayLiteral("<$3=8.2937>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "{EEPROM:12.5|1|1|8.2937|90000|90000|0|300000|300000|0}"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(backend.ramToTableOpening(), 8.2937);

        // ...so a 4-decimal echo that rounds to the same 3 decimals but
        // differs in the 4th is a mismatch.
        const qsizetype beforeFourth = pressRaw->writeCount();
        QVERIFY(backend.setRamToTableOpening(8.2937));
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        QCOMPARE(pressRaw->writeAt(beforeFourth + 1), QByteArrayLiteral("<$3=8.2937>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "{EEPROM:12.5|1|1|8.2940|90000|90000|0|300000|300000|0}"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("RAM_TO_TABLE_ACK_MISMATCH"));

        // A coarser echo never widens the band beyond 3 decimals.
        const qsizetype beforeCoarse = pressRaw->writeCount();
        QVERIFY(backend.setRamToTableOpening(8.2937));
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        QCOMPARE(pressRaw->writeAt(beforeCoarse + 1), QByteArrayLiteral("<$3=8.2937>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "{EEPROM:12.5|1|1|8.3|90000|90000|0|300000|300000|0}"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("RAM_TO_TABLE_ACK_MISMATCH"));
    }

    void ramToTableWriteFailsFastOnEepromBusyAndStopTimeout()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        const qsizetype beforeSetting = pressRaw->writeCount();

        QVERIFY(backend.setRamToTableOpening(8.2937));
        QCOMPARE(pressRaw->writeAt(beforeSetting), QByteArrayLiteral("<stop>\n"));
        // An EEPROM BUSY before the STOP confirmation is not ours to judge.
        pressRaw->receive(QByteArrayLiteral("[EEPROM BUSY]"));
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        QCOMPARE(pressRaw->writeCount(), beforeSetting + 1);
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        QCOMPARE(pressRaw->writeAt(beforeSetting + 1), QByteArrayLiteral("<$3=8.2937>\n"));
        pressRaw->receive(QByteArrayLiteral("[EEPROM BUSY]"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("RAM_TO_TABLE_EEPROM_BUSY"));
        QVERIFY(!backend.pressOperationActive());
        QVERIFY(!backend.m_commandDeadlineTimer.isActive());

        const qsizetype beforeRetry = pressRaw->writeCount();
        QVERIFY(backend.setRamToTableOpening(8.2937));
        QCOMPARE(pressRaw->writeAt(beforeRetry), QByteArrayLiteral("<stop>\n"));
        QVERIFY(QMetaObject::invokeMethod(&backend.m_commandDeadlineTimer, "timeout",
                                          Qt::DirectConnection));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("RAM_TO_TABLE_STOP_TIMEOUT"));
        QCOMPARE(pressRaw->writeCount(), beforeRetry + 1);
    }

    void ramToTableWriteRejectsOutOfRangeAndUnsafeState()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(!backend.setRamToTableOpening(7.949));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("INVALID_ARGUMENT"));
        pressRaw->receive(QByteArrayLiteral(
            "<BEND JOG|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(!backend.setRamToTableOpening(8.3));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("NOT_READY"));
    }

    void manualStrokeWritesRetractPlaneRetractAndBendInOrder()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.5|-0.5|0|0|0|0|1|1|1|0|0|0|0|0>"));
        const qsizetype beforeStroke = pressRaw->writeCount();

        QVERIFY(backend.startManualStroke(-0.1, -1.0, 4.0, 2.0));
        QCOMPARE(pressRaw->writeAt(beforeStroke), QByteArrayLiteral("<$R=-0.1000>\n"));
        pressRaw->receive(QByteArrayLiteral("R set to: -0.1000"));
        QCOMPARE(pressRaw->writeAt(beforeStroke + 1),
                 QByteArrayLiteral("<-0.1000, 4.0000, retract>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "<RETRACT JOG|-0.3|-0.3|0|1|-0.1|-0.1|4|1|1|0|0.2|0|0|0>"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|-0.1|-0.1|4|1|1|0|0|0|0|0>"));
        QCOMPARE(pressRaw->writeAt(beforeStroke + 2),
                 QByteArrayLiteral("<-1.0000, 2.0000, bend>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "<BEND JOG|-0.5|-0.5|0|1|-1|-1|2|1|1|0|0.5|0|0|0>"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|-1|-1|2|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void manualModeConfigurationRequiresControllerStatusOrEcho()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        const qsizetype beforeManual = pressRaw->writeCount();

        QVERIFY(backend.setManualModeEnabled(true));
        QCOMPARE(pressRaw->writeAt(beforeManual), QByteArrayLiteral("<ManualEnable>\n"));
        QVERIFY(!backend.manualModeEnabled());
        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|1|12.5000|0}"));
        QVERIFY(backend.manualModeEnabled());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        QVERIFY(backend.setManualModeMaxTonnage(8.5));
        QCOMPARE(pressRaw->writeAt(beforeManual + 1), QByteArrayLiteral("<$MT=8.5000>\n"));
        pressRaw->receive(QByteArrayLiteral("[RECEIVED STRING: $MT=8.5000]"));
        QCOMPARE(backend.manualModeMaxTonnagePerRam(), 8.5);
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        QVERIFY(backend.setManualModeEnabled(false));
        QCOMPARE(pressRaw->writeAt(beforeManual + 2), QByteArrayLiteral("<ManualDisable>\n"));
        pressRaw->receive(QByteArrayLiteral("<TEMP:-0.1|0|8.5000|0>"));
        QVERIFY(!backend.manualModeEnabled());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void primingRequiresShutdownAndAuthoritativeStatus()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(!backend.setPrimingEnabled(true));

        const qsizetype beforeStop = pressRaw->writeCount();
        QVERIFY(backend.killHydraulics());
        QCOMPARE(pressRaw->writeAt(beforeStop), QByteArrayLiteral("<HydraulicShutdown>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "<HYDRAULIC SHUTDOWN|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        const qsizetype beforeEnable = pressRaw->writeCount();
        QVERIFY(backend.setPrimingEnabled(true));
        QCOMPARE(pressRaw->writeAt(beforeEnable), QByteArrayLiteral("<PrimingEnable>\n"));
        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|0|12.5000|1}"));
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        pressRaw->receive(QByteArrayLiteral(
            "<PRIMING MODE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.primingModeEnabled());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        const qsizetype beforeDisable = pressRaw->writeCount();
        QVERIFY(backend.setPrimingEnabled(false));
        QCOMPARE(pressRaw->writeAt(beforeDisable), QByteArrayLiteral("<PrimingDisable>\n"));
        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|0|12.5000|0}"));
        QVERIFY(!backend.primingModeEnabled());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void primingLatchIsAuthoritativeAndLegacySafe()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<PRIMING MODE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));

        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|0|12.5000|1}"));
        QVERIFY(!backend.primingLatchSupported());
        QVERIFY(!backend.setPrimingLatch(QStringLiteral("Y1"), true));

        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|0|12.5000|1|1|0|0}"));
        QVERIFY(backend.primingLatchSupported());
        const qsizetype beforeLatch = pressRaw->writeCount();
        QVERIFY(backend.setPrimingLatch(QStringLiteral("Y1"), true));
        QCOMPARE(pressRaw->writeAt(beforeLatch), QByteArrayLiteral("<PrimingLatch:Y1>\n"));
        QVERIFY(!backend.primingLatchY1());

        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|0|12.5000|1|1|1|0}"));
        QVERIFY(backend.primingLatchY1());
        QVERIFY(backend.stopPressMotion());
        QVERIFY(!backend.primingLatchY1());

        // A delayed pre-STOP TEMP must not restart the locally revoked epoch.
        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|0|12.5000|1|1|1|0}"));
        QVERIFY(!backend.primingLatchY1());
        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|0|12.5000|0|1|0|0}"));
        QVERIFY(!backend.primingLatchY1());
    }

    void customFirmwareManualEchoCompletesWithoutTemporaryStatus()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.setManualModeEnabled(true));
        pressRaw->receive(QByteArrayLiteral("[CMD:ManualEnable]"));
        QVERIFY(backend.manualModeEnabled());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        QVERIFY(backend.setManualModeEnabled(false));
        pressRaw->receive(QByteArrayLiteral("[CMD:ManualDisable]"));
        QVERIFY(!backend.manualModeEnabled());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void manualDisableIsAdmittedWithoutConfirmedEnabledState()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(!backend.manualModeEnabled());
        const qsizetype beforeDisable = pressRaw->writeCount();

        QVERIFY(backend.setManualModeEnabled(false));
        QCOMPARE(pressRaw->writeAt(beforeDisable), QByteArrayLiteral("<ManualDisable>\n"));
        pressRaw->receive(QByteArrayLiteral("[CMD:ManualDisable]"));
        QVERIFY(!backend.manualModeEnabled());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void manualMaxTonnageEchoMustMatchRequestedValue()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.setManualModeMaxTonnage(8.5));
        pressRaw->receive(QByteArrayLiteral("[CMD:$MT=9.5000]"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(),
                 QStringLiteral("MANUAL_MAX_TONNAGE_ACK_MISMATCH"));
    }

    void nativeTonnageHoldUsesTypedFrameAndControlledCancel()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.setManualModeEnabled(true));
        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|1|12.5000|0}"));
        const qsizetype beforeHold = pressRaw->writeCount();

        QVERIFY(backend.nativeTonnageHoldSupported());
        QVERIFY(backend.startTonnageHold(4.25, 5.0, 6.0));
        QCOMPARE(pressRaw->writeAt(beforeHold), QByteArrayLiteral("<TH:4.250,5.000,6.000>\n"));
        pressRaw->receive(QByteArrayLiteral("{TH:ARMED}"));
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        QVERIFY(backend.stopTonnageHold());
        QCOMPARE(pressRaw->writeAt(beforeHold + 1), QByteArrayLiteral("<cancel>\n"));
        pressRaw->receive(QByteArrayLiteral("{TH:DONE}"));
        QVERIFY(backend.pressOperationActive());
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void thcCommissioningUsesBoundedTypedFramesAndFreshIdleCompletion()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.setManualModeEnabled(true));
        pressRaw->receive(QByteArrayLiteral("[MANUAL ENABLED]"));
        const qsizetype beforeArm = pressRaw->writeCount();

        QVERIFY(backend.armThcCommissioning(0.5, 0.5, -0.5));
        QCOMPARE(pressRaw->writeAt(beforeArm),
             QByteArrayLiteral("<THC:ARM:0.500,0.500,-0.500>\n"));
        pressRaw->receive(QByteArrayLiteral("{THC:ARMED}"));
        QVERIFY(backend.startThcCommissioning());
        QCOMPARE(pressRaw->writeAt(beforeArm + 1), QByteArrayLiteral("<THC:START>\n"));
        pressRaw->receive(QByteArrayLiteral("{THC:RUNNING}"));
        QVERIFY(backend.heartbeatThcCommissioning());
        QCOMPARE(pressRaw->writeAt(beforeArm + 2), QByteArrayLiteral("<THC:HB>\n"));
        pressRaw->receive(QByteArrayLiteral("{THC:HB}"));
        pressRaw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        QVERIFY(backend.releaseThcCommissioning());
        QCOMPARE(pressRaw->writeAt(beforeArm + 3), QByteArrayLiteral("<THC:RELEASE>\n"));
        pressRaw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        pressRaw->receive(QByteArrayLiteral("{THC:DONE}"));
        QVERIFY(backend.pressOperationActive());
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.pressOperationActive());

        QVERIFY(!backend.armThcCommissioning(1.001, 0.5, -0.5));
        QVERIFY(!backend.armThcCommissioning(0.5, 1.001, -0.5));
        QVERIFY(!backend.armThcCommissioning(0.5, 0.5, -0.499));
    }

    void thcContactProfileUsesDedicatedFixedFrameWithoutManualMode()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(!backend.manualModeEnabled());
        const qsizetype beforeProfile = pressRaw->writeCount();
        QVERIFY(backend.startThcContactProfileCommissioning());
        QCOMPARE(pressRaw->writeAt(beforeProfile),
                 QByteArrayLiteral("<THC:CONTACT_PROFILE>\n"));
        pressRaw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_RUNNING}"));
        QCOMPARE(backend.thcCommissioningState(), QStringLiteral("CONTACT_PROFILE_RUNNING"));
        QVERIFY(!backend.m_commandDeadlineTimer.isActive());
        QVERIFY(backend.heartbeatThcCommissioning());
        pressRaw->receive(QByteArrayLiteral("{THC:HB}"));
        QCOMPARE(backend.thcCommissioningState(), QStringLiteral("CONTACT_PROFILE_RUNNING"));
        QVERIFY(!backend.m_commandDeadlineTimer.isActive());
        pressRaw->receive(QByteArrayLiteral(
            "<TH_COMMISSIONING|-2.84|-2.84|0|0|0|0|1|1|1|0|0|0.18|0.18|0>"));
        QVERIFY(!backend.m_thcContactProfileContactObserved);
        QVERIFY(!backend.m_commandDeadlineTimer.isActive());
        pressRaw->receive(QByteArrayLiteral("{THC:CONTACT}"));
        QVERIFY(backend.m_thcContactProfileContactObserved);
        QVERIFY(backend.m_commandDeadlineTimer.isActive());
        QCOMPARE(backend.m_commandDeadlineTimer.interval(), 65000);
        pressRaw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        QCOMPARE(backend.thcCommissioningState(), QStringLiteral("HOLDING"));
        QVERIFY(!backend.m_commandDeadlineTimer.isActive());
        pressRaw->receive(QByteArrayLiteral("{THC:ERROR:NO_PROGRESS}"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QVERIFY(backend.m_thcContactProfileContactObserved);
        QVERIFY(!backend.m_thcContactProfileActive);
    }

    void thcTuningQueryIsReadOnlyCorrelatedAndBounded()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QSignalSpy finished(&backend, &MachineControlBackend::thcTuningQueryFinished);

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|0|1|1|0|0|0|0|0>"));
        backend.m_primingModeEnabled = true;
        QVERIFY(!backend.queryThcTuning());
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("OPERATION_IN_PROGRESS"));
        backend.m_primingModeEnabled = false;
        const qsizetype beforeQuery = pressRaw->writeCount();
        QVERIFY(backend.queryThcTuning());
        QCOMPARE(pressRaw->writeAt(beforeQuery), QByteArrayLiteral("<THC:TUNE?>\n"));
        QVERIFY(!backend.queryThcTuning());
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("OPERATION_IN_PROGRESS"));
        QVERIFY(!backend.homePress());
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("OPERATION_IN_PROGRESS"));
        QVERIFY(!backend.setRamToTableOpening(8.250));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("OPERATION_IN_PROGRESS"));
        QCOMPARE(pressRaw->writeCount(), beforeQuery + 1);

        pressRaw->receive(QByteArrayLiteral("{THC:HB}"));
        QCOMPARE(finished.size(), 0);
        const QByteArray expected = QByteArrayLiteral(
            "{THC:TUNE:v=1,cq=0.0100,fs=0.0500,rate=0.0100,auth=0.1500,brake=freeze,safe=freeze}");
        pressRaw->receive(expected);
        QCOMPARE(finished.size(), 1);
        QCOMPARE(finished.at(0).at(0).toBool(), true);
        QCOMPARE(finished.at(0).at(1).toString(), QString::fromLatin1(expected));
        QCOMPARE(finished.at(0).at(2).toString(), QString());

        QVERIFY(backend.queryThcTuning());
        backend.m_thcTuningQueryTimer.setInterval(1);
        backend.m_thcTuningQueryTimer.start();
        QTRY_COMPARE_WITH_TIMEOUT(finished.size(), 2, 100);
        QCOMPARE(finished.at(1).at(0).toBool(), false);
        QCOMPARE(finished.at(1).at(2).toString(), QStringLiteral("TIMEOUT"));
        QVERIFY(!backend.queryThcTuning());
        pressRaw->receive(expected);
        QCOMPARE(finished.size(), 2);
        QVERIFY(!pressRaw->isOpen());

        auto errorPress = std::make_unique<ScriptedMachineTransport>(true);
        auto errorModule = std::make_unique<ScriptedMachineTransport>(false);
        auto *errorPressRaw = errorPress.get();
        MachineControlBackend errorBackend(std::move(errorPress), std::move(errorModule));
        QSignalSpy errorFinished(&errorBackend,
                                 &MachineControlBackend::thcTuningQueryFinished);
        QVERIFY(errorBackend.connectPress());
        errorPressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        errorPressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QVERIFY(errorBackend.queryThcTuning());
        errorPressRaw->receive(QByteArrayLiteral("{THC:TUNE:ERROR:UNKNOWN}"));
        QCOMPARE(errorFinished.size(), 0);
        errorPressRaw->receive(QByteArrayLiteral("{THC:TUNE:ERROR:BUSY}"));
        QCOMPARE(errorFinished.size(), 1);
        QCOMPARE(errorFinished.at(0).at(0).toBool(), false);
        QCOMPARE(errorFinished.at(0).at(1).toString(), QString());
        QCOMPARE(errorFinished.at(0).at(2).toString(), QStringLiteral("BUSY"));
    }

    void thcContactProfileAllowsConvergedAcquisitionReleaseBeforeHolding()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|0|0|1|1|1|0|0|0|0|0>"));
        const qsizetype beforeProfile = pressRaw->writeCount();
        QVERIFY(backend.startThcContactProfileCommissioning());
        pressRaw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_RUNNING}"));

        QVERIFY(backend.releaseThcCommissioning());
        QCOMPARE(pressRaw->writeAt(beforeProfile + 1),
                 QByteArrayLiteral("<THC:RELEASE>\n"));
        pressRaw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        pressRaw->receive(QByteArrayLiteral("{THC:DONE}"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.pressOperationActive());
    }

    void thcContactProfileTimeoutCancelsBeforeReportingFailure()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.startThcContactProfileCommissioning());
        pressRaw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_RUNNING}"));
        // Use the owning timer with an immediate expiry; no wall-clock
        // 60-second wait is needed for this deterministic cancellation path.
        const qsizetype beforeTimeout = pressRaw->writeCount();
        backend.m_commandDeadlineTimer.start(0);
        QTRY_VERIFY_WITH_TIMEOUT(pressRaw->writeCount() > beforeTimeout, 1000);
        QCOMPARE(pressRaw->writeAt(pressRaw->writeCount() - 1),
                 QByteArrayLiteral("<THC:CANCEL>\n"));
        QVERIFY(backend.pressOperationActive());
        QVERIFY(backend.operationState() != QStringLiteral("FAILED"));
        pressRaw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("THC_COMMAND_TIMEOUT"));
    }

    void automaticThcContactProfileOwnsHeartbeatReleaseAndDeadline()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|0|0|1|1|1|0|0|0|0|0>"));
        const qsizetype beforeProfile = pressRaw->writeCount();
        QVERIFY(backend.startAutomaticThcContactProfile());
        QCOMPARE(backend.operationName(), QStringLiteral("automatic-thc-contact-profile"));
        QCOMPARE(pressRaw->writeAt(beforeProfile),
                 QByteArrayLiteral("<THC:CONTACT_PROFILE>\n"));

        pressRaw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_RUNNING}"));
        QVERIFY(backend.m_thcContactProfileHeartbeatTimer.isActive());
        QCOMPARE(backend.m_thcContactProfileHeartbeatTimer.interval(), 250);
        backend.sendThcContactProfileHeartbeat();
        QCOMPARE(pressRaw->writeAt(pressRaw->writeCount() - 1),
                 QByteArrayLiteral("<THC:HB>\n"));

        pressRaw->receive(QByteArrayLiteral("{THC:CONTACT}"));
        QCOMPARE(backend.m_commandDeadlineTimer.interval(), 65000);
        const qsizetype beforeHolding = pressRaw->writeCount();
        pressRaw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        QCOMPARE(pressRaw->writeCount(), beforeHolding);
        QVERIFY(backend.m_commandDeadlineTimer.isActive());
        QCOMPARE(backend.m_commandDeadlineTimer.interval(), 60000);

        // Expiry of the qualified observation epoch advances to typed release;
        // it must not cancel or report an otherwise healthy AUTO 1 T cycle.
        backend.m_commandDeadlineTimer.start(0);
        QTRY_VERIFY_WITH_TIMEOUT(pressRaw->writeCount() > beforeHolding, 1000);
        QCOMPARE(pressRaw->writeAt(pressRaw->writeCount() - 1),
             QByteArrayLiteral("<THC:RELEASE>\n"));
        QVERIFY(backend.pressOperationActive());
        QVERIFY(backend.operationState() != QStringLiteral("FAILED"));

        pressRaw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        QVERIFY(backend.m_commandDeadlineTimer.isActive());
        QCOMPARE(backend.m_commandDeadlineTimer.interval(), 45000);
        pressRaw->receive(QByteArrayLiteral("{THC:DONE}"));
        QVERIFY(!backend.m_thcContactProfileHeartbeatTimer.isActive());
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.pressOperationActive());

        // A clean release retains Home and can finish deep in the profile's
        // travel. The backend must permit another explicit AUTO command.
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-2.5795|-2.5807|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressHomed());
        const qsizetype beforeRepeat = pressRaw->writeCount();
        QVERIFY(backend.startAutomaticThcContactProfile());
        QCOMPARE(pressRaw->writeAt(beforeRepeat),
                 QByteArrayLiteral("<THC:CONTACT_PROFILE>\n"));
        pressRaw->receive(QByteArrayLiteral("{THC:ERROR:TRAVEL_CLEARANCE}"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("THC_ERROR_TRAVEL_CLEARANCE"));
    }

    void toolChangeCapabilityRemovesAutoHoldCapAndRunsTouchMoveSeat()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QSignalSpy events(&backend, &MachineControlBackend::toolChangeEvent);

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        QCOMPARE(pressRaw->writeAt(pressRaw->writeCount() - 1), QByteArrayLiteral("<TCH?>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(!backend.toolChangeSupported());
        QVERIFY(!backend.startToolChangeTouch(0.125, -2.0));
        pressRaw->receive(QByteArrayLiteral("{TCH:CAP:1}"));
        QVERIFY(backend.toolChangeSupported());

        // AUTO HOLD has no host 60 s release on TCH images.
        QVERIFY(backend.startAutomaticThcContactProfile());
        pressRaw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_RUNNING}"));
        pressRaw->receive(QByteArrayLiteral("{THC:CONTACT}"));
        pressRaw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        QVERIFY(!backend.m_commandDeadlineTimer.isActive());
        QVERIFY(backend.cancelThcCommissioning());
        pressRaw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(!backend.pressOperationActive());

        // TOUCH: only valid backoffs, jog-held heartbeat, contact, backoff.
        QVERIFY(!backend.startToolChangeTouch(0.2, -2.0));
        qsizetype before = pressRaw->writeCount();
        QVERIFY(backend.startToolChangeTouch(0.125, -2.5));
        QCOMPARE(pressRaw->writeAt(before), QByteArrayLiteral("<THC:TOUCH:0.125,-2.5000>\n"));
        pressRaw->receive(QByteArrayLiteral("{TCH:PHASE:TOUCH}"));
        QVERIFY(!backend.m_commandDeadlineTimer.isActive());
        QVERIFY(!backend.m_thcContactProfileHeartbeatTimer.isActive());
        QVERIFY(backend.heartbeatToolChangeTouch());
        QCOMPARE(pressRaw->writeAt(pressRaw->writeCount() - 1), QByteArrayLiteral("<THC:HB>\n"));
        pressRaw->receive(QByteArrayLiteral("{TCH:CONTACT:-1.8000,0.21}"));
        QCOMPARE(backend.toolChangeContactPosition(), -1.8);
        pressRaw->receive(QByteArrayLiteral("{TCH:PHASE:BACKOFF}"));
        pressRaw->receive(QByteArrayLiteral("{TCH:BACKOFF_DONE:-1.6750}"));
        pressRaw->receive(QByteArrayLiteral("{THC:DONE}"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1.675|-1.675|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(events.size(), 4);
        QCOMPARE(events.at(0).at(0).toString(), QStringLiteral("TOUCH"));
        QCOMPARE(events.at(1).at(0).toString(), QStringLiteral("CONTACT"));
        QCOMPARE(events.at(3).at(0).toString(), QStringLiteral("BACKOFF_DONE"));
        QCOMPARE(events.at(3).at(1).toDouble(), -1.675);

        // MOVE: host-renewed lease and typed failure.
        before = pressRaw->writeCount();
        QVERIFY(backend.startToolChangeMove(-1.425));
        QCOMPARE(pressRaw->writeAt(before), QByteArrayLiteral("<THC:MOVE:-1.4250>\n"));
        pressRaw->receive(QByteArrayLiteral("{TCH:PHASE:MOVE}"));
        QVERIFY(backend.m_thcContactProfileHeartbeatTimer.isActive());
        pressRaw->receive(QByteArrayLiteral("{THC:ERROR:MOVE_CONTACT}"));
        QCOMPARE(backend.operationError(), QStringLiteral("THC_ERROR_MOVE_CONTACT"));
        QVERIFY(!backend.m_thcContactProfileHeartbeatTimer.isActive());
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1.6|-1.6|0|0|0|0|0|1|1|0|0|0|0|0>"));

        // SEAT: no Manual mode, TH lease, pause/resume, done.
        before = pressRaw->writeCount();
        QVERIFY(backend.startToolChangeSeat(1.0, 5.0, -0.5));
        QCOMPARE(pressRaw->writeAt(before), QByteArrayLiteral("<TH:SEAT:1.000,5.000,-0.5000>\n"));
        pressRaw->receive(QByteArrayLiteral("{TCH:PHASE:SEAT_ARMED}"));
        pressRaw->receive(QByteArrayLiteral("{TH:ARMED}"));
        QVERIFY(backend.m_tonnageHoldHeartbeatTimer.isActive());
        pressRaw->receive(QByteArrayLiteral("{TCH:SEAT_PAUSED}"));
        QCOMPARE(backend.toolChangePhase(), QStringLiteral("SEAT_PAUSED"));
        pressRaw->receive(QByteArrayLiteral("{TCH:SEAT_RESUMED}"));
        pressRaw->receive(QByteArrayLiteral("{TCH:SEAT_DONE:-0.5000}"));
        pressRaw->receive(QByteArrayLiteral("{TH:DONE}"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.5|-0.5|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(backend.toolChangeMode(), QString());
    }

    void automaticThcContactProfileSendsSelectedTarget()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|0|0|1|1|1|0|0|0|0|0>"));

        // Out-of-range targets never reach the controller.
        const qsizetype beforeInvalid = pressRaw->writeCount();
        QVERIFY(!backend.startAutomaticThcContactProfile(0.49));
        QVERIFY(!backend.startAutomaticThcContactProfile(20.01));
        QVERIFY(!backend.startAutomaticThcContactProfile(std::numeric_limits<double>::quiet_NaN()));
        QCOMPARE(pressRaw->writeCount(), beforeInvalid);

        // 1.0 T keeps the bare validated frame.
        QVERIFY(backend.startAutomaticThcContactProfile(1.0));
        QCOMPARE(pressRaw->writeAt(beforeInvalid), QByteArrayLiteral("<THC:CONTACT_PROFILE>\n"));
        pressRaw->receive(QByteArrayLiteral("{THC:ERROR:BUSY}"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));

        // Any other target uses the suffix. Firmware without it answers FORMAT.
        const qsizetype beforeTarget = pressRaw->writeCount();
        QVERIFY(backend.startAutomaticThcContactProfile(0.75));
        QCOMPARE(pressRaw->writeAt(beforeTarget), QByteArrayLiteral("<THC:CONTACT_PROFILE:0.750>\n"));
        // The scripted transport admits anything; the real serial allowlist
        // must admit the exact backend frame too (2026-11-01 field failure).
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            SerialDeviceDiscovery::DeviceRole::Press, pressRaw->writeAt(beforeTarget)));
        pressRaw->receive(QByteArrayLiteral("{THC:ERROR:FORMAT}"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("THC_ERROR_FORMAT"));

        const qsizetype beforeHigh = pressRaw->writeCount();
        QVERIFY(backend.startAutomaticThcContactProfile(2.5));
        QCOMPARE(pressRaw->writeAt(beforeHigh), QByteArrayLiteral("<THC:CONTACT_PROFILE:2.500>\n"));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            SerialDeviceDiscovery::DeviceRole::Press, pressRaw->writeAt(beforeHigh)));
        pressRaw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_RUNNING}"));
        QCOMPARE(backend.operationName(), QStringLiteral("automatic-thc-contact-profile"));
        QVERIFY(backend.m_thcContactProfileHeartbeatTimer.isActive());
    }

    void nativeTonnageHoldCancelRequiresDoneBeforeFreshIdle()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.setManualModeEnabled(true));
        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|1|12.5000|0}"));
        QVERIFY(backend.startTonnageHold(4.25, 5.0, 6.0));
        pressRaw->receive(QByteArrayLiteral("{TH:ARMED}"));
        QVERIFY(backend.stopTonnageHold());

        // This IDLE was already queued before cancel reached the parser; it
        // must not complete or permit a fresh command.
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressOperationActive());
        QVERIFY(!backend.startTonnageHold(4.25, 5.0, 6.0));

        pressRaw->receive(QByteArrayLiteral("{TH:DONE}"));
        QVERIFY(backend.pressOperationActive());
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void nativeTonnageHoldLeaseUsesExplicitHeartbeatAcknowledgement()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.setManualModeEnabled(true));
        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|1|12.5000|0}"));
        const qsizetype beforeHold = pressRaw->writeCount();
        QVERIFY(backend.startTonnageHold(4.25, 5.0, 6.0));
        QTRY_VERIFY_WITH_TIMEOUT(pressRaw->writeCount() > beforeHold + 1, 1500);
        QCOMPARE(pressRaw->writeAt(pressRaw->writeCount() - 1), QByteArrayLiteral("<TH:HB>\n"));
        pressRaw->receive(QByteArrayLiteral("{TH:HB}"));
        QVERIFY(backend.pressOperationActive());
    }

    void v13FirmwareAdvertisesFirmwareOwnedTonnageHold()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|-1|-1|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.setManualModeEnabled(true));
        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|1|12.5000|0}"));
        const qsizetype beforeHold = pressRaw->writeCount();

        QVERIFY(backend.nativeTonnageHoldSupported());
        QVERIFY(backend.startTonnageHold(3.0, 5.0, 6.0));
        QCOMPARE(pressRaw->writeAt(beforeHold),
             QByteArrayLiteral("<TH:3.000,5.000,6.000>\n"));
    }

    void nativeTonnageHoldStopsAtHostSafetyLimit()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.setManualModeEnabled(true));
        pressRaw->receive(QByteArrayLiteral("[CMD:ManualEnable]"));
        QVERIFY(backend.startTonnageHold(4.25, 5.0, 5.0));
        const qsizetype beforeLimit = pressRaw->writeCount();
        pressRaw->receive(QByteArrayLiteral(
            "<SAFETY JOG|-1.1|-1.1|0|1|-4|-4|5|1|1|0|2.9|12.1|12.0|0>"));
        QVERIFY(backend.pressOperationActive());
        QVERIFY(backend.operationState() != QStringLiteral("FAILED"));
        QCOMPARE(pressRaw->writeAt(beforeLimit), QByteArrayLiteral("<stop>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1.1|-1.1|0|0|-4|-4|5|1|1|0|0|12.1|12.0|0>"));
        QVERIFY(backend.pressOperationActive());
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1.1|-1.1|0|0|-4|-4|5|1|1|0|0|12.1|12.0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("TONNAGE_LIMIT_EXCEEDED"));
        QVERIFY(!backend.pressOperationActive());
    }

    void nativeTonnageHoldErrorWaitsForStopConfirmation()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.setManualModeEnabled(true));
        pressRaw->receive(QByteArrayLiteral("[CMD:ManualEnable]"));
        QVERIFY(backend.startTonnageHold(4.25, 5.0, 5.0));
        const qsizetype beforeError = pressRaw->writeCount();

        pressRaw->receive(QByteArrayLiteral("{TH:ERROR:NO_PROGRESS}"));
        QCOMPARE(pressRaw->writeAt(beforeError), QByteArrayLiteral("<stop>\n"));
        QVERIFY(backend.pressOperationActive());
        QVERIFY(backend.operationState() != QStringLiteral("FAILED"));
        pressRaw->receive(QByteArrayLiteral("{TH:ERROR:NO_PROGRESS}"));
        QVERIFY(backend.pressOperationActive());
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("TONNAGE_HOLD_NO_PROGRESS"));
        QVERIFY(!backend.pressOperationActive());
    }

    void legacyTonnageHoldAndStrokeBlockedWithoutCorrelation()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.1]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1|-1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.setManualModeEnabled(true));
        pressRaw->receive(QByteArrayLiteral("{TEMP:-0.1|1|12.5000|0}"));
        const qsizetype beforeHold = pressRaw->writeCount();

        QVERIFY(!backend.nativeTonnageHoldSupported());
        QVERIFY(!backend.startTonnageHold(3.0, 5.0, 5.0));
        QVERIFY(!backend.startManualStroke(-0.2, -1, 5, 5));
        QVERIFY(!backend.jogPress(-1, 5, "bump"));
        QCOMPARE(pressRaw->writeCount(), beforeHold);
    }

    void originalProgramAdmissionAllowsCorrelatedRunPhases()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *pressRaw = press.get();
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        const QByteArray idle("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|0|0|0|0|0>");
        const QByteArray idlePedal("<IDLE|-0.2|-0.2|0|0|0|0|1|1|1|1|0|0|0|0>");
        const auto drainIdle = [pressRaw](const QByteArray &frame) {
            for (int n = 0; n < 40; ++n)
                pressRaw->receive(frame);
        };

        QVERIFY(backend.connectPress());
        pressRaw->receive("[LS-BEND v1.1]");
        pressRaw->receive(idle);
        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.homeModule());
        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));

        // The lease itself writes nothing (v1.1 previously: COMMAND_DISABLED).
        qsizetype writes = pressRaw->writeCount();
        QVERIFY(backend.beginProgramRun());
        QCOMPARE(pressRaw->writeCount(), writes);

        // STARTING: retract plane acknowledged by the original TEMP echo.
        QVERIFY(backend.setPressRetractPlane(-0.2));
        QCOMPARE(pressRaw->writeAt(writes), QByteArray("<$R=-0.2000>\n"));
        pressRaw->receive("[RECEIVED STRING: $R=-0.2000]");
        pressRaw->receive("{TEMP:-0.2|0|12.5000|0}");
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.commandOperationActive());

        // SAFETY_CLEARANCE_POSITION_MOVE: echo + JOG COMPLETED + drained IDLE.
        writes = pressRaw->writeCount();
        QVERIFY(backend.jogPress(-0.5, 5, "safety"));
        QCOMPARE(pressRaw->writeAt(writes), QByteArray("<-0.5000, 5.0000, safety>\n"));
        pressRaw->receive("[RECEIVED STRING: -0.5000, 5.0000, safety]");
        pressRaw->receive("<SAFETY JOG|-0.4|-0.4|0|0|0|0|1|1|1|0|0|0|0|0>");
        pressRaw->receive("[JOG COMPLETED]");
        drainIdle(idle);
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        // CLAMP_MATERIAL_MOVE: sent with the pedal released; v1.1 holds for it.
        writes = pressRaw->writeCount();
        QVERIFY(backend.jogPress(-1.0, 5, "clamp"));
        QCOMPARE(pressRaw->writeAt(writes), QByteArray("<-1.0000, 5.0000, clamp>\n"));
        pressRaw->receive("[RECEIVED STRING: -1.0000, 5.0000, clamp]");
        pressRaw->receive("<CLAMP JOG HOLD|-0.8|-0.8|0|0|0|0|1|1|1|1|0|0|0|0>");
        pressRaw->receive("[JOG COMPLETED]");
        drainIdle(idlePedal);
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        // BEND_MOVE: the held pedal is admitted only inside the program lease.
        writes = pressRaw->writeCount();
        QVERIFY(backend.jogPress(-1.2, 5, "bend"));
        QCOMPARE(pressRaw->writeAt(writes), QByteArray("<-1.2000, 5.0000, bend>\n"));
        pressRaw->receive("[RECEIVED STRING: -1.2000, 5.0000, bend]");
        pressRaw->receive("<BEND JOG HOLD|-1.1|-1.1|0|0|0|0|1|1|1|1|0|0|0|0>");
        pressRaw->receive("[BEND COMPLETED]");
        QVERIFY(backend.commandOperationActive()); // original retract still pending
        pressRaw->receive("<RETRACT JOG|-0.6|-0.6|0|0|0|0|1|1|1|0|0|0|0|0>");
        pressRaw->receive("[JOG COMPLETED]");
        drainIdle(idle);
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        // Chained or uncorrelated operations stay blocked during the lease.
        writes = pressRaw->writeCount();
        QVERIFY(!backend.startManualStroke(-0.2, -1, 5, 5));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("COMMAND_DISABLED"));
        QVERIFY(!backend.startTonnageHold(3.0, 5.0, 5.0));
        QVERIFY(!backend.jogPress(-1, 5, "bump"));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("COMMAND_DISABLED"));
        QCOMPARE(pressRaw->writeCount(), writes);

        // Outside the lease a held pedal still blocks clamp/bend dispatch.
        backend.endProgramRun();
        pressRaw->receive(idlePedal);
        QVERIFY(!backend.jogPress(-1.2, 5, "bend"));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("NOT_READY"));
        QCOMPARE(pressRaw->writeCount(), writes);
    }

    void programAdmissionRequiresBothFreshHomedIdleControllers()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *pressRaw = press.get();
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));

        QVERIFY(!backend.beginProgramRun());
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("NOT_HOMED"));
        QVERIFY(backend.homeModule());
        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.beginProgramRun());
        QVERIFY(!backend.beginProgramRun());
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("OPERATION_IN_PROGRESS"));
        backend.endProgramRun();
        QVERIFY(backend.beginProgramRun());
        backend.endProgramRun();
        QVERIFY(!backend.startProgram());
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("COMMAND_DISABLED"));
    }

    void failedRunPhaseReleasesNativeProgramAdmission()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *pressRaw = press.get();
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.homeModule());
        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));

        QVERIFY(backend.beginProgramRun());
        QVERIFY(backend.jogPress(-1.0, 5.0, QStringLiteral("safety")));
        const qsizetype beforeFailure = pressRaw->writeCount();
        pressRaw->receive(QByteArrayLiteral("[BEND REACH FAIL]"));
        QCOMPARE(pressRaw->writeAt(beforeFailure), QByteArrayLiteral("<stop>\n"));
        QVERIFY(backend.pressOperationActive());
        QVERIFY(backend.operationState() != QStringLiteral("FAILED"));
        QVERIFY(!backend.beginProgramRun());
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressOperationActive());
        QVERIFY(!backend.beginProgramRun());
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("BEND_REACH_FAIL"));
        QVERIFY(backend.beginProgramRun());
    }

    void panelReleaseDoesNotReplacePendingSafetyStop()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|-0.1|-0.1|5|1|1|0|0|0|0|0>"));
        QVERIFY(backend.jogPress(-4.0, 5.0, QStringLiteral("panel-advance")));
        pressRaw->receive(QByteArrayLiteral(
            "<SAFETY JOG|-0.2|-0.2|0|2|-0.2|-4|5|1|1|0|-3.8|0|0|0>"));

        const qsizetype beforeFailure = pressRaw->writeCount();
        pressRaw->receive(QByteArrayLiteral("[INVALID COMMAND]"));
        QCOMPARE(pressRaw->writeCount(), beforeFailure + 1);
        QCOMPARE(pressRaw->writeAt(beforeFailure), QByteArrayLiteral("<stop>\n"));

        QVERIFY(backend.abortPress());
        QCOMPARE(pressRaw->writeCount(), beforeFailure + 1);
        QVERIFY(backend.pressOperationActive());

        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.2|-0.2|0|0|-0.2|-0.2|0|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("INVALID_COMMAND"));
    }

    void panelReleaseDuringControllerAlarmKeepsPendingSafetyStop()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1.0|-1.0|0|0|-1.0|-1.0|5|1|1|0|0|0|0|0>"));
        QVERIFY(backend.jogPress(-0.05, 5.0, QStringLiteral("panel-retract")));
        pressRaw->receive(QByteArrayLiteral(
            "<RETRACT JOG|-0.9|-0.9|0|2|-0.8|-0.05|5|1|1|0|0.8|0|0|0>"));

        const qsizetype beforeFailure = pressRaw->writeCount();
        pressRaw->receive(QByteArrayLiteral(
            "<MACHINE TRACKING ERROR|-0.8|-0.83|0.03|0|-0.815|-0.05|5|1|1|0|0|0|0|1>"));
        QCOMPARE(pressRaw->writeCount(), beforeFailure + 1);
        QCOMPARE(pressRaw->writeAt(beforeFailure), QByteArrayLiteral("<stop>\n"));

        QVERIFY(backend.holdPressMotion());
        QCOMPARE(pressRaw->writeCount(), beforeFailure + 1);
        QVERIFY(backend.pressOperationActive());
        QCOMPARE(backend.operationName(), QStringLiteral("jog-panel-retract"));

        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<MACHINE TRACKING ERROR|-0.8|-0.83|0.03|0|-0.815|-0.05|5|1|1|0|0|0|0|1>"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("CONTROLLER_ALARM"));
        QVERIFY(!backend.pressOperationActive());
        QCOMPARE(pressRaw->writeCount(), beforeFailure + 1);
    }

    void failedSafetyStopWriteLatchesPressAdmissionClosed()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.jogPress(-1.0, 5.0, QStringLiteral("bend")));
        pressRaw->setWriteSucceeds(false);
        pressRaw->receive(QByteArrayLiteral("[BEND REACH FAIL]"));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(),
                 QStringLiteral("BEND_REACH_FAIL_SAFETY_WRITE_FAILED"));

        pressRaw->setWriteSucceeds(true);
        QVERIFY(!backend.jogPress(-0.5, 5.0, QStringLiteral("retract")));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("NOT_READY"));

        QVERIFY(backend.disconnectPress());
        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(!backend.jogPress(-0.5, 5.0, QStringLiteral("retract")));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("NOT_READY"));

        const qsizetype beforeHome = pressRaw->writeCount();
        QVERIFY(backend.homePress());
        QCOMPARE(pressRaw->writeAt(beforeHome), QByteArrayLiteral("<$H>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "<HOMING|-0.1|-0.1|0|1|0|-0.05|5|1|1|0|0|0|0|0>"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|-0.05|-0.05|0|1|1|0|0|0|0|0>"));

        const qsizetype beforeRecoveredJog = pressRaw->writeCount();
        QVERIFY(backend.jogPress(-0.5, 5.0, QStringLiteral("panel-advance")));
        QCOMPARE(pressRaw->writeAt(beforeRecoveredJog),
                 QByteArrayLiteral("<-0.5000, 5.0000, panel-advance>\n"));
    }

    void moduleErrorsFailOperationAndAlarmRevokesHoming()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(false);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.homeModule());
        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));

        QVERIFY(backend.moveModule(1.0, 0.0, 100.0));
        moduleRaw->receive(QByteArrayLiteral("error:15"));
        QCOMPARE(backend.operationError(), QStringLiteral("GRBL_ERROR_15"));
        QVERIFY(backend.moduleHomed());

        QVERIFY(backend.moveModule(1.0, 0.0, 100.0));
        moduleRaw->receive(QByteArrayLiteral("ALARM:2"));
        QCOMPARE(backend.operationError(), QStringLiteral("GRBL_ALARM_2"));
        QVERIFY(!backend.moduleHomed());
    }

    void continuousModuleJogCancelsWithRealtimeByteAndWaitsForNonJog()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(false);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("$110=2540"));
        moduleRaw->receive(QByteArrayLiteral("$111=2540"));
        moduleRaw->receive(QByteArrayLiteral("$120=254"));
        moduleRaw->receive(QByteArrayLiteral("$121=254"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.homeModule());
        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        const qsizetype beforeJog = moduleRaw->writeCount();

        QVERIFY(backend.jogModule(QStringLiteral("R"), -1, 0.025, 50.0, true));
        QCOMPARE(moduleRaw->writeAt(beforeJog),
             QByteArrayLiteral("$J=G20 G91 Y-0.0347 F 50\n"));
        // Three segments queued so GRBL's planner never starves.
        QCOMPARE(moduleRaw->writeCount(), beforeJog + 3);
        moduleRaw->receive(QByteArrayLiteral("ok"));
        QCOMPARE(moduleRaw->writeCount(), beforeJog + 4);
        QCOMPARE(moduleRaw->writeAt(beforeJog + 3),
                 QByteArrayLiteral("$J=G20 G91 Y-0.0347 F 50\n"));
        // Re-press of the same direction while streaming must not add frames.
        QVERIFY(backend.jogModule(QStringLiteral("R"), -1, 0.025, 50.0, true));
        QCOMPARE(moduleRaw->writeCount(), beforeJog + 4);
        moduleRaw->receive(QByteArrayLiteral("<Jog|MPos:0,-0.01,0|WCO:0,0,0>"));
        QVERIFY(backend.stopModule());
        // 3 lines still in GRBL RX: cancel waits for their replies so they
        // cannot execute after the jog-cancel (overshoot on release).
        QCOMPARE(moduleRaw->writeCount(), beforeJog + 4);
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,-0.01,0|WCO:0,0,0>"));
        QVERIFY(backend.commandOperationActive());
        moduleRaw->receive(QByteArrayLiteral("error:8"));
        QCOMPARE(moduleRaw->writeCount(), beforeJog + 4);
        moduleRaw->receive(QByteArrayLiteral("ok"));
        QCOMPARE(moduleRaw->writeCount(), beforeJog + 5);
        QCOMPARE(moduleRaw->writeAt(moduleRaw->writeCount() - 1), QByteArrayLiteral("\x85"));
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.operationState() != QStringLiteral("FAILED"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,-0.01,0|WCO:0,0,0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void serialLogContentMatchesJavaFormatting()
    {
        QCOMPARE(SerialMachineTransport::machineLogContent(
                     QByteArray(1, static_cast<char>(0x85))),
                 QByteArrayLiteral("Byte 0x85"));
        QCOMPARE(SerialMachineTransport::machineLogContent(
                     QByteArrayLiteral("<VER>\r\n")),
                 QByteArrayLiteral("<VER>"));
    }

    void movingModuleStopUsesFeedHoldResetAndReinitializesBeforeCompletion()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(false);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("<Run|MPos:0,0,0|WCO:0,0,0>"));
        const qsizetype beforeStop = moduleRaw->writeCount();

        QVERIFY(backend.stopModule());
        QCOMPARE(moduleRaw->writeAt(beforeStop), QByteArrayLiteral("!"));
        moduleRaw->receive(QByteArrayLiteral("<Hold:0|MPos:0,0,0|WCO:0,0,0>"));
        QCOMPARE(moduleRaw->writeAt(beforeStop + 1), QByteArrayLiteral("\x18"));
        QVERIFY(backend.commandOperationActive());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        QCOMPARE(moduleRaw->writeAt(beforeStop + 2), QByteArrayLiteral("$$\n"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(backend.moduleConnectionState(), QStringLiteral("READY"));
    }

    void idleModuleStopResetsImmediatelyAndReinitializesBeforeCompletion()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(false);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        const qsizetype beforeStop = moduleRaw->writeCount();

        QVERIFY(backend.stopModule());
        QCOMPARE(moduleRaw->writeAt(beforeStop), QByteArrayLiteral("\x18"));
        QCOMPARE(backend.moduleConnectionState(), QStringLiteral("RESETTING"));
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(backend.moduleConnectionState(), QStringLiteral("READY"));
    }

    void pressStopBypassesActiveMotionAndCompletesOnlyOnIdle()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.jogPress(-1.0, 5.0, QStringLiteral("bend")));
        pressRaw->receive(QByteArrayLiteral(
            "<SAFETY JOG|-0.2|-0.2|0|2|-1|-1|5|1|1|0|0.8|0|0|0>"));
        const qsizetype beforeStop = pressRaw->writeCount();
        QVERIFY(backend.stopPressMotion());
        QCOMPARE(pressRaw->writeAt(beforeStop), QByteArrayLiteral("<stop>\n"));
        QCOMPARE(backend.operationName(), QStringLiteral("stop-motion"));
        pressRaw->receive(QByteArrayLiteral(
            "<SAFETY JOG|-0.21|-0.21|0|0|-0.21|-0.21|5|1|1|0|0|0|0|0>"));
        QVERIFY(backend.commandOperationActive());
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.21|-0.21|0|0|-0.21|-0.21|5|1|1|0|0|0|0|0>"));
        QVERIFY(backend.commandOperationActive());
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.21|-0.21|0|0|-0.21|-0.21|5|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void pressPanelReleaseUsesHoldAndCompletesOnlyAfterHeldIdle()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.5|-0.5|0|0|-0.5|-0.5|5|1|1|0|0|0|0|0>"));
        QVERIFY(backend.jogPress(-4.0, 5.0, QStringLiteral("panel-advance")));
        pressRaw->receive(QByteArrayLiteral(
            "<SAFETY JOG|-0.6|-0.6|0|1|-4|-4|5|1|1|0|3.4|0|0|0>"));

        const qsizetype beforeHold = pressRaw->writeCount();
        QVERIFY(backend.holdPressMotion());
        QCOMPARE(pressRaw->writeAt(beforeHold), QByteArrayLiteral("<hold>\n"));
        QCOMPARE(backend.operationName(), QStringLiteral("hold-motion"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.6|-0.6|0|0|-0.6|-0.6|5|1|1|0|0|0|0|0>"));
        QVERIFY(backend.commandOperationActive());
        pressRaw->receive(QByteArrayLiteral("[HELD]"));
        QVERIFY(backend.commandOperationActive());
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.6|-0.6|0|0|-0.6|-0.6|5|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.pressOperationActive());
    }

    void pressHomeIsExactManualWriteAndTelemetryCompleted()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressReady());
        QVERIFY(backend.pressTelemetryFresh());
        const qsizetype handshakeWriteCount = pressRaw->writeCount();

        QVERIFY(backend.homePress());
        QCOMPARE(pressRaw->writeCount(), handshakeWriteCount + 1);
        QCOMPARE(pressRaw->writeAt(handshakeWriteCount), QByteArrayLiteral("<$H>\n"));
        QVERIFY(backend.pressOperationActive());
        QVERIFY(backend.commandOperationActive());
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));

        QVERIFY(!backend.homePress());
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("OPERATION_IN_PROGRESS"));
        QCOMPARE(pressRaw->writeCount(), handshakeWriteCount + 1);
        pressRaw->receive(QByteArrayLiteral(
            "<HOMING|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        QVERIFY(backend.pressOperationActive());
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressHomed());
        QVERIFY(!backend.pressOperationActive());
        QVERIFY(!backend.commandOperationActive());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(finished.size(), 1);
    }

    void pressHomeAbortUsesUnconditionalStopAndAcceptsStartupRequired()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.homePress());
        pressRaw->receive(QByteArrayLiteral(
            "<HOMING|0|0|0|1|0|6|7.5|1|1|0|6|0|0|0>"));

        const qsizetype beforeAbort = pressRaw->writeCount();
        QVERIFY(backend.abortPress());
        QCOMPARE(pressRaw->writeAt(pressRaw->writeCount() - 1), QByteArrayLiteral("<stop>\n"));
        QCOMPARE(pressRaw->writeAt(beforeAbort), QByteArrayLiteral("<stop>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.commandOperationActive());
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.pressOperationActive());
    }

    void ordinaryPressAbortStillRequiresIdleConfirmation()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.jogPress(-1.0, 5.0, QStringLiteral("safety")));
        pressRaw->receive(QByteArrayLiteral(
            "<SAFETY JOG|-0.1|-0.1|0|1|-1|-1|5|1|1|0|0.9|0|0|0>"));

        QVERIFY(backend.abortPress());
        QCOMPARE(pressRaw->writeAt(pressRaw->writeCount() - 1), QByteArrayLiteral("<stop>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.commandOperationActive());
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|-0.1|-0.1|5|1|1|0|0|0|0|0>"));
        QVERIFY(backend.commandOperationActive());
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|-0.1|-0.1|5|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void pressHomeAbortAcceptsIdleCompletionRace()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.homePress());
        pressRaw->receive(QByteArrayLiteral(
            "<HOMING|0|0|0|1|0|6|7.5|1|1|0|6|0|0|0>"));
        QVERIFY(backend.abortPress());

        // Home may complete between the host's last HOMING frame and firmware
        // parsing STOP. In that race STOP preserves homingDone and reports IDLE.
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.05|-0.05|0|0|-0.05|-0.05|2|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.pressOperationActive());
    }

    void pressHomeAbortBeforeProgressRejectsStaleIdle()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.homePress());
        QVERIFY(backend.abortPress());

        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.commandOperationActive());
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.commandOperationActive());
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void pressCanBeManuallyHomedAgainFromFreshIdle()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        const qsizetype handshakeWriteCount = pressRaw->writeCount();
        QVERIFY(backend.pressHomed());

        QVERIFY(backend.homePress());
        QCOMPARE(pressRaw->writeCount(), handshakeWriteCount + 1);
        QCOMPARE(pressRaw->writeAt(handshakeWriteCount), QByteArrayLiteral("<$H>\n"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressOperationActive());
        pressRaw->receive(QByteArrayLiteral(
            "<HOMING|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressHomed());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        QVERIFY(backend.homePress());
        QCOMPARE(pressRaw->writeCount(), handshakeWriteCount + 2);
        QCOMPARE(pressRaw->writeAt(handshakeWriteCount + 1), QByteArrayLiteral("<$H>\n"));
    }

    void pressHomeExplicitRefusal_data()
    {
        QTest::addColumn<QByteArray>("refusal");
        QTest::addColumn<QString>("reason");
        QTest::newRow("retained-alarm") << QByteArray("[CONTROLLER ALARM ACTIVE]")
                                      << QStringLiteral("CONTROLLER_ALARM_ACTIVE");
        QTest::newRow("unsettled") << QByteArray("[HOME RECOVERY NOT SETTLED]")
                                 << QStringLiteral("HOME_RECOVERY_NOT_SETTLED");
    }

    void pressHomeExplicitRefusal()
    {
        QFETCH(QByteArray, refusal);
        QFETCH(QString, reason);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        const QByteArray alarm("<MACHINE TRACKING ERROR|-1.4862|-1.5189|0|0|0|0|1|1|1|0|0|0|0|1>");
        pressRaw->receive(alarm);
        QVERIFY(backend.homePress());
        const qsizetype writes = pressRaw->writeCount();
        pressRaw->receive(refusal);
        QCOMPARE(pressRaw->writeCount(), writes + 1);
        QCOMPARE(pressRaw->writeAt(writes), QByteArrayLiteral("<stop>\n"));
        pressRaw->receive(alarm);
        QVERIFY(backend.pressOperationActive());
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(alarm);
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), reason);
        QVERIFY(!backend.pressHomed());
        QVERIFY(!backend.pressOperationActive());
        QVERIFY(backend.pressConnected());
        QCOMPARE(pressRaw->writeCount(), writes + 1);
    }

    void pressHomingCalibrationFailureKeepsTransportConnected()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.homePress());
        pressRaw->receive(QByteArrayLiteral(
            "<HOMING|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        const qsizetype writesBeforeFailure = pressRaw->writeCount();
        pressRaw->receive(QByteArrayLiteral(
            "<Y1 TONNAGE CALIB. FAIL|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));

        QCOMPARE(pressRaw->writeCount(), writesBeforeFailure + 1);
        QCOMPARE(pressRaw->writeAt(writesBeforeFailure), QByteArrayLiteral("<stop>\n"));
        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));

        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("Y1_TONNAGE_CALIB_FAIL"));
        QVERIFY(backend.pressConnected());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("READY"));
        QVERIFY(pressRaw->isOpen());
        QVERIFY(!backend.pressOperationActive());
        QVERIFY(!backend.pressHomed());
    }

    void seriousPressAlarmDuringHomeConfirmsStopBeforeFailure()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.homePress());
        pressRaw->receive(QByteArrayLiteral(
            "<HOMING|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        const qsizetype writesBeforeAlarm = pressRaw->writeCount();
        pressRaw->receive(QByteArrayLiteral(
            "<HYDRAULIC SHUTDOWN|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));

        QCOMPARE(pressRaw->writeCount(), writesBeforeAlarm + 1);
        QCOMPARE(pressRaw->writeAt(writesBeforeAlarm), QByteArrayLiteral("<stop>\n"));
        QVERIFY(backend.pressOperationActive());
        QVERIFY(backend.pressConnected());
        QVERIFY(pressRaw->isOpen());
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));

        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        QVERIFY(backend.pressOperationActive());
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));

        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("CONTROLLER_ALARM"));
        QVERIFY(backend.pressConnected());
        QVERIFY(pressRaw->isOpen());
        QVERIFY(!backend.pressOperationActive());
    }

    void firmwareHomeTerminalFailureConfirmsStopBeforeFailure()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.homePress());
        pressRaw->receive(QByteArrayLiteral(
            "<HOMING-BUMP|-0.05|-0.02|0|0|-0.05|-0.05|0|1|1|0|0|0|0|0>"));
        const qsizetype writesBeforeFailure = pressRaw->writeCount();

        pressRaw->receive(QByteArrayLiteral("[HOMING RETRACT TIMEOUT]"));

        QCOMPARE(pressRaw->writeCount(), writesBeforeFailure + 1);
        QCOMPARE(pressRaw->writeAt(writesBeforeFailure), QByteArrayLiteral("<stop>\n"));
        QVERIFY(backend.pressOperationActive());

        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressOperationActive());

        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));

        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("HOMING_RETRACT_TIMEOUT"));
        QVERIFY(!backend.pressHomed());
    }

    void moduleAlarmHomeUnlocksThenHomesAndWaitsForTelemetry()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(false);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);

        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1BG ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$0=10"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral(
            "<Alarm|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.moduleReady());
        QCOMPARE(backend.moduleState(), QStringLiteral("ALARM"));
        const qsizetype handshakeWriteCount = moduleRaw->writeCount();

        QVERIFY(backend.homeModule());
        QCOMPARE(moduleRaw->writeAt(handshakeWriteCount), QByteArrayLiteral("$X\n"));
        QVERIFY(backend.moduleOperationActive());
        moduleRaw->receive(QByteArrayLiteral("ok"));
        QCOMPARE(moduleRaw->writeAt(handshakeWriteCount + 1), QByteArrayLiteral("$H\n"));
        moduleRaw->receive(QByteArrayLiteral(
            "<Home|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(!backend.moduleHomed());
        QVERIFY(backend.moduleOperationActive());
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        QVERIFY(!backend.moduleHomed());
        moduleRaw->receive(QByteArrayLiteral(
            "<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.moduleHomed());
        QVERIFY(!backend.moduleOperationActive());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(finished.size(), 1);
    }

    void homeAllStartsPressAndModuleSimultaneously()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *pressRaw = press.get();
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1BG ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$0=10"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        finished.clear();

        QVERIFY(backend.homeAll());
        const auto id = backend.operationId();
        QCOMPARE(pressRaw->writeAt(pressRaw->writeCount() - 1), QByteArrayLiteral("<$H>\n"));
        QCOMPARE(moduleRaw->writeAt(moduleRaw->writeCount() - 1), QByteArrayLiteral("$H\n"));
        QVERIFY(backend.pressOperationActive());
        QVERIFY(backend.moduleOperationActive());
        QVERIFY(!backend.homeModule());
        QVERIFY(!backend.homePress());

        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        QCOMPARE(backend.operationDevice(), QStringLiteral("press"));
        pressRaw->receive(QByteArrayLiteral("<HOMING|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        pressRaw->receive(QByteArrayLiteral("<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressHomed());
        QCOMPARE(finished.size(), 1);
        QCOMPARE(finished.at(0).at(1).toString(), QStringLiteral("press"));
        // Press motion stays blocked until the module home finishes.
        QVERIFY(!backend.startRetractJog(5.0));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.moduleHomed());
        QCOMPARE(finished.size(), 3); // press home, rejected jog, module home
        QCOMPARE(finished.last().at(0).toULongLong(), id);
        QCOMPARE(finished.last().at(1).toString(), QStringLiteral("module"));
        QCOMPARE(finished.last().at(3).toString(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.moduleOperationActive());
    }

    void moduleHomeUsesOperationDeadlineAndCanRepeatFromIdle()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(false);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module), nullptr, 1000, 5000);

        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1BG ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$0=10"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        const qsizetype handshakeWriteCount = moduleRaw->writeCount();

        QVERIFY(backend.homeModule());
        QCOMPARE(moduleRaw->writeAt(handshakeWriteCount), QByteArrayLiteral("$H\n"));
        QTest::qWait(1350);
        QVERIFY(backend.moduleConnected());
        QVERIFY(backend.moduleOperationActive());
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));

        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.moduleHomed());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));

        QVERIFY(backend.homeModule());
        QCOMPARE(moduleRaw->writeAt(moduleRaw->writeCount() - 1), QByteArrayLiteral("$H\n"));
        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.moduleHomed());
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
    }

    void completedModuleHomeIgnoresDelayedHomeTelemetry()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(false);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1BG ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$0=10"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));

        QVERIFY(backend.homeModule());
        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.moduleHomed());

        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.moduleHomed());
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.moduleHomed());
    }

    void transientModuleTelemetryStallPreservesConfirmedHoming()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(false);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1BG ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$0=10"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));

        QVERIFY(backend.homeModule());
        moduleRaw->receive(QByteArrayLiteral("<Home|MPos:0,0,0|WCO:0,0,0>"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.moduleHomed());

        QTest::qWait(3100);
        QVERIFY(!backend.moduleReady());
        QVERIFY(!backend.moduleTelemetryFresh());
        QVERIFY(backend.moduleHomed());

        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0,0,0|WCO:0,0,0>"));
        QVERIFY(backend.moduleReady());
        QVERIFY(backend.moduleHomed());
    }

    void homeTimeoutRequiresConfirmedPhysicalStopBeforeClosingTransport()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module), nullptr, 1000, 20);
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.homePress());
        const qsizetype writesBeforeTimeout = pressRaw->writeCount();
        QTRY_COMPARE_WITH_TIMEOUT(pressRaw->writeCount(), writesBeforeTimeout + 1, 200);
        QCOMPARE(pressRaw->writeAt(pressRaw->writeCount() - 1), QByteArrayLiteral("<stop>\n"));
        QVERIFY(backend.pressConnected());
        QVERIFY(backend.pressOperationActive());
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        QCOMPARE(finished.size(), 0);

        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressConnected());
        QCOMPARE(finished.size(), 0);

        pressRaw->receive(QByteArrayLiteral("[STOPPED]"));
        QVERIFY(backend.pressConnected());
        QVERIFY(backend.pressOperationActive());
        QCOMPARE(finished.size(), 0);
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QTRY_VERIFY_WITH_TIMEOUT(!backend.pressConnected(), 200);
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("HOMING_TIMEOUT"));
        QVERIFY(!backend.pressHomed());
        QCOMPARE(finished.size(), 1);
    }

    void serialWriteAllowlistAcceptsOnlyTypedVerifiedFrames()
    {
        using Role = SerialDeviceDiscovery::DeviceRole;
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(Role::Press,
                                                            QByteArrayLiteral("<!?>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(Role::Press,
                                                            QByteArrayLiteral("<$H>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(Role::Module,
                                                            QByteArrayLiteral("$X\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(Role::Module,
                                                            QByteArrayLiteral("$H\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<-0.1000, 5.0000, retract>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<cancel>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<hold>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<stop>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$R=-0.2500>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<ManualEnable>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<ManualDisable>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<PrimingEnable>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<PrimingDisable>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<HydraulicShutdown>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$3=8.2925>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$3=7.9500>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$3=8.7500>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$3=7.9499>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$3=8.7501>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$3=8.29>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$3=-8.2925>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$3=8.2925>")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$4=8.2925>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$3=8.2925>\n<$H>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$3=8.2925>\n\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Module, QByteArrayLiteral("<$3=8.2925>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$MT=0.5000>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$MT=12.5000>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:1.000,0,0>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:4.250,5.000,6.000>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:0.500,0.500,0.500>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:24.000,15.000,15.000>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:HB>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<THC:ARM:0.500,0.500,-0.500>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<THC:START>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<THC:HB>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<THC:RELEASE>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<THC:CANCEL>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<THC:CONTACT_PROFILE>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<THC:TUNE?>\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Module, QByteArrayLiteral("$J=G20 G91 X-0.1000 F 100\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Module, QByteArrayLiteral("G20 G90 G54 G1 X1.0000 F100.00\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Module, QByteArrayLiteral("G20 G10 P1 L20 Y 0.0000\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(
            Role::Module, QByteArrayLiteral("G20 G91 G54 X 0.2500 F 100.00\n")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(Role::Module,
                                                            QByteArrayLiteral("!")));
        QVERIFY(SerialMachineTransport::isWriteFrameAllowed(Role::Module,
                                                            QByteArrayLiteral("\x85")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(Role::Press,
                                                             QByteArrayLiteral("<jog>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(Role::Press,
                                                             QByteArrayLiteral("<$H>")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(Role::Press,
                                     QByteArrayLiteral("<hold>")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(Role::Press,
                                     QByteArrayLiteral("<HOLD>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(Role::Module,
                                     QByteArrayLiteral("<hold>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(Role::Module,
                                                             QByteArrayLiteral("$J=X1\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<-0.1, 5, retract>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<-0.1000, 99.0000, exploit>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<-0.1000, -5.0000, retract>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$X=-0.2500>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<ManualEnable>")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<PrimingEnable>")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<HydraulicShutdown>")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<hydraulicshutdown>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$MT=-0.5000>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<$MT=12.5>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:1.0,0,0>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:1.000,0,2>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:4.250,5.000,6.000>")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:4.250,5.00,6.000>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:4.250,5.000,6.000,0>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:nan,5.000,6.000>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:4.250,inf,6.000>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:-4.250,5.000,6.000>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:0.000,5.000,6.000>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:4.250,0.000,6.000>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:4.250,5.000,0.000>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:24.001,5.000,6.000>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:4.250,15.001,6.000>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<TH:4.250,5.000,15.001>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Module, QByteArrayLiteral("<TH:4.250,5.000,6.000>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Module, QByteArrayLiteral("<TH:HB>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<THC:ARM:1.001,0.500,-0.500>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<THC:ARM:0.500,1.001,-0.500>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<THC:ARM:0.500,0.500,-0.499>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Module, QByteArrayLiteral("<THC:START>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Module, QByteArrayLiteral("<THC:CONTACT_PROFILE>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Module, QByteArrayLiteral("<THC:TUNE?>\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<THC:TUNE?>")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Press, QByteArrayLiteral("<THC:TUNE?>\nextra")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(
            Role::Module, QByteArrayLiteral("G20 G90 G53 G1 X1.0000 F100.00\n")));
        QVERIFY(!SerialMachineTransport::isWriteFrameAllowed(Role::Module,
                                                             QByteArrayLiteral("$H")));
    }

    void serialStableEndpointPrefersPortNameWithoutSerialNumber()
    {
        SerialDeviceDiscovery::PortDescriptor first;
        first.portName = QStringLiteral("ttyACM0");
        first.systemLocation = QStringLiteral("/sys/devices/usb6/6-1/ttyACM0");
        first.hasVendorIdentifier = true;
        first.hasProductIdentifier = true;
        first.vendorIdentifier = 0x2341;
        first.productIdentifier = 0x0069;

        SerialDeviceDiscovery::PortDescriptor refreshed = first;
        refreshed.systemLocation = QStringLiteral("/sys/devices/usb6/6-1:1.0/ttyACM0");
        QCOMPARE(SerialDeviceDiscovery::stableEndpointId(first),
                 SerialDeviceDiscovery::stableEndpointId(refreshed));
    }

    void safetyInputsAreReadOnlyDefaults()
    {
        MachineControlBackend backend;

        QVERIFY(!backend.safetyJogLeft());
        QVERIFY(!backend.safetyJogRight());
        QVERIFY(!backend.bendPedal());
        QVERIFY(!backend.antiBind());
    }

    void discoveryClassifiesOnlyProductionRuntimeIds()
    {
        using Role = SerialDeviceDiscovery::DeviceRole;
        QCOMPARE(SerialDeviceDiscovery::classify(0x2341, 0x0069), Role::Press);
        QCOMPARE(SerialDeviceDiscovery::classify(0x1A86, 0x7523), Role::Press);
        QCOMPARE(SerialDeviceDiscovery::classify(0x2341, 0x0043), Role::Module);
        QCOMPARE(SerialDeviceDiscovery::classify(0x16D0, 0x0EFB), Role::Module);
        QCOMPARE(SerialDeviceDiscovery::classify(0x2341, 0x0369), Role::Unknown);
        QCOMPARE(SerialDeviceDiscovery::classify(0x0000, 0x0000), Role::Unknown);
    }

    void discoveryRejectsMissingMetadataAndAmbiguousRoles()
    {
        using Descriptor = SerialDeviceDiscovery::PortDescriptor;
        Descriptor missingMetadata;
        missingMetadata.portName = QStringLiteral("COM1");
        Descriptor pressOne;
        pressOne.portName = QStringLiteral("COM2");
        pressOne.systemLocation = QStringLiteral("COM2");
        pressOne.hasVendorIdentifier = true;
        pressOne.hasProductIdentifier = true;
        pressOne.vendorIdentifier = 0x2341;
        pressOne.productIdentifier = 0x0069;
        Descriptor pressTwo = pressOne;
        pressTwo.portName = QStringLiteral("COM3");
        pressTwo.systemLocation = QStringLiteral("COM3");

        auto absent = SerialDeviceDiscovery::select(
            SerialDeviceDiscovery::DeviceRole::Press, {missingMetadata});
        QVERIFY(!absent.available);
        QCOMPARE(absent.error, QStringLiteral("ENDPOINT_ABSENT"));
        auto ambiguous = SerialDeviceDiscovery::select(
            SerialDeviceDiscovery::DeviceRole::Press, {pressOne, pressTwo});
        QVERIFY(!ambiguous.available);
        QVERIFY(ambiguous.ambiguous);
        QCOMPARE(ambiguous.error, QStringLiteral("ENDPOINT_AMBIGUOUS"));
    }

    void availableTransportOpensOnlyToInitializingAndHandshakeWrites()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *pressRaw = press.get();
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.pressTransportAvailable());
        QVERIFY(backend.moduleTransportAvailable());
        QVERIFY(backend.connectPress());
        QVERIFY(backend.connectModule());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("INITIALIZING"));
        QCOMPARE(backend.moduleConnectionState(), QStringLiteral("INITIALIZING"));
        QVERIFY(backend.pressConnected());
        QVERIFY(backend.moduleConnected());
        QVERIFY(!backend.pressReady());
        QVERIFY(!backend.moduleReady());
        QVERIFY(!backend.homePress());
        QVERIFY(!backend.homeModule());
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("NOT_READY"));
        QCOMPARE(pressRaw->writeCount(), 2);
        QCOMPARE(pressRaw->writeAt(0), QByteArrayLiteral("<!?>\n"));
        QCOMPARE(pressRaw->writeAt(1), QByteArrayLiteral("<?>\n"));
        QCOMPARE(moduleRaw->writeCount(), 1);
        QCOMPARE(moduleRaw->writeAt(0), QByteArrayLiteral("\x18"));
    }

    void transportAvailabilityAndDropFailClosed()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QSignalSpy availability(&backend, &MachineControlBackend::transportAvailabilityChanged);

        moduleRaw->setAvailable(true);
        QCOMPARE(availability.size(), 1);
        QVERIFY(backend.moduleTransportAvailable());
        QVERIFY(backend.connectPress());
        pressRaw->drop();
        QVERIFY(!backend.pressConnected());
        QVERIFY(!backend.pressReady());
        QVERIFY(!backend.pressHomed());
        QVERIFY(!backend.pressOperationActive());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("DISCONNECTED"));
        QCOMPARE(backend.pressMachineState(), QStringLiteral("UNKNOWN"));
    }

    void transportErrorCannotLeaveStaleConnectionAuthority()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QSignalSpy failure(&backend, &MachineControlBackend::connectionFailed);

        QVERIFY(backend.connectPress());
        pressRaw->fail(QStringLiteral("DEVICE_REMOVED"));
        QCOMPARE(failure.size(), 1);
        QVERIFY(!backend.pressConnected());
        QVERIFY(!backend.pressReady());
        QVERIFY(!backend.pressHomed());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("FAULTED"));
        QCOMPARE(backend.pressMachineState(), QStringLiteral("UNKNOWN"));

        QVERIFY(backend.connectPress());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("INITIALIZING"));
    }

    void detailedOpenFailureIsReportedOnce()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        press->setOpenSucceeds(false);
        press->setOpenError(QStringLiteral("OPEN_FAILED: No such file or directory"));
        MachineControlBackend backend(std::move(press), std::move(module));
        QSignalSpy connectionFailed(&backend, &MachineControlBackend::connectionFailed);
        QSignalSpy rejected(&backend, &MachineControlBackend::operationRejected);

        QVERIFY(!backend.connectPress());
        QCOMPARE(connectionFailed.size(), 1);
        QCOMPARE(connectionFailed.constFirst().at(1).toString(),
                 QStringLiteral("OPEN_FAILED: No such file or directory"));
        QCOMPARE(rejected.size(), 0);
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("DISCONNECTED"));
    }

    void failedPressOperationPreservesConnectedTransport()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));
        QSignalSpy connectionFailed(&backend, &MachineControlBackend::connectionFailed);

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-0.1|-0.1|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressReady());
        pressRaw->setWriteSucceeds(false);

        QVERIFY(!backend.jogPress(-0.2, 5.0, QStringLiteral("retract")));
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("JOG_RETRACT_WRITE_FAILED"));
        QVERIFY(backend.pressConnected());
        QVERIFY(backend.pressReady());
        QVERIFY(pressRaw->isOpen());
        QCOMPARE(connectionFailed.size(), 0);
    }

    void sameUsbIdentityPathChangeRefreshesSelection()
    {
        using Discovery = SerialDeviceDiscovery;
        Discovery::PortDescriptor ttyAcm0;
        ttyAcm0.portName = QStringLiteral("ttyACM0");
        ttyAcm0.systemLocation = QStringLiteral("/dev/ttyACM0");
        ttyAcm0.serialNumber = QStringLiteral("PRESS-SERIAL");
        ttyAcm0.hasVendorIdentifier = true;
        ttyAcm0.hasProductIdentifier = true;
        ttyAcm0.vendorIdentifier = 0x2341;
        ttyAcm0.productIdentifier = 0x0069;
        Discovery::PortDescriptor ttyAcm2 = ttyAcm0;
        ttyAcm2.portName = QStringLiteral("ttyACM2");
        ttyAcm2.systemLocation = QStringLiteral("/dev/ttyACM2");

        const Discovery::Selection before = Discovery::select(
            Discovery::DeviceRole::Press, {ttyAcm0});
        const Discovery::Selection after = Discovery::select(
            Discovery::DeviceRole::Press, {ttyAcm2});
        QCOMPARE(Discovery::stableEndpointId(before.port),
                 Discovery::stableEndpointId(after.port));
        QVERIFY(!Discovery::selectionsEqual(before, after));
        QCOMPARE(after.port.portName, QStringLiteral("ttyACM2"));
    }

    void unexpectedPressDropReconnectsAfterUniqueEndpointReturns()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module), nullptr,
                                      1000, 5000, 5);

        QVERIFY(backend.connectPress());
        QCOMPARE(pressRaw->writeCount(), qsizetype(2));
        pressRaw->setAvailable(false);
        pressRaw->drop();
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("DISCONNECTED"));
        QVERIFY(!backend.pressConnected());

        pressRaw->setAvailable(true);
        QTRY_COMPARE_WITH_TIMEOUT(backend.pressConnectionState(),
                                  QStringLiteral("INITIALIZING"), 200);
        QCOMPARE(pressRaw->writeCount(), qsizetype(4));
        QCOMPARE(pressRaw->writeAt(2), QByteArrayLiteral("<!?>\n"));
        QCOMPARE(pressRaw->writeAt(3), QByteArrayLiteral("<?>\n"));
        QVERIFY(!backend.pressReady());
        QVERIFY(!backend.pressHomed());
    }

    void explicitPressDisconnectCancelsReconnectIntent()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module), nullptr,
                                      1000, 5000, 5);

        QVERIFY(backend.connectPress());
        QVERIFY(backend.disconnectPress());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("DISCONNECTED"));
        pressRaw->setAvailable(false);
        pressRaw->setAvailable(true);
        QTest::qWait(30);
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("DISCONNECTED"));
        QCOMPARE(pressRaw->writeCount(), qsizetype(2));
    }

    void pressFaultRetriesHandshakeWithoutMotionCommands()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module), nullptr,
                                      1000, 5000, 5);

        QVERIFY(backend.connectPress());
        pressRaw->fail(QStringLiteral("SERIAL_ERROR"));
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("FAULTED"));
        QTRY_COMPARE_WITH_TIMEOUT(backend.pressConnectionState(),
                                  QStringLiteral("INITIALIZING"), 200);
        QCOMPARE(pressRaw->writeCount(), qsizetype(4));
        for (qsizetype index = 0; index < pressRaw->writeCount(); ++index) {
            const QByteArray frame = pressRaw->writeAt(index);
            QVERIFY(frame == QByteArrayLiteral("<!?>\n")
                    || frame == QByteArrayLiteral("<?>\n"));
        }
        QVERIFY(!backend.pressOperationActive());
    }

    void pressHandshakeRequiresExactWelcome()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("LS-BEND v1.2"));
        QVERIFY(!backend.pressReady());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2 extra]"));
        QVERIFY(!backend.pressReady());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        QVERIFY(!backend.pressReady());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("INITIALIZING"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1.1000|-1.2000|0.1000|2.5|-1.3000|-1.2500|12.0|0|1|1|0.0500|3.25|4.5|1>"));
        QVERIFY(backend.pressReady());
        QVERIFY(backend.pressHomed());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("READY"));
        QCOMPARE(backend.pressFirmwareVersion(), QStringLiteral("1.2"));
        QCOMPARE(pressRaw->writeCount(), 3);
        QCOMPARE(pressRaw->writeAt(2), QByteArrayLiteral("<VER>\n"));
    }

    void historicalV12ResetAcknowledgementRetriggersIdentityQuery()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        QCOMPARE(pressRaw->writeCount(), 2);
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QVERIFY(!backend.pressReady());
        pressRaw->receive(QByteArrayLiteral("[HARD RESET]"));
        QCOMPARE(pressRaw->writeCount(), 3);
        QCOMPARE(pressRaw->writeAt(2), QByteArrayLiteral("<?>\n"));
        pressRaw->receive(QByteArrayLiteral("[HARD RESET]"));
        QCOMPARE(pressRaw->writeCount(), 3);
        QVERIFY(!backend.pressReady());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|0|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressReady());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("READY"));
        QCOMPARE(backend.pressFirmwareVersion(), QStringLiteral("1.2"));
        QCOMPARE(pressRaw->writeCount(), 4);
        QCOMPARE(pressRaw->writeAt(3), QByteArrayLiteral("<VER>\n"));
    }

    void softResetAfterIdentityFailsClosed()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral("[SOFT RESET]"));
        QVERIFY(!backend.pressReady());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("DISCONNECTED"));
    }

    void moduleHandshakeRequiresSettingsModalAndFreshStatus()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(false);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectModule());
        QCOMPARE(moduleRaw->writeCount(), 1);
        QCOMPARE(moduleRaw->writeAt(0), QByteArrayLiteral("\x18"));
        moduleRaw->receive(QByteArrayLiteral("Grbl almost"));
        QVERIFY(!backend.moduleReady());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        QCOMPARE(moduleRaw->writeCount(), 2);
        QCOMPARE(moduleRaw->writeAt(1), QByteArrayLiteral("$$\n"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        QCOMPARE(moduleRaw->writeCount(), 2);
        moduleRaw->receive(QByteArrayLiteral("$0=10"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        QCOMPARE(moduleRaw->writeAt(2), QByteArrayLiteral("$G\n"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        QCOMPARE(moduleRaw->writeCount(), 3);
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G21 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        QCOMPARE(moduleRaw->writeAt(3), QByteArrayLiteral("?"));
        QVERIFY(!backend.moduleReady());
        moduleRaw->receive(QByteArrayLiteral("<NotAState|MPos:0.000,0.000,0.000>"));
        QVERIFY(!backend.moduleReady());
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0.000,0.000,0.000|WCO:0.000,0.000,0.000>"));
        QVERIFY(backend.moduleReady());
        QVERIFY(!backend.moduleHomed());
        QCOMPARE(backend.moduleConnectionState(), QStringLiteral("READY"));
        QCOMPARE(backend.moduleState(), QStringLiteral("IDLE"));
        QCOMPARE(backend.moduleFirmwareVersion(), QStringLiteral("1.1h"));
    }

    void initializationDeadlineClosesAndClearsAuthority()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        MachineControlBackend backend(std::move(press), std::move(module), nullptr, 20);
        QSignalSpy failure(&backend, &MachineControlBackend::connectionFailed);

        QVERIFY(backend.connectPress());
        QTRY_VERIFY_WITH_TIMEOUT(!backend.pressConnected(), 200);
        QVERIFY(!backend.pressReady());
        QVERIFY(!backend.pressHomed());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("DISCONNECTED"));
        QVERIFY(failure.size() >= 1);
        QCOMPARE(failure.constLast().at(1).toString(), QStringLiteral("INITIALIZATION_TIMEOUT"));
    }

    void handshakeWriteFailureRejectsConnection()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        press->setWriteSucceeds(false);
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(!backend.connectPress());
        QVERIFY(!backend.pressConnected());
        QVERIFY(!backend.pressReady());
        QCOMPARE(backend.pressConnectionState(), QStringLiteral("DISCONNECTED"));
    }

    void controllerWelcomeAfterReadyIsTreatedAsReset()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *pressRaw = press.get();
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressReady());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        QVERIFY(!backend.pressConnected());
        QVERIFY(!backend.pressReady());

        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$0=10"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G21 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:0.000,0.000,0.000|WCO:0.000,0.000,0.000>"));
        QVERIFY(backend.moduleReady());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        QVERIFY(!backend.moduleConnected());
        QVERIFY(!backend.moduleReady());
    }

    void temporaryStatusAcceptsOnlyLegacyOrV4BleedLatchForms()
    {
        const auto legacy = MachineProtocolParsers::parsePressTemporaryStatus(
            QByteArrayLiteral("{TEMP:-0.3000|0|12.5000|0}"));
        QVERIFY(legacy.has_value());
        QVERIFY(!legacy->primingLatchSupported);

        const auto capable = MachineProtocolParsers::parsePressTemporaryStatus(
            QByteArrayLiteral("{TEMP:-0.3000|0|12.5000|1|1|1|0}"));
        QVERIFY(capable.has_value());
        QVERIFY(capable->primingLatchSupported);
        QVERIFY(capable->primingLatchY1);
        QVERIFY(!capable->primingLatchY2);
        QVERIFY(!MachineProtocolParsers::parsePressTemporaryStatus(
            QByteArrayLiteral("{TEMP:-0.3000|0|12.5000|1|1|0}")).has_value());
        QVERIFY(!MachineProtocolParsers::parsePressTemporaryStatus(
            QByteArrayLiteral("{TEMP:-0.3000|0|12.5000|1|0|0|0}")).has_value());
    }

    void typedPressParserRejectsPartialAndNonFiniteFrames()
    {
        QVERIFY(!MachineProtocolParsers::parsePressTelemetry(QByteArrayLiteral("<IDLE|1|2>")));
        QVERIFY(!MachineProtocolParsers::parsePressTelemetry(QByteArrayLiteral(
            "<IDLE|nan|2|0|0|0|0|1|1|1|0|0|0|0|0>")));
        const auto parsed = MachineProtocolParsers::parsePressTelemetry(QByteArrayLiteral(
            "<bend jog|-1.1|-1.2|0.1|2.5|-1.3|-1.25|12|0|1|1|0.05|3.25|4.5|1>"));
        QVERIFY(parsed);
        QCOMPARE(parsed->state, QStringLiteral("BEND_JOG"));
        QCOMPARE(parsed->y1Position, -1.1);
        QCOMPARE(parsed->y2Position, -1.2);
        QVERIFY(!parsed->y1MeasuredVelocity.has_value());
        QVERIFY(!parsed->y2MeasuredVelocity.has_value());
        QVERIFY(parsed->safetyJogLeft);
        QVERIFY(!parsed->safetyJogRight);
        QVERIFY(parsed->bendPedal);
        QVERIFY(parsed->physicalPedal);
        QVERIFY(!parsed->physicalPedalAvailable);
        QVERIFY(parsed->antiBind);

        const auto extended = MachineProtocolParsers::parsePressTelemetry(QByteArrayLiteral(
            "<bend jog|-1.1|-1.2|0.1|2.5|-1.3|-1.25|12|0|1|1|0.05|3.25|4.5|1|-4.5|-3.5>"));
        QVERIFY(extended);
        QCOMPARE(extended->y1MeasuredVelocity, std::optional<double>(-4.5));
        QCOMPARE(extended->y2MeasuredVelocity, std::optional<double>(-3.5));
        QVERIFY(!extended->y1MotorRpm.has_value());
        QVERIFY(!extended->y2MotorRpm.has_value());

        const auto motorExtended = MachineProtocolParsers::parsePressTelemetry(QByteArrayLiteral(
            "<bend jog|-1.1|-1.2|0.1|2.5|-1.3|-1.25|12|0|1|1|0.05|3.25|4.5|1|-4.5|-3.5|-200|400>"));
        QVERIFY(motorExtended);
        QCOMPARE(motorExtended->y1MotorRpm, std::optional<double>(-200.0));
        QCOMPARE(motorExtended->y2MotorRpm, std::optional<double>(400.0));

        const auto physicalPedalExtended = MachineProtocolParsers::parsePressTelemetry(
            QByteArrayLiteral(
                "<bend jog|-1.1|-1.2|0.1|2.5|-1.3|-1.25|12|0|1|0|0.05|3.25|4.5|1|-4.5|-3.5|-200|400|1>"));
        QVERIFY(physicalPedalExtended);
        QVERIFY(!physicalPedalExtended->bendPedal);
        QVERIFY(physicalPedalExtended->physicalPedal);
        QVERIFY(physicalPedalExtended->physicalPedalAvailable);
        QVERIFY(!MachineProtocolParsers::parsePressTelemetry(QByteArrayLiteral(
            "<bend jog|-1.1|-1.2|0.1|2.5|-1.3|-1.25|12|0|1|0|0.05|3.25|4.5|1|-4.5|-3.5|-200|400|bad>")));

        const auto legacyDiagnostic = MachineProtocolParsers::parsePressTelemetry(
            QByteArrayLiteral(
                "<bend jog|-1.1|-1.2|0.1|2.5|-1.3|-1.25|12|0|1|1|0.05|3.25|4.5|1|-4.5|-3.5|-200|400|7|8|9|1|1200|1|1300|0>"));
        QVERIFY(legacyDiagnostic);
        QVERIFY(legacyDiagnostic->physicalPedal);
        QVERIFY(!legacyDiagnostic->physicalPedalAvailable);

        const auto physicalPedalDiagnostic = MachineProtocolParsers::parsePressTelemetry(
            QByteArrayLiteral(
                "<bend jog|-1.1|-1.2|0.1|2.5|-1.3|-1.25|12|0|1|0|0.05|3.25|4.5|1|-4.5|-3.5|-200|400|7|8|9|1|1200|1|1300|0|1>"));
        QVERIFY(physicalPedalDiagnostic);
        QVERIFY(!physicalPedalDiagnostic->bendPedal);
        QVERIFY(physicalPedalDiagnostic->physicalPedal);
        QVERIFY(physicalPedalDiagnostic->physicalPedalAvailable);
    }

    void pressTelemetryPublishesAtomicallyAndClearsOnDrop()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        QVERIFY(!backend.pressReady());
        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|-1.1|-1.2|0.1|2.5|-1.3|-1.25|12|0|1|1|0.05|3.25|4.5|1>"));
        QVERIFY(backend.pressReady());
        QVERIFY(backend.pressTelemetryFresh());
        QCOMPARE(backend.pressTelemetrySequence(), 1ULL);
        QVERIFY(backend.independentRamTelemetryAvailable());
        QCOMPARE(backend.ramPositionY1(), -1.1);
        QCOMPARE(backend.ramPositionY2(), -1.2);
        QCOMPARE(backend.ramTargetPosition(), -1.3);
        QCOMPARE(backend.ramCommandedJogPosition(), -1.25);
        QCOMPARE(backend.ramJogSpeed(), 12.0);
        QCOMPARE(backend.ramDistanceToGo(), 0.05);
        QCOMPARE(backend.ramLoadY1(), 3.25);
        QCOMPARE(backend.ramLoadY2(), 4.5);
        QVERIFY(!backend.measuredRamVelocityAvailable());
        QVERIFY(!backend.motorRpmAvailable());
        QVERIFY(backend.safetyJogLeft());
        QVERIFY(!backend.safetyJogRight());
        QVERIFY(backend.bendPedal());
        QVERIFY(backend.physicalPedal());
        QVERIFY(!backend.physicalPedalAvailable());
        QVERIFY(backend.antiBind());

        pressRaw->receive(QByteArrayLiteral(
            "<BEND_JOG|-1.1|-1.2|0.1|2.5|-1.3|-1.25|12|0|1|1|0.05|3.25|4.5|1|-4.5|-3.5>"));
        QCOMPARE(backend.pressTelemetrySequence(), 2ULL);
        QVERIFY(backend.measuredRamVelocityAvailable());
        QCOMPARE(backend.measuredRamVelocity(), -4.0);

        pressRaw->receive(QByteArrayLiteral(
            "<BEND_JOG|-1.1|-1.2|0.1|2.5|-1.3|-1.25|12|0|1|1|0.05|3.25|4.5|1|-4.5|-3.5|-200|400>"));
        QCOMPARE(backend.pressTelemetrySequence(), 3ULL);
        QVERIFY(backend.motorRpmAvailable());
        QCOMPARE(backend.motorRpmY1(), -200.0);
        QCOMPARE(backend.motorRpmY2(), 400.0);

        pressRaw->receive(QByteArrayLiteral(
            "<BEND_JOG|-1.1|-1.2|0.1|2.5|-1.3|-1.25|12|0|1|0|0.05|3.25|4.5|1|-4.5|-3.5|-200|400|1>"));
        QCOMPARE(backend.pressTelemetrySequence(), 4ULL);
        QVERIFY(!backend.bendPedal());
        QVERIFY(backend.physicalPedal());
        QVERIFY(backend.physicalPedalAvailable());

        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|bad|-9|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QCOMPARE(backend.pressTelemetrySequence(), 4ULL);
        QCOMPARE(backend.ramPositionY1(), -1.1);
        QCOMPARE(backend.ramPositionY2(), -1.2);
        pressRaw->drop();
        QVERIFY(!backend.pressTelemetryFresh());
        QVERIFY(!backend.independentRamTelemetryAvailable());
        QVERIFY(!backend.measuredRamVelocityAvailable());
        QCOMPARE(backend.measuredRamVelocity(), 0.0);
        QVERIFY(!backend.motorRpmAvailable());
        QCOMPARE(backend.motorRpmY1(), 0.0);
        QCOMPARE(backend.motorRpmY2(), 0.0);
        QCOMPARE(backend.ramPositionY1(), 0.0);
        QCOMPARE(backend.ramPositionY2(), 0.0);
        QVERIFY(!backend.physicalPedal());
        QVERIFY(!backend.physicalPedalAvailable());
    }

    void grblTelemetryRequiresUnitAndWcoThenPublishesPositionsAndPins()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(false);
        auto module = std::make_unique<ScriptedMachineTransport>(true);
        auto *moduleRaw = module.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectModule());
        moduleRaw->receive(QByteArrayLiteral("Grbl 1.1h ['$' for help]"));
        moduleRaw->receive(QByteArrayLiteral("$0=10"));
        moduleRaw->receive(QByteArrayLiteral("$13=1"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("[GC:G0 G54 G17 G20 G90]"));
        moduleRaw->receive(QByteArrayLiteral("ok"));
        moduleRaw->receive(QByteArrayLiteral("<Idle|MPos:10.5,2.25,0|WCO:1.5,0.25,0|Pn:X1Y2>"));

        QVERIFY(backend.moduleReady());
        QVERIFY(backend.moduleTelemetryFresh());
        QCOMPARE(backend.moduleMachineX(), 10.5);
        QCOMPARE(backend.moduleMachineR(), 2.25);
        QCOMPARE(backend.moduleWorkX(), 9.0);
        QCOMPARE(backend.moduleWorkR(), 2.0);
        QVERIFY(backend.moduleLimitX1());
        QVERIFY(!backend.moduleLimitX2());
        QVERIFY(!backend.moduleLimitR1());
        QVERIFY(backend.moduleLimitR2());
    }

    void grblStatePreservesSubstate()
    {
        const auto parsed = MachineProtocolParsers::parseGrblTelemetry(QByteArrayLiteral(
            "<Hold:0|WPos:1.000,2.000,0.000|WCO:0.100,0.200,0.000|FS:25,0>"));
        QVERIFY(parsed);
        QCOMPARE(parsed->state, QStringLiteral("HOLD_0"));
        QVERIFY(parsed->workPosition);
        QVERIFY(parsed->workCoordinateOffset);
        QCOMPARE(parsed->feedRate, 25);
    }

    void lifecycleDerivesOperationAndHomingFromFreshTelemetry()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto module = std::make_unique<ScriptedMachineTransport>(false);
        auto *pressRaw = press.get();
        MachineControlBackend backend(std::move(press), std::move(module));

        QVERIFY(backend.connectPress());
        pressRaw->receive(QByteArrayLiteral("[LS-BEND v1.2]"));
        pressRaw->receive(QByteArrayLiteral(
            "<STARTUP HOMING REQUIRED|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressReady());
        QVERIFY(!backend.pressHomed());
        QVERIFY(!backend.pressOperationActive());

        pressRaw->receive(QByteArrayLiteral(
            "<HOMING|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(!backend.pressHomed());
        QVERIFY(backend.pressOperationActive());

        pressRaw->receive(QByteArrayLiteral(
            "<IDLE|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(backend.pressHomed());
        QVERIFY(!backend.pressOperationActive());

        pressRaw->receive(QByteArrayLiteral(
            "<MAX TONNAGE ERROR|0|0|0|0|0|0|1|1|1|0|0|0|0|0>"));
        QVERIFY(!backend.pressReady());
        QVERIFY(!backend.pressHomed());
        QVERIFY(!backend.pressOperationActive());
    }

    void thcV53RemoteTuneDuringHold()
    {
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw, 2));
        QVERIFY(backend.startContinuousThcContactProfile());
        v53Hold(raw);
        raw->receive(v51ProductionTelemetry());
        const auto id = backend.operationId();
        const auto lease = backend.m_thcV53ClientDeadlineMs;
        QObject context;
        QList<QJsonObject> replies;
        QJsonObject settings = QJsonObject::fromVariantMap(v53Settings(0.3));
        ThcV53RemoteTuning::dispatch(&backend, {{"command", "thc_v53_live_tune"}, {"settings", settings}},
                                     &context, [&replies](const QJsonObject &r) { replies.append(r); });
        QVERIFY(replies.isEmpty());
        QCOMPARE(raw->writeAt(raw->writeCount() - 1),
                 QByteArrayLiteral("<THC:V53:TUNE:1,0.300000,0.020000,0.030000,0.010000,0.010000,0.050000>\n"));
        raw->receive(v53Reply("1", "0.300000", 2));
        QCOMPARE(replies.size(), 1);
        QVERIFY(replies[0].value("ok").toBool());
        QCOMPARE(replies[0].value("thcLiveTuning").toObject().value("kp").toDouble(), 0.3);
        QCOMPARE(replies[0].value("thcLiveTuning").toObject().value("revision").toInt(), 1);
        QVERIFY(replies[0].value("thcContinuousActive").toBool());
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.m_thcV53ClientDeadlineMs, lease); // never renews the panel lease
        raw->receive(v53Reply("1", "0.300000", 2));
        QCOMPARE(replies.size(), 1); // exactly one reply

        replies.clear();
        ThcV53RemoteTuning::dispatch(&backend, {{"command", "thc_v53_live_query"}}, &context,
                                     [&replies](const QJsonObject &r) { replies.append(r); });
        QCOMPARE(raw->writeAt(raw->writeCount() - 1), QByteArrayLiteral("<THC:V53?>\n"));
        raw->receive(v53Reply("1", "0.300000", 2));
        QCOMPARE(replies.size(), 1);
        QVERIFY(replies[0].value("ok").toBool());
        QVERIFY(replies[0].value("thcLiveTuningExtended").toBool());

        replies.clear();
        const auto writes = raw->writeCount();
        ThcV53RemoteTuning::dispatch(&backend, {{"command", "thc_v53_live_status"}}, &context,
                                     [&replies](const QJsonObject &r) { replies.append(r); });
        QCOMPARE(replies.size(), 1);
        QVERIFY(replies[0].value("ok").toBool());
        QCOMPARE(raw->writeCount(), writes);
    }

    void thcV53RemoteTuneRejects_data()
    {
        QTest::addColumn<QString>("request");
        QTest::addColumn<QString>("error");
        QTest::newRow("extra-field") << R"({"command":"thc_v53_live_tune","settings":{"kp":0.3,"ki":0.02,"kd":0.03,"rate":0.01,"cq":0.01,"fs":0.05},"x":1})" << "INVALID_ARGUMENT";
        QTest::newRow("no-settings") << R"({"command":"thc_v53_live_tune"})" << "INVALID_ARGUMENT";
        QTest::newRow("string-value") << R"({"command":"thc_v53_live_tune","settings":{"kp":"0.3","ki":0.02,"kd":0.03,"rate":0.01,"cq":0.01,"fs":0.05}})" << "INVALID_ARGUMENT";
        QTest::newRow("five-keys") << R"({"command":"thc_v53_live_tune","settings":{"kp":0.3,"ki":0.02,"kd":0.03,"rate":0.01,"cq":0.01}})" << "V53_ARGUMENT";
        QTest::newRow("unknown-key") << R"({"command":"thc_v53_live_tune","settings":{"kp":0.3,"ki":0.02,"kd":0.03,"rate":0.01,"cq":0.01,"gain":0.05}})" << "V53_ARGUMENT";
        QTest::newRow("query-extra") << R"({"command":"thc_v53_live_query","x":1})" << "INVALID_ARGUMENT";
        QTest::newRow("not-holding") << R"({"command":"thc_v53_live_tune","settings":{"kp":0.3,"ki":0.02,"kd":0.03,"rate":0.01,"cq":0.01,"fs":0.05}})" << "V53_NOT_HOLDING";
    }

    void thcV53RemoteTuneRejects()
    {
        QFETCH(QString, request);
        QFETCH(QString, error);
        auto press = std::make_unique<ScriptedMachineTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<ScriptedMachineTransport>(false));
        QVERIFY(v53Ready(backend, raw, 2));
        QVERIFY(backend.startContinuousThcContactProfile());
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V53_RUNNING}"));
        if (QTest::currentDataTag() != QByteArray("not-holding")) {
            raw->receive(QByteArrayLiteral("{THC:CONTACT}"));
            raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        }
        raw->receive(v51ProductionTelemetry());
        const auto writes = raw->writeCount();
        QObject context;
        QList<QJsonObject> replies;
        ThcV53RemoteTuning::dispatch(&backend, QJsonDocument::fromJson(request.toUtf8()).object(), &context,
                                     [&replies](const QJsonObject &r) { replies.append(r); });
        QCOMPARE(replies.size(), 1);
        QVERIFY(!replies[0].value("ok").toBool());
        QCOMPARE(replies[0].value("error").toString(), error);
        QCOMPARE(raw->writeCount(), writes);
        QCOMPARE(backend.thcLiveTuning().value("kp").toDouble(), 0.15);
    }
};

QTEST_MAIN(MachineControlBackendTests)
#include "tst_MachineControlBackend.moc"
