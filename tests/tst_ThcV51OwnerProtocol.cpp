#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

#include <functional>
#include <memory>
#include <utility>

#include "MachineControlBackend.h"
#include "MachineTransport.h"
#include "SerialMachineTransport.h"
#include "ThcV51OwnerProtocol.h"

// In-memory fixture only: no serial discovery, ports, sockets or device probes.
class V51OwnerMockTransport final : public MachineTransport
{
public:
    explicit V51OwnerMockTransport(bool available) : m_available(available) {}

    bool isAvailable() const override { return m_available; }
    bool isOpen() const override { return m_open; }
    QString endpointId() const override
    {
        return m_available ? QStringLiteral("mock:v51-owner") : QString();
    }
    QString endpointDisplayName() const override
    {
        return m_available ? QStringLiteral("V51 owner mock") : QString();
    }
    bool open() override
    {
        if (!m_available)
            return false;
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
        m_writes.append(frame);
        // Copy the hook: synchronous replies may replace it reentrantly.
        const auto hook = m_writeHook;
        if (hook)
            hook(frame);
        return true;
    }
    void receive(const QByteArray &frame) { emit frameReceived(frame); }
    const QList<QByteArray> &writes() const { return m_writes; }
    qsizetype count(const QByteArray &frame) const { return m_writes.count(frame); }
    void setWriteHook(std::function<void(const QByteArray &)> hook)
    {
        m_writeHook = std::move(hook);
    }

private:
    bool m_available = false;
    bool m_open = false;
    QList<QByteArray> m_writes;
    std::function<void(const QByteArray &)> m_writeHook;
};

class V51OwnerHomeGuard final
{
public:
    V51OwnerHomeGuard()
        : m_wasSet(qEnvironmentVariableIsSet("BENDCNC_QT_HOME")),
          m_value(qgetenv("BENDCNC_QT_HOME"))
    {
    }
    ~V51OwnerHomeGuard()
    {
        if (m_wasSet)
            qputenv("BENDCNC_QT_HOME", m_value);
        else
            qunsetenv("BENDCNC_QT_HOME");
    }

private:
    bool m_wasSet;
    QByteArray m_value;
};

// Deadline/timer assertions require: friend class ThcV51OwnerProtocolTests;
// in MachineControlBackend. Deliberately no private-public macro or sleeps.
class ThcV51OwnerProtocolTests final : public QObject
{
    Q_OBJECT

    V51OwnerHomeGuard m_homeGuard;
    QTemporaryDir m_home;

    static QString pinnedHash()
    {
        return QStringLiteral("a79f02982fdbec4f08bf494d08c22e05b2bb144d0fa3890b3cd537e4fadccd14");
    }

    static QByteArray productionIdle(const QByteArray &state = QByteArrayLiteral("IDLE"),
                                     const QByteArray &pidOutput = QByteArrayLiteral("-7.25"))
    {
        // Retained PID command at 4; measured velocities/RPM at 15..18;
        // physical pedal at 19. These are independent production fields.
        return '<' + state + "|-0.2|-0.2|0|" + pidOutput
            + "|-0.2|-0.2|1|1|1|0|0|0.4|0.5|0|0|0|0|0|0>";
    }

    static bool ready(MachineControlBackend &backend, V51OwnerMockTransport *raw)
    {
        if (!backend.connectPress())
            return false;
        raw->receive(QByteArrayLiteral("[LS-BEND v1.3]"));
        raw->receive(productionIdle());
        return backend.pressReady() && backend.pressHomed() && backend.pressTelemetryFresh();
    }

    static QJsonObject startRequest()
    {
        return {{QStringLiteral("command"), QStringLiteral("thc_contact_profile_v51")},
                {QStringLiteral("binarySha256"), pinnedHash()}};
    }

    static QJsonObject ownerRequest(const QString &command, qulonglong id)
    {
        return {{QStringLiteral("command"), command},
                {QStringLiteral("operationId"), QString::number(id)}};
    }

    static QJsonObject rejection(const QString &error)
    {
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), error}};
    }

    static void contact(V51OwnerMockTransport *raw)
    {
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        raw->receive(QByteArrayLiteral("{THC:CONTACT}"));
    }

    static void preserveOwnerBudget(MachineControlBackend &backend)
    {
        // Keep unrelated lease checks out of the deterministic phase seam.
        backend.m_thcV51ClientDeadlineMs = backend.m_thcV51Clock.elapsed() + 60000;
    }

    static QString noProgressFailure()
    {
        return QStringLiteral("THC_V51_FIRMWARE_ERROR:{THC:ERROR:V51_NO_PROGRESS}");
    }

    static QByteArray noProgressStopDiagnostic()
    {
        // Embedded reason text is diagnostic evidence, never a CANCELLED ACK.
        return QByteArrayLiteral("[TH_STOP reason={THC:ERROR:V51_NO_PROGRESS} mask=0]");
    }

    static void verifyCancellationDiagnostics(const MachineControlBackend &backend,
                                               const QString &pending, bool confirmed,
                                               bool stopUnconfirmed)
    {
        QCOMPARE(backend.thcV51PendingFailure(), pending);
        QCOMPARE(backend.thcV51CancellationConfirmed(), confirmed);
        QCOMPARE(backend.pressSafetyStopUnconfirmed(), stopUnconfirmed);
    }

    static void verifyOwnerReplyDiagnostics(const MachineControlBackend &backend,
                                            const QJsonObject &reply, const QString &pending,
                                            bool confirmed, bool stopUnconfirmed)
    {
        verifyCancellationDiagnostics(backend, pending, confirmed, stopUnconfirmed);
        QCOMPARE(reply.value(QStringLiteral("operationId")), QJsonValue(QString::number(backend.operationId())));
        QCOMPARE(reply.value(QStringLiteral("operationName")), QJsonValue(backend.operationName()));
        QCOMPARE(reply.value(QStringLiteral("operationState")), QJsonValue(backend.operationState()));
        QCOMPARE(reply.value(QStringLiteral("operationError")), QJsonValue(backend.operationError()));
        QCOMPARE(reply.value(QStringLiteral("thcState")), QJsonValue(backend.thcCommissioningState()));
        QCOMPARE(reply.value(QStringLiteral("thcV51PendingFailure")), QJsonValue(pending));
        QCOMPARE(reply.value(QStringLiteral("thcV51CancellationConfirmed")), QJsonValue(confirmed));
        QCOMPARE(reply.value(QStringLiteral("pressSafetyStopUnconfirmed")), QJsonValue(stopUnconfirmed));
        QCOMPARE(reply.value(QStringLiteral("firmwareImageAttested")), QJsonValue(false));
    }

    static QJsonObject diagnosticSnapshot(const MachineControlBackend &backend)
    {
        return {
            {QStringLiteral("operationId"), QString::number(backend.operationId())},
            {QStringLiteral("operationName"), backend.operationName()},
            {QStringLiteral("operationState"), backend.operationState()},
            {QStringLiteral("operationError"), backend.operationError()},
            {QStringLiteral("thcState"), backend.thcCommissioningState()},
            {QStringLiteral("thcV51PendingFailure"), backend.thcV51PendingFailure()},
            {QStringLiteral("thcV51CancellationConfirmed"), backend.thcV51CancellationConfirmed()},
            {QStringLiteral("pressSafetyStopUnconfirmed"), backend.pressSafetyStopUnconfirmed()},
            {QStringLiteral("commandOperationActive"), backend.commandOperationActive()},
            {QStringLiteral("pressOperationActive"), backend.pressOperationActive()}
        };
    }

    static QJsonObject unconfirmedNoProgressSnapshot(qulonglong id)
    {
        return {
            {QStringLiteral("operationId"), QString::number(id)},
            {QStringLiteral("operationName"), QStringLiteral("thc-contact-profile-v51")},
            {QStringLiteral("operationState"), QStringLiteral("FAILED")},
            {QStringLiteral("operationError"), noProgressFailure() + QStringLiteral("_CANCEL_CONFIRMATION_TIMEOUT")},
            {QStringLiteral("thcState"), QStringLiteral("FAILED_STOP_UNCONFIRMED")},
            {QStringLiteral("thcV51PendingFailure"), QString()},
            {QStringLiteral("thcV51CancellationConfirmed"), false},
            {QStringLiteral("pressSafetyStopUnconfirmed"), true},
            {QStringLiteral("commandOperationActive"), false},
            {QStringLiteral("pressOperationActive"), false}
        };
    }

    static void replayNoProgressCancellation(MachineControlBackend &backend,
                                             V51OwnerMockTransport *raw)
    {
        const auto id = backend.operationId();
        const auto before = raw->writes().size();
        raw->receive(QByteArrayLiteral("{THC:ERROR:V51_NO_PROGRESS}"));
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<THC:CANCEL>\n"));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        QCOMPARE(backend.operationError(), QString());
        QCOMPARE(backend.thcCommissioningState(), QStringLiteral("CANCELLING"));
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::AwaitCancel);
        verifyCancellationDiagnostics(backend, noProgressFailure(), false, true);
        const auto deadline = backend.m_thcV51PhaseDeadlineMs;
        const auto sequence = backend.pressTelemetrySequence();
        raw->receive(QByteArrayLiteral("{THC:ERROR:NOT_ACTIVE}"));
        raw->receive(noProgressStopDiagnostic());
        raw->receive(productionIdle());
        QCOMPARE(backend.pressTelemetrySequence(), sequence + 1);
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::AwaitCancel);
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, deadline);
        QVERIFY(!backend.m_thcV51CancelAcknowledged);
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.pressOperationActive());
        QCOMPARE(backend.operationError(), QString());
        QCOMPARE(backend.thcCommissioningState(), QStringLiteral("CANCELLING"));
        verifyCancellationDiagnostics(backend, noProgressFailure(), false, true);
        QCOMPARE(raw->writes().size(), before + 1);
    }

    static void verifyTerminalTimersStopped(const MachineControlBackend &backend)
    {
        QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV51ClientLeaseTimer.isActive());
        QVERIFY(!backend.m_thcV51PhaseTimer.isActive());
        QVERIFY(!backend.m_thcV51OverallTimer.isActive());
        QVERIFY(!backend.m_thcV51Clock.isValid());
    }

    static void verifyArmingCancellation(bool lifecycleSignal)
    {
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        const auto before = raw->writes().size();
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        bool callbackEntered = false;
        QJsonObject cancelResponse;
        const auto cancelWhenArming = [&] {
            if (callbackEntered
                || backend.m_thcV51Phase != MachineControlBackend::ThcV51Phase::AwaitStart
                || backend.thcCommissioningState() != QStringLiteral("CONTACT_PROFILE_V51_ARMING"))
                return;
            callbackEntered = true; // Set before cancellation emits another signal.
            cancelResponse = ThcV51OwnerProtocol::dispatch(&backend,
                ownerRequest(QStringLiteral("thc_v51_cancel"), backend.operationId()));
        };
        if (lifecycleSignal)
            QObject::connect(&backend, &MachineControlBackend::commandLifecycleChanged,
                             &backend, cancelWhenArming, Qt::DirectConnection);
        else
            QObject::connect(&backend, &MachineControlBackend::pressStateChanged,
                             &backend, cancelWhenArming, Qt::DirectConnection);

        const auto response = ThcV51OwnerProtocol::dispatch(&backend, startRequest());
        QVERIFY(callbackEntered);
        QCOMPARE(cancelResponse.value(QStringLiteral("ok")), QJsonValue(true));
        QCOMPARE(response.value(QStringLiteral("ok")), QJsonValue(false));
        QCOMPARE(response.value(QStringLiteral("error")),
                 QJsonValue(QStringLiteral("BACKEND_GUARD_OR_DISPATCH_FAILED")));
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<THC:CANCEL>\n"));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CONTACT_PROFILE_V51>\n")), qsizetype(0));
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::AwaitCancel);
        QCOMPARE(backend.operationName(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        QVERIFY(backend.commandOperationActive());
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV51ClientLeaseTimer.isActive());
        QVERIFY(!backend.m_thcV51OverallTimer.isActive());
        QCOMPARE(finished.count(), 0);
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        raw->receive(productionIdle());
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(finished.count(), 1);
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        verifyTerminalTimersStopped(backend);
    }

