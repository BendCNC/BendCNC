#pragma once

#include <QColor>
#include <QByteArray>
#include <QMutex>
#include <QPointF>
#include <QPointer>
#include <QQuickItem>
#include <QTransform>
#include <QVector>
#include <QtQml/qqmlregistration.h>

#include <memory>

class QSGNode;

class NativeRunRenderer : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int acceptedRevision READ acceptedRevision NOTIFY acceptedRevisionChanged)
    Q_PROPERTY(int presentedRevision READ presentedRevision NOTIFY presentedRevisionChanged)
    Q_PROPERTY(bool packetValid READ packetValid NOTIFY packetValidChanged)
    Q_PROPERTY(QString packetError READ packetError NOTIFY packetErrorChanged)
    Q_PROPERTY(int batchCount READ batchCount NOTIFY acceptedRevisionChanged)
    Q_PROPERTY(int vertexCount READ vertexCount NOTIFY acceptedRevisionChanged)
    Q_PROPERTY(int parseMilliseconds READ parseMilliseconds NOTIFY acceptedRevisionChanged)
    Q_PROPERTY(int coalescedFrameCount READ coalescedFrameCount NOTIFY acceptedRevisionChanged)
    Q_PROPERTY(int tessellationCacheHits READ tessellationCacheHits NOTIFY acceptedRevisionChanged)
    Q_PROPERTY(int tessellationCacheMisses READ tessellationCacheMisses NOTIFY acceptedRevisionChanged)
    Q_PROPERTY(int retainedTransformUpdates READ retainedTransformUpdates NOTIFY acceptedRevisionChanged)
    Q_PROPERTY(int sceneGraphGeometryUpdates READ sceneGraphGeometryUpdates NOTIFY presentedRevisionChanged)
    Q_PROPERTY(int sceneGraphTransformUpdates READ sceneGraphTransformUpdates NOTIFY presentedRevisionChanged)
    Q_PROPERTY(QString presentedGeometryDigest READ presentedGeometryDigest NOTIFY presentedRevisionChanged)
    Q_PROPERTY(QObject *timingSink READ timingSink WRITE setTimingSink)
    Q_PROPERTY(QString backendName READ backendName CONSTANT)

public:
    enum OpaquePrimitive : int {
        OpaqueTriangles = 1
    };
    Q_ENUM(OpaquePrimitive)

    struct OpaqueTriangleBatchDefinition {
        QVector<QPointF> vertices;
        QColor color;
    };

    explicit NativeRunRenderer(QQuickItem *parent = nullptr);
    ~NativeRunRenderer() override;

    int acceptedRevision() const;
    int presentedRevision() const;
    bool packetValid() const;
    QString packetError() const;
    int batchCount() const;
    int vertexCount() const;
    int parseMilliseconds() const;
    int coalescedFrameCount() const;
    int tessellationCacheHits() const;
    int tessellationCacheMisses() const;
    int retainedTransformUpdates() const;
    int sceneGraphGeometryUpdates() const;
    int sceneGraphTransformUpdates() const;
    QString presentedGeometryDigest() const;
    QObject *timingSink() const;
    void setTimingSink(QObject *timingSink);
    QString backendName() const;

    Q_INVOKABLE bool submitFrame(const QVariantList &commands, int revision);
    Q_INVOKABLE bool beginOpaqueBatchInstall(int expectedBatchCount);
    Q_INVOKABLE bool appendOpaqueBatch(int primitive,
                                       const QVariantList &xyVertices,
                                       const QColor &color);
    Q_INVOKABLE bool commitOpaqueBatchInstall();
    Q_INVOKABLE void cancelOpaqueBatchInstall();
    Q_INVOKABLE bool setOpaqueBatchTransform(int batchIndex,
                                             qreal m11, qreal m12,
                                             qreal m21, qreal m22,
                                             qreal dx, qreal dy);
    Q_INVOKABLE bool submitSharedOpaqueTransform(qreal m11, qreal m12,
                                                 qreal m21, qreal m22,
                                                 qreal dx, qreal dy,
                                                 int revision);
    Q_INVOKABLE bool submitOpaqueRevision(int revision);

    bool installOpaqueTriangleBatches(
        const QVector<OpaqueTriangleBatchDefinition> &batches,
        QString *error = nullptr);
    bool submitOpaqueTriangleFrame(const QVector<QTransform> &transforms,
                                   int revision, QString *error = nullptr);

signals:
    void acceptedRevisionChanged();
    void presentedRevisionChanged();
    void packetValidChanged();
    void packetErrorChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;

private:
    struct TessellationCache;
    struct Batch {
        QVector<QPointF> vertices;
        std::shared_ptr<const QVector<QPointF>> retainedVertices;
        QColor color;
        QByteArray geometryKey;
        QTransform meshTransform;

        const QVector<QPointF> &vertexData() const noexcept
        {
            return retainedVertices ? *retainedVertices : vertices;
        }
    };
    struct Packet {
        int revision = 0;
        QVector<Batch> batches;
        int tessellationCacheHits = 0;
        int tessellationCacheMisses = 0;
        int retainedTransformUpdates = 0;
    };

    struct ParseResult {
        std::shared_ptr<const Packet> packet;
        QString error;
        int parseMilliseconds = 0;
    };

    static std::shared_ptr<const Packet> parsePacket(const QVariantList &commands,
                                                     int revision,
                                                     QString *error,
                                                     const std::shared_ptr<TessellationCache> &cache);
    static ParseResult parseTimedPacket(const QVariantList &commands,
                                        int revision,
                                        const std::shared_ptr<TessellationCache> &cache);
    struct InstalledOpaqueBatch {
        std::shared_ptr<const QVector<QPointF>> vertices;
        QColor color;
        QByteArray geometryKey;
    };
    bool rejectOpaqueOperation(const QString &error, QString *outputError = nullptr);
    void setPacketStatus(bool valid, const QString &error);
    void acceptPacket(const std::shared_ptr<const Packet> &packet,
                      int parseMilliseconds);
    void startPendingParse();
    void finishParse(int revision, const ParseResult &result);
    void finishPresentation(int revision, int geometryUpdates, int transformUpdates,
                            const QString &geometryDigest);

    int m_acceptedRevision = 0;
    int m_presentedRevision = 0;
    bool m_packetValid = true;
    QString m_packetError;
    int m_batchCount = 0;
    int m_vertexCount = 0;
    int m_parseMilliseconds = 0;
    int m_coalescedFrameCount = 0;
    int m_tessellationCacheHits = 0;
    int m_tessellationCacheMisses = 0;
    int m_retainedTransformUpdates = 0;
    int m_sceneGraphGeometryUpdates = 0;
    int m_sceneGraphTransformUpdates = 0;
    QString m_presentedGeometryDigest;
    QPointer<QObject> m_timingSink;

    mutable QMutex m_packetMutex;
    std::shared_ptr<const Packet> m_packet;
    QVariantList m_pendingCommands;
    int m_pendingRevision = 0;
    bool m_parseRunning = false;
    std::shared_ptr<TessellationCache> m_tessellationCache;

    QVector<InstalledOpaqueBatch> m_installedOpaqueBatches;
    QVector<QTransform> m_opaqueTransforms;
    QVector<QTransform> m_committedOpaqueTransforms;
    QVector<OpaqueTriangleBatchDefinition> m_stagedOpaqueBatches;
    qsizetype m_stagedOpaqueVertexCount = 0;
    int m_expectedOpaqueBatchCount = 0;
    bool m_opaqueInstallActive = false;
    QString m_opaqueInstallError;
    bool m_opaqueTransformStageValid = true;
};
