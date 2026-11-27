#include <QCursor>
#include <QGuiApplication>
#include <QFile>
#include <QDir>
#include <QDirIterator>
#include <QHash>
#include <QSettings>
#include <QStandardPaths>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>
#include <QWindow>
#include <memory>
#include "FileIo.h"
#include "DisplaySleepController.h"
#include "HostSystemBackend.h"
#include "LicenseManager.h"
#include "MachineFirmwareBackend.h"
#include "MachineControlBackend.h"
#include "ThcLiveIntegrationCheck.h"
#include "ThcV51OwnerProtocol.h"
#include "ThcV53RemoteTuning.h"
#include "ModalPreviewController.h"
#include "NativeRunRenderer.h"
#include "RunFrameTiming.h"
#include "SerialDeviceDiscovery.h"
#include "SerialMachineTransport.h"
#include "UnfoldSequencePlanner.h"

namespace {

int integerArgument(const QStringList &arguments, const QString &prefix,
                    int fallback)
{
    for (const QString &argument : arguments) {
        if (!argument.startsWith(prefix))
            continue;
        bool valid = false;
        const int value = argument.mid(prefix.size()).toInt(&valid);
        return valid ? value : fallback;
    }
    return fallback;
}

QString stringArgument(const QStringList &arguments, const QString &prefix)
{
    for (const QString &argument : arguments) {
        if (argument.startsWith(prefix))
            return argument.mid(prefix.size());
    }
    return {};
}

QJsonObject commissioningStatus(const MachineControlBackend *control)
{
    return {
        {QStringLiteral("ok"), true},
        {QStringLiteral("pressConnected"), control->pressConnected()},
        {QStringLiteral("pressReady"), control->pressReady()},
        {QStringLiteral("pressHomed"), control->pressHomed()},
        {QStringLiteral("pressOperationActive"), control->pressOperationActive()},
        {QStringLiteral("pressTelemetryFresh"), control->pressTelemetryFresh()},
        {QStringLiteral("manualModeEnabled"), control->manualModeEnabled()},
        {QStringLiteral("manualModeMaxTonnagePerRam"), control->manualModeMaxTonnagePerRam()},
        {QStringLiteral("machineState"), control->pressMachineState()},
        {QStringLiteral("bendPedal"), control->bendPedal()},
        {QStringLiteral("physicalPedal"), control->physicalPedal()},
        {QStringLiteral("physicalPedalAvailable"), control->physicalPedalAvailable()},
        {QStringLiteral("antiBind"), control->antiBind()},
        {QStringLiteral("ramPositionY1"), control->ramPositionY1()},
        {QStringLiteral("ramPositionY2"), control->ramPositionY2()},
        {QStringLiteral("ramLoadY1"), control->ramLoadY1()},
        {QStringLiteral("ramLoadY2"), control->ramLoadY2()},
        {QStringLiteral("thcSupported"), control->thcCommissioningSupported()},
        {QStringLiteral("thcState"), control->thcCommissioningState()},
        {QStringLiteral("thcContactObserved"), control->thcContactObserved()},
        {QStringLiteral("thcV51HostCapability"), ThcV51OwnerProtocol::capability()},
        {QStringLiteral("thcV51RunningAcknowledged"), control->thcV51RunningAcknowledged()},
        {QStringLiteral("thcV51PendingFailure"), control->thcV51PendingFailure()},
        {QStringLiteral("thcV51CancellationConfirmed"), control->thcV51CancellationConfirmed()},
        {QStringLiteral("pressSafetyStopUnconfirmed"), control->pressSafetyStopUnconfirmed()},
        {QStringLiteral("thcV51ClientLeaseMs"), 2000},
        {QStringLiteral("firmwareImageAttested"), false},
        {QStringLiteral("operationId"), QString::number(control->operationId())},
        {QStringLiteral("operationName"), control->operationName()},
        {QStringLiteral("operationState"), control->operationState()},
        {QStringLiteral("operationError"), control->operationError()},
        {QStringLiteral("serialDiagnosticLogsEnabled"), control->serialDiagnosticLogsEnabled()}
    };
}

// Diagnostic: BENDCNC_STALL_TRACE_MS=<n> logs every GUI-thread event
// whose handling exceeds n ms (receiver type/name/QML file, event type).
class StallTraceApplication : public QGuiApplication
{
public:
    StallTraceApplication(int &argc, char **argv) : QGuiApplication(argc, argv)
    {
        m_thresholdMs = qEnvironmentVariableIntValue("BENDCNC_STALL_TRACE_MS");
    }
    bool notify(QObject *receiver, QEvent *event) override
    {
        if (m_thresholdMs <= 0)
            return QGuiApplication::notify(receiver, event);
        QElapsedTimer timer;
        timer.start();
        const QEvent::Type type = event->type();
        const bool result = QGuiApplication::notify(receiver, event);
        const qint64 ms = timer.elapsed();
        if (ms >= m_thresholdMs && receiver) {
            QString where;
            if (QQmlContext *ctx = qmlContext(receiver))
                where = ctx->baseUrl().fileName();
            const QVariant interval = receiver->property("interval");
            qInfo().noquote() << "STALL-TRACE ms=" + QString::number(ms)
                << "event=" + QString::number(int(type))
                << "class=" + QString::fromLatin1(receiver->metaObject()->className())
                << "name=" + receiver->objectName()
                << "qml=" + where
                << (interval.isValid() ? "interval=" + interval.toString() : QString());
        }
        return result;
    }
private:
    int m_thresholdMs = 0;
};

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication::setApplicationVersion(QStringLiteral(BENDCNC_APP_VERSION));
    // DataStore loads the JSON bundled in the application's qrc tree through
    // synchronous XMLHttpRequest. Qt disables local-resource XHR unless this
    // switch is set before QGuiApplication is constructed, which otherwise
    // leaves programs, bends, tools, and settings silently empty.
    qputenv("QML_XHR_ALLOW_FILE_READ", QByteArrayLiteral("1"));

