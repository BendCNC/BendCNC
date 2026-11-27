#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class QQmlEngine;

class ModalPreviewController final : public QObject
{
    Q_OBJECT

public:
    explicit ModalPreviewController(QQmlEngine *engine,
                                    const QString &previewRoot,
                                    QObject *parent = nullptr);

    Q_INVOKABLE void trimUnusedComponentCache();
    Q_INVOKABLE QStringList availableVersions() const;

private:
    QQmlEngine *m_engine = nullptr;
    QString m_previewRoot;
};