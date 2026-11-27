#pragma once

#include "MachineTransport.h"

class NullMachineTransport final : public MachineTransport
{
    Q_OBJECT

public:
    explicit NullMachineTransport(QObject *parent = nullptr)
        : MachineTransport(parent)
    {
    }

    bool isAvailable() const override { return false; }
    bool isOpen() const override { return false; }
    QString endpointId() const override { return {}; }
    QString endpointDisplayName() const override { return {}; }
    bool open() override;
    void close() override;
    bool writeFrame(const QByteArray &frame) override;
};
