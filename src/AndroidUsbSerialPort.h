#pragma once

// Android replacement for the QSerialPort subset used by SerialMachineTransport.
// Android apps cannot open USB-serial adapters as tty devices; the Java driver

#include <QByteArray>
#include <QList>
#include <QObject>
#include <QSerialPort>
#include <QString>

class AndroidUsbSerialPort : public QObject
{
    Q_OBJECT

public:
    struct DeviceInfo {
        QString name;
        quint16 vendorId = 0;
        quint16 productId = 0;
        QString serialNumber;
        QString product;
    };

    explicit AndroidUsbSerialPort(QObject *parent = nullptr);
    ~AndroidUsbSerialPort() override;

    static QList<DeviceInfo> devices();

    void setPortName(const QString &name) { m_portName = name; }
    void setBaudRate(qint32 baud) { m_baud = baud; }
    void setDataBits(QSerialPort::DataBits) {}
    void setParity(QSerialPort::Parity) {}
    void setStopBits(QSerialPort::StopBits) {}
    void setFlowControl(QSerialPort::FlowControl) {}
    void setReadBufferSize(qint64) {}

    bool open(QIODevice::OpenMode mode);
    void close();
    bool isOpen() const { return m_handle > 0; }
    qint64 write(const QByteArray &data);
    QByteArray readAll();
    qint64 bytesToWrite() const { return 0; }
    QString errorString() const { return m_errorString; }

    // Called from the Java reader thread (queued to this object's thread).
    static void deliverData(int handle, const QByteArray &data);
    static void deliverError(int handle, const QString &message);

signals:
    void readyRead();
    void bytesWritten(qint64 bytes);
    void errorOccurred(QSerialPort::SerialPortError error);

private:
    QString m_portName;
    qint32 m_baud = 115200;
    int m_handle = 0;
    QByteArray m_buffer;
    QString m_errorString;
};
