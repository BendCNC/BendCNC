#include "SerialDeviceDiscovery.h"

#include <QLoggingCategory>
#include <QMetaObject>
#include <QPointer>
#include <QThreadPool>
#include <QSerialPortInfo>
#ifdef Q_OS_ANDROID
#include "AndroidUsbSerialPort.h"
#endif

namespace {
constexpr quint16 ArduinoVendor = 0x2341;
constexpr quint16 PressArduinoProduct = 0x0069;
constexpr quint16 PressCh340Vendor = 0x1A86;
constexpr quint16 PressCh340Product = 0x7523;
constexpr quint16 ModuleArduinoProduct = 0x0043;
constexpr quint16 ModuleVendor = 0x16D0;
constexpr quint16 ModuleProduct = 0x0EFB;
}

SerialDeviceDiscovery::SerialDeviceDiscovery(QObject *parent)
    : QObject(parent)
{
    m_scanTimer.setInterval(1000);
    m_scanTimer.setSingleShot(false);
    connect(&m_scanTimer, &QTimer::timeout, this, &SerialDeviceDiscovery::refreshAsync);
    refresh();
    m_scanTimer.start();
}

SerialDeviceDiscovery::DeviceRole SerialDeviceDiscovery::classify(quint16 vendorIdentifier,
                                                                   quint16 productIdentifier)
{
    if ((vendorIdentifier == ArduinoVendor && productIdentifier == PressArduinoProduct)
        || (vendorIdentifier == PressCh340Vendor && productIdentifier == PressCh340Product)) {
        return DeviceRole::Press;
    }
    if ((vendorIdentifier == ArduinoVendor && productIdentifier == ModuleArduinoProduct)
        || (vendorIdentifier == ModuleVendor && productIdentifier == ModuleProduct)) {
        return DeviceRole::Module;
    }
    return DeviceRole::Unknown;
}

SerialDeviceDiscovery::Selection SerialDeviceDiscovery::select(DeviceRole role,
                                                                const QList<PortDescriptor> &ports)
{
    QList<PortDescriptor> candidates;
    for (const PortDescriptor &port : ports) {
        if (!port.hasVendorIdentifier || !port.hasProductIdentifier)
            continue;
        if (classify(port.vendorIdentifier, port.productIdentifier) == role)
            candidates.push_back(port);
    }

    Selection result;
    if (candidates.isEmpty()) {
        result.error = QStringLiteral("ENDPOINT_ABSENT");
        return result;
    }
    if (candidates.size() != 1) {
        result.ambiguous = true;
        result.error = QStringLiteral("ENDPOINT_AMBIGUOUS");
        return result;
    }
    result.available = true;
    result.port = candidates.constFirst();
    return result;
}

QList<SerialDeviceDiscovery::PortDescriptor> SerialDeviceDiscovery::systemPorts()
{
    QList<PortDescriptor> result;
#ifdef Q_OS_ANDROID
    for (const AndroidUsbSerialPort::DeviceInfo &device : AndroidUsbSerialPort::devices()) {
        PortDescriptor descriptor;
        descriptor.portName = device.name;
        descriptor.systemLocation = device.name;
        descriptor.description = device.product;
        descriptor.serialNumber = device.serialNumber;
        descriptor.hasVendorIdentifier = true;
        descriptor.hasProductIdentifier = true;
        descriptor.vendorIdentifier = device.vendorId;
        descriptor.productIdentifier = device.productId;
        result.push_back(descriptor);
    }
    return result;
#endif
    const QList<QSerialPortInfo> ports = QSerialPortInfo::availablePorts();
    result.reserve(ports.size());
    for (const QSerialPortInfo &port : ports) {
        PortDescriptor descriptor;
        descriptor.portName = port.portName();
        descriptor.systemLocation = port.systemLocation();
        descriptor.description = port.description();
        descriptor.manufacturer = port.manufacturer();
        descriptor.serialNumber = port.serialNumber();
        descriptor.hasVendorIdentifier = port.hasVendorIdentifier();
        descriptor.hasProductIdentifier = port.hasProductIdentifier();
        if (descriptor.hasVendorIdentifier)
            descriptor.vendorIdentifier = port.vendorIdentifier();
        if (descriptor.hasProductIdentifier)
            descriptor.productIdentifier = port.productIdentifier();
        result.push_back(descriptor);
    }
    return result;
}

