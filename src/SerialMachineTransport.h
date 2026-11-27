#pragma once

#include "MachineTransport.h"
#include "SerialDeviceDiscovery.h"

#include <QByteArray>
#include <QSerialPort>
#ifdef Q_OS_ANDROID
#include "AndroidUsbSerialPort.h"
#endif

class SerialMachineTransport final : public MachineTransport
{
    Q_OBJECT

public:
    static constexpr qsizetype MaximumBufferedBytes = 16 * 1024;
    static constexpr qsizetype MaximumFrameBytes = 4096;

    SerialMachineTransport(SerialDeviceDiscovery *discovery,
                           SerialDeviceDiscovery::DeviceRole role,
                           bool diagnosticLoggingEnabled = true,
                           QObject *parent = nullptr);

    bool isAvailable() const override;
    bool isOpen() const override { return m_port.isOpen(); }
    QString endpointId() const override;
    QString endpointDisplayName() const override;
    bool open() override;
    void close() override;
    bool writeFrame(const QByteArray &frame) override;
    void setDiagnosticLoggingEnabled(bool enabled) override;
    bool diagnosticLoggingEnabled() const override { return m_diagnosticLoggingEnabled; }
    static bool isWriteFrameAllowed(SerialDeviceDiscovery::DeviceRole role,
                                    const QByteArray &frame);
    static QByteArray machineLogContent(const QByteArray &frame);

private slots:
    void onSelectionChanged();
    void onReadyRead();
    void onBytesWritten(qint64 bytes);
    void onSerialError(QSerialPort::SerialPortError error);

private:
    SerialDeviceDiscovery::Selection selection() const;
    void processReceiveBuffer();
    void failClosed(const QString &message);

    SerialDeviceDiscovery *m_discovery = nullptr;
    SerialDeviceDiscovery::DeviceRole m_role = SerialDeviceDiscovery::DeviceRole::Unknown;
#ifdef Q_OS_ANDROID
    AndroidUsbSerialPort m_port;
#else
    QSerialPort m_port;
#endif
    QByteArray m_receiveBuffer;
    QString m_openEndpointId;
    QString m_openPortName;
    bool m_opening = false;
    bool m_closing = false;
    bool m_diagnosticLoggingEnabled = true;
};
