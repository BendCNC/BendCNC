#include "NullMachineTransport.h"

bool NullMachineTransport::open()
{
    emit transportError(QStringLiteral("Native transport is unavailable."));
    return false;
}

void NullMachineTransport::close()
{
}

bool NullMachineTransport::writeFrame(const QByteArray &frame)
{
    Q_UNUSED(frame)
    emit transportError(QStringLiteral("Cannot send a frame without a native transport."));
    return false;
}
