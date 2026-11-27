#pragma once

#include "MachineControlBackend.h"
#include <QJsonObject>

// Typed owner-only socket adapter. Host support is NOT firmware attestation.
// No parameter can select arbitrary serial commands, tuning or fallback modes.
namespace ThcV51OwnerProtocol {

inline QJsonObject capability()
{
    return {
        {QStringLiteral("type"), QStringLiteral("bounded-contact-profile-v51")},
        {QStringLiteral("ownerCommand"), QStringLiteral("thc_contact_profile_v51")},
        {QStringLiteral("firmwareCommand"), QStringLiteral("THC:CONTACT_PROFILE_V51")},
        {QStringLiteral("runningMarker"), QStringLiteral("THC:CONTACT_PROFILE_V51_RUNNING")},
        {QStringLiteral("acquisitionMaxMs"), 180000},
        {QStringLiteral("holdMs"), 60000},
        {QStringLiteral("operationMaxMs"), 330000},
        {QStringLiteral("thcLeaseMs"), 2000},
        {QStringLiteral("thcHeartbeatCommand"), QStringLiteral("THC:HB")},
        {QStringLiteral("thcHeartbeatIntervalMs"), 250},
        {QStringLiteral("generalHeartbeatSeparate"), true},
        {QStringLiteral("generalHeartbeatCommand"), QStringLiteral("?")},
        {QStringLiteral("generalHeartbeatTimeoutMs"), 30000},
        {QStringLiteral("generalHeartbeatIntervalMs"), 250},
        {QStringLiteral("ordinaryContactProfileMaxMs"), 60000},
        {QStringLiteral("fallbackAllowed"), false}
    };
}

inline bool handles(const QString &command)
{
    return command == QStringLiteral("thc_contact_profile_v51")
        || command == QStringLiteral("thc_v51_heartbeat")
        || command == QStringLiteral("thc_v51_release")
        || command == QStringLiteral("thc_v51_cancel");
}

inline bool blocksUncorrelatedRequest(MachineControlBackend *control, const QString &command)
{
    return control->commandOperationActive()
        && control->operationName() == QStringLiteral("thc-contact-profile-v51")
        && (command == QStringLiteral("heartbeat") || command == QStringLiteral("thc_release"));
}

inline QJsonObject dispatch(MachineControlBackend *control, const QJsonObject &request)
{
    const QString command = request.value(QStringLiteral("command")).toString();
    const bool start = command == QStringLiteral("thc_contact_profile_v51");
    const QString argument = start ? QStringLiteral("binarySha256") : QStringLiteral("operationId");
    if (!handles(command) || request.size() != 2 || !request.contains(argument)
        || !request.value(argument).isString())
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("INVALID_ARGUMENT")}};

    if (!start && (request.value(argument).toString() != QString::number(control->operationId())
        || control->operationName() != QStringLiteral("thc-contact-profile-v51")
        || !control->commandOperationActive()))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("V51_OWNER_MISMATCH")}};

    bool accepted = false;
    if (start)
        accepted = control->startThcContactProfileV51Commissioning(request.value(argument).toString());
    else if (command == QStringLiteral("thc_v51_heartbeat"))
        accepted = control->heartbeatThcCommissioning();
    else if (command == QStringLiteral("thc_v51_release"))
        accepted = control->releaseThcCommissioning();
    else
        accepted = control->cancelThcCommissioning();

    QJsonObject response{
        {QStringLiteral("ok"), accepted},
        {QStringLiteral("operationId"), QString::number(control->operationId())},
        {QStringLiteral("operationName"), control->operationName()},
        {QStringLiteral("operationState"), control->operationState()},
        {QStringLiteral("operationError"), control->operationError()},
        {QStringLiteral("thcState"), control->thcCommissioningState()},
        {QStringLiteral("thcV51RunningAcknowledged"), control->thcV51RunningAcknowledged()},
        {QStringLiteral("thcV51PendingFailure"), control->thcV51PendingFailure()},
        {QStringLiteral("thcV51CancellationConfirmed"), control->thcV51CancellationConfirmed()},
        {QStringLiteral("pressSafetyStopUnconfirmed"), control->pressSafetyStopUnconfirmed()},
        {QStringLiteral("firmwareImageAttested"), false}
    };
    if (!accepted)
        response.insert(QStringLiteral("error"), QStringLiteral("BACKEND_GUARD_OR_DISPATCH_FAILED"));
    return response; // ok means dispatch/owner renewal, never physical completion.
}

} // namespace ThcV51OwnerProtocol