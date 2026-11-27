#pragma once

#include <QByteArray>
#include <QSet>
#include <QString>

#include <optional>

struct PressTelemetryFrame
{
    QString state;
    double y1Position = 0.0;
    double y2Position = 0.0;
    double yError = 0.0;
    double velocity = 0.0;
    double targetPosition = 0.0;
    double commandedJogPosition = 0.0;
    double jogSpeed = 0.0;
    bool safetyJogLeft = false;
    bool safetyJogRight = false;
    bool bendPedal = false;
    bool physicalPedal = false;
    bool physicalPedalAvailable = false;
    double distanceToGo = 0.0;
    double y1Tonnage = 0.0;
    double y2Tonnage = 0.0;
    bool antiBind = false;
    std::optional<double> y1MeasuredVelocity;
    std::optional<double> y2MeasuredVelocity;
    std::optional<double> y1MotorRpm;
    std::optional<double> y2MotorRpm;
};

struct PressTemporaryStatusFrame
{
    double safetyRetract = 0.0;
    bool manualModeEnabled = false;
    double manualModeMaxTonnagePerRam = 0.0;
    bool primingModeEnabled = false;
    bool primingLatchSupported = false;
    bool primingLatchY1 = false;
    bool primingLatchY2 = false;
};

struct PressEepromSettingsFrame
{
    double maxTonnageThreshold = 0.0;
    bool deflectionCompEnabled = false;
    bool watchdogEnabled = false;
    double ramToTableOpening = 0.0;
    int ramToTableOpeningDecimals = 0;
};

struct GrblPosition
{
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;
};

struct GrblTelemetryFrame
{
    QString state;
    std::optional<GrblPosition> machinePosition;
    std::optional<GrblPosition> workPosition;
    std::optional<GrblPosition> workCoordinateOffset;
    QSet<QString> activePins;
    int feedRate = 0;
    int spindleSpeed = 0;
};

namespace MachineProtocolParsers
{
std::optional<PressTelemetryFrame> parsePressTelemetry(const QByteArray &frame);
std::optional<PressTemporaryStatusFrame> parsePressTemporaryStatus(const QByteArray &frame);
std::optional<PressEepromSettingsFrame> parsePressEepromSettings(const QByteArray &frame);
std::optional<GrblTelemetryFrame> parseGrblTelemetry(const QByteArray &frame);
QString normalizePressState(const QString &state);
QString normalizeGrblState(const QString &state);
bool pressStateIsAlarm(const QString &state);
bool pressStateIsHomingCalibrationFailure(const QString &state);
}