QString SerialDeviceDiscovery::stableEndpointId(const PortDescriptor &port)
{
    const QString usbId = QStringLiteral("%1:%2")
                              .arg(port.vendorIdentifier, 4, 16, QLatin1Char('0'))
                              .arg(port.productIdentifier, 4, 16, QLatin1Char('0'))
                              .toUpper();
    if (!port.serialNumber.trimmed().isEmpty())
        return usbId + QLatin1Char(':') + port.serialNumber.trimmed();
    // QSerialPortInfo can transiently omit or rewrite the Linux USB sysfs
    // location while an Uno R4 re-enumerates. portName is the endpoint the
    // open QSerialPort actually owns and is stable for normal scans; using
    // systemLocation here caused a false DEVICE_REMOVED immediately after a
    // successful open. A real disappearance still changes availability.
    if (!port.portName.trimmed().isEmpty())
        return usbId + QLatin1Char(':') + port.portName.trimmed();
    if (!port.systemLocation.trimmed().isEmpty())
        return usbId + QLatin1Char(':') + port.systemLocation.trimmed();
    return usbId + QLatin1Char(':') + port.portName.trimmed();
}

QString SerialDeviceDiscovery::displayName(const PortDescriptor &port)
{
    const QString description = port.description.trimmed();
    return description.isEmpty() ? port.portName : description + QStringLiteral(" (")
        + port.portName + QLatin1Char(')');
}

void SerialDeviceDiscovery::refresh()
{
    applyPorts(systemPorts());
}

// QSerialPortInfo::availablePorts() walks udev/sysfs and took ~75 ms per
// call on the RK3566 press, stalling the GUI thread (and the Live 3D
// animation) once per second. Periodic scans therefore run on the global
// thread pool; the selection logic still runs on this object's thread.
void SerialDeviceDiscovery::refreshAsync()
{
#ifdef Q_OS_ANDROID
    refresh();
#else
    if (m_scanInFlight)
        return;
    m_scanInFlight = true;
    QPointer<SerialDeviceDiscovery> self(this);
    QThreadPool::globalInstance()->start([self] {
        QList<PortDescriptor> ports = systemPorts();
        if (!self)
            return;
        QMetaObject::invokeMethod(self.data(), [self, ports = std::move(ports)] {
            if (!self)
                return;
            self->m_scanInFlight = false;
            self->applyPorts(ports);
        }, Qt::QueuedConnection);
    });
#endif
}

void SerialDeviceDiscovery::applyPorts(const QList<PortDescriptor> &ports)
{
    const Selection nextPress = select(DeviceRole::Press, ports);
    const Selection nextModule = select(DeviceRole::Module, ports);
    if (selectionsEqual(m_pressSelection, nextPress)
        && selectionsEqual(m_moduleSelection, nextModule)) {
        return;
    }
    m_pressSelection = nextPress;
    m_moduleSelection = nextModule;
    const auto describe = [](const PortDescriptor &port) {
        const QString vid = port.hasVendorIdentifier
            ? QStringLiteral("%1").arg(port.vendorIdentifier, 4, 16, QLatin1Char('0')).toUpper()
            : QStringLiteral("NONE");
        const QString pid = port.hasProductIdentifier
            ? QStringLiteral("%1").arg(port.productIdentifier, 4, 16, QLatin1Char('0')).toUpper()
            : QStringLiteral("NONE");
        return QStringLiteral("%1 path=%2 vid=%3 pid=%4 description=%5 manufacturer=%6 serial=%7")
            .arg(port.portName, port.systemLocation, vid, pid, port.description,
                 port.manufacturer, port.serialNumber);
    };
    for (const PortDescriptor &port : ports)
        qInfo().noquote() << QStringLiteral("SERIAL-DISCOVERY PORT ") + describe(port);
    qInfo().noquote() << QStringLiteral("SERIAL-DISCOVERY PRESS available=%1 error=%2 endpoint=%3")
                            .arg(m_pressSelection.available)
                            .arg(m_pressSelection.error, displayName(m_pressSelection.port));
    qInfo().noquote() << QStringLiteral("SERIAL-DISCOVERY MODULE available=%1 error=%2 endpoint=%3")
                            .arg(m_moduleSelection.available)
                            .arg(m_moduleSelection.error, displayName(m_moduleSelection.port));
    emit selectionsChanged();
}

bool SerialDeviceDiscovery::selectionsEqual(const Selection &left, const Selection &right)
{
    return left.available == right.available && left.ambiguous == right.ambiguous
        && left.error == right.error
    && stableEndpointId(left.port) == stableEndpointId(right.port)
    // The stable USB identity answers "is this the same controller?" but
    // the mutable path answers "where must it be opened now?". Linux can
    // re-enumerate the same Uno R4 from ttyACM0 to ttyACM2. Treat that as
    // a selection update so a reconnect never retries the stale node.
    && left.port.portName == right.port.portName
    && left.port.systemLocation == right.port.systemLocation;
}
