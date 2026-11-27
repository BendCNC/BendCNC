#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>

class MachineTransport : public QObject
{
    Q_OBJECT

public:
    explicit MachineTransport(QObject *parent = nullptr)
        : QObject(parent)
    {
    }

    ~MachineTransport() override = default;

    virtual bool isAvailable() const = 0;
    virtual bool isOpen() const = 0;
    virtual QString endpointId() const = 0;
    virtual QString endpointDisplayName() const = 0;
    virtual bool open() = 0;
    virtual void close() = 0;
    virtual bool writeFrame(const QByteArray &frame) = 0;
    virtual void setDiagnosticLoggingEnabled(bool enabled) { Q_UNUSED(enabled); }
    virtual bool diagnosticLoggingEnabled() const { return false; }

signals:
    void availabilityChanged();
    void opened();
    void closed();
    void frameReceived(const QByteArray &frame);
    // Emitted before validation or serial queuing so rejected and failed TX
    // attempts remain part of the diagnostic record.
    void frameWriteAttempted(const QByteArray &frame);
    void frameWritten(const QByteArray &frame);
    void transportError(const QString &message);
};