    StallTraceApplication app(argc, argv);

    const bool verifyThcLive = app.arguments().contains(
        QStringLiteral("--verify-thc-live-integration"));
    if (verifyThcLive && !app.arguments().contains(QStringLiteral("--offline-validation"))) {
        qCritical("THC-LIVE-INTEGRATION FAIL requires --offline-validation");
        return 64; // Reject before any serial discovery or backend is constructed.
    }

    // Qt Quick Text uses the application font, not ApplicationWindow.font.
    // Load the same bundled faces on Windows and EGLFS before creating QML.
    QString regularFamily;
    for (const QString &face : {QStringLiteral("fira-sans-regular.ttf"),
                                QStringLiteral("fira-sans-bold.ttf"),
                                QStringLiteral("fira-sans-light.ttf"),
                                QStringLiteral("fire-sans-italic.ttf")}) {
        const QString resource = QStringLiteral(":/qt/qml/BendCNCPrototype/qml/fonts/") + face;
        const int id = QFontDatabase::addApplicationFont(resource);
        if (id < 0 || QFontDatabase::applicationFontFamilies(id).isEmpty()) {
            qFatal("Bundled font unavailable: %s", qPrintable(resource));
        }
        if (face == QStringLiteral("fira-sans-regular.ttf"))
            regularFamily = QFontDatabase::applicationFontFamilies(id).first();
    }
    QFont applicationFont = app.font();
    applicationFont.setFamily(regularFamily);
#ifndef Q_OS_ANDROID
    // The press image has no emoji/symbol system fonts (only DejaVu/Ubuntu),
    // so UI icons like \U0001F5A5 \U0001F4BE \u26A1 rendered blank. Bundle OFL
    // Noto Symbols/Emoji (monochrome) as explicit fallbacks after Fira Sans.
    {
        QStringList families{regularFamily};
        for (const QString &face : {QStringLiteral("NotoSansSymbols2-Regular.ttf"),
                                    QStringLiteral("NotoSansSymbols.ttf"),
                                    QStringLiteral("NotoEmoji-Regular.ttf")}) {
            const int id = QFontDatabase::addApplicationFont(
                QStringLiteral(":/qt/qml/BendCNCPrototype/qml/fonts/") + face);
            if (id >= 0)
                families += QFontDatabase::applicationFontFamilies(id);
            else
                qWarning("Symbol font unavailable: %s", qPrintable(face));
        }
        applicationFont.setFamilies(families);
    }
#endif
#ifdef Q_OS_ANDROID
    // Android system fonts lack many UI symbols (\u23FB power, \u2699, \u2315...).
    // android/build-deploy-android.ps1 packages OFL Noto symbol fonts as APK
    // assets; append them as explicit fallbacks after Fira Sans.
    QStringList families{regularFamily};
    for (const QString &face : {QStringLiteral("NotoSansSymbols2-Regular.ttf"),
                                QStringLiteral("NotoSansSymbols.ttf"),
                                QStringLiteral("NotoSansMath-Regular.ttf")}) {
        const int id = QFontDatabase::addApplicationFont(QStringLiteral("assets:/fonts/") + face);
        if (id >= 0)
            families += QFontDatabase::applicationFontFamilies(id);
        else
            qWarning("Android symbol font unavailable: %s", qPrintable(face));
    }
    applicationFont.setFamilies(families);
#endif
    app.setFont(applicationFont);
    qInfo("APP-FONT family=%s", qPrintable(regularFamily));

    // Organization/application identifiers so QML `Settings` (QSettings) can
    // initialize a stable storage location instead of failing with status 1.
    // One-time migration: copy legacy BendOS data/settings
    // before switching the organization folder to BendCNC (old copy is left untouched).
    QCoreApplication::setApplicationName(QStringLiteral("BendCNC"));
    QString legacyDataDir;
    QHash<QString, QVariant> legacyValues;
    for (const QString &legacyOrg : {QStringLiteral("BendOS")}) {
        QCoreApplication::setOrganizationName(legacyOrg);
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
        if (legacyDataDir.isEmpty() && !dir.isEmpty() && QDir(dir).exists())
            legacyDataDir = dir;
        if (legacyValues.isEmpty()) {
            QSettings legacySettings;
            for (const QString &key : legacySettings.allKeys())
                legacyValues.insert(key, legacySettings.value(key));
        }
    }

    QCoreApplication::setOrganizationName(QStringLiteral("BendCNC"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("bendcnc.local"));
    const QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (!legacyDataDir.isEmpty() && QDir(legacyDataDir).exists() && !QDir(dataDir).exists()) {
        QDirIterator it(legacyDataDir, QDir::Files | QDir::Hidden | QDir::NoDotAndDotDot,
                        QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString source = it.next();
            const QString target = QDir(dataDir).filePath(QDir(legacyDataDir).relativeFilePath(source));
            QDir().mkpath(QFileInfo(target).absolutePath());
            QFile::copy(source, target);
        }
        qInfo("DATA-MIGRATION %s -> %s", qPrintable(legacyDataDir), qPrintable(dataDir));
    }
    QSettings settings;
    if (settings.allKeys().isEmpty() && !legacyValues.isEmpty()) {
        for (auto it = legacyValues.cbegin(); it != legacyValues.cend(); ++it)
            settings.setValue(it.key(), it.value());
        settings.sync();
    }

    const bool modalPreview = app.arguments().contains(
        QStringLiteral("--modal-preview"));
    const QString modalPreviewVersion = stringArgument(
        app.arguments(), QStringLiteral("--modal-preview-version="));
    const bool offlineValidation = modalPreview || app.arguments().contains(
        QStringLiteral("--offline-validation"));
    const bool frameTimingEnabled = app.arguments().contains(
        QStringLiteral("--run-frame-timing"));
    const int frameTimingWindowMs = integerArgument(
        app.arguments(), QStringLiteral("--run-frame-timing-window-ms="), 1000);
    RunFrameTiming runFrameTiming(frameTimingEnabled, frameTimingWindowMs);
    QQmlApplicationEngine engine;
    QString modalPreviewRoot;
#ifdef BENDCNC_QML_SOURCE_DIR
    modalPreviewRoot = QDir(QStringLiteral(BENDCNC_QML_SOURCE_DIR))
        .filePath(QStringLiteral("modal-previews"));
#endif
    ModalPreviewController modalPreviewController(&engine, modalPreviewRoot);
    engine.rootContext()->setContextProperty(
        QStringLiteral("modalPreviewController"), &modalPreviewController);
    engine.rootContext()->setContextProperty(QStringLiteral("runFrameTiming"),
                                             &runFrameTiming);
    const bool serialLogsForcedOn = app.arguments().contains(
        QStringLiteral("--serial-debug-logs-on"));
    const bool serialLogsForcedOff = app.arguments().contains(
        QStringLiteral("--serial-debug-logs-off"));
#if defined(Q_PROCESSOR_ARM_64)
    // Production ARM kiosk defaults quiet even when an older installed
    // launcher cannot yet pass the new flag. Diagnostics remain one flag away.
    const bool serialDiagnosticLogs = serialLogsForcedOn && !serialLogsForcedOff;
#else
    // PC development and test launches retain complete serial diagnostics.
    const bool serialDiagnosticLogs = !serialLogsForcedOff || serialLogsForcedOn;
#endif

    // Expose the narrow C++ file-IO backend to QML as a context property `fileIo`
    // (also auto-registered as the QML singleton `FileIo` via QML_ELEMENT). AppState
    // wires this into core/storage/EntityStorage.js so production JSON writes are
    // atomic and backup-guarded. Pure-QML XMLHttpRequest cannot create new files.
    static FileIo fileIo;
    engine.rootContext()->setContextProperty(QStringLiteral("fileIo"), &fileIo);
    DisplaySleepController displaySleepController;
    engine.rootContext()->setContextProperty(QStringLiteral("displaySleepController"),
                                             &displaySleepController);
    HostSystemBackend hostSystem(offlineValidation);
    engine.rootContext()->setContextProperty(QStringLiteral("hostSystem"), &hostSystem);
    UnfoldSequencePlanner unfoldPlanner;
    engine.rootContext()->setContextProperty(QStringLiteral("unfoldPlanner"), &unfoldPlanner);
    LicenseManager licenseManager;
    engine.rootContext()->setContextProperty(QStringLiteral("license"), &licenseManager);
    MachineFirmwareBackend machineFirmware(offlineValidation);
    engine.rootContext()->setContextProperty(QStringLiteral("machineFirmware"), &machineFirmware);
    engine.rootContext()->setContextProperty(
        QStringLiteral("bendcncModalPreviewVersion"),
        modalPreviewVersion.isEmpty() ? QStringLiteral("current") : modalPreviewVersion);

    // Validation on the press-brake computer must be unable to claim either
    // serial endpoint. The explicit offline flag substitutes null transports;
    // normal development launches retain read-only discovery and guarded
    // handshake support.
    std::unique_ptr<SerialDeviceDiscovery> serialDiscovery;
    std::unique_ptr<MachineControlBackend> machineControl;
    if (offlineValidation) {
        machineControl = std::make_unique<MachineControlBackend>();
    } else {
        serialDiscovery = std::make_unique<SerialDeviceDiscovery>();
        machineControl = std::make_unique<MachineControlBackend>(
            std::make_unique<SerialMachineTransport>(
                serialDiscovery.get(), SerialDeviceDiscovery::DeviceRole::Press,
                serialDiagnosticLogs),
            std::make_unique<SerialMachineTransport>(
                serialDiscovery.get(), SerialDeviceDiscovery::DeviceRole::Module,
                serialDiagnosticLogs));
    }
    machineControl->setSerialDiagnosticLogsEnabled(serialDiagnosticLogs);
    engine.rootContext()->setContextProperty(QStringLiteral("machineControl"),
                                             machineControl.get());
    machineFirmware.setMachineControl(machineControl.get());

    std::unique_ptr<QLocalServer> commissioningServer;
    const QString commissioningSocket = stringArgument(
        app.arguments(), QStringLiteral("--commissioning-home-socket="));
    if (!offlineValidation && !commissioningSocket.isEmpty()) {
        QFile::remove(commissioningSocket);
        commissioningServer = std::make_unique<QLocalServer>();
        commissioningServer->setSocketOptions(QLocalServer::UserAccessOption);
        QObject::connect(commissioningServer.get(), &QLocalServer::newConnection,
                         &app, [server = commissioningServer.get(),
                                control = machineControl.get(), engine = &engine] {
            while (QLocalSocket *socket = server->nextPendingConnection()) {
                QObject::connect(socket, &QLocalSocket::readyRead, socket,
                                 [socket, control, engine] {
                    if (socket->property("commissioningRequestHandled").toBool())
                        return;
                    if (!socket->canReadLine()) {
                        if (socket->bytesAvailable() > 4096)
                            socket->disconnectFromServer();
                        return;
                    }
                    socket->setProperty("commissioningRequestHandled", true);
                    const QByteArray requestLine = socket->readLine();
                    if (requestLine.size() > 4096) {
                        socket->write(QByteArrayLiteral("{\"ok\":false,\"error\":\"REQUEST_TOO_LARGE\"}\n"));
                        socket->flush();
                        socket->disconnectFromServer();
                        return;
                    }
                    const QByteArray request = requestLine.trimmed();
                    // Preserve the shipped HOME_PRESS owner-only protocol.
                    if (request == QByteArrayLiteral("HOME_PRESS")) {
                        socket->write(control->homePress() ? QByteArrayLiteral("DISPATCHED\n")
                                                           : QByteArrayLiteral("REJECTED BACKEND_GUARD\n"));
                        socket->flush(); socket->disconnectFromServer(); return;
                    }
                    QJsonParseError parseError;
                    const QJsonDocument document = QJsonDocument::fromJson(request, &parseError);
                    QJsonObject response;
                    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
                        response = {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("INVALID_JSON")}};
                    } else {
                        const QJsonObject object = document.object();
                        const QString command = object.value(QStringLiteral("command")).toString();
                        bool accepted = false;
                        if (command == QStringLiteral("status")) {
                            response = commissioningStatus(control);
                        } else if (command == QStringLiteral("sim_run")) {
                            // Visual-only SIM RUN (same path as the UI button);
                            // QML refuses it while a real RUN is active.
                            QVariant result;
                            QObject *root = engine->rootObjects().isEmpty()
                                ? nullptr : engine->rootObjects().constFirst();
                            const bool invoked = root && QMetaObject::invokeMethod(
                                root, "remoteSimControl", Q_RETURN_ARG(QVariant, result),
                                Q_ARG(QVariant, object.value(QStringLiteral("action")).toString()));
                            response = invoked ? QJsonObject::fromVariantMap(result.toMap())
                                               : QJsonObject{{QStringLiteral("ok"), false},
                                                             {QStringLiteral("error"), QStringLiteral("UI_NOT_READY")}};
                        } else if (ThcV51OwnerProtocol::handles(command)) {
                            response = ThcV51OwnerProtocol::dispatch(control, object);
                        } else if (ThcV53RemoteTuning::handles(command)) {
                            ThcV53RemoteTuning::dispatch(control, object, socket,
                                [socket](const QJsonObject &reply) {
                                socket->write(QJsonDocument(reply).toJson(QJsonDocument::Compact) + '\n');
                                socket->flush();
                                socket->disconnectFromServer();
                            });
                            return;
                        } else if (ThcV51OwnerProtocol::blocksUncorrelatedRequest(control, command)) {
                            response = {{QStringLiteral("ok"), false},
                                        {QStringLiteral("error"), QStringLiteral("V51_OWNER_REQUIRED")}};
                        } else if (command == QStringLiteral("home_press")) {
                            accepted = control->homePress();
                        } else if (command == QStringLiteral("jog_press")) {
                            // Same backend path (and guards) as the UI Move To / Advance.
                            accepted = control->jogPress(object.value(QStringLiteral("target")).toDouble(),
                                object.value(QStringLiteral("speed")).toDouble(),
                                object.value(QStringLiteral("type")).toString());
                        } else if (command == QStringLiteral("run_program")) {
                            // Starts the loaded program through the normal UI RUN
                            // path (all readiness/license guards). Requires
                            // Settings -> Remote RUN enabled.
                            accepted = control->requestRemoteRun();
                        } else if (command == QStringLiteral("manual_enable")) {
                            accepted = control->setManualModeEnabled(true);
                        } else if (command == QStringLiteral("manual_disable")) {
                            accepted = control->setManualModeEnabled(false);
                        } else if (command == QStringLiteral("manual_max_tonnage")) {
                            accepted = control->setManualModeMaxTonnage(
                                object.value(QStringLiteral("tonsPerRam")).toDouble());
                        } else if (command == QStringLiteral("thc_arm")) {
                            accepted = control->armThcCommissioning(object.value(QStringLiteral("target")).toDouble(),
                                object.value(QStringLiteral("speed")).toDouble(), object.value(QStringLiteral("floor")).toDouble());
                        } else if (command == QStringLiteral("thc_contact_profile")) {
                            accepted = control->startThcContactProfileCommissioning();
                        } else if (command == QStringLiteral("thc_tune_query")) {
                            if (object.size() != 1) {
                                response = {{QStringLiteral("ok"), false},
                                            {QStringLiteral("error"), QStringLiteral("INVALID_ARGUMENT")}};
                            } else {
                                auto connection = std::make_shared<QMetaObject::Connection>();
                                *connection = QObject::connect(
                                    control, &MachineControlBackend::thcTuningQueryFinished,
                                    socket, [socket, connection](bool ok, const QString &tuning,
                                                                 const QString &error) {
                                        QObject::disconnect(*connection);
                                        socket->setProperty("thcTuningQueryOwner", false);
                                        QJsonObject reply{{QStringLiteral("ok"), ok}};
                                        if (ok)
                                            reply.insert(QStringLiteral("response"), tuning);
                                        else
                                            reply.insert(QStringLiteral("error"), error);
                                        socket->write(QJsonDocument(reply).toJson(QJsonDocument::Compact) + '\n');
                                        socket->flush();
                                        socket->disconnectFromServer();
                                    });
                                accepted = control->queryThcTuning();
                                if (accepted) {
                                    socket->setProperty("thcTuningQueryOwner", true);
                                    QObject::connect(socket, &QLocalSocket::disconnected,
                                                     control, [socket, control] {
                                        if (socket->property("thcTuningQueryOwner").toBool())
                                            control->cancelThcTuningQuery();
                                    });
                                    return;
                                }
                                QObject::disconnect(*connection);
                            }
                        } else if (command == QStringLiteral("thc_start")) {
                            accepted = control->startThcCommissioning();
                        } else if (command == QStringLiteral("thc_release")) {
                            accepted = control->releaseThcCommissioning();
                        } else if (command == QStringLiteral("heartbeat")) {
                            accepted = control->heartbeatThcCommissioning();
                        } else if (command == QStringLiteral("cancel")) {
                            accepted = control->cancelThcCommissioning();
                        } else {
                            response = {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("UNKNOWN_COMMAND")}};
                        }
                        if (response.isEmpty()) {
                            response = commissioningStatus(control);
                            response.insert(QStringLiteral("ok"), accepted);
                            if (!accepted) response.insert(QStringLiteral("error"), control->lastRejectReason());
                        }
                    }
                    socket->write(QJsonDocument(response).toJson(QJsonDocument::Compact) + '\n');
                    socket->flush();
                    socket->disconnectFromServer();
                });
            }
        });
        if (!commissioningServer->listen(commissioningSocket)) {
            qCritical().noquote() << "COMMISSIONING-HOME-SOCKET state=FAILED"
                                  << "path=" + commissioningSocket
                                  << "error=" + commissioningServer->errorString();
            return -2;
        }
        qInfo().noquote() << "COMMISSIONING-HOME-SOCKET state=LISTENING"
                          << "path=" + commissioningSocket;
    }

    if (!offlineValidation && app.arguments().contains(QStringLiteral("--read-only-connect-smoke"))) {
        QObject::connect(machineControl.get(), &MachineControlBackend::connectionFailed,
                         &app, [](const QString &device, const QString &reason) {
            qWarning().noquote() << "READ-ONLY-CONNECT-SMOKE failure"
                                 << "device=" + device << "reason=" + reason;
        });
    }

    // Modal preview mode is intentionally offline and loads a design-only
    // gallery. Normal launches continue to use the production application.
    QUrl rootQml(QStringLiteral("qrc:/qt/qml/BendCNCPrototype/qml/main.qml"));
    if (modalPreview) {
#ifdef BENDCNC_QML_SOURCE_DIR
        const QString sourcePreview = QDir(QStringLiteral(BENDCNC_QML_SOURCE_DIR))
            .filePath(QStringLiteral("ModalPreviewer.qml"));
        if (QFileInfo::exists(sourcePreview))
            rootQml = QUrl::fromLocalFile(sourcePreview);
        else
#endif
            rootQml = QUrl(QStringLiteral(
                "qrc:/qt/qml/BendCNCPrototype/qml/ModalPreviewer.qml"));
    }
    engine.load(rootQml);
    if (engine.rootObjects().isEmpty())
        return -1;
    if (verifyThcLive)
        startThcLiveIntegrationCheck(&app, engine.rootObjects().constFirst(), machineControl.get());
    if (auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst()))
        runFrameTiming.attachWindow(window);
    const int exitAfterMilliseconds = integerArgument(
        app.arguments(), QStringLiteral("--run-exit-after-ms="), 0);
    if (exitAfterMilliseconds > 0) {
        QTimer::singleShot(exitAfterMilliseconds, &app, [&app, exitAfterMilliseconds] {
            qInfo().noquote() << "RUN-BOUNDED-EXIT"
                              << "elapsedMs=" + QString::number(exitAfterMilliseconds);
            app.quit();
        });
    }
    if (!offlineValidation && app.arguments().contains(QStringLiteral("--read-only-connect-smoke"))) {
        QTimer::singleShot(1500, machineControl.get(), [control = machineControl.get()] {
            const bool moduleAccepted = control->connectModule();
            qInfo().noquote() << "READ-ONLY-CONNECT-SMOKE requested"
                              << "moduleAccepted=" << moduleAccepted;
        });
        QTimer::singleShot(3500, machineControl.get(), [control = machineControl.get()] {
            const bool pressAccepted = control->connectPress();
            qInfo().noquote() << "READ-ONLY-CONNECT-SMOKE requested"
                              << "pressAccepted=" << pressAccepted;
        });
        QTimer::singleShot(14000, &app, &QCoreApplication::quit);
        QTimer::singleShot(13500, machineControl.get(), [control = machineControl.get()] {
            qInfo().noquote() << "READ-ONLY-CONNECT-SMOKE final"
                              << "pressState=" + control->pressConnectionState()
                              << "pressReady=" + QString::number(control->pressReady())
                              << "pressFirmware=" + control->pressFirmwareVersion()
                              << "pressMachineState=" + control->pressMachineState()
                              << "moduleState=" + control->moduleConnectionState()
                              << "moduleReady=" + QString::number(control->moduleReady())
                              << "moduleFirmware=" + control->moduleFirmwareVersion()
                              << "moduleMachineState=" + control->moduleState();
        });
    }
    if (app.arguments().contains(QStringLiteral("--fullscreen"))) {
        if (auto *window = qobject_cast<QWindow *>(engine.rootObjects().constFirst()))
            window->showFullScreen();
#ifdef Q_OS_LINUX
        // Press kiosk is touch-only: hide the pointer.
        QGuiApplication::setOverrideCursor(QCursor(Qt::BlankCursor));
#endif
    }
    return app.exec();
}
