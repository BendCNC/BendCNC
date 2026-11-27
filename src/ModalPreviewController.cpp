#include "ModalPreviewController.h"

#include <QDir>
#include <QFileInfo>
#include <QQmlEngine>

ModalPreviewController::ModalPreviewController(QQmlEngine *engine,
                                               const QString &previewRoot,
                                               QObject *parent)
    : QObject(parent), m_engine(engine), m_previewRoot(previewRoot)
{
}

void ModalPreviewController::trimUnusedComponentCache()
{
    if (m_engine)
        m_engine->trimComponentCache();
}

QStringList ModalPreviewController::availableVersions() const
{
    QStringList versions;
    const QDir root(m_previewRoot);
    const QFileInfoList directories = root.entryInfoList(
        QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &directory : directories) {
        if (QFileInfo::exists(directory.filePath() + QStringLiteral("/PreviewScene.qml")))
            versions.append(directory.fileName());
    }
    return versions;
}