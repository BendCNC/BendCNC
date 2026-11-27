#pragma once

#include "MachineControlBackend.h"
#include <QJsonObject>
#include <functional>
#include <memory>

// Owner-only commissioning-socket adapter for V53 live tuning. It reuses the
// exact admitted panel paths (queryThcLiveTuning/applyThcLiveTuning): same
// guards, same six-key strict frame, no lease renewal, motion or new frames.
namespace ThcV53RemoteTuning {

inline bool handles(const QString &command)
{
    return command == QStringLiteral("thc_v53_live_status")
        || command == QStringLiteral("thc_v53_live_query")
        || command == QStringLiteral("thc_v53_live_tune");
}

inline QJsonObject snapshot(const MachineControlBackend *control)
{
    return {
        {QStringLiteral("thcLiveTuning"), QJsonObject::fromVariantMap(control->thcLiveTuning())},
        {QStringLiteral("thcLiveTuningSupported"), control->thcLiveTuningSupported()},
        {QStringLiteral("thcLiveTuningExtended"), control->thcLiveTuningExtended()},
        {QStringLiteral("thcLiveTuningPending"), control->thcLiveTuningPending()},
        {QStringLiteral("thcLiveTuningError"), control->thcLiveTuningError()},
        {QStringLiteral("thcLiveDiagnostics"), QJsonObject::fromVariantMap(control->thcLiveDiagnostics())},
        {QStringLiteral("thcFineLoad"), QJsonObject::fromVariantMap(control->thcFineLoad())},
        {QStringLiteral("thcContinuousActive"), control->thcContinuousActive()},
        {QStringLiteral("operationId"), QString::number(control->operationId())},
        {QStringLiteral("operationName"), control->operationName()},
        {QStringLiteral("operationState"), control->operationState()},
        {QStringLiteral("machineState"), control->pressMachineState()},
        {QStringLiteral("ramLoadY1"), control->ramLoadY1()},
        {QStringLiteral("ramLoadY2"), control->ramLoadY2()}
    };
}

// Calls reply exactly once, synchronously or after the backend settles the
// request (confirmed reply, mismatch, timeout or invalidation).
inline void dispatch(MachineControlBackend *control, const QJsonObject &request, QObject *context,
                     const std::function<void(const QJsonObject &)> &reply)
{
    const auto result = [control, reply](const QString &error) {
        QJsonObject response = snapshot(control);
        response.insert(QStringLiteral("ok"), error.isEmpty());
        if (!error.isEmpty()) response.insert(QStringLiteral("error"), error);
        reply(response);
    };
    const QString command = request.value(QStringLiteral("command")).toString();
    if (!handles(command)) return result(QStringLiteral("INVALID_ARGUMENT"));
    if (command == QStringLiteral("thc_v53_live_status"))
        return result(request.size() == 1 ? QString() : QStringLiteral("INVALID_ARGUMENT"));

    const bool tune = command == QStringLiteral("thc_v53_live_tune");
    QVariantMap settings;
    if (tune) {
        const QJsonValue value = request.value(QStringLiteral("settings"));
        if (request.size() != 2 || !value.isObject()) return result(QStringLiteral("INVALID_ARGUMENT"));
        const QJsonObject object = value.toObject();
        for (auto it = object.begin(); it != object.end(); ++it) {
            if (!it.value().isDouble()) return result(QStringLiteral("INVALID_ARGUMENT"));
            settings.insert(it.key(), it.value().toDouble());
        }
    } else if (request.size() != 1) {
        return result(QStringLiteral("INVALID_ARGUMENT"));
    }

    const bool accepted = tune ? control->applyThcLiveTuning(settings) : control->queryThcLiveTuning();
    if (!accepted) {
        const QString error = control->thcLiveTuningError();
        return result(error.isEmpty() ? QStringLiteral("V53_REQUEST_REJECTED") : error);
    }
    const auto settle = [control, result] {
        const QString error = control->thcLiveTuningError();
        result(!error.isEmpty() ? error
               : control->thcLiveTuningSupported() ? QString() : QStringLiteral("V53_NOT_CONFIRMED"));
    };
    if (!control->thcLiveTuningPending()) return settle();
    auto connection = std::make_shared<QMetaObject::Connection>();
    *connection = QObject::connect(control, &MachineControlBackend::thcLiveTuningChanged, context,
                                   [control, connection, settle] {
        if (control->thcLiveTuningPending()) return;
        QObject::disconnect(*connection);
        settle();
    });
}

} // namespace ThcV53RemoteTuning
