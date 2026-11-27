#pragma once

#include <QList>
#include <QObject>
#include <QString>
#include <QTimer>

class SerialDeviceDiscovery final : public QObject
{
    Q_OBJECT

public:
    enum class DeviceRole {
        Unknown,
        Press,
        Module
    };
    Q_ENUM(DeviceRole)

    struct PortDescriptor {
        QString portName;
        QString systemLocation;
        QString description;
        QString manufacturer;
        QString serialNumber;
        bool hasVendorIdentifier = false;
        bool hasProductIdentifier = false;
        quint16 vendorIdentifier = 0;
        quint16 productIdentifier = 0;
    };

    struct Selection {
        bool available = false;
        bool ambiguous = false;
        QString error;
        PortDescriptor port;
    };

    explicit SerialDeviceDiscovery(QObject *parent = nullptr);

    static DeviceRole classify(quint16 vendorIdentifier, quint16 productIdentifier);
    static Selection select(DeviceRole role, const QList<PortDescriptor> &ports);
    static QList<PortDescriptor> systemPorts();
    static QString stableEndpointId(const PortDescriptor &port);
    static QString displayName(const PortDescriptor &port);
    static bool selectionsEqual(const Selection &left, const Selection &right);

    Selection pressSelection() const { return m_pressSelection; }
    Selection moduleSelection() const { return m_moduleSelection; }
    bool available() const { return m_pressSelection.available || m_moduleSelection.available; }

public slots:
    void refresh();

signals:
    void selectionsChanged();

private:
    void refreshAsync();
    void applyPorts(const QList<PortDescriptor> &ports);

    QTimer m_scanTimer;
    bool m_scanInFlight = false;
    Selection m_pressSelection;
    Selection m_moduleSelection;
};
