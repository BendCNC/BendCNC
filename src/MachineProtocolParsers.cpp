#include "MachineProtocolParsers.h"

#include <QRegularExpression>

#include <cmath>

namespace
{
bool parseFiniteDouble(const QString &text, double &value)
{
    bool ok = false;
    value = text.toDouble(&ok);
    return ok && std::isfinite(value);
}

bool parseInteger(const QString &text, int &value)
{
    bool ok = false;
    const double parsed = text.toDouble(&ok);
    if (!ok || !std::isfinite(parsed))
        return false;
    value = static_cast<int>(parsed);
    return true;
}

std::optional<GrblPosition> parsePosition(const QString &value)
{
    const QStringList parts = value.split(QLatin1Char(','));
    if (parts.size() != 3)
        return std::nullopt;
    GrblPosition position;
    if (!parseFiniteDouble(parts.at(0), position.x)
        || !parseFiniteDouble(parts.at(1), position.y)
        || !parseFiniteDouble(parts.at(2), position.z)) {
        return std::nullopt;
    }
    return position;
}

QSet<QString> parsePins(const QString &value)
{
    static const QRegularExpression pinPattern(QStringLiteral("[A-Z][0-9]?"));
    QSet<QString> pins;
    auto iterator = pinPattern.globalMatch(value.toUpper());
    while (iterator.hasNext())
        pins.insert(iterator.next().captured());
    return pins;
}
}

namespace MachineProtocolParsers
{
QString normalizePressState(const QString &state)
{
    QString normalized = state.trimmed().toUpper();
    normalized.replace(QRegularExpression(QStringLiteral("[-/\\s]+")), QStringLiteral("_"));
    normalized.remove(QRegularExpression(QStringLiteral("[.\\s]+")));
    static const QSet<QString> states = {
        QStringLiteral("STARTUP_HOMING_REQUIRED"), QStringLiteral("HOMING"),
        QStringLiteral("HOMING_BUMP"), QStringLiteral("SAFETY_JOG"),
        QStringLiteral("SAFETY_JOG_HOLD"), QStringLiteral("CLAMP_JOG"),
        QStringLiteral("CLAMP_JOG_HOLD"), QStringLiteral("BEND_JOG"),
        QStringLiteral("BEND_DEPTH_REACHED"), QStringLiteral("BEND_JOG_HOLD"),
        QStringLiteral("RETRACT_JOG"), QStringLiteral("RELEASE_LOAD_RETRACT"),
        QStringLiteral("IDLE"), QStringLiteral("PRIMING_MODE"),
        QStringLiteral("ANTIBIND_TRIGGERED"), QStringLiteral("ENCODER_SYNC_ERROR"),
        QStringLiteral("Y1_TONNAGE_CALIB_FAIL"), QStringLiteral("Y2_TONNAGE_CALIB_FAIL"),
        QStringLiteral("Y1_Y2_TONNAGE_CALIB_FAIL"), QStringLiteral("Y1_NEG_TONN_FAIL"),
        QStringLiteral("Y2_NEG_TONN_FAIL"), QStringLiteral("Y1_Y2_NEG_TONN_FAIL"),
        QStringLiteral("STEADY_STATE_MOTION"), QStringLiteral("MACHINE_TRACKING_ERROR"),
        QStringLiteral("MAX_TONNAGE_ERROR"), QStringLiteral("STATIONARY_LOAD_TIMEOUT"),
        QStringLiteral("HYDRAULIC_SHUTDOWN")
    };
    return states.contains(normalized) ? normalized : QStringLiteral("UNKNOWN");
}

QString normalizeGrblState(const QString &state)
{
    QString normalized = state.trimmed().toUpper();
    normalized.replace(QLatin1Char(':'), QLatin1Char('_'));
    static const QSet<QString> states = {
        QStringLiteral("IDLE"), QStringLiteral("RUN"), QStringLiteral("HOLD_0"),
        QStringLiteral("HOLD_1"), QStringLiteral("JOG"), QStringLiteral("ALARM"),
        QStringLiteral("DOOR_0"), QStringLiteral("DOOR_1"), QStringLiteral("DOOR_2"),
        QStringLiteral("DOOR_3"), QStringLiteral("CHECK"), QStringLiteral("HOME"),
        QStringLiteral("SLEEP"), QStringLiteral("WAIT_1")
    };
    return states.contains(normalized) ? normalized : QStringLiteral("UNKNOWN");
}

bool pressStateIsAlarm(const QString &state)
{
    static const QSet<QString> alarms = {
        QStringLiteral("ANTIBIND_TRIGGERED"), QStringLiteral("ENCODER_SYNC_ERROR"),
        QStringLiteral("Y1_TONNAGE_CALIB_FAIL"), QStringLiteral("Y2_TONNAGE_CALIB_FAIL"),
        QStringLiteral("Y1_Y2_TONNAGE_CALIB_FAIL"), QStringLiteral("Y1_NEG_TONN_FAIL"),
        QStringLiteral("Y2_NEG_TONN_FAIL"), QStringLiteral("Y1_Y2_NEG_TONN_FAIL"),
        QStringLiteral("STEADY_STATE_MOTION"), QStringLiteral("MACHINE_TRACKING_ERROR"),
        QStringLiteral("MAX_TONNAGE_ERROR"), QStringLiteral("STATIONARY_LOAD_TIMEOUT"),
        QStringLiteral("HYDRAULIC_SHUTDOWN")
    };
    return alarms.contains(state);
}

bool pressStateIsHomingCalibrationFailure(const QString &state)
{
    static const QSet<QString> failures = {
        QStringLiteral("Y1_TONNAGE_CALIB_FAIL"),
        QStringLiteral("Y2_TONNAGE_CALIB_FAIL"),
        QStringLiteral("Y1_Y2_TONNAGE_CALIB_FAIL")
    };
    return failures.contains(state);
}

std::optional<PressTelemetryFrame> parsePressTelemetry(const QByteArray &frame)
{
    const QString line = QString::fromLatin1(frame).trimmed();
    if (!line.startsWith(QLatin1Char('<')) || !line.endsWith(QLatin1Char('>')))
        return std::nullopt;
    const QStringList fields = line.mid(1, line.size() - 2).split(QLatin1Char('|'));
    if (fields.size() < 15)
        return std::nullopt;

    PressTelemetryFrame result;
    result.state = normalizePressState(fields.at(0));
    if (!parseFiniteDouble(fields.at(1), result.y1Position)
        || !parseFiniteDouble(fields.at(2), result.y2Position)
        || !parseFiniteDouble(fields.at(3), result.yError)
        || !parseFiniteDouble(fields.at(4), result.velocity)
        || !parseFiniteDouble(fields.at(5), result.targetPosition)
        || !parseFiniteDouble(fields.at(6), result.commandedJogPosition)
        || !parseFiniteDouble(fields.at(7), result.jogSpeed)
        || !parseFiniteDouble(fields.at(11), result.distanceToGo)
        || !parseFiniteDouble(fields.at(12), result.y1Tonnage)
        || !parseFiniteDouble(fields.at(13), result.y2Tonnage)) {
        return std::nullopt;
    }
    if ((fields.at(8) != QStringLiteral("0") && fields.at(8) != QStringLiteral("1"))
        || (fields.at(9) != QStringLiteral("0") && fields.at(9) != QStringLiteral("1"))
        || (fields.at(10) != QStringLiteral("0") && fields.at(10) != QStringLiteral("1"))
        || (fields.at(14) != QStringLiteral("0") && fields.at(14) != QStringLiteral("1"))) {
        return std::nullopt;
    }
    result.safetyJogLeft = fields.at(8) == QStringLiteral("0");
    result.safetyJogRight = fields.at(9) == QStringLiteral("0");
    result.bendPedal = fields.at(10) == QStringLiteral("1");
    result.antiBind = fields.at(14) == QStringLiteral("1");
    if (fields.size() >= 17) {
        double y1MeasuredVelocity = 0.0;
        double y2MeasuredVelocity = 0.0;
        if (!parseFiniteDouble(fields.at(15), y1MeasuredVelocity)
            || !parseFiniteDouble(fields.at(16), y2MeasuredVelocity)) {
            return std::nullopt;
        }
        result.y1MeasuredVelocity = y1MeasuredVelocity;
        result.y2MeasuredVelocity = y2MeasuredVelocity;
    }
    if (fields.size() >= 19) {
        double y1MotorRpm = 0.0;
        double y2MotorRpm = 0.0;
        if (!parseFiniteDouble(fields.at(17), y1MotorRpm)
            || !parseFiniteDouble(fields.at(18), y2MotorRpm)) {
            return std::nullopt;
        }
        result.y1MotorRpm = y1MotorRpm;
        result.y2MotorRpm = y2MotorRpm;
    }
    // Production appends the physical pedal at index 19. New diagnostic
    // firmware preserves its legacy indices 19..26 and appends the same bit at
    // index 27. Older diagnostic frames have 27 fields and use the fallback.
    const int physicalPedalIndex = fields.size() == 20 ? 19
        : (fields.size() == 28 ? 27 : -1);
    if (physicalPedalIndex >= 0) {
        if (fields.at(physicalPedalIndex) != QStringLiteral("0")
            && fields.at(physicalPedalIndex) != QStringLiteral("1")) {
            return std::nullopt;
        }
        result.physicalPedal = fields.at(physicalPedalIndex) == QStringLiteral("1");
        result.physicalPedalAvailable = true;
    } else {
        // Legacy controllers expose only the admitted/double-tap pedal bit.
        result.physicalPedal = result.bendPedal;
    }
    return result;
}

std::optional<PressTemporaryStatusFrame> parsePressTemporaryStatus(const QByteArray &frame)
{
    const QString line = QString::fromLatin1(frame).trimmed();
    const bool angleDelimited = line.startsWith(QStringLiteral("<TEMP:"))
        && line.endsWith(QLatin1Char('>'));
    const bool braceDelimited = line.startsWith(QStringLiteral("{TEMP:"))
        && line.endsWith(QLatin1Char('}'));
    if (!angleDelimited && !braceDelimited)
        return std::nullopt;
    const QStringList fields = line.mid(6, line.size() - 7).split(QLatin1Char('|'));
    // Original controllers report exactly four fields.  The per-axis Bleed
    // latch extension is exactly seven fields; reject partial/unknown forms.
    if (fields.size() != 4 && fields.size() != 7)
        return std::nullopt;

    PressTemporaryStatusFrame result;
    if (!parseFiniteDouble(fields.at(0), result.safetyRetract)
        || !parseFiniteDouble(fields.at(2), result.manualModeMaxTonnagePerRam)
        || (fields.at(1) != QStringLiteral("0") && fields.at(1) != QStringLiteral("1"))
        || (fields.at(3) != QStringLiteral("0") && fields.at(3) != QStringLiteral("1"))) {
        return std::nullopt;
    }
    result.manualModeEnabled = fields.at(1) == QStringLiteral("1");
    result.primingModeEnabled = fields.at(3) == QStringLiteral("1");
    if (fields.size() == 7) {
        if (fields.at(4) != QStringLiteral("1")
            || (fields.at(5) != QStringLiteral("0") && fields.at(5) != QStringLiteral("1"))
            || (fields.at(6) != QStringLiteral("0") && fields.at(6) != QStringLiteral("1"))) {
            return std::nullopt;
        }
        result.primingLatchSupported = true;
        result.primingLatchY1 = fields.at(5) == QStringLiteral("1");
        result.primingLatchY2 = fields.at(6) == QStringLiteral("1");
    }
    return result;
}

std::optional<PressEepromSettingsFrame> parsePressEepromSettings(const QByteArray &frame)
{
    const QString line = QString::fromLatin1(frame).trimmed();
    if (!line.startsWith(QStringLiteral("{EEPROM:"))
        || !line.endsWith(QLatin1Char('}'))) {
        return std::nullopt;
    }
    const QStringList fields = line.mid(8, line.size() - 9).split(QLatin1Char('|'));
    if (fields.size() != 10)
        return std::nullopt;

    PressEepromSettingsFrame result;
    if (!parseFiniteDouble(fields.at(0), result.maxTonnageThreshold)
        || !parseFiniteDouble(fields.at(3), result.ramToTableOpening)
        || (fields.at(1) != QStringLiteral("0") && fields.at(1) != QStringLiteral("1"))
        || (fields.at(2) != QStringLiteral("0") && fields.at(2) != QStringLiteral("1"))
        || !(result.ramToTableOpening > 0.0)) {
        return std::nullopt;
    }
    for (qsizetype index = 4; index < fields.size(); ++index) {
        double ignored = 0.0;
        if (!parseFiniteDouble(fields.at(index), ignored))
            return std::nullopt;
    }
    const QString opening = fields.at(3).trimmed();
    const qsizetype point = opening.indexOf(QLatin1Char('.'));
    result.ramToTableOpeningDecimals = point < 0 ? 0 : int(opening.size() - point - 1);
    result.deflectionCompEnabled = fields.at(1) == QStringLiteral("1");
    result.watchdogEnabled = fields.at(2) == QStringLiteral("1");
    return result;
}

std::optional<GrblTelemetryFrame> parseGrblTelemetry(const QByteArray &frame)
{
    const QString line = QString::fromLatin1(frame).trimmed();
    if (!line.startsWith(QLatin1Char('<')) || !line.endsWith(QLatin1Char('>')))
        return std::nullopt;
    const QStringList fields = line.mid(1, line.size() - 2).split(QLatin1Char('|'));
    if (fields.isEmpty())
        return std::nullopt;

    GrblTelemetryFrame result;
    result.state = normalizeGrblState(fields.at(0));
    if (result.state == QStringLiteral("UNKNOWN"))
        return std::nullopt;

    for (qsizetype index = 1; index < fields.size(); ++index) {
        const QString &field = fields.at(index);
        const qsizetype separator = field.indexOf(QLatin1Char(':'));
        if (separator <= 0)
            return std::nullopt;
        const QString name = field.left(separator);
        const QString value = field.mid(separator + 1);
        if (name == QStringLiteral("MPos")) {
            result.machinePosition = parsePosition(value);
            if (!result.machinePosition)
                return std::nullopt;
        } else if (name == QStringLiteral("WPos")) {
            result.workPosition = parsePosition(value);
            if (!result.workPosition)
                return std::nullopt;
        } else if (name == QStringLiteral("WCO")) {
            result.workCoordinateOffset = parsePosition(value);
            if (!result.workCoordinateOffset)
                return std::nullopt;
        } else if (name == QStringLiteral("Pn")) {
            result.activePins = parsePins(value);
        } else if (name == QStringLiteral("F")) {
            if (!parseInteger(value, result.feedRate))
                return std::nullopt;
        } else if (name == QStringLiteral("FS")) {
            const QStringList rates = value.split(QLatin1Char(','));
            if (rates.size() != 2 || !parseInteger(rates.at(0), result.feedRate)
                || !parseInteger(rates.at(1), result.spindleSpeed)) {
                return std::nullopt;
            }
        }
    }
    if (!result.machinePosition && !result.workPosition)
        return std::nullopt;
    return result;
}
}