private slots:
    void initTestCase()
    {
        QVERIFY(m_home.isValid());
        QVERIFY(qputenv("BENDCNC_QT_HOME", m_home.path().toLocal8Bit()));
    }

    void capabilityMatchesSealedFixture()
    {
        // Independent sealed contract, not an expectation derived from capability().
        const QByteArray sealed = R"json({
            "type":"bounded-contact-profile-v51",
            "ownerCommand":"thc_contact_profile_v51",
            "firmwareCommand":"THC:CONTACT_PROFILE_V51",
            "runningMarker":"THC:CONTACT_PROFILE_V51_RUNNING",
            "acquisitionMaxMs":180000,
            "holdMs":60000,
            "operationMaxMs":330000,
            "thcLeaseMs":2000,
            "thcHeartbeatCommand":"THC:HB",
            "thcHeartbeatIntervalMs":250,
            "generalHeartbeatSeparate":true,
            "generalHeartbeatCommand":"?",
            "generalHeartbeatTimeoutMs":30000,
            "generalHeartbeatIntervalMs":250,
            "ordinaryContactProfileMaxMs":60000,
            "fallbackAllowed":false
        })json";
        QJsonParseError error;
        const auto expected = QJsonDocument::fromJson(sealed, &error);
        QCOMPARE(error.error, QJsonParseError::NoError);
        QVERIFY(expected.isObject());
        QCOMPARE(ThcV51OwnerProtocol::capability(), expected.object());
        QCOMPARE(ThcV51OwnerProtocol::capability().size(), 16);
        QVERIFY(!ThcV51OwnerProtocol::capability().contains(QStringLiteral("firmwareImageAttested")));
    }

    void handlesOnlyExactOwnerCommands_data()
    {
        QTest::addColumn<QString>("command");
        QTest::addColumn<bool>("handled");
        for (const char *command : {"thc_contact_profile_v51", "thc_v51_heartbeat",
                                    "thc_v51_release", "thc_v51_cancel"})
            QTest::newRow(command) << QString::fromLatin1(command) << true;
        for (const char *command : {"", "THC_CONTACT_PROFILE_V51", "thc_contact_profile_v51 ",
                                    "thc_contact_profile_v51\n", "thc_contact_profile_v51_extra",
                                    "thc_contact_profile", "thc_contact_profile_auto", "thc_heartbeat",
                                    "thc_release", "thc_cancel", "thc_v51_cancel\n"})
            QTest::newRow(command[0] ? command : "empty") << QString::fromLatin1(command) << false;
    }

    void handlesOnlyExactOwnerCommands()
    {
        QFETCH(QString, command);
        QFETCH(bool, handled);
        QCOMPARE(ThcV51OwnerProtocol::handles(command), handled);
    }

    void startRejectsNonExactJson_data()
    {
        QTest::addColumn<QString>("variant");
        for (const char *variant : {"missing-command", "missing-hash", "empty-request",
                                    "extra-field", "operation-id-instead", "hash-null", "hash-number",
                                    "hash-bool", "hash-array", "hash-object", "command-null",
                                    "command-number", "command-bool", "command-array", "command-object",
                                    "command-uppercase", "command-suffix", "command-newline"})
            QTest::newRow(variant) << QString::fromLatin1(variant);
    }

    void startRejectsNonExactJson()
    {
        QFETCH(QString, variant);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        auto request = startRequest();
        if (variant == "missing-command") request.remove(QStringLiteral("command"));
        if (variant == "missing-hash") request.remove(QStringLiteral("binarySha256"));
        if (variant == "empty-request") request = QJsonObject();
        if (variant == "extra-field") request.insert(QStringLiteral("fallbackAllowed"), false);
        if (variant == "operation-id-instead") {
            request.remove(QStringLiteral("binarySha256"));
            request.insert(QStringLiteral("operationId"), QStringLiteral("1"));
        }
        const auto wrongType = [](const QString &type) -> QJsonValue {
            if (type == "null") return QJsonValue(QJsonValue::Null);
            if (type == "number") return QJsonValue(51);
            if (type == "bool") return QJsonValue(true);
            if (type == "array") return QJsonValue(QJsonArray());
            return QJsonValue(QJsonObject());
        };
        if (variant.startsWith("hash-"))
            request.insert(QStringLiteral("binarySha256"), wrongType(variant.mid(5)));
        if (variant.startsWith("command-")) {
            const auto type = variant.mid(8);
            if (type == "uppercase") request.insert(QStringLiteral("command"), QStringLiteral("THC_CONTACT_PROFILE_V51"));
            else if (type == "suffix") request.insert(QStringLiteral("command"), QStringLiteral("thc_contact_profile_v51_extra"));
            else if (type == "newline") request.insert(QStringLiteral("command"), QStringLiteral("thc_contact_profile_v51\n"));
            else request.insert(QStringLiteral("command"), wrongType(type));
        }
        const auto before = raw->writes().size();
        const auto id = backend.operationId();
        QSignalSpy lifecycle(&backend, &MachineControlBackend::commandLifecycleChanged);
        QCOMPARE(ThcV51OwnerProtocol::dispatch(&backend, request), rejection(QStringLiteral("INVALID_ARGUMENT")));
        QCOMPARE(raw->writes().size(), before);
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(lifecycle.count(), 0);
        QVERIFY(!backend.commandOperationActive());
    }

    void startRequiresExactPinnedBinary_data()
    {
        QTest::addColumn<QString>("hash");
        QTest::newRow("empty") << QString();
        QTest::newRow("different-pin") << QString(64, QLatin1Char('0'));
        QTest::newRow("uppercase") << pinnedHash().toUpper();
        QTest::newRow("leading-space") << (QLatin1Char(' ') + pinnedHash());
        QTest::newRow("trailing-space") << (pinnedHash() + QLatin1Char(' '));
        QTest::newRow("newline") << (pinnedHash() + QLatin1Char('\n'));
        QTest::newRow("truncated") << pinnedHash().left(63);
    }

    void startRequiresExactPinnedBinary()
    {
        QFETCH(QString, hash);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        auto request = startRequest();
        request.insert(QStringLiteral("binarySha256"), hash);
        const auto before = raw->writes().size();
        const auto response = ThcV51OwnerProtocol::dispatch(&backend, request);
        QCOMPARE(response.value(QStringLiteral("ok")), QJsonValue(false));
        QCOMPARE(response.value(QStringLiteral("error")),
                 QJsonValue(QStringLiteral("BACKEND_GUARD_OR_DISPATCH_FAILED")));
        QCOMPARE(response.value(QStringLiteral("firmwareImageAttested")), QJsonValue(false));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("INVALID_ARGUMENT"));
        QCOMPARE(raw->writes().size(), before);
        QVERIFY(!backend.commandOperationActive());
    }

    void startOkMeansDispatchNotRunningAcknowledgement()
    {
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(!backend.thcV51RunningAcknowledged()); // v1.3 banner is not V51 attestation.
        QCOMPARE(startRequest().size(), 2);
        const auto before = raw->writes().size();
        const auto response = ThcV51OwnerProtocol::dispatch(&backend, startRequest());
        const QJsonObject expected{
            {QStringLiteral("ok"), true},
            {QStringLiteral("operationId"), QString::number(backend.operationId())},
            {QStringLiteral("operationName"), QStringLiteral("thc-contact-profile-v51")},
            {QStringLiteral("operationState"), QStringLiteral("SENT")},
            {QStringLiteral("operationError"), QString()},
            {QStringLiteral("thcState"), QStringLiteral("CONTACT_PROFILE_V51_ARMING")},
            {QStringLiteral("thcV51RunningAcknowledged"), false},
            {QStringLiteral("pressSafetyStopUnconfirmed"), false},
            {QStringLiteral("thcV51PendingFailure"), QString()},
            {QStringLiteral("thcV51CancellationConfirmed"), false},
            {QStringLiteral("firmwareImageAttested"), false}
        };
        QCOMPARE(response, expected);
        verifyOwnerReplyDiagnostics(backend, response, QString(), false, false);
        QVERIFY(backend.operationId() > 0);
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<THC:CONTACT_PROFILE_V51>\n"));
        QVERIFY(!backend.thcV51RunningAcknowledged());
        raw->receive(productionIdle());
        QVERIFY(backend.commandOperationActive());
        QVERIFY(!backend.thcV51RunningAcknowledged());
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        QVERIFY(backend.thcV51RunningAcknowledged());
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        const auto renewed = ThcV51OwnerProtocol::dispatch(&backend,
            ownerRequest(QStringLiteral("thc_v51_heartbeat"), backend.operationId()));
        QCOMPARE(renewed.value(QStringLiteral("ok")), QJsonValue(true));
        QCOMPARE(renewed.value(QStringLiteral("thcV51RunningAcknowledged")), QJsonValue(true));
        QCOMPARE(renewed.value(QStringLiteral("firmwareImageAttested")), QJsonValue(false));
        verifyOwnerReplyDiagnostics(backend, renewed, QString(), false, false);
        QCOMPARE(response.value(QStringLiteral("thcV51RunningAcknowledged")), QJsonValue(false));
    }

    void runningAcknowledgementRequiresExactFrame_data()
    {
        QTest::addColumn<QByteArray>("frame");
        QTest::addColumn<bool>("accepted");
        QTest::newRow("exact") << QByteArray("{THC:CONTACT_PROFILE_V51_RUNNING}") << true;
        for (const QByteArray &frame : {QByteArray("{THC:CONTACT_PROFILE_RUNNING}"),
                QByteArray("{thc:contact_profile_v51_running}"),
                QByteArray(" {THC:CONTACT_PROFILE_V51_RUNNING}"),
                QByteArray("{THC:CONTACT_PROFILE_V51_RUNNING} "),
                QByteArray("{THC:CONTACT_PROFILE_V51_RUNNING}\n"),
                QByteArray("{THC:CONTACT_PROFILE_V51_RUNNING}\r\n"),
                QByteArray("{THC:CONTACT_PROFILE_V51_RUNNING_EXTRA}"),
                QByteArray("{THC: CONTACT_PROFILE_V51_RUNNING}"), QByteArray("{THC:RUNNING}"),
                QByteArray("{THC:ARMED}"), QByteArray("{THC:CONTACT}"),
                QByteArray("{THC:HOLDING}"), QByteArray("{THC:RELEASING}"),
                QByteArray("{THC:DONE}"), QByteArray("{TH:DONE}"), QByteArray("{THC:CANCELLED}")})
            QTest::newRow(frame.constData()) << frame << false;
    }

    void runningAcknowledgementRequiresExactFrame()
    {
        QFETCH(QByteArray, frame);
        QFETCH(bool, accepted);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        const auto id = backend.operationId();
        raw->receive(frame);
        QCOMPARE(backend.thcV51RunningAcknowledged(), accepted);
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(accepted ? 0 : 1));
        QVERIFY(backend.commandOperationActive());
        if (accepted)
            QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        else {
            QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::AwaitCancel);
            QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
        }
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CONTACT_PROFILE>\n")), qsizetype(0));
    }

    void ownerRequestsRequireExactCorrelation_data()
    {
        QTest::addColumn<QString>("command");
        QTest::addColumn<QString>("variant");
        for (const char *command : {"thc_v51_heartbeat", "thc_v51_release", "thc_v51_cancel"}) {
            for (const char *variant : {"mismatch", "negative", "leading-zero", "space", "newline", "empty",
                                        "number", "null", "bool", "array", "object", "missing", "extra"}) {
                const QByteArray row = QByteArray(command) + '-' + variant;
                QTest::newRow(row.constData()) << QString::fromLatin1(command) << QString::fromLatin1(variant);
            }
        }
    }

    void ownerRequestsRequireExactCorrelation()
    {
        QFETCH(QString, command);
        QFETCH(QString, variant);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw); // Even an otherwise release-admissible cycle requires correlation.
        const auto id = backend.operationId();
        auto request = ownerRequest(command, id);
        const auto key = QStringLiteral("operationId");
        if (variant == "mismatch") request.insert(key, QString::number(id + 1));
        if (variant == "negative") request.insert(key, QLatin1Char('-') + QString::number(id));
        if (variant == "leading-zero") request.insert(key, QLatin1Char('0') + QString::number(id));
        if (variant == "space") request.insert(key, QString::number(id) + QLatin1Char(' '));
        if (variant == "newline") request.insert(key, QString::number(id) + QLatin1Char('\n'));
        if (variant == "empty") request.insert(key, QString());
        if (variant == "number") request.insert(key, double(id));
        if (variant == "null") request.insert(key, QJsonValue(QJsonValue::Null));
        if (variant == "bool") request.insert(key, true);
        if (variant == "array") request.insert(key, QJsonArray());
        if (variant == "object") request.insert(key, QJsonObject());
        if (variant == "missing") request.remove(key);
        if (variant == "extra") request.insert(QStringLiteral("binarySha256"), pinnedHash());
        const bool invalidJson = variant == "number" || variant == "null" || variant == "bool"
            || variant == "array" || variant == "object" || variant == "missing" || variant == "extra";
        const auto before = raw->writes().size();
        const auto client = backend.m_thcV51ClientDeadlineMs;
        const auto phase = backend.m_thcV51PhaseDeadlineMs;
        QSignalSpy lifecycle(&backend, &MachineControlBackend::commandLifecycleChanged);
        QCOMPARE(ThcV51OwnerProtocol::dispatch(&backend, request),
                 rejection(invalidJson ? QStringLiteral("INVALID_ARGUMENT") : QStringLiteral("V51_OWNER_MISMATCH")));
        QCOMPARE(raw->writes().size(), before);
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        QCOMPARE(backend.m_thcV51ClientDeadlineMs, client);
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, phase);
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::Acquisition);
        QCOMPARE(lifecycle.count(), 0);
        QVERIFY(backend.thcV51RunningAcknowledged());
    }

    void ownerRequestsRejectLegacyOperation_data()
    {
        QTest::addColumn<QString>("command");
        for (const char *command : {"thc_v51_heartbeat", "thc_v51_release", "thc_v51_cancel"})
            QTest::newRow(command) << QString::fromLatin1(command);
    }

    void ownerRequestsRejectLegacyOperation()
    {
        QFETCH(QString, command);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(backend.startAutomaticThcContactProfile());
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_RUNNING}"));
        // A legacy failure remnant must never be advertised as a V51 owner failure.
        backend.m_pendingThcFailure = QStringLiteral("LEGACY_PENDING_FAILURE");
        verifyCancellationDiagnostics(backend, QString(), false, false);
        const auto id = backend.operationId();
        const auto state = backend.operationState();
        const auto before = raw->writes().size();
        QVERIFY(backend.commandOperationActive());
        QCOMPARE(ThcV51OwnerProtocol::dispatch(&backend, ownerRequest(command, id)),
                 rejection(QStringLiteral("V51_OWNER_MISMATCH")));
        QCOMPARE(raw->writes().size(), before);
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationName(), QStringLiteral("automatic-thc-contact-profile"));
        QCOMPARE(backend.operationState(), state);
        QVERIFY(!backend.thcV51RunningAcknowledged());
        verifyCancellationDiagnostics(backend, QString(), false, false);
    }

    void ownerHeartbeatRenewsLeaseWithoutSerialDispatch()
    {
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        preserveOwnerBudget(backend);
        const auto oldClient = backend.m_thcV51ClientDeadlineMs;
        const auto phase = backend.m_thcV51PhaseDeadlineMs;
        const auto overall = backend.m_thcV51OverallDeadlineMs;
        const auto beforeWrites = raw->writes().size();
        const auto before = backend.m_thcV51Clock.elapsed();
        const auto response = ThcV51OwnerProtocol::dispatch(&backend,
            ownerRequest(QStringLiteral("thc_v51_heartbeat"), backend.operationId()));
        const auto after = backend.m_thcV51Clock.elapsed();
        QCOMPARE(response.value(QStringLiteral("ok")), QJsonValue(true));
        QCOMPARE(response.value(QStringLiteral("thcV51RunningAcknowledged")), QJsonValue(true));
        QCOMPARE(response.value(QStringLiteral("firmwareImageAttested")), QJsonValue(false));
        QCOMPARE(raw->writes().size(), beforeWrites);
        QVERIFY(backend.m_thcV51ClientDeadlineMs >= before + 2000);
        QVERIFY(backend.m_thcV51ClientDeadlineMs <= after + 2000);
        QVERIFY(backend.m_thcV51ClientDeadlineMs < oldClient);
        QCOMPARE(backend.m_thcV51ClientLeaseTimer.interval(), 2000);
        QVERIFY(backend.m_thcV51ClientLeaseTimer.isActive());
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, phase);
        QCOMPARE(backend.m_thcV51OverallDeadlineMs, overall);
    }

    void dualHeartbeatDoesNotRenewOwnerOrPhase()
    {
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        preserveOwnerBudget(backend);
        const auto client = backend.m_thcV51ClientDeadlineMs;
        const auto phase = backend.m_thcV51PhaseDeadlineMs;
        const auto overall = backend.m_thcV51OverallDeadlineMs;
        QCOMPARE(backend.m_thcV51HeartbeatTimer.interval(), 250);
        QVERIFY(backend.m_thcV51HeartbeatTimer.isActive());
        const auto before = raw->writes().size();
        for (int n = 0; n < 3; ++n) {
            QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51HeartbeatTimer, "timeout", Qt::DirectConnection));
            QCOMPARE(raw->writes().size(), before + (n + 1) * 2);
            QCOMPARE(raw->writes().at(before + n * 2), QByteArrayLiteral("<THC:HB>\n"));
            QCOMPARE(raw->writes().at(before + n * 2 + 1), QByteArrayLiteral("<?>\n"));
            raw->receive(QByteArrayLiteral("{THC:HB}"));
            QCOMPARE(backend.m_thcV51ClientDeadlineMs, client);
            QCOMPARE(backend.m_thcV51PhaseDeadlineMs, phase);
            QCOMPARE(backend.m_thcV51OverallDeadlineMs, overall);
            QVERIFY(!backend.thcV51RunningAcknowledged());
        }
        QCOMPARE(raw->writes().size(), before + 6);
    }

    void ownerReleaseDispatchRequiresCorrelatedAcquisition()
    {
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        const auto id = backend.operationId();
        const auto before = raw->writes().size();
        const auto request = ownerRequest(QStringLiteral("thc_v51_release"), id);
        QCOMPARE(ThcV51OwnerProtocol::dispatch(&backend, request).value(QStringLiteral("ok")), QJsonValue(false));
        QCOMPARE(raw->writes().size(), before); // Correct owner, but not CONTACT yet.
        contact(raw);
        const auto response = ThcV51OwnerProtocol::dispatch(&backend, request);
        QCOMPARE(response.value(QStringLiteral("ok")), QJsonValue(true));
        QCOMPARE(response.value(QStringLiteral("operationId")), QJsonValue(QString::number(id)));
        QCOMPARE(response.value(QStringLiteral("thcState")), QJsonValue(QStringLiteral("RELEASE_PENDING")));
        QCOMPARE(response.value(QStringLiteral("firmwareImageAttested")), QJsonValue(false));
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<THC:RELEASE>\n"));
        QVERIFY(backend.commandOperationActive()); // ok is not DONE or physical completion.
    }

    void terminalEvidenceMustBeFreshAndPreserveRetainedPid_data()
    {
        QTest::addColumn<bool>("cancelled");
        QTest::newRow("owner-cancel") << true;
        QTest::newRow("owner-release") << false;
    }

    void terminalEvidenceMustBeFreshAndPreserveRetainedPid()
    {
        QFETCH(bool, cancelled);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        preserveOwnerBudget(backend);
        const auto id = backend.operationId();
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        const auto response = ThcV51OwnerProtocol::dispatch(&backend,
            ownerRequest(cancelled ? QStringLiteral("thc_v51_cancel") : QStringLiteral("thc_v51_release"), id));
        QCOMPARE(response.value(QStringLiteral("ok")), QJsonValue(true));
        QCOMPARE(response.value(QStringLiteral("firmwareImageAttested")), QJsonValue(false));
        verifyOwnerReplyDiagnostics(backend, response,
            cancelled ? QStringLiteral("THC_V51_CANCEL_REQUESTED") : QString(), false, cancelled);
        if (!cancelled)
            raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        const auto idle = productionIdle();
        QCOMPARE(idle.count('|'), 19);
        raw->receive(idle); // Pre-terminal IDLE alone cannot finish ownership.
        QVERIFY(backend.commandOperationActive());
        QVERIFY(!backend.thcV51CancellationConfirmed());
        if (cancelled) {
            for (const QByteArray &malformed : {QByteArray("{thc:cancelled}"),
                    QByteArray(" {THC:CANCELLED}"), QByteArray("{THC:CANCELLED} "),
                    QByteArray("{THC:CANCELLED}\n"), QByteArray("{THC:CANCELLED}\r\n"),
                    QByteArray("{THC: CANCELLED}"), QByteArray("{THC:CANCELLED_EXTRA}"),
                    QByteArray("{TH:CANCELLED}"), QByteArray("{THC:DONE}")}) {
                raw->receive(malformed);
                raw->receive(idle);
                QVERIFY(!backend.m_thcV51CancelAcknowledged);
                QVERIFY(backend.commandOperationActive());
                verifyCancellationDiagnostics(backend, QStringLiteral("THC_V51_CANCEL_REQUESTED"), false, true);
            }
        }
        const auto sequence = backend.pressTelemetrySequence();
        const auto marker = cancelled ? QByteArrayLiteral("{THC:CANCELLED}") : QByteArrayLiteral("{THC:DONE}");
        raw->receive(marker);
        raw->receive(marker);
        QCOMPARE(backend.m_thcV51TerminalTelemetrySequence, sequence);
        QVERIFY(!backend.thcV51CancellationConfirmed());
        backend.handleThcV51Telemetry(true); // Cached IDLE is not a subsequent frame.
        QVERIFY(backend.commandOperationActive());
        QVERIFY(!backend.thcV51CancellationConfirmed());
        raw->receive(productionIdle(QByteArrayLiteral("IDLE"), QByteArrayLiteral("nan")));
        QCOMPARE(backend.pressTelemetrySequence(), sequence);
        QVERIFY(backend.commandOperationActive());
        QVERIFY(!backend.thcV51CancellationConfirmed());
        for (const QByteArray &state : {QByteArray("idle"), QByteArray(" IDLE"), QByteArray("IDLE ")}) {
            raw->receive(productionIdle(state));
            QVERIFY(backend.commandOperationActive());
            QVERIFY(!backend.thcV51CancellationConfirmed());
        }
        if (cancelled) {
            auto fields = idle.split('|');
            fields[15] = QByteArrayLiteral("nan");
            const auto beforeMalformed = backend.pressTelemetrySequence();
            raw->receive(fields.join('|'));
            QCOMPARE(backend.pressTelemetrySequence(), beforeMalformed);
            verifyCancellationDiagnostics(backend, QStringLiteral("THC_V51_CANCEL_REQUESTED"), false, true);
            fields = idle.split('|');
            fields[14] = QByteArrayLiteral("1");
            raw->receive(fields.join('|')); // A fresh IDLE with anti-bind is not stop proof.
            QVERIFY(backend.antiBind());
            QVERIFY(backend.commandOperationActive());
            verifyCancellationDiagnostics(backend, QStringLiteral("THC_V51_CANCEL_REQUESTED"), false, true);
            // Isolate freshness from anti-bind: every other confirmation guard
            // now passes, so cached stale telemetry alone must remain insufficient.
            backend.m_antiBind = false;
            backend.m_pressTelemetryFresh = false;
            backend.handleThcV51Telemetry(true, backend.m_pressFrameArrival);
            QVERIFY(backend.commandOperationActive());
            verifyCancellationDiagnostics(backend, QStringLiteral("THC_V51_CANCEL_REQUESTED"), false, true);
        }
        QCOMPARE(finished.count(), 0);
        int terminalLifecycleCalls = 0;
        QString presentationAtLifecycle;
        QString pendingAtLifecycle;
        bool proofAtLifecycle = false;
        bool latchAtLifecycle = true;
        const auto connection = QObject::connect(&backend, &MachineControlBackend::commandLifecycleChanged,
            &backend, [&] {
                if (backend.operationId() != id || backend.commandOperationActive())
                    return;
                ++terminalLifecycleCalls;
                presentationAtLifecycle = backend.thcCommissioningState();
                pendingAtLifecycle = backend.thcV51PendingFailure();
                proofAtLifecycle = backend.thcV51CancellationConfirmed();
                latchAtLifecycle = backend.pressSafetyStopUnconfirmed();
            }, Qt::DirectConnection);
        raw->receive(idle);
        QObject::disconnect(connection);
        QCOMPARE(terminalLifecycleCalls, 1);
        QCOMPARE(presentationAtLifecycle, cancelled ? QStringLiteral("FAILED") : QStringLiteral("DONE"));
        QCOMPARE(pendingAtLifecycle, QString());
        QCOMPARE(proofAtLifecycle, cancelled);
        QVERIFY(!latchAtLifecycle);
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationState(), cancelled ? QStringLiteral("FAILED") : QStringLiteral("COMPLETED"));
        QCOMPARE(backend.operationError(), cancelled ? QStringLiteral("THC_V51_CANCEL_REQUESTED") : QString());
        verifyCancellationDiagnostics(backend, QString(), cancelled, false);
        QCOMPARE(backend.ramVelocity(), -7.25);
        QVERIFY(backend.measuredRamVelocityAvailable());
        QCOMPARE(backend.measuredRamVelocity(), 0.0);
        QVERIFY(backend.physicalPedalAvailable());
        QVERIFY(!backend.commandOperationActive());
        QVERIFY(!backend.pressOperationActive());
        QVERIFY(!backend.m_pressSafetyStopUnconfirmed);
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.at(0).at(0).toULongLong(), id);
        QCOMPARE(finished.at(0).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(finished.at(0).at(3).toString(), backend.operationState());
        QCOMPARE(finished.at(0).at(4).toString(), backend.operationError());
        verifyTerminalTimersStopped(backend);
        const auto before = raw->writes().size();
        QCOMPARE(ThcV51OwnerProtocol::dispatch(&backend,
            ownerRequest(QStringLiteral("thc_v51_heartbeat"), id)), rejection(QStringLiteral("V51_OWNER_MISMATCH")));
        QCOMPARE(raw->writes().size(), before);
    }

    void firmwareNoProgressCancellationTimeoutPublishesTerminalDiagnostics()
    {
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        verifyCancellationDiagnostics(backend, QString(), false, false);
        const auto started = ThcV51OwnerProtocol::dispatch(&backend, startRequest());
        QCOMPARE(started.value(QStringLiteral("ok")), QJsonValue(true));
        verifyOwnerReplyDiagnostics(backend, started, QString(), false, false);
        contact(raw);
        preserveOwnerBudget(backend);
        const auto id = backend.operationId();
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        int terminalLifecycleCalls = 0;
        int terminalFinishedCalls = 0;
        QJsonObject lifecycleSnapshot;
        QJsonObject finishedSnapshot;
        QObject::connect(&backend, &MachineControlBackend::commandLifecycleChanged, &backend, [&] {
            if (backend.operationId() != id || backend.operationState() != QStringLiteral("FAILED"))
                return;
            ++terminalLifecycleCalls;
            lifecycleSnapshot = diagnosticSnapshot(backend);
        }, Qt::DirectConnection);
        QObject::connect(&backend, &MachineControlBackend::commandOperationFinished, &backend,
            [&](qulonglong finishedId, const QString &, const QString &, const QString &, const QString &) {
                if (finishedId != id)
                    return;
                ++terminalFinishedCalls;
                finishedSnapshot = diagnosticSnapshot(backend);
            }, Qt::DirectConnection);

        replayNoProgressCancellation(backend, raw);
        QCOMPARE(finished.count(), 0);
        const auto before = raw->writes().size();
        const auto deadline = backend.m_thcV51PhaseDeadlineMs;
        const auto pendingReply = ThcV51OwnerProtocol::dispatch(&backend,
            ownerRequest(QStringLiteral("thc_v51_cancel"), id));
        QCOMPARE(pendingReply.value(QStringLiteral("ok")), QJsonValue(true));
        verifyOwnerReplyDiagnostics(backend, pendingReply, noProgressFailure(), false, true);
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, deadline);
        QCOMPARE(raw->writes().size(), before);

        backend.m_thcV51PhaseDeadlineMs = 0; // Deterministic expiry, no sleeps or event-loop wait.
        QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51PhaseTimer, "timeout", Qt::DirectConnection));
        QCOMPARE(terminalLifecycleCalls, 1);
        QCOMPARE(terminalFinishedCalls, 1);
        QCOMPARE(lifecycleSnapshot, unconfirmedNoProgressSnapshot(id));
        QCOMPARE(finishedSnapshot, unconfirmedNoProgressSnapshot(id));
        QCOMPARE(diagnosticSnapshot(backend), unconfirmedNoProgressSnapshot(id));
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.at(0).at(0).toULongLong(), id);
        QCOMPARE(finished.at(0).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(finished.at(0).at(3).toString(), QStringLiteral("FAILED"));
        QCOMPARE(finished.at(0).at(4).toString(),
                 noProgressFailure() + QStringLiteral("_CANCEL_CONFIRMATION_TIMEOUT"));
        verifyTerminalTimersStopped(backend);

        // Late exact evidence cannot retroactively certify a timed-out owner.
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        raw->receive(productionIdle());
        QCOMPARE(diagnosticSnapshot(backend), unconfirmedNoProgressSnapshot(id));
        QCOMPARE(finished.count(), 1);
        QCOMPARE(raw->writes().size(), before);
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
    }

    void repeatedCancellationCannotRenewDeadlinesOrDispatch()
    {
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        preserveOwnerBudget(backend);
        replayNoProgressCancellation(backend, raw);
        const auto id = backend.operationId();
        const auto before = raw->writes().size();
        // Distinct sentinel budgets expose any reset without needing elapsed wall time.
        backend.m_thcV51PhaseDeadlineMs = backend.m_thcV51Clock.elapsed() + 60000;
        backend.m_thcV51PhaseTimer.start(60000);
        const auto phase = backend.m_thcV51PhaseDeadlineMs;
        const auto client = backend.m_thcV51ClientDeadlineMs;
        const auto overall = backend.m_thcV51OverallDeadlineMs;
        const auto release = backend.m_thcV51ReleaseDeadlineMs;
        const auto epoch = backend.m_thcV51Clock.msecsSinceReference();
        QSignalSpy lifecycle(&backend, &MachineControlBackend::commandLifecycleChanged);
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        for (int n = 0; n < 3; ++n) {
            const auto cancelled = ThcV51OwnerProtocol::dispatch(&backend,
                ownerRequest(QStringLiteral("thc_v51_cancel"), id));
            QCOMPARE(cancelled.value(QStringLiteral("ok")), QJsonValue(true));
            verifyOwnerReplyDiagnostics(backend, cancelled, noProgressFailure(), false, true);
            for (const char *command : {"thc_v51_heartbeat", "thc_v51_release"}) {
                const auto rejected = ThcV51OwnerProtocol::dispatch(&backend,
                    ownerRequest(QString::fromLatin1(command), id));
                QCOMPARE(rejected.value(QStringLiteral("ok")), QJsonValue(false));
                QCOMPARE(rejected.value(QStringLiteral("error")),
                         QJsonValue(QStringLiteral("BACKEND_GUARD_OR_DISPATCH_FAILED")));
                verifyOwnerReplyDiagnostics(backend, rejected, noProgressFailure(), false, true);
            }
            QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51HeartbeatTimer, "timeout", Qt::DirectConnection));
            QCOMPARE(backend.m_thcV51PhaseDeadlineMs, phase);
            QCOMPARE(backend.m_thcV51ClientDeadlineMs, client);
            QCOMPARE(backend.m_thcV51OverallDeadlineMs, overall);
            QCOMPARE(backend.m_thcV51ReleaseDeadlineMs, release);
            QCOMPARE(backend.m_thcV51Clock.msecsSinceReference(), epoch);
            QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::AwaitCancel);
            QVERIFY(backend.m_thcV51PhaseTimer.isActive());
            QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
            QVERIFY(!backend.m_thcV51ClientLeaseTimer.isActive());
            QVERIFY(!backend.m_thcV51OverallTimer.isActive());
            QCOMPARE(raw->writes().size(), before);
        }
        for (const char *command : {"thc_v51_cancel", "thc_v51_heartbeat", "thc_v51_release"})
            QCOMPARE(ThcV51OwnerProtocol::dispatch(&backend,
                ownerRequest(QString::fromLatin1(command), id + 1)), rejection(QStringLiteral("V51_OWNER_MISMATCH")));
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, phase);
        QCOMPARE(backend.m_thcV51ClientDeadlineMs, client);
        QCOMPARE(lifecycle.count(), 0);
        QCOMPARE(finished.count(), 0);
        QCOMPARE(raw->writes().size(), before);
        backend.m_thcV51PhaseDeadlineMs = 0;
        const auto expired = ThcV51OwnerProtocol::dispatch(&backend,
            ownerRequest(QStringLiteral("thc_v51_cancel"), id));
        QCOMPARE(expired.value(QStringLiteral("ok")), QJsonValue(false));
        verifyOwnerReplyDiagnostics(backend, expired, QString(), false, true);
        QCOMPARE(diagnosticSnapshot(backend), unconfirmedNoProgressSnapshot(id));
        QCOMPARE(lifecycle.count(), 1);
        QCOMPARE(finished.count(), 1);
        QCOMPARE(raw->writes().size(), before);
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        verifyTerminalTimersStopped(backend);
    }

    void firmwareNoProgressConfirmedCancellationPublishesProof()
    {
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        preserveOwnerBudget(backend);
        replayNoProgressCancellation(backend, raw);
        const auto id = backend.operationId();
        const auto before = raw->writes().size();
        const auto sequence = backend.pressTelemetrySequence();
        const auto deadline = backend.m_thcV51PhaseDeadlineMs;
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        QVERIFY(backend.m_thcV51CancelAcknowledged);
        QCOMPARE(backend.m_thcV51TerminalTelemetrySequence, sequence);
        verifyCancellationDiagnostics(backend, noProgressFailure(), false, true);
        backend.handleThcV51Telemetry(true, backend.m_pressFrameArrival); // Cached pre-ACK IDLE.
        QVERIFY(backend.commandOperationActive());
        verifyCancellationDiagnostics(backend, noProgressFailure(), false, true);
        const auto acknowledgedReply = ThcV51OwnerProtocol::dispatch(&backend,
            ownerRequest(QStringLiteral("thc_v51_cancel"), id));
        QCOMPARE(acknowledgedReply.value(QStringLiteral("ok")), QJsonValue(true));
        verifyOwnerReplyDiagnostics(backend, acknowledgedReply, noProgressFailure(), false, true);
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, deadline);
        int terminalLifecycleCalls = 0;
        QJsonObject lifecycleSnapshot;
        QObject::connect(&backend, &MachineControlBackend::commandLifecycleChanged, &backend, [&] {
            if (backend.operationId() != id || backend.operationState() != QStringLiteral("FAILED"))
                return;
            ++terminalLifecycleCalls;
            lifecycleSnapshot = diagnosticSnapshot(backend);
        }, Qt::DirectConnection);
        raw->receive(productionIdle()); // First new valid exact IDLE after the exact ACK.
        QCOMPARE(backend.pressTelemetrySequence(), sequence + 1);
        QJsonObject expected = unconfirmedNoProgressSnapshot(id);
        expected.insert(QStringLiteral("operationError"), noProgressFailure());
        expected.insert(QStringLiteral("thcState"), QStringLiteral("FAILED"));
        expected.insert(QStringLiteral("thcV51CancellationConfirmed"), true);
        expected.insert(QStringLiteral("pressSafetyStopUnconfirmed"), false);
        QCOMPARE(terminalLifecycleCalls, 1);
        QCOMPARE(lifecycleSnapshot, expected);
        QCOMPARE(diagnosticSnapshot(backend), expected);
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.at(0).at(0).toULongLong(), id);
        QCOMPARE(finished.at(0).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(finished.at(0).at(3).toString(), QStringLiteral("FAILED"));
        QCOMPARE(finished.at(0).at(4).toString(), noProgressFailure());
        verifyTerminalTimersStopped(backend);
        raw->receive(QByteArrayLiteral("{THC:ERROR:NOT_ACTIVE}"));
        raw->receive(productionIdle());
        QCOMPARE(diagnosticSnapshot(backend), expected);
        QCOMPARE(raw->writes().size(), before);
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(finished.count(), 1);
    }

    void pendingFailureGetterRequiresActualCancellingOwner_data()
    {
        QTest::addColumn<QString>("variant");
        for (const char *variant : {"actual-owner", "terminal-command", "different-operation",
                                    "different-device", "different-press-phase", "different-v51-phase"})
            QTest::newRow(variant) << QString::fromLatin1(variant);
    }

    void pendingFailureGetterRequiresActualCancellingOwner()
    {
        QFETCH(QString, variant);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        preserveOwnerBudget(backend);
        replayNoProgressCancellation(backend, raw);
        const auto before = raw->writes().size();
        // Retain the same private failure while invalidating one ownership guard.
        if (variant == "terminal-command") backend.m_operationState = QStringLiteral("FAILED");
        if (variant == "different-operation") backend.m_operationName = QStringLiteral("home");
        if (variant == "different-device") backend.m_operationDevice = QStringLiteral("module");
        if (variant == "different-press-phase")
            backend.m_pressCommandPhase = MachineControlBackend::PressCommandPhase::ThcCommissioning;
        if (variant == "different-v51-phase")
            backend.m_thcV51Phase = MachineControlBackend::ThcV51Phase::Acquisition;
        QCOMPARE(backend.m_pendingThcFailure, noProgressFailure());
        verifyCancellationDiagnostics(backend,
            variant == "actual-owner" ? noProgressFailure() : QString(), false, true);
        QCOMPARE(raw->writes().size(), before); // Getter evaluation is read-only.
    }

    void unconfirmedCancellationRequiresExplicitHome()
    {
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        preserveOwnerBudget(backend);
        replayNoProgressCancellation(backend, raw);
        const auto oldId = backend.operationId();
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        backend.m_thcV51PhaseDeadlineMs = 0;
        QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51PhaseTimer, "timeout", Qt::DirectConnection));
        QCOMPARE(diagnosticSnapshot(backend), unconfirmedNoProgressSnapshot(oldId));
        QCOMPARE(finished.count(), 1);
        const auto before = raw->writes().size();
        const auto blocked = ThcV51OwnerProtocol::dispatch(&backend, startRequest());
        QCOMPARE(blocked.value(QStringLiteral("ok")), QJsonValue(false));
        QCOMPARE(blocked.value(QStringLiteral("error")),
                 QJsonValue(QStringLiteral("BACKEND_GUARD_OR_DISPATCH_FAILED")));
        QCOMPARE(backend.lastRejectReason(), QStringLiteral("NOT_READY"));
        verifyOwnerReplyDiagnostics(backend, blocked, QString(), false, true);
        QCOMPARE(raw->writes().size(), before);
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CONTACT_PROFILE_V51>\n")), qsizetype(1));
        // A rejected new command may itself have an id; Home must open a fresh owner.
        const auto beforeHomeId = backend.operationId();
        QVERIFY(backend.homePress());
        const auto homeId = backend.operationId();
        QCOMPARE(homeId, beforeHomeId + 1);
        QVERIFY(homeId > oldId);
        QCOMPARE(backend.operationName(), QStringLiteral("home"));
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        QCOMPARE(backend.operationError(), QString());
        verifyCancellationDiagnostics(backend, QString(), false, true);
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<$H>\n"));
        QVERIFY(backend.m_pressHomePending);
        QVERIFY(backend.m_pressHomingTimer.isActive());
        verifyTerminalTimersStopped(backend);
        const auto finishedBeforeLateEvidence = finished.count();
        QSignalSpy homeLifecycle(&backend, &MachineControlBackend::commandLifecycleChanged);
        for (QTimer *timer : {&backend.m_thcV51HeartbeatTimer, &backend.m_thcV51ClientLeaseTimer,
                             &backend.m_thcV51PhaseTimer, &backend.m_thcV51OverallTimer})
            QVERIFY(QMetaObject::invokeMethod(timer, "timeout", Qt::DirectConnection));
        for (const QByteArray &late : {QByteArray("{THC:ERROR:V51_NO_PROGRESS}"),
                QByteArray("{THC:ERROR:NOT_ACTIVE}"), noProgressStopDiagnostic(),
                QByteArray("{THC:CANCELLED}"), QByteArray("{THC:CONTACT_PROFILE_V51_RUNNING}"),
                QByteArray("{THC:CONTACT}"), QByteArray("{THC:HOLDING}"),
                QByteArray("{THC:RELEASING}"), QByteArray("{THC:DONE}"),
                QByteArray("{TH:TIMEOUT}"), productionIdle()}) {
            raw->receive(late);
            QCOMPARE(backend.operationId(), homeId);
            QCOMPARE(backend.operationName(), QStringLiteral("home"));
            QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
            QCOMPARE(backend.operationError(), QString());
            QVERIFY(backend.commandOperationActive());
            QVERIFY(backend.pressOperationActive());
            QVERIFY(backend.m_pressHomePending);
            QVERIFY(backend.m_pressHomingTimer.isActive());
            verifyCancellationDiagnostics(backend, QString(), false, true);
        }
        for (const char *command : {"thc_v51_cancel", "thc_v51_heartbeat", "thc_v51_release"})
            QCOMPARE(ThcV51OwnerProtocol::dispatch(&backend,
                ownerRequest(QString::fromLatin1(command), oldId)), rejection(QStringLiteral("V51_OWNER_MISMATCH")));
        QCOMPARE(homeLifecycle.count(), 0);
        QCOMPARE(finished.count(), finishedBeforeLateEvidence);
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        verifyTerminalTimersStopped(backend);
        raw->receive(productionIdle(QByteArrayLiteral("HOMING")));
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        verifyCancellationDiagnostics(backend, QString(), false, true);
        raw->receive(productionIdle());
        QCOMPARE(backend.operationId(), homeId);
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.commandOperationActive());
        QVERIFY(!backend.pressOperationActive());
        verifyCancellationDiagnostics(backend, QString(), false, false); // Home is recovery, not V51 cancel proof.
        QCOMPARE(finished.count(), finishedBeforeLateEvidence + 1);
        QCOMPARE(finished.last().at(0).toULongLong(), homeId);
        QCOMPARE(finished.last().at(2).toString(), QStringLiteral("home"));
        QCOMPARE(finished.last().at(3).toString(), QStringLiteral("COMPLETED"));
        const auto restarted = ThcV51OwnerProtocol::dispatch(&backend, startRequest());
        QCOMPARE(restarted.value(QStringLiteral("ok")), QJsonValue(true));
        QCOMPARE(backend.operationId(), homeId + 1);
        verifyOwnerReplyDiagnostics(backend, restarted, QString(), false, false);
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CONTACT_PROFILE_V51>\n")), qsizetype(2));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
    }

    void unconfirmedTerminalLifecycleReentrantHomePreservesOldDiagnostics()
    {
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        preserveOwnerBudget(backend);
        replayNoProgressCancellation(backend, raw);
        const auto oldId = backend.operationId();
        const auto before = raw->writes().size();
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        int homeCalls = 0;
        bool homeAccepted = false;
        qulonglong homeId = 0;
        QJsonObject oldSnapshot;
        const auto connection = QObject::connect(&backend, &MachineControlBackend::commandLifecycleChanged,
            &backend, [&] {
                // Do not gate on presentation: stale CANCELLING is the regression.
                if (homeCalls || backend.operationId() != oldId
                    || backend.operationState() != QStringLiteral("FAILED"))
                    return;
                ++homeCalls;
                oldSnapshot = diagnosticSnapshot(backend); // Observe before replacing the owner.
                homeAccepted = backend.homePress();
                homeId = backend.operationId();
            }, Qt::DirectConnection);
        backend.m_thcV51PhaseDeadlineMs = 0;
        QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51PhaseTimer, "timeout", Qt::DirectConnection));
        QObject::disconnect(connection);
        QCOMPARE(homeCalls, 1);
        QCOMPARE(oldSnapshot, unconfirmedNoProgressSnapshot(oldId));
        QVERIFY(homeAccepted);
        QCOMPARE(homeId, oldId + 1);
        QCOMPARE(backend.operationId(), homeId);
        QCOMPARE(backend.operationName(), QStringLiteral("home"));
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        QCOMPARE(backend.operationError(), QString());
        verifyCancellationDiagnostics(backend, QString(), false, true);
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.pressOperationActive());
        QVERIFY(backend.m_pressHomePending);
        QVERIFY(backend.m_pressHomingTimer.isActive());
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<$H>\n"));
        QCOMPARE(finished.count(), 1);
        // The immutable finished payload must remain the OLD failed V51, not Home.
        QCOMPARE(finished.at(0).at(0).toULongLong(), oldId);
        QCOMPARE(finished.at(0).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(finished.at(0).at(3).toString(), QStringLiteral("FAILED"));
        QCOMPARE(finished.at(0).at(4).toString(),
                 noProgressFailure() + QStringLiteral("_CANCEL_CONFIRMATION_TIMEOUT"));
        verifyTerminalTimersStopped(backend);
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        raw->receive(productionIdle());
        QCOMPARE(backend.operationId(), homeId);
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        verifyCancellationDiagnostics(backend, QString(), false, true);
        QCOMPARE(finished.count(), 1);
        QCOMPARE(raw->writes().size(), before + 1);
        raw->receive(productionIdle(QByteArrayLiteral("HOMING")));
        raw->receive(productionIdle());
        QCOMPARE(backend.operationId(), homeId);
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        verifyCancellationDiagnostics(backend, QString(), false, false);
        QCOMPARE(finished.count(), 2);
        QCOMPARE(finished.at(1).at(0).toULongLong(), homeId);
        QCOMPARE(finished.at(1).at(2).toString(), QStringLiteral("home"));
        QCOMPARE(finished.at(1).at(3).toString(), QStringLiteral("COMPLETED"));
        QCOMPARE(finished.at(1).at(4).toString(), QString());
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
    }

    void pressStateArmingCancellationCannotWriteStart()
    {
        verifyArmingCancellation(false);
    }

    void lifecycleArmingCancellationCannotWriteStart()
    {
        verifyArmingCancellation(true);
    }

    void releasePendingCancellationCannotWriteRelease_data()
    {
        QTest::addColumn<bool>("expiredHold");
        QTest::newRow("explicit-release") << false;
        QTest::newRow("expired-hold-release") << true;
    }

    void releasePendingCancellationCannotWriteRelease()
    {
        QFETCH(bool, expiredHold);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        preserveOwnerBudget(backend);
        if (expiredHold)
            backend.m_thcV51PhaseDeadlineMs = 0;
        const auto id = backend.operationId();
        const auto before = raw->writes().size();
        bool callbackEntered = false;
        QJsonObject cancelResponse;
        QObject::connect(&backend, &MachineControlBackend::pressStateChanged, &backend, [&] {
            if (callbackEntered
                || backend.m_thcV51Phase != MachineControlBackend::ThcV51Phase::AwaitRelease
                || backend.thcCommissioningState() != QStringLiteral("RELEASE_PENDING"))
                return;
            callbackEntered = true;
            cancelResponse = ThcV51OwnerProtocol::dispatch(&backend,
                ownerRequest(QStringLiteral("thc_v51_cancel"), id));
        }, Qt::DirectConnection);
        const auto response = ThcV51OwnerProtocol::dispatch(&backend,
            ownerRequest(QStringLiteral("thc_v51_release"), id));
        QVERIFY(callbackEntered);
        QCOMPARE(cancelResponse.value(QStringLiteral("ok")), QJsonValue(true));
        QCOMPARE(response.value(QStringLiteral("ok")), QJsonValue(false));
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<THC:CANCEL>\n"));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:RELEASE>\n")), qsizetype(0));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::AwaitCancel);
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QVERIFY(backend.commandOperationActive());
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        raw->receive(productionIdle());
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        verifyTerminalTimersStopped(backend);
    }

    void synchronousReleaseReportsExactlyOneDispatch_data()
    {
        QTest::addColumn<bool>("expiredHold");
        QTest::addColumn<QString>("reply");
        for (bool expired : {false, true}) {
            for (const char *reply : {"releasing", "done", "completed"}) {
                const QByteArray row = QByteArray(expired ? "expired-" : "explicit-") + reply;
                QTest::newRow(row.constData()) << expired << QString::fromLatin1(reply);
            }
        }
    }

    void synchronousReleaseReportsExactlyOneDispatch()
    {
        QFETCH(bool, expiredHold);
        QFETCH(QString, reply);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        preserveOwnerBudget(backend);
        if (expiredHold)
            backend.m_thcV51PhaseDeadlineMs = 0; // No 1 ms races or wall-clock waiting.
        const auto id = backend.operationId();
        const auto before = raw->writes().size();
        QSignalSpy rejected(&backend, &MachineControlBackend::operationRejected);
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        int hookCalls = 0;
        raw->setWriteHook([&, reply](const QByteArray &frame) {
            if (frame != QByteArrayLiteral("<THC:RELEASE>\n"))
                return;
            ++hookCalls;
            raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
            if (reply != "releasing")
                raw->receive(QByteArrayLiteral("{THC:DONE}"));
            if (reply == "completed")
                raw->receive(productionIdle());
        });
        // Direct API is important: expired HOLD checks can dispatch internally.
        const bool accepted = backend.releaseThcCommissioning();
        raw->setWriteHook({});
        QVERIFY(accepted);
        QCOMPARE(hookCalls, 1);
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:RELEASE>\n")), qsizetype(1));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(0));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(rejected.count(), 0);
        if (reply == "completed") {
            QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
            QCOMPARE(finished.count(), 1);
        } else {
            QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
            QCOMPARE(finished.count(), 0);
            QCOMPARE(backend.m_thcV51Phase, reply == "releasing"
                ? MachineControlBackend::ThcV51Phase::Releasing : MachineControlBackend::ThcV51Phase::AwaitIdle);
            QVERIFY(!backend.releaseThcCommissioning());
            if (reply == "releasing")
                raw->receive(QByteArrayLiteral("{THC:DONE}"));
            raw->receive(productionIdle());
        }
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.at(0).at(0).toULongLong(), id);
        QCOMPARE(finished.at(0).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(finished.at(0).at(3).toString(), QStringLiteral("COMPLETED"));
        QCOMPARE(finished.at(0).at(4).toString(), QString());
        QCOMPARE(backend.ramVelocity(), -7.25);
        QCOMPARE(backend.measuredRamVelocity(), 0.0);
        QVERIFY(!backend.m_pressSafetyStopUnconfirmed);
        QVERIFY(!backend.pressOperationActive());
        verifyTerminalTimersStopped(backend);
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:RELEASE>\n")), qsizetype(1));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(0));
    }

    void lateCycleEvidenceCannotExtendOrCompleteOwner_data()
    {
        QTest::addColumn<QString>("stage");
        for (const char *stage : {"acquisition", "release", "terminal-idle", "overall"})
            QTest::newRow(stage) << QString::fromLatin1(stage);
    }

    void lateCycleEvidenceCannotExtendOrCompleteOwner()
    {
        QFETCH(QString, stage);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        preserveOwnerBudget(backend);
        const auto id = backend.operationId();
        const auto epoch = backend.m_thcV51Clock.msecsSinceReference();
        const auto overall = backend.m_thcV51OverallDeadlineMs;
        const auto acquisition = backend.m_thcV51PhaseDeadlineMs;
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        raw->receive(QByteArrayLiteral("{THC:CONTACT}"));
        raw->receive(QByteArrayLiteral("{THC:HB}"));
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, acquisition);
        QCOMPARE(backend.m_thcV51OverallDeadlineMs, overall);
        QCOMPARE(backend.m_thcV51Clock.msecsSinceReference(), epoch);
        if (stage == "release" || stage == "terminal-idle") {
            QVERIFY(backend.releaseThcCommissioning());
            raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
        }
        if (stage == "terminal-idle")
            raw->receive(QByteArrayLiteral("{THC:DONE}"));
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        if (stage == "overall")
            backend.m_thcV51OverallDeadlineMs = 0;
        else
            backend.m_thcV51PhaseDeadlineMs = 0;
        if (stage == "acquisition" || stage == "overall")
            raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        else if (stage == "release")
            raw->receive(QByteArrayLiteral("{THC:DONE}"));
        else
            raw->receive(productionIdle());
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::AwaitCancel);
        QCOMPARE(backend.operationId(), id);
        QVERIFY(backend.commandOperationActive());
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QCOMPARE(finished.count(), 0);
        const auto cancellation = backend.m_thcV51PhaseDeadlineMs;
        const auto before = raw->writes().size();
        for (const QByteArray &late : {QByteArray("{THC:CONTACT_PROFILE_V51_RUNNING}"),
                                      QByteArray("{THC:HOLDING}"), QByteArray("{THC:RELEASING}"),
                                      QByteArray("{THC:DONE}"), productionIdle()})
            raw->receive(late);
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, cancellation);
        QCOMPARE(backend.m_thcV51Clock.msecsSinceReference(), epoch);
        QCOMPARE(raw->writes().size(), before);
        QVERIFY(backend.commandOperationActive());
        QCOMPARE(ThcV51OwnerProtocol::dispatch(&backend,
            ownerRequest(QStringLiteral("thc_v51_heartbeat"), id)).value(QStringLiteral("ok")), QJsonValue(false));
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        raw->receive(productionIdle());
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.at(0).at(0).toULongLong(), id);
        QCOMPARE(finished.at(0).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(finished.at(0).at(3).toString(), QStringLiteral("FAILED"));
        const auto error = stage == "overall" ? QStringLiteral("THC_V51_OVERALL_TIMEOUT")
                                               : QStringLiteral("THC_V51_PHASE_TIMEOUT");
        QCOMPARE(backend.operationError(), error);
        QCOMPARE(finished.at(0).at(4).toString(), error);
        verifyTerminalTimersStopped(backend);
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CONTACT_PROFILE>\n")), qsizetype(0));
    }

    void previousCycleCannotAuthorizeNewOwner()
    {
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        const auto oldId = backend.operationId();
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend,
            ownerRequest(QStringLiteral("thc_v51_cancel"), oldId)).value(QStringLiteral("ok")).toBool());
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        raw->receive(productionIdle());
        verifyCancellationDiagnostics(backend, QString(), true, false);
        const auto restarted = ThcV51OwnerProtocol::dispatch(&backend, startRequest());
        QCOMPARE(restarted.value(QStringLiteral("ok")), QJsonValue(true));
        verifyOwnerReplyDiagnostics(backend, restarted, QString(), false, false);
        QCOMPARE(backend.operationId(), oldId + 1);
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QVERIFY(!backend.thcContactObserved());
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, qint64(5000));
        QCOMPARE(backend.m_thcV51OverallDeadlineMs, qint64(330000));
        const auto before = raw->writes().size();
        const auto client = backend.m_thcV51ClientDeadlineMs;
        for (const char *command : {"thc_v51_heartbeat", "thc_v51_release", "thc_v51_cancel"})
            QCOMPARE(ThcV51OwnerProtocol::dispatch(&backend,
                ownerRequest(QString::fromLatin1(command), oldId)), rejection(QStringLiteral("V51_OWNER_MISMATCH")));
        QCOMPARE(raw->writes().size(), before);
        QCOMPARE(backend.m_thcV51ClientDeadlineMs, client);
        QCOMPARE(backend.operationId(), oldId + 1);
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
    }

    void uncorrelatedRequestsBlockedOnlyForActiveV51Owner_data()
    {
        QTest::addColumn<QString>("context");
        QTest::addColumn<QString>("command");
        QTest::addColumn<bool>("blocked");
        for (const char *context : {"idle", "legacy-profile", "home", "v51-arming",
                                    "v51-acquisition", "v51-cancelling", "v51-await-idle",
                                    "v51-completed"}) {
            const QString contextName = QString::fromLatin1(context);
            const bool activeV51 = contextName.startsWith("v51-") && contextName != "v51-completed";
            for (const char *command : {"heartbeat", "thc_release", "cancel", "thc_cancel",
                                        "thc_heartbeat", "thc_contact_profile_v51", "thc_v51_heartbeat",
                                        "thc_v51_release", "thc_v51_cancel", "home", "stop", "",
                                        "HEARTBEAT", "heartbeat ", "THC_RELEASE", "thc_release\n"}) {
                const QString commandName = QString::fromLatin1(command);
                const QByteArray row = QByteArray(context) + '-' + (command[0] ? command : "empty");
                QTest::newRow(row.constData()) << contextName << commandName
                    << (activeV51 && (commandName == "heartbeat" || commandName == "thc_release"));
            }
        }
    }

    void uncorrelatedRequestsBlockedOnlyForActiveV51Owner()
    {
        QFETCH(QString, context);
        QFETCH(QString, command);
        QFETCH(bool, blocked);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        if (context == "legacy-profile") {
            QVERIFY(backend.startAutomaticThcContactProfile());
            raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_RUNNING}"));
        } else if (context == "home") {
            QVERIFY(backend.homePress());
        } else if (context.startsWith("v51-")) {
            QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
            if (context != "v51-arming")
                contact(raw);
            if (context == "v51-cancelling") {
                QVERIFY(ThcV51OwnerProtocol::dispatch(&backend,
                    ownerRequest(QStringLiteral("thc_v51_cancel"), backend.operationId()))
                    .value(QStringLiteral("ok")).toBool());
            } else if (context == "v51-await-idle" || context == "v51-completed") {
                QVERIFY(ThcV51OwnerProtocol::dispatch(&backend,
                    ownerRequest(QStringLiteral("thc_v51_release"), backend.operationId()))
                    .value(QStringLiteral("ok")).toBool());
                raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
                raw->receive(QByteArrayLiteral("{THC:DONE}"));
                if (context == "v51-completed")
                    raw->receive(productionIdle());
            }
        }
        QCOMPARE(backend.commandOperationActive(), context != "idle" && context != "v51-completed");
        const auto id = backend.operationId();
        const auto state = backend.operationState();
        const auto phase = backend.m_thcV51Phase;
        const auto clientDeadline = backend.m_thcV51ClientDeadlineMs;
        const auto phaseDeadline = backend.m_thcV51PhaseDeadlineMs;
        const auto overallDeadline = backend.m_thcV51OverallDeadlineMs;
        const auto before = raw->writes().size();
        QSignalSpy lifecycle(&backend, &MachineControlBackend::commandLifecycleChanged);
        QSignalSpy rejected(&backend, &MachineControlBackend::operationRejected);
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        // Pure socket-routing gate: rejected legacy requests must never reach
        // heartbeat/release backend methods. Generic cancel stays admissible.
        QCOMPARE(ThcV51OwnerProtocol::blocksUncorrelatedRequest(&backend, command), blocked);
        QCOMPARE(raw->writes().size(), before);
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationState(), state);
        QCOMPARE(backend.m_thcV51Phase, phase);
        QCOMPARE(backend.m_thcV51ClientDeadlineMs, clientDeadline);
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, phaseDeadline);
        QCOMPARE(backend.m_thcV51OverallDeadlineMs, overallDeadline);
        QCOMPARE(lifecycle.count(), 0);
        QCOMPARE(rejected.count(), 0);
        QCOMPARE(finished.count(), 0);
    }

    void terminalPressStateCallbackCannotCompleteReplacementStop_data()
    {
        QTest::addColumn<QString>("terminal");
        QTest::addColumn<QString>("expectedState");
        QTest::addColumn<QString>("expectedError");
        QTest::newRow("done") << QStringLiteral("done") << QStringLiteral("COMPLETED") << QString();
        QTest::newRow("cancelled") << QStringLiteral("cancelled") << QStringLiteral("FAILED")
                                 << QStringLiteral("THC_V51_CANCEL_REQUESTED");
        QTest::newRow("acquisition-timeout") << QStringLiteral("phase-timeout") << QStringLiteral("FAILED")
                                           << QStringLiteral("THC_V51_PHASE_TIMEOUT");
    }

    void terminalPressStateCallbackCannotCompleteReplacementStop()
    {
        QFETCH(QString, terminal);
        QFETCH(QString, expectedState);
        QFETCH(QString, expectedError);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        preserveOwnerBudget(backend);
        const auto oldId = backend.operationId();
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        if (terminal == "done") {
            QVERIFY(backend.releaseThcCommissioning());
            raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
            raw->receive(QByteArrayLiteral("{THC:DONE}"));
        } else {
            if (terminal == "cancelled") {
                QVERIFY(backend.cancelThcCommissioning());
            } else {
                backend.m_thcV51PhaseDeadlineMs = 0;
                QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51PhaseTimer, "timeout", Qt::DirectConnection));
            }
            QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::AwaitCancel);
            raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        }
        QVERIFY(backend.pressOperationActive());
        QCOMPARE(finished.count(), 0);
        const auto before = raw->writes().size();
        int stopCalls = 0;
        bool stopAccepted = false;
        bool oldCommandActiveAtCallback = true;
        QString stateAtCallback;
        QString errorAtCallback;
        qulonglong replacementId = 0;
        const auto connection = QObject::connect(&backend, &MachineControlBackend::pressStateChanged,
            &backend, [&] {
                // Do not gate on commandOperationActive(): stale lifecycle
                // authority at this exact signal is part of the repro.
                if (stopCalls || backend.pressOperationActive())
                    return;
                ++stopCalls;
                oldCommandActiveAtCallback = backend.commandOperationActive();
                stateAtCallback = backend.operationState();
                errorAtCallback = backend.operationError();
                stopAccepted = backend.stopPressMotion();
                replacementId = backend.operationId();
            }, Qt::DirectConnection);
        raw->receive(productionIdle()); // Fresh IDLE completes only the old V51.
        QObject::disconnect(connection);
        QCOMPARE(stopCalls, 1);
        QVERIFY(stopAccepted);
        QVERIFY(!oldCommandActiveAtCallback);
        QCOMPARE(stateAtCallback, expectedState);
        QCOMPARE(errorAtCallback, expectedError);
        QCOMPARE(replacementId, oldId + 1);
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<stop>\n"));
        QCOMPARE(backend.operationId(), replacementId);
        QCOMPARE(backend.operationName(), QStringLiteral("stop-motion"));
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        QCOMPARE(backend.operationError(), QString());
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.pressOperationActive());
        QCOMPARE(backend.m_pressCommandPhase, MachineControlBackend::PressCommandPhase::AwaitStopIdle);
        QVERIFY(!backend.m_pressStopAcknowledged);
        QVERIFY(backend.m_commandDeadlineTimer.isActive());
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.at(0).at(0).toULongLong(), oldId);
        QCOMPARE(finished.at(0).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(finished.at(0).at(3).toString(), expectedState);
        QCOMPARE(finished.at(0).at(4).toString(), expectedError);
        verifyTerminalTimersStopped(backend);
        raw->receive(productionIdle()); // Neither cached nor new IDLE acknowledges STOP.
        QVERIFY(backend.commandOperationActive());
        QCOMPARE(finished.count(), 1);
        raw->receive(QByteArrayLiteral("[STOPPED]"));
        raw->receive(productionIdle());
        QCOMPARE(backend.operationId(), replacementId);
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.commandOperationActive());
        QVERIFY(!backend.pressOperationActive());
        QCOMPARE(finished.count(), 2);
        QCOMPARE(finished.at(1).at(0).toULongLong(), replacementId);
        QCOMPARE(finished.at(1).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(1).at(2).toString(), QStringLiteral("stop-motion"));
        QCOMPARE(finished.at(1).at(3).toString(), QStringLiteral("COMPLETED"));
        QCOMPARE(finished.at(1).at(4).toString(), QString());
    }

    void terminalLifecycleCallbackStartsHomeAndPreservesFinishedPayload_data()
    {
        terminalPressStateCallbackCannotCompleteReplacementStop_data();
    }

    void terminalLifecycleCallbackStartsHomeAndPreservesFinishedPayload()
    {
        QFETCH(QString, terminal);
        QFETCH(QString, expectedState);
        QFETCH(QString, expectedError);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        preserveOwnerBudget(backend);
        const auto oldId = backend.operationId();
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        if (terminal == "done") {
            QVERIFY(backend.releaseThcCommissioning());
            raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
            raw->receive(QByteArrayLiteral("{THC:DONE}"));
        } else {
            if (terminal == "cancelled") {
                QVERIFY(backend.cancelThcCommissioning());
            } else {
                backend.m_thcV51PhaseDeadlineMs = 0;
                QVERIFY(QMetaObject::invokeMethod(&backend.m_thcV51PhaseTimer, "timeout", Qt::DirectConnection));
            }
            raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        }
        QCOMPARE(finished.count(), 0);
        const auto before = raw->writes().size();
        int homeCalls = 0;
        bool homeAccepted = false;
        bool pressActiveAtCallback = true;
        QString presentationAtCallback;
        QString pendingAtCallback;
        bool proofAtCallback = false;
        bool latchAtCallback = true;
        qulonglong homeId = 0;
        const auto connection = QObject::connect(&backend, &MachineControlBackend::commandLifecycleChanged,
            &backend, [&] {
                if (homeCalls || backend.operationId() != oldId || backend.operationState() != expectedState)
                    return;
                ++homeCalls;
                pressActiveAtCallback = backend.pressOperationActive();
                presentationAtCallback = backend.thcCommissioningState();
                pendingAtCallback = backend.thcV51PendingFailure();
                proofAtCallback = backend.thcV51CancellationConfirmed();
                latchAtCallback = backend.pressSafetyStopUnconfirmed();
                homeAccepted = backend.homePress();
                homeId = backend.operationId();
            }, Qt::DirectConnection);
        raw->receive(productionIdle());
        QObject::disconnect(connection);
        QCOMPARE(homeCalls, 1);
        QVERIFY(!pressActiveAtCallback);
        QCOMPARE(presentationAtCallback, terminal == "done" ? QStringLiteral("DONE") : QStringLiteral("FAILED"));
        QCOMPARE(pendingAtCallback, QString());
        QCOMPARE(proofAtCallback, terminal != "done");
        QVERIFY(!latchAtCallback);
        QVERIFY(homeAccepted);
        QCOMPARE(homeId, oldId + 1);
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<$H>\n"));
        QCOMPARE(backend.operationId(), homeId);
        QCOMPARE(backend.operationName(), QStringLiteral("home"));
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        QCOMPARE(backend.operationError(), QString());
        verifyCancellationDiagnostics(backend, QString(), false, false);
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.pressOperationActive());
        QVERIFY(backend.m_pressHomePending);
        QVERIFY(backend.m_pressHomingTimer.isActive());
        QCOMPARE(finished.count(), 1);
        // These expectations are the old immutable payload, NOT current Home
        // fields. The lifecycle callback has already replaced all of those.
        QCOMPARE(finished.at(0).at(0).toULongLong(), oldId);
        QCOMPARE(finished.at(0).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(finished.at(0).at(3).toString(), expectedState);
        QCOMPARE(finished.at(0).at(4).toString(), expectedError);
        verifyTerminalTimersStopped(backend);
        raw->receive(productionIdle()); // Old terminal IDLE cannot finish a new Home.
        QVERIFY(backend.commandOperationActive());
        QCOMPARE(finished.count(), 1);
        raw->receive(productionIdle(QByteArrayLiteral("HOMING")));
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        raw->receive(productionIdle());
        QCOMPARE(backend.operationId(), homeId);
        QCOMPARE(backend.operationState(), QStringLiteral("COMPLETED"));
        QVERIFY(!backend.commandOperationActive());
        QVERIFY(!backend.pressOperationActive());
        QCOMPARE(finished.count(), 2);
        QCOMPARE(finished.at(1).at(0).toULongLong(), homeId);
        QCOMPARE(finished.at(1).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(1).at(2).toString(), QStringLiteral("home"));
        QCOMPARE(finished.at(1).at(3).toString(), QStringLiteral("COMPLETED"));
        QCOMPARE(finished.at(1).at(4).toString(), QString());
    }

    void expiredAcquisitionFrameCannotAcknowledgeReplacementOwner()
    {
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        preserveOwnerBudget(backend);
        const auto oldId = backend.operationId();
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::Acquisition);
        backend.m_thcV51PhaseDeadlineMs = 0;
        const auto before = raw->writes().size();
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        QSignalSpy lifecycle(&backend, &MachineControlBackend::commandLifecycleChanged);
        int replacementStarts = 0;
        int cancellationWrites = 0;
        qulonglong replacementId = 0;
        qint64 clientDeadline = -1;
        qint64 phaseDeadline = -1;
        qint64 overallDeadline = -1;
        QJsonObject replacementResponse;
        const auto connection = QObject::connect(&backend, &MachineControlBackend::commandOperationFinished,
            &backend, [&](qulonglong id, const QString &, const QString &, const QString &, const QString &) {
                if (replacementStarts || id != oldId)
                    return;
                ++replacementStarts;
                replacementResponse = ThcV51OwnerProtocol::dispatch(&backend, startRequest());
                replacementId = backend.operationId();
                clientDeadline = backend.m_thcV51ClientDeadlineMs;
                phaseDeadline = backend.m_thcV51PhaseDeadlineMs;
                overallDeadline = backend.m_thcV51OverallDeadlineMs;
            }, Qt::DirectConnection);
        raw->setWriteHook([&](const QByteArray &frame) {
            if (frame != QByteArrayLiteral("<THC:CANCEL>\n"))
                return;
            ++cancellationWrites;
            if (cancellationWrites != 1)
                return; // Do not let a buggy second cancellation hide the repro.
            raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
            raw->receive(productionIdle());
        });
        // The old frame expires acquisition. Cancellation and a replacement
        // start both finish synchronously before this same frame returns.
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}"));
        raw->setWriteHook({});
        QObject::disconnect(connection);
        QCOMPARE(replacementStarts, 1);
        QCOMPARE(replacementResponse.value(QStringLiteral("ok")), QJsonValue(true));
        QCOMPARE(replacementId, oldId + 1);
        QCOMPARE(replacementResponse.value(QStringLiteral("operationId")), QJsonValue(QString::number(replacementId)));
        QCOMPARE(replacementResponse.value(QStringLiteral("operationState")), QJsonValue(QStringLiteral("SENT")));
        QCOMPARE(replacementResponse.value(QStringLiteral("thcV51RunningAcknowledged")), QJsonValue(false));
        QCOMPARE(cancellationWrites, 1);
        QCOMPARE(raw->writes().size(), before + 2);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<THC:CANCEL>\n"));
        QCOMPARE(raw->writes().at(before + 1), QByteArrayLiteral("<THC:CONTACT_PROFILE_V51>\n"));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CONTACT_PROFILE_V51>\n")), qsizetype(2));
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.at(0).at(0).toULongLong(), oldId);
        QCOMPARE(finished.at(0).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(finished.at(0).at(3).toString(), QStringLiteral("FAILED"));
        QCOMPARE(finished.at(0).at(4).toString(), QStringLiteral("THC_V51_PHASE_TIMEOUT"));
        QCOMPARE(lifecycle.count(), 2); // Old FAILED, new SENT; no spurious ACK.
        QCOMPARE(backend.operationId(), replacementId);
        QCOMPARE(backend.operationName(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        QCOMPARE(backend.operationError(), QString());
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::AwaitStart);
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.pressOperationActive());
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QVERIFY(!backend.thcContactObserved());
        QVERIFY(!backend.m_thcV51CancelAcknowledged);
        QVERIFY(!backend.m_pressSafetyStopUnconfirmed);
        QCOMPARE(phaseDeadline, qint64(5000));
        QCOMPARE(overallDeadline, qint64(330000));
        QCOMPARE(clientDeadline, qint64(2000));
        QCOMPARE(backend.m_thcV51ClientDeadlineMs, clientDeadline);
        QCOMPARE(backend.m_thcV51PhaseDeadlineMs, phaseDeadline);
        QCOMPARE(backend.m_thcV51OverallDeadlineMs, overallDeadline);
        QVERIFY(backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(backend.m_thcV51ClientLeaseTimer.isActive());
        QVERIFY(backend.m_thcV51PhaseTimer.isActive());
        QVERIFY(backend.m_thcV51OverallTimer.isActive());
        raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_V51_RUNNING}")); // A new frame may ACK.
        QCOMPARE(backend.operationId(), replacementId);
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::Approach);
        QVERIFY(backend.thcV51RunningAcknowledged());
        QCOMPARE(ThcV51OwnerProtocol::dispatch(&backend,
            ownerRequest(QStringLiteral("thc_v51_heartbeat"), replacementId)).value(QStringLiteral("ok")), QJsonValue(true));
        QCOMPARE(raw->writes().size(), before + 2);
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(finished.count(), 1);
    }

    void armingSignalLeaseExpiryCannotWriteStart_data()
    {
        QTest::addColumn<bool>("lifecycleSignal");
        QTest::newRow("lifecycle") << true;
        QTest::newRow("press-state") << false;
    }

    void armingSignalLeaseExpiryCannotWriteStart()
    {
        QFETCH(bool, lifecycleSignal);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        const auto before = raw->writes().size();
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        int expiryCallbacks = 0;
        qulonglong id = 0;
        const auto expireWhenArming = [&] {
            if (expiryCallbacks
                || backend.m_thcV51Phase != MachineControlBackend::ThcV51Phase::AwaitStart
                || backend.thcCommissioningState() != QStringLiteral("CONTACT_PROFILE_V51_ARMING"))
                return;
            ++expiryCallbacks;
            id = backend.operationId();
            // Only expire the deadline; do not call cancel or service a timer.
            // The returning arming path must re-check before writing START.
            backend.m_thcV51ClientDeadlineMs = 0;
        };
        if (lifecycleSignal)
            QObject::connect(&backend, &MachineControlBackend::commandLifecycleChanged,
                             &backend, expireWhenArming, Qt::DirectConnection);
        else
            QObject::connect(&backend, &MachineControlBackend::pressStateChanged,
                             &backend, expireWhenArming, Qt::DirectConnection);
        const auto response = ThcV51OwnerProtocol::dispatch(&backend, startRequest());
        QCOMPARE(expiryCallbacks, 1);
        QVERIFY(id > 0);
        QCOMPARE(response.value(QStringLiteral("ok")), QJsonValue(false));
        QCOMPARE(response.value(QStringLiteral("error")),
                 QJsonValue(QStringLiteral("BACKEND_GUARD_OR_DISPATCH_FAILED")));
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<THC:CANCEL>\n"));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CONTACT_PROFILE_V51>\n")), qsizetype(0));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::AwaitCancel);
        QCOMPARE(backend.m_pendingThcFailure, QStringLiteral("THC_V51_CLIENT_LEASE_EXPIRED"));
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.pressOperationActive());
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QVERIFY(backend.m_pressSafetyStopUnconfirmed);
        QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV51ClientLeaseTimer.isActive());
        QVERIFY(!backend.m_thcV51OverallTimer.isActive());
        QVERIFY(backend.m_thcV51PhaseTimer.isActive());
        QCOMPARE(finished.count(), 0);
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        raw->receive(productionIdle());
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("THC_V51_CLIENT_LEASE_EXPIRED"));
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.at(0).at(0).toULongLong(), id);
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(finished.at(0).at(3).toString(), QStringLiteral("FAILED"));
        QCOMPARE(finished.at(0).at(4).toString(), QStringLiteral("THC_V51_CLIENT_LEASE_EXPIRED"));
        verifyTerminalTimersStopped(backend);
    }

    void releasePendingSignalLeaseExpiryCannotWriteRelease_data()
    {
        QTest::addColumn<QString>("stage");
        for (const char *stage : {"acquisition", "holding", "expired-hold"})
            QTest::newRow(stage) << QString::fromLatin1(stage);
    }

    void releasePendingSignalLeaseExpiryCannotWriteRelease()
    {
        QFETCH(QString, stage);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        if (stage != "acquisition")
            raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        preserveOwnerBudget(backend);
        if (stage == "expired-hold")
            backend.m_thcV51PhaseDeadlineMs = 0;
        const auto id = backend.operationId();
        const auto before = raw->writes().size();
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        int expiryCallbacks = 0;
        QObject::connect(&backend, &MachineControlBackend::pressStateChanged, &backend, [&] {
            if (expiryCallbacks || backend.operationId() != id
                || backend.m_thcV51Phase != MachineControlBackend::ThcV51Phase::AwaitRelease
                || backend.thcCommissioningState() != QStringLiteral("RELEASE_PENDING"))
                return;
            ++expiryCallbacks;
            backend.m_thcV51ClientDeadlineMs = 0; // No explicit cancellation or timer invocation.
        }, Qt::DirectConnection);
        const auto response = ThcV51OwnerProtocol::dispatch(&backend,
            ownerRequest(QStringLiteral("thc_v51_release"), id));
        QCOMPARE(expiryCallbacks, 1);
        QCOMPARE(response.value(QStringLiteral("ok")), QJsonValue(false));
        QCOMPARE(response.value(QStringLiteral("error")),
                 QJsonValue(QStringLiteral("BACKEND_GUARD_OR_DISPATCH_FAILED")));
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<THC:CANCEL>\n"));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:RELEASE>\n")), qsizetype(0));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(1));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::AwaitCancel);
        QCOMPARE(backend.m_pendingThcFailure, QStringLiteral("THC_V51_CLIENT_LEASE_EXPIRED"));
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.pressOperationActive());
        QVERIFY(!backend.thcV51RunningAcknowledged());
        QVERIFY(backend.m_pressSafetyStopUnconfirmed);
        QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV51ClientLeaseTimer.isActive());
        QVERIFY(!backend.m_thcV51OverallTimer.isActive());
        QVERIFY(backend.m_thcV51PhaseTimer.isActive());
        QCOMPARE(finished.count(), 0);
        raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
        raw->receive(productionIdle());
        QCOMPARE(backend.operationState(), QStringLiteral("FAILED"));
        QCOMPARE(backend.operationError(), QStringLiteral("THC_V51_CLIENT_LEASE_EXPIRED"));
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.at(0).at(0).toULongLong(), id);
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(finished.at(0).at(3).toString(), QStringLiteral("FAILED"));
        QCOMPARE(finished.at(0).at(4).toString(), QStringLiteral("THC_V51_CLIENT_LEASE_EXPIRED"));
        verifyTerminalTimersStopped(backend);
    }

    void preterminalIdleCannotCorroborateNestedTerminalMarker_data()
    {
        QTest::addColumn<bool>("cancelled");
        QTest::newRow("nested-done") << false;
        QTest::newRow("nested-cancelled") << true;
    }

    void preterminalIdleCannotCorroborateNestedTerminalMarker()
    {
        QFETCH(bool, cancelled);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(ThcV51OwnerProtocol::dispatch(&backend, startRequest()).value(QStringLiteral("ok")).toBool());
        contact(raw);
        raw->receive(QByteArrayLiteral("{THC:HOLDING}"));
        preserveOwnerBudget(backend);
        QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::Holding);
        const auto id = backend.operationId();
        const auto sequence = backend.pressTelemetrySequence();
        const auto before = raw->writes().size();
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        int releaseWrites = 0;
        QJsonObject cancelResponse;
        raw->setWriteHook([&](const QByteArray &frame) {
            if (frame != QByteArrayLiteral("<THC:RELEASE>\n"))
                return;
            ++releaseWrites;
            if (releaseWrites != 1)
                return; // A second dispatch must not hide the regression.
            raw->receive(QByteArrayLiteral("{THC:RELEASING}"));
            if (cancelled) {
                cancelResponse = ThcV51OwnerProtocol::dispatch(&backend,
                    ownerRequest(QStringLiteral("thc_v51_cancel"), id));
                raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
            } else {
                raw->receive(QByteArrayLiteral("{THC:DONE}"));
            }
            // No IDLE here: only the already-arrived outer frame exists.
        });
        backend.m_thcV51PhaseDeadlineMs = 0;
        // Production parsing checks the expired HOLD before accepting this
        // IDLE's fields. Nested terminal replies arrive during that RELEASE;
        // later parsing of the outer IDLE must not make its arrival fresh.
        raw->receive(productionIdle());
        raw->setWriteHook({});
        QCOMPARE(releaseWrites, 1);
        if (cancelled)
            QCOMPARE(cancelResponse.value(QStringLiteral("ok")), QJsonValue(true));
        QCOMPARE(raw->writes().size(), before + (cancelled ? 2 : 1));
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<THC:RELEASE>\n"));
        if (cancelled)
            QCOMPARE(raw->writes().at(before + 1), QByteArrayLiteral("<THC:CANCEL>\n"));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:RELEASE>\n")), qsizetype(1));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(cancelled ? 1 : 0));
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationName(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(backend.operationState(), QStringLiteral("ACKNOWLEDGED"));
        QCOMPARE(backend.operationError(), QString());
        QCOMPARE(backend.m_pressCommandPhase, MachineControlBackend::PressCommandPhase::ThcV51);
        QCOMPARE(backend.m_thcV51Phase, cancelled
            ? MachineControlBackend::ThcV51Phase::AwaitCancel : MachineControlBackend::ThcV51Phase::AwaitIdle);
        QCOMPARE(backend.thcV51RunningAcknowledged(), !cancelled);
        QCOMPARE(backend.m_thcV51CancelAcknowledged, cancelled);
        QCOMPARE(backend.m_pressSafetyStopUnconfirmed, cancelled);
        QCOMPARE(backend.m_thcV51TerminalTelemetrySequence, sequence);
        // A nested newer frame discards the suspended outer frame entirely;
        // it must not publish stale telemetry or count as terminal evidence.
        QCOMPARE(backend.pressTelemetrySequence(), sequence);
        QCOMPARE(backend.m_thcV51TerminalArrival, backend.m_pressFrameArrival);
        QVERIFY(backend.commandOperationActive());
        QVERIFY(backend.pressOperationActive());
        QCOMPARE(finished.count(), 0);
        QVERIFY(backend.m_thcV51Clock.isValid());
        QVERIFY(backend.m_thcV51PhaseTimer.isActive());
        QCOMPARE(backend.m_thcV51OverallTimer.isActive(), !cancelled);
        QVERIFY(!backend.m_thcV51HeartbeatTimer.isActive());
        QVERIFY(!backend.m_thcV51ClientLeaseTimer.isActive());
        QVERIFY(!backend.m_commandDeadlineTimer.isActive());

        raw->receive(productionIdle()); // First IDLE to ARRIVE after the terminal marker.
        QCOMPARE(backend.pressTelemetrySequence(), sequence + 1);
        const auto expectedState = cancelled ? QStringLiteral("FAILED") : QStringLiteral("COMPLETED");
        const auto expectedError = cancelled ? QStringLiteral("THC_V51_CANCEL_REQUESTED") : QString();
        QCOMPARE(backend.operationId(), id);
        QCOMPARE(backend.operationState(), expectedState);
        QCOMPARE(backend.operationError(), expectedError);
        QVERIFY(!backend.commandOperationActive());
        QVERIFY(!backend.pressOperationActive());
        QVERIFY(!backend.m_pressSafetyStopUnconfirmed);
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.at(0).at(0).toULongLong(), id);
        QCOMPARE(finished.at(0).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile-v51"));
        QCOMPARE(finished.at(0).at(3).toString(), expectedState);
        QCOMPARE(finished.at(0).at(4).toString(), expectedError);
        QCOMPARE(backend.ramVelocity(), -7.25);
        QCOMPARE(backend.measuredRamVelocity(), 0.0);
        verifyTerminalTimersStopped(backend);
        QCOMPARE(raw->writes().size(), before + (cancelled ? 2 : 1));
    }

    void legacyParserContinuationCannotMutateReplacementOwner_data()
    {
        QTest::addColumn<bool>("runningAck");
        QTest::newRow("done-press-state") << false;
        QTest::newRow("running-ack-lifecycle") << true;
    }

    void legacyParserContinuationCannotMutateReplacementOwner()
    {
        QFETCH(bool, runningAck);
        auto press = std::make_unique<V51OwnerMockTransport>(true);
        auto *raw = press.get();
        MachineControlBackend backend(std::move(press), std::make_unique<V51OwnerMockTransport>(false));
        QVERIFY(ready(backend, raw));
        QVERIFY(backend.startThcContactProfileCommissioning());
        if (!runningAck)
            raw->receive(QByteArrayLiteral("{THC:CONTACT_PROFILE_RUNNING}"));
        const auto oldId = backend.operationId();
        QCOMPARE(backend.operationName(), QStringLiteral("thc-contact-profile"));
        QCOMPARE(backend.m_pressCommandPhase, MachineControlBackend::PressCommandPhase::ThcCommissioning);
        QCOMPARE(backend.operationState(), runningAck ? QStringLiteral("SENT") : QStringLiteral("ACKNOWLEDGED"));
        const auto before = raw->writes().size();
        QSignalSpy finished(&backend, &MachineControlBackend::commandOperationFinished);
        QSignalSpy lifecycle(&backend, &MachineControlBackend::commandLifecycleChanged);
        int replacementStarts = 0;
        bool legacyStillActive = true;
        QString legacyState;
        QString legacyError;
        qulonglong replacementId = 0;
        qint64 clientDeadline = -1;
        qint64 phaseDeadline = -1;
        qint64 overallDeadline = -1;
        qint64 epoch = -1;
        QJsonObject replacementResponse;
        const auto replaceOwner = [&] {
            if (replacementStarts || backend.operationId() != oldId
                || backend.m_pressCommandPhase != MachineControlBackend::PressCommandPhase::ThcCommissioning
                || backend.thcCommissioningState() != (runningAck
                    ? QStringLiteral("CONTACT_PROFILE_RUNNING") : QStringLiteral("DONE"))
                || (runningAck && backend.operationState() != QStringLiteral("ACKNOWLEDGED")))
                return;
            ++replacementStarts; // Guard before nested parser signals.
            raw->receive(QByteArrayLiteral("{THC:CANCELLED}"));
            raw->receive(productionIdle());
            legacyStillActive = backend.commandOperationActive();
            legacyState = backend.operationState();
            legacyError = backend.operationError();
            replacementResponse = ThcV51OwnerProtocol::dispatch(&backend, startRequest());
            replacementId = backend.operationId();
            clientDeadline = backend.m_thcV51ClientDeadlineMs;
            phaseDeadline = backend.m_thcV51PhaseDeadlineMs;
            overallDeadline = backend.m_thcV51OverallDeadlineMs;
            epoch = backend.m_thcV51Clock.msecsSinceReference();
        };
        const auto connection = runningAck
            ? QObject::connect(&backend, &MachineControlBackend::commandLifecycleChanged,
                               &backend, replaceOwner, Qt::DirectConnection)
            : QObject::connect(&backend, &MachineControlBackend::pressStateChanged,
                               &backend, replaceOwner, Qt::DirectConnection);
        // The legacy DONE/ACK parser is still on the stack when its signal
        // subscriber terminates the old operation and starts a new V51 owner.
        raw->receive(runningAck ? QByteArrayLiteral("{THC:CONTACT_PROFILE_RUNNING}")
                                : QByteArrayLiteral("{THC:DONE}"));
        QObject::disconnect(connection);
        QCOMPARE(replacementStarts, 1);
        QVERIFY(!legacyStillActive);
        QCOMPARE(legacyState, QStringLiteral("FAILED"));
        QCOMPARE(legacyError, QStringLiteral("THC_CANCELLED"));
        QCOMPARE(replacementResponse.value(QStringLiteral("ok")), QJsonValue(true));
        QCOMPARE(replacementId, oldId + 1);
        QCOMPARE(replacementResponse.value(QStringLiteral("operationId")), QJsonValue(QString::number(replacementId)));
        QCOMPARE(replacementResponse.value(QStringLiteral("operationState")), QJsonValue(QStringLiteral("SENT")));
        QCOMPARE(replacementResponse.value(QStringLiteral("thcV51RunningAcknowledged")), QJsonValue(false));
        QCOMPARE(raw->writes().size(), before + 1);
        QCOMPARE(raw->writes().at(before), QByteArrayLiteral("<THC:CONTACT_PROFILE_V51>\n"));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CONTACT_PROFILE>\n")), qsizetype(1));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CONTACT_PROFILE_V51>\n")), qsizetype(1));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:CANCEL>\n")), qsizetype(0));
        QCOMPARE(raw->count(QByteArrayLiteral("<THC:RELEASE>\n")), qsizetype(0));
        QCOMPARE(clientDeadline, qint64(2000));
        QCOMPARE(phaseDeadline, qint64(5000));
        QCOMPARE(overallDeadline, qint64(330000));
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.at(0).at(0).toULongLong(), oldId);
        QCOMPARE(finished.at(0).at(1).toString(), QStringLiteral("press"));
        QCOMPARE(finished.at(0).at(2).toString(), QStringLiteral("thc-contact-profile"));
        QCOMPARE(finished.at(0).at(3).toString(), QStringLiteral("FAILED"));
        QCOMPARE(finished.at(0).at(4).toString(), QStringLiteral("THC_CANCELLED"));
        for (bool freshIdle : {false, true}) {
            if (freshIdle)
                raw->receive(productionIdle()); // IDLE alone must not complete the replacement.
            QCOMPARE(backend.operationId(), replacementId);
            QCOMPARE(backend.operationName(), QStringLiteral("thc-contact-profile-v51"));
            QCOMPARE(backend.operationState(), QStringLiteral("SENT"));
            QCOMPARE(backend.operationError(), QString());
            QCOMPARE(backend.m_pressCommandPhase, MachineControlBackend::PressCommandPhase::ThcV51);
            QCOMPARE(backend.m_thcV51Phase, MachineControlBackend::ThcV51Phase::AwaitStart);
            QCOMPARE(backend.thcCommissioningState(), QStringLiteral("CONTACT_PROFILE_V51_ARMING"));
            QVERIFY(backend.commandOperationActive());
            QVERIFY(backend.pressOperationActive());
            QVERIFY(!backend.thcV51RunningAcknowledged());
            QVERIFY(!backend.thcContactObserved());
            QVERIFY(!backend.m_thcV51CancelAcknowledged);
            QVERIFY(!backend.m_tonnageHoldDoneAcknowledged);
            QVERIFY(!backend.m_pressSafetyStopUnconfirmed);
            QVERIFY(!backend.m_thcContactProfileActive);
            QVERIFY(!backend.m_thcContactProfileAutomaticLifecycle);
            QVERIFY(!backend.m_thcContactProfileHeartbeatTimer.isActive());
            QVERIFY(!backend.m_commandDeadlineTimer.isActive());
            QVERIFY(backend.m_thcV51Clock.isValid());
            QCOMPARE(backend.m_thcV51Clock.msecsSinceReference(), epoch);
            QCOMPARE(backend.m_thcV51ClientDeadlineMs, clientDeadline);
            QCOMPARE(backend.m_thcV51PhaseDeadlineMs, phaseDeadline);
            QCOMPARE(backend.m_thcV51OverallDeadlineMs, overallDeadline);
            QVERIFY(backend.m_thcV51HeartbeatTimer.isActive());
            QVERIFY(backend.m_thcV51ClientLeaseTimer.isActive());
            QVERIFY(backend.m_thcV51PhaseTimer.isActive());
            QVERIFY(backend.m_thcV51OverallTimer.isActive());
            QCOMPARE(lifecycle.count(), runningAck ? 3 : 2); // No new-owner ACK/finish.
            QCOMPARE(finished.count(), 1);
            QCOMPARE(raw->writes().size(), before + 1);
        }
    }

    void serialAllowlistIsExactAndRoleBound_data()
    {
        QTest::addColumn<int>("role");
        QTest::addColumn<QByteArray>("frame");
        QTest::addColumn<bool>("allowed");
        using Role = SerialDeviceDiscovery::DeviceRole;
        QTest::newRow("v51-press") << int(Role::Press) << QByteArray("<THC:CONTACT_PROFILE_V51>\n") << true;
        QTest::newRow("v51-module") << int(Role::Module) << QByteArray("<THC:CONTACT_PROFILE_V51>\n") << false;
        QTest::newRow("v51-unknown") << int(Role::Unknown) << QByteArray("<THC:CONTACT_PROFILE_V51>\n") << false;
        for (const QByteArray &frame : {QByteArray("<thc:contact_profile_v51>\n"),
                QByteArray("<THC:CONTACT_PROFILE_V51_EXTRA>\n"), QByteArray("<THC:CONTACT_PROFILE_V51>"),
                QByteArray("<THC:CONTACT_PROFILE_V51>\r\n"), QByteArray("<THC:CONTACT_PROFILE_V51>\n\n"),
                QByteArray(" <THC:CONTACT_PROFILE_V51>\n"), QByteArray("<THC:CONTACT_PROFILE_V51> \n"),
                QByteArray("<THC:CONTACT_PROFILE_V51:1>\n"), QByteArray("<THC:CONTACT_PROFILE_V51,1>\n"),
                QByteArray("<THC:CONTACT_PROFILE_V51>\n<THC:HB>\n")})
            QTest::newRow(frame.constData()) << int(Role::Press) << frame << false;
        QTest::newRow("legacy-contact-profile") << int(Role::Press) << QByteArray("<THC:CONTACT_PROFILE>\n") << true;
        QTest::newRow("legacy-tonnage-hold") << int(Role::Press) << QByteArray("<TH:1.000,0,1>\n") << true;
        QTest::newRow("legacy-th-heartbeat") << int(Role::Press) << QByteArray("<TH:HB>\n") << true;
        QTest::newRow("thc-heartbeat") << int(Role::Press) << QByteArray("<THC:HB>\n") << true;
        QTest::newRow("general-heartbeat") << int(Role::Press) << QByteArray("<?>\n") << true;
        QTest::newRow("thc-release") << int(Role::Press) << QByteArray("<THC:RELEASE>\n") << true;
        QTest::newRow("thc-cancel") << int(Role::Press) << QByteArray("<THC:CANCEL>\n") << true;
    }

    void serialAllowlistIsExactAndRoleBound()
    {
        QFETCH(int, role);
        QFETCH(QByteArray, frame);
        QFETCH(bool, allowed);
        // Static grammar validation only; never instantiate a serial transport.
        QCOMPARE(SerialMachineTransport::isWriteFrameAllowed(
                     static_cast<SerialDeviceDiscovery::DeviceRole>(role), frame), allowed);
    }
};

QTEST_GUILESS_MAIN(ThcV51OwnerProtocolTests)
#include "tst_ThcV51OwnerProtocol.moc"