#pragma once

#include "MachineControlBackend.h"
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QMetaProperty>
#include <QPointer>
#include <QQuickItem>
#include <QTimer>

// Only called by an explicitly offline launch. Exercises the packaged Manual
// entry and the real native metadata; never queries or changes controller state.
inline void startThcLiveIntegrationCheck(QCoreApplication *app, QObject *window,
                                         MachineControlBackend *backend)
{
    auto fail = [](const QString &reason) {
        qCritical().noquote() << "THC-LIVE-INTEGRATION FAIL" << reason;
        QCoreApplication::exit(5);
    };
    const auto *meta = backend->metaObject();
    for (const char *method : {"queryThcLiveTuning()", "applyThcLiveTuning(QVariantMap)",
                               "startContinuousThcContactProfile()", "heartbeatThcCommissioning()",
                               "releaseThcCommissioning()", "cancelThcCommissioning()"}) {
        if (meta->indexOfMethod(method) < 0) {
            QTimer::singleShot(0, app, [fail, method] { fail(QString::fromLatin1(method)); });
            return;
        }
    }
    for (const char *name : {"pressSafetyStopUnconfirmed", "thcLiveTuningSupported",
                             "thcLiveTuningPending", "thcContinuousActive"}) {
        const auto property = meta->property(meta->indexOfProperty(name));
        if (!property.isValid() || property.metaType().id() != QMetaType::Bool
            || property.isWritable() || !property.hasNotifySignal()) {
            QTimer::singleShot(0, app, [fail, name] { fail(QString::fromLatin1(name)); });
            return;
        }
    }
    const auto fineProperty = meta->property(meta->indexOfProperty("thcFineLoad"));
    if (!fineProperty.isValid() || fineProperty.metaType().id() != QMetaType::QVariantMap
        || fineProperty.isWritable() || !fineProperty.isFinal() || !fineProperty.hasNotifySignal()
        || fineProperty.notifySignal().name() != QByteArrayLiteral("thcFineLoadChanged")) {
        QTimer::singleShot(0, app, [fail] { fail(QStringLiteral("isolated fine-load native metadata")); });
        return;
    }
    const auto initialOperation = backend->operationId();
    window->setProperty("selectedTab", 4);
    auto *timer = new QTimer(app);
    QElapsedTimer deadline;
    deadline.start();
    QObject::connect(timer, &QTimer::timeout, app,
                     [window = QPointer<QObject>(window), backend, timer, deadline,
                      initialOperation, fail, phase = 0]() mutable {
        auto reject = [&](const QString &reason) { timer->stop(); fail(reason); };
        if (!window || deadline.elapsed() > 8000) {
            reject(QStringLiteral("packaged Manual/panel readiness timeout"));
            return;
        }
        if (backend->pressTransportAvailable() || backend->moduleTransportAvailable()
            || backend->pressConnected() || backend->moduleConnected()
            || backend->commandOperationActive() || backend->thcContinuousActive()
            || backend->thcLiveTuningPending() || backend->thcLiveTuningSupported()
            || !backend->thcFineLoad().isEmpty()
            || backend->operationId() != initialOperation) {
            reject(QStringLiteral("offline check changed native operation/transport state"));
            return;
        }
        auto *manual = window->findChild<QObject *>(QStringLiteral("manual-mode-view"));
        if (!manual) return;
        auto *loader = manual->findChild<QObject *>(QStringLiteral("manual-thc-live-loader"));
        auto *entry = manual->findChild<QQuickItem *>(QStringLiteral("button-thc-live-fine-tune"));
        if (!loader || !entry || !entry->isVisible() || !entry->isEnabled()) {
            reject(QStringLiteral("Manual tuning entry/loader missing or hidden"));
            return;
        }
        QObject *panel = loader->property("item").value<QObject *>();
        if (phase == 0 || phase == 2) {
            if (panel || manual->property("liveTuningOpen").toBool()) {
                reject(QStringLiteral("closed panel was not lazily unloaded"));
                return;
            }
            if (!QMetaObject::invokeMethod(entry, "clicked", Qt::DirectConnection)) {
                reject(QStringLiteral("Manual entry cannot be activated"));
                return;
            }
            ++phase;
            return;
        }
        if (!panel || !panel->property("opened").toBool()) return;
        if (panel->objectName() != QStringLiteral("thc-live-tuning-panel")
            || panel->property("backend").value<QObject *>() != backend
            || !panel->property("apiAvailable").toBool()
            || !panel->property("offline").toBool()
            || panel->property("canQuery").toBool()
            || panel->property("canApply").toBool()
            || panel->property("canStart").toBool()
            || panel->property("renewing").toBool()) {
            reject(QStringLiteral("native-backed panel API/offline guards failed"));
            return;
        }
        const auto *history = panel->findChild<QObject *>(QStringLiteral("thc-live-telemetry-history"));
        if (!history || history->property("backend").value<QObject *>() != backend
            || history->property("preferFine").toBool() || history->property("fineAvailable").toBool()
            || !history->property("fineOwnerId").toString().isEmpty()) {
            reject(QStringLiteral("packaged fine-source observer/offline isolation failed"));
            return;
        }
        if (phase == 1) {
            if (!QMetaObject::invokeMethod(panel, "close", Qt::DirectConnection)) {
                reject(QStringLiteral("panel cannot close"));
                return;
            }
            ++phase;
            return;
        }
        timer->stop();
        qInfo("THC-LIVE-INTEGRATION PASS packaged-entry native-api offline-inert close-reopen");
        QCoreApplication::exit(0);
    });
    timer->start(50);
}