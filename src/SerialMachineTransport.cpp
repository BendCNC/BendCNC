#include "SerialMachineTransport.h"

#include <QDebug>
#include <QIODevice>
#include <QRegularExpression>

#include <cmath>

#ifdef Q_OS_UNIX
#include <termios.h>
#endif

namespace
{
QString roleName(SerialDeviceDiscovery::DeviceRole role)
{
    return role == SerialDeviceDiscovery::DeviceRole::Press
        ? QStringLiteral("press") : QStringLiteral("module");
}

QString visibleFrame(const QByteArray &frame)
{
    QByteArray visible = frame;
    visible.replace("\r", "\\r");
    visible.replace("\n", "\\n");
    return QString::fromLatin1(visible);
}

bool isValidatedNativeTonnageHoldFrame(const QString &text)
{
    // Keep this grammar aligned with MachineControlBackend::startTonnageHold().
    // The legacy TH form remains separately allowlisted for compatible
    // controllers; only the three-value native v1.3 command is range-checked.
    static const QRegularExpression nativeTonnageHoldPattern(
        QStringLiteral("^<TH:(\\d+(?:\\.\\d{3})),(\\d+(?:\\.\\d{3})),(\\d+(?:\\.\\d{3}))>\\n$"));
    const QRegularExpressionMatch match = nativeTonnageHoldPattern.match(text);
    if (!match.hasMatch())
        return false;

    bool targetOk = false;
    bool bendSpeedOk = false;
    bool jogSpeedOk = false;
    const double target = match.capturedView(1).toDouble(&targetOk);
    const double bendSpeed = match.capturedView(2).toDouble(&bendSpeedOk);
    const double jogSpeed = match.capturedView(3).toDouble(&jogSpeedOk);
    return targetOk && bendSpeedOk && jogSpeedOk
        && std::isfinite(target) && std::isfinite(bendSpeed) && std::isfinite(jogSpeed)
        && target >= 0.5 && target <= 24.0
        && bendSpeed >= 0.5 && bendSpeed <= 15.0
        && jogSpeed >= 0.5 && jogSpeed <= 15.0;
}

bool isValidatedRamToTableFrame(const QString &text)
{
    // Keep aligned with MachineControlBackend::setRamToTableOpening(): the
    // firmware stores $3 without a range check, so the transport enforces the
    // same 7.950-8.750 in window on the exact four-decimal wire form.
    static const QRegularExpression pattern(
        QStringLiteral("\\A<\\$3=(\\d\\.\\d{4})>\\n\\z"));
    const QRegularExpressionMatch match = pattern.match(text);
    if (!match.hasMatch())
        return false;
    bool ok = false;
    const double opening = match.capturedView(1).toDouble(&ok);
    return ok && std::isfinite(opening) && opening >= 7.950 && opening <= 8.750;
}

bool isValidatedToolChangeFrame(const QString &text)
{
    // Keep aligned with MachineControlBackend tool-change TOUCH/MOVE/SEAT.
    if (text == QStringLiteral("<TCH?>\n"))
        return true;
    static const QRegularExpression touchPattern(QStringLiteral(
        "\\A<THC:TOUCH:(0\\.125|0\\.250),(-[0-9]\\.[0-9]{4})>\\n\\z"));
    static const QRegularExpression movePattern(QStringLiteral(
        "\\A<THC:MOVE:(-[0-9]\\.[0-9]{4})>\\n\\z"));
    static const QRegularExpression seatPattern(QStringLiteral(
        "\\A<TH:SEAT:([0-9]{1,2}\\.[0-9]{3}),([0-9]{1,2}\\.[0-9]{3}),(-?[0-9]\\.[0-9]{4})>\\n\\z"));
    bool ok = false;
    if (const auto m = touchPattern.match(text); m.hasMatch()) {
        const double floor = m.capturedView(2).toDouble(&ok);
        return ok && floor >= -4.0 && floor <= -0.05;
    }
    if (const auto m = movePattern.match(text); m.hasMatch()) {
        const double target = m.capturedView(1).toDouble(&ok);
        return ok && target >= -3.99 && target <= -0.05;
    }
    if (const auto m = seatPattern.match(text); m.hasMatch()) {
        bool ok2 = false, ok3 = false;
        const double bend = m.capturedView(1).toDouble(&ok);
        const double jog = m.capturedView(2).toDouble(&ok2);
        const double plane = m.capturedView(3).toDouble(&ok3);
        return ok && ok2 && ok3 && bend >= 0.5 && bend <= 15.0
            && jog >= 0.5 && jog <= 15.0 && plane >= -4.0 && plane <= 0.0;
    }
    return false;
}

bool isValidatedThcFrame(const QString &text)
{
    if (text == QStringLiteral("<THC:TUNE?>\n")
        || text == QStringLiteral("<THC:V53?>\n"))
        return true;
    if (text == QStringLiteral("<THC:START>\n") || text == QStringLiteral("<THC:HB>\n")
        || text == QStringLiteral("<THC:RELEASE>\n") || text == QStringLiteral("<THC:CANCEL>\n"))
        return true;
    if (text == QStringLiteral("<THC:CONTACT_PROFILE>\n")
        || text == QStringLiteral("<THC:CONTACT_PROFILE_V51>\n")
        || text == QStringLiteral("<THC:CONTACT_PROFILE_V53>\n"))
        return true;
    // V53 approach-speed suffix sent by startThcContactProfileV53 (84cd9e3).
    if (text.startsWith(QStringLiteral("<THC:CONTACT_PROFILE_V53:"))) {
        static const QRegularExpression v53Pattern(QStringLiteral(
            "\\A<THC:CONTACT_PROFILE_V53:((?:0|[1-9][0-9]?)\\.[0-9]{3})>\\n\\z"));
        const QRegularExpressionMatch v53 = v53Pattern.match(text);
        if (!v53.hasMatch()) return false;
        bool ok = false;
        const double ipm = v53.capturedView(1).toDouble(&ok);
        return ok && std::isfinite(ipm) && ipm >= 0.5 && ipm <= 15.0;
    }
    // Optional AUTO target suffix. Keep aligned with
    // MachineControlBackend::startThcContactProfileCommissioning() and the V53
    // firmware window (TONNAGE_HOLD_MIN_TARGET..THC_CONTACT_PROFILE_MAX_TARGET_T).
    if (text.startsWith(QStringLiteral("<THC:CONTACT_PROFILE:"))) {
        static const QRegularExpression targetPattern(QStringLiteral(
            "\\A<THC:CONTACT_PROFILE:((?:0|[1-9][0-9]?)\\.[0-9]{3})(?:,((?:0|[1-9][0-9]?)\\.[0-9]{3}))?>\\n\\z"));
        const QRegularExpressionMatch target = targetPattern.match(text);
        if (!target.hasMatch()) return false;
        bool ok = false;
        const double tons = target.capturedView(1).toDouble(&ok);
        if (!ok || !std::isfinite(tons) || tons < 0.5 || tons > 20.0) return false;
        if (target.capturedView(2).isEmpty()) return true;
        const double ipm = target.capturedView(2).toDouble(&ok);
        return ok && std::isfinite(ipm) && ipm >= 0.5 && ipm <= 15.0;
    }
    // V53 has a 128-byte payload (excluding <, > and newline), NOT the
    // macro-off 64-byte limit. Admit only the backend's canonical wire form.
    if (text.startsWith(QStringLiteral("<THC:V53:TUNE:"))) {
        static const QRegularExpression tunePattern(QStringLiteral(
            "\\A<THC:V53:TUNE:(0|[1-9][0-9]{0,9}),([0-9]+\\.[0-9]{6}),([0-9]+\\.[0-9]{6}),([0-9]+\\.[0-9]{6}),([0-9]+\\.[0-9]{6}),([0-9]+\\.[0-9]{6}),([0-9]+\\.[0-9]{6})>\\n\\z"));
        const auto tune = tunePattern.match(text);
        if (!tune.hasMatch() || text.size() - 3 > 128) return false;
        bool ok = false;
        const auto revision = tune.captured(1).toULongLong(&ok);
        if (!ok || revision == 0 || revision > 4294967295ULL) return false;
        double values[6];
        const double low[] = {0, 0, 0, 0.002, 0.005, 0.020};
        const double high[] = {0.30, 0.04, 0.06, 0.010, 0.020, 0.100};
        static const QRegularExpression extendedNumber(QStringLiteral(
            "\\A(?:0|[1-9][0-9]{0,8})\\.[0-9]{6}\\z"));
        // Stateless union: retain historical v1 frames (including padding).
        // Only the backend's negotiated capability authorizes expanded writes.
        bool legacy = true;
        bool extended = true;
        for (int i = 0; i < 6; ++i) {
            const QString value = tune.captured(i + 2);
            values[i] = value.toDouble(&ok);
            if (!ok || !std::isfinite(values[i])) return false;
            legacy = legacy && values[i] >= low[i] && values[i] <= high[i];
            extended = extended && extendedNumber.match(value).hasMatch()
                && values[i] >= (i == 5 ? 0.000001 : 0.0)
                && values[i] <= 999999999.999999;
        }
        return (legacy || extended) && values[5] > values[4];
    }
    static const QRegularExpression armPattern(
        QStringLiteral("^<THC:ARM:(\\d+\\.\\d{3}),(\\d+\\.\\d{3}),(-\\d+\\.\\d{3})>\\n$"));
    const QRegularExpressionMatch match = armPattern.match(text);
    if (!match.hasMatch()) return false;
    bool targetOk = false, speedOk = false, floorOk = false;
    const double target = match.capturedView(1).toDouble(&targetOk);
    const double speed = match.capturedView(2).toDouble(&speedOk);
    const double floor = match.capturedView(3).toDouble(&floorOk);
    return targetOk && speedOk && floorOk && std::isfinite(target) && std::isfinite(speed)
        && std::isfinite(floor) && target >= 0.5 && target <= 1.0
        && speed >= 0.5 && speed <= 1.0 && std::abs(floor + 0.5) < 1e-9;
}

}

SerialMachineTransport::SerialMachineTransport(SerialDeviceDiscovery *discovery,
                                               SerialDeviceDiscovery::DeviceRole role,
                                               bool diagnosticLoggingEnabled,
                                               QObject *parent)
    : MachineTransport(parent)
    , m_discovery(discovery)
    , m_role(role)
    , m_diagnosticLoggingEnabled(diagnosticLoggingEnabled)
{
    Q_ASSERT(m_discovery);
    connect(m_discovery, &SerialDeviceDiscovery::selectionsChanged,
            this, &SerialMachineTransport::onSelectionChanged);
    using Port = decltype(m_port);
    connect(&m_port, &Port::readyRead, this, &SerialMachineTransport::onReadyRead);
    connect(&m_port, &Port::bytesWritten,
            this, &SerialMachineTransport::onBytesWritten);
    connect(&m_port, &Port::errorOccurred,
            this, &SerialMachineTransport::onSerialError);
}

bool SerialMachineTransport::isAvailable() const
{
    return selection().available;
}

QString SerialMachineTransport::endpointId() const
{
    return SerialDeviceDiscovery::stableEndpointId(selection().port);
}

QString SerialMachineTransport::endpointDisplayName() const
{
    return SerialDeviceDiscovery::displayName(selection().port);
}

bool SerialMachineTransport::open()
{
    if (m_port.isOpen())
        return true;
    SerialDeviceDiscovery::Selection selected = selection();
    if (m_discovery) {
        m_discovery->refresh();
        selected = selection();
    }
    if (!selected.available) {
        emit transportError(selected.error.isEmpty() ? QStringLiteral("ENDPOINT_ABSENT")
                                                     : selected.error);
        return false;
    }

    m_port.setPortName(selected.port.portName);
    m_port.setBaudRate(QSerialPort::Baud115200);
    m_port.setDataBits(QSerialPort::Data8);
    m_port.setParity(QSerialPort::NoParity);
    m_port.setStopBits(QSerialPort::OneStop);
    m_port.setFlowControl(QSerialPort::NoFlowControl);
    m_port.setReadBufferSize(MaximumBufferedBytes);
    m_receiveBuffer.clear();
    m_openEndpointId = SerialDeviceDiscovery::stableEndpointId(selected.port);
    m_openPortName = selected.port.portName;
    m_opening = true;
    const bool portOpened = m_port.open(QIODevice::ReadWrite);
    m_opening = false;
    if (!portOpened) {
        const QString error = QStringLiteral("OPEN_FAILED: ") + m_port.errorString();
        qWarning().noquote() << "SERIAL-OPEN role=" + roleName(m_role)
                             << "endpoint=" + selected.port.portName
                             << "result=failed error=" + error;
        m_openEndpointId.clear();
        m_openPortName.clear();
        emit transportError(error);
        return false;
    }
#if defined(Q_OS_UNIX) && !defined(Q_OS_ANDROID)
    termios options {};
    const int descriptor = static_cast<int>(m_port.handle());
    if (descriptor < 0 || ::tcgetattr(descriptor, &options) != 0) {
        failClosed(QStringLiteral("TERMIOS_READ_FAILED"));
        return false;
    }
    options.c_cflag &= ~HUPCL;
    if (::tcsetattr(descriptor, TCSANOW, &options) != 0) {
        failClosed(QStringLiteral("TERMIOS_WRITE_FAILED"));
        return false;
    }
#endif
    qInfo().noquote() << "SERIAL-OPEN role=" + roleName(m_role)
                      << "endpoint=" + selected.port.portName
                      << "result=opened baud=115200 hupcl=off";
    emit opened();
    return true;
}

void SerialMachineTransport::close()
{
    if (!m_port.isOpen()) {
        m_receiveBuffer.clear();
        m_openEndpointId.clear();
        m_openPortName.clear();
        return;
    }
    m_closing = true;
    m_port.close();
    m_closing = false;
    m_receiveBuffer.clear();
    m_openEndpointId.clear();
    m_openPortName.clear();
    emit closed();
}

bool SerialMachineTransport::writeFrame(const QByteArray &frame)
{
    emit frameWriteAttempted(frame);
    if (!m_port.isOpen()) {
        // This is an operation-admission failure, not proof that an owned
        // serial endpoint was lost. The backend receives false and fails only
        // the requesting operation.
        qWarning().noquote() << "SERIAL-TX role=" + roleName(m_role)
                             << "result=not-open frame=" + visibleFrame(frame);
        return false;
    }
    if (!isWriteFrameAllowed(m_role, frame)) {
        qWarning().noquote() << "SERIAL-TX role=" + roleName(m_role)
                             << "result=disabled frame=" + visibleFrame(frame);
        // Exact allowlist rejection is local and must never tear down a valid
        // machine connection. The caller handles the false return as an
        // operation failure.
        return false;
    }
    const qint64 written = m_port.write(frame);
    if (written != frame.size()) {
        failClosed(QStringLiteral("SHORT_WRITE"));
        return false;
    }
    // QSerialPort::write() queues an asynchronous write. flush() only asks the
    // backend to push currently buffered bytes and may return false during USB
    // re-enumeration even though the accepted write completes moments later.
    // Real WriteError/ResourceError signals still fail closed in onSerialError.
    if (m_diagnosticLoggingEnabled) {
        qInfo().noquote() << "SERIAL-TX role=" + roleName(m_role)
                          << "frame=" + visibleFrame(frame)
                          << "pending=" + QString::number(m_port.bytesToWrite());
    }
    emit frameWritten(machineLogContent(frame));
    return true;
}

void SerialMachineTransport::setDiagnosticLoggingEnabled(bool enabled)
{
    if (m_diagnosticLoggingEnabled == enabled)
        return;
    m_diagnosticLoggingEnabled = enabled;
    qInfo().noquote() << "SERIAL-DIAGNOSTICS role=" + roleName(m_role)
                      << "enabled=" + QString(enabled ? QStringLiteral("true")
                                                       : QStringLiteral("false"));
}

QByteArray SerialMachineTransport::machineLogContent(const QByteArray &frame)
{
    QByteArray content = frame;
    while (content.endsWith('\n') || content.endsWith('\r'))
        content.chop(1);
    if (content.size() == 1) {
        const unsigned char value = static_cast<unsigned char>(content.at(0));
        if (value < 0x20 || value >= 0x7f)
            return QByteArrayLiteral("Byte 0x")
                + QByteArray::number(value, 16).rightJustified(2, '0').toUpper();
    }
    return content;
}

bool SerialMachineTransport::isWriteFrameAllowed(SerialDeviceDiscovery::DeviceRole role,
                                                 const QByteArray &frame)
{
    static const QRegularExpression pressJogPattern(
        QStringLiteral("^<-?\\d+(?:\\.\\d{4}), \\d+(?:\\.\\d{4}), (?:safety|retract|clamp|bend|bump|panel-retract|panel-advance)>\\n$"));
    static const QRegularExpression pressSettingPattern(
        QStringLiteral("^<\\$R=-?\\d+(?:\\.\\d{4})>\\n$"));
    static const QRegularExpression pressManualTonnagePattern(
        QStringLiteral("^<\\$MT=\\d+(?:\\.\\d{4})>\\n$"));
    static const QRegularExpression pressRunPedalModePattern(
        QStringLiteral("^<\\$PM=[0-4]>\\n$"));
    static const QRegularExpression pressTonnageHoldPattern(
        QStringLiteral("^<TH:\\d+(?:\\.\\d{3}),0,[01]>\\n$"));
    static const QRegularExpression moduleJogPattern(
        QStringLiteral("^\\$J=G2[01] G91 [XY]-?\\d+(?:\\.\\d{4}) F \\d+\\n$"));
    static const QRegularExpression moduleMovePattern(
        QStringLiteral("^G2[01] G90 G5[4-9] G1 [XY]-?\\d+(?:\\.\\d{4}) F\\d+(?:\\.\\d{2})\\n$"));
    static const QRegularExpression moduleIncrementalMovePattern(
        QStringLiteral("^G2[01] G91 G5[4-9] [XY] -?\\d+(?:\\.\\d{4}) F \\d+(?:\\.\\d{2})\\n$"));
    static const QRegularExpression moduleCoordinatePattern(
        QStringLiteral("^G5[4-9]\\n$"));
    static const QRegularExpression moduleSetCoordinatePattern(
        QStringLiteral("^G20 G10 P[1-6] L20 [XY] -?\\d+(?:\\.\\d{4})\\n$"));
    const QString text = QString::fromLatin1(frame);
    const bool pressFrame = role == SerialDeviceDiscovery::DeviceRole::Press
        && (frame == QByteArrayLiteral("<!>\n") || frame == QByteArrayLiteral("<!?>\n")
            || frame == QByteArrayLiteral("<?>\n")
            || frame == QByteArrayLiteral("<VER>\n")
            || frame == QByteArrayLiteral("<$H>\n")
            || frame == QByteArrayLiteral("<ManualEnable>\n")
            || frame == QByteArrayLiteral("<ManualDisable>\n")
            || frame == QByteArrayLiteral("<PrimingEnable>\n")
            || frame == QByteArrayLiteral("<PrimingDisable>\n")
            || frame == QByteArrayLiteral("<PrimingLatch:Y1>\n")
            || frame == QByteArrayLiteral("<PrimingLatch:Y2>\n")
            || frame == QByteArrayLiteral("<PrimingRelease:Y1>\n")
            || frame == QByteArrayLiteral("<PrimingRelease:Y2>\n")
            || frame == QByteArrayLiteral("<PrimingHeartbeat>\n")
            || frame == QByteArrayLiteral("<HydraulicShutdown>\n")
            || frame == QByteArrayLiteral("<cancel>\n")
            || frame == QByteArrayLiteral("<hold>\n")
            || frame == QByteArrayLiteral("<stop>\n")
            || pressJogPattern.match(text).hasMatch()
            || pressSettingPattern.match(text).hasMatch()
            || isValidatedRamToTableFrame(text)
            || pressManualTonnagePattern.match(text).hasMatch()
            || pressRunPedalModePattern.match(text).hasMatch()
            // The retained two-field form is a legacy compatibility command.
            // Native v1.3 frames must pass the exact, finite, bounded grammar.
            || pressTonnageHoldPattern.match(text).hasMatch()
            || isValidatedNativeTonnageHoldFrame(text)
            || frame == QByteArrayLiteral("<TH:HB>\n")
            || isValidatedThcFrame(text)
            || isValidatedToolChangeFrame(text));
    const bool moduleFrame = role == SerialDeviceDiscovery::DeviceRole::Module
        && (frame == QByteArrayLiteral("\x18") || frame == QByteArrayLiteral("$$\n")
            || frame == QByteArrayLiteral("$G\n") || frame == QByteArrayLiteral("?")
            || frame == QByteArrayLiteral("$X\n") || frame == QByteArrayLiteral("$H\n")
            || frame == QByteArrayLiteral("!") || frame == QByteArrayLiteral("\x85")
            || moduleJogPattern.match(text).hasMatch()
            || moduleMovePattern.match(text).hasMatch()
            || moduleIncrementalMovePattern.match(text).hasMatch()
            || moduleCoordinatePattern.match(text).hasMatch()
            || moduleSetCoordinatePattern.match(text).hasMatch());
    return pressFrame || moduleFrame;
}

void SerialMachineTransport::onSelectionChanged()
{
    emit availabilityChanged();
    if (!m_port.isOpen())
        return;
    const SerialDeviceDiscovery::Selection selected = selection();
    const QString selectedId = SerialDeviceDiscovery::stableEndpointId(selected.port);
    if (!selected.available || selectedId != m_openEndpointId
            || selected.port.portName != m_openPortName)
        failClosed(QStringLiteral("DEVICE_REMOVED"));
}

void SerialMachineTransport::onReadyRead()
{
    m_receiveBuffer.append(m_port.readAll());
    if (m_receiveBuffer.size() > MaximumBufferedBytes) {
        failClosed(QStringLiteral("RECEIVE_OVERFLOW"));
        return;
    }
    processReceiveBuffer();
}

void SerialMachineTransport::onSerialError(QSerialPort::SerialPortError error)
{
    if (error == QSerialPort::NoError || m_opening || m_closing)
        return;
    if (error == QSerialPort::ResourceError || error == QSerialPort::DeviceNotFoundError
        || error == QSerialPort::ReadError || error == QSerialPort::WriteError) {
        failClosed(QStringLiteral("SERIAL_ERROR: ") + m_port.errorString());
    }
}

void SerialMachineTransport::onBytesWritten(qint64 bytes)
{
    if (!m_diagnosticLoggingEnabled)
        return;
    qInfo().noquote() << "SERIAL-WRITTEN role=" + roleName(m_role)
                      << "bytes=" + QString::number(bytes)
                      << "pending=" + QString::number(m_port.bytesToWrite());
}

SerialDeviceDiscovery::Selection SerialMachineTransport::selection() const
{
    if (!m_discovery)
        return {};
    return m_role == SerialDeviceDiscovery::DeviceRole::Press
        ? m_discovery->pressSelection() : m_discovery->moduleSelection();
}

void SerialMachineTransport::processReceiveBuffer()
{
    while (true) {
        const qsizetype newline = m_receiveBuffer.indexOf('\n');
        const qsizetype carriage = m_receiveBuffer.indexOf('\r');
        qsizetype delimiter = -1;
        if (newline >= 0 && carriage >= 0)
            delimiter = qMin(newline, carriage);
        else
            delimiter = qMax(newline, carriage);
        if (delimiter < 0)
            break;
        if (delimiter > MaximumFrameBytes) {
            failClosed(QStringLiteral("FRAME_OVERFLOW"));
            return;
        }
        QByteArray frame = m_receiveBuffer.left(delimiter);
        qsizetype consume = delimiter + 1;
        if (consume < m_receiveBuffer.size()) {
            const char first = m_receiveBuffer.at(delimiter);
            const char second = m_receiveBuffer.at(consume);
            if ((first == '\r' && second == '\n') || (first == '\n' && second == '\r'))
                ++consume;
        }
        m_receiveBuffer.remove(0, consume);
        if (!frame.isEmpty()) {
            if (m_diagnosticLoggingEnabled) {
                qInfo().noquote() << "SERIAL-RX role=" + roleName(m_role)
                                  << "frame=" + visibleFrame(frame);
            }
            emit frameReceived(frame);
        }
    }
    if (m_receiveBuffer.size() > MaximumFrameBytes)
        failClosed(QStringLiteral("FRAME_OVERFLOW"));
}

void SerialMachineTransport::failClosed(const QString &message)
{
    const bool wasOpen = m_port.isOpen();
    m_closing = true;
    if (wasOpen)
        m_port.close();
    m_closing = false;
    m_receiveBuffer.clear();
    m_openEndpointId.clear();
    m_openPortName.clear();
    qWarning().noquote() << "SERIAL-CLOSE role=" + roleName(m_role)
                         << "reason=" + message;
    emit transportError(message);
    if (wasOpen)
        emit closed();
}
