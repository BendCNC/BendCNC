#pragma once

#include <QtCanvasPainter/QCanvasPainterItem>
#include <QtCanvasPainter/QCanvasPainterItemRenderer>
#include <memory>
#include <QCache>
#include <QPointer>
#include <QVariantList>

class CanvasPainterRunItem;

class CanvasPainterRunItemRenderer final : public QCanvasPainterItemRenderer
{
public:
    CanvasPainterRunItemRenderer();
    ~CanvasPainterRunItemRenderer() override;

    void synchronizeData(QCanvasPainterItem *item) override;
    void paint(QCanvasPainter *painter) override;

private:
    class Private;
    std::unique_ptr<Private> d;
    QPointer<CanvasPainterRunItem> m_item;
    int m_revision = 0;
};

class CanvasPainterRunItem : public QCanvasPainterItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(CanvasPainterRunRenderer)
    Q_PROPERTY(bool packetValid READ packetValid NOTIFY packetValidChanged FINAL)
    Q_PROPERTY(QString packetError READ packetError NOTIFY packetErrorChanged FINAL)
    Q_PROPERTY(int acceptedRevision READ acceptedRevision NOTIFY acceptedRevisionChanged FINAL)
    Q_PROPERTY(int presentedRevision READ presentedRevision NOTIFY presentedRevisionChanged FINAL)
    Q_PROPERTY(int batchCount READ batchCount NOTIFY batchCountChanged FINAL)
    Q_PROPERTY(int preparedCacheHits READ preparedCacheHits NOTIFY preparedCacheStatsChanged FINAL)
    Q_PROPERTY(int preparedCacheMisses READ preparedCacheMisses NOTIFY preparedCacheStatsChanged FINAL)
    Q_PROPERTY(int preparedCommandCount READ preparedCommandCount NOTIFY preparedCacheStatsChanged FINAL)
    Q_PROPERTY(qreal prepareMilliseconds READ prepareMilliseconds NOTIFY preparedCacheStatsChanged FINAL)
    Q_PROPERTY(int preparedCacheEntries READ preparedCacheEntries NOTIFY preparedCacheStatsChanged FINAL)
    Q_PROPERTY(int preparedCacheCost READ preparedCacheCost NOTIFY preparedCacheStatsChanged FINAL)
    Q_PROPERTY(int preparedCacheEvictions READ preparedCacheEvictions NOTIFY preparedCacheStatsChanged FINAL)
    Q_PROPERTY(int largestPreparedFrameCost READ largestPreparedFrameCost NOTIFY preparedCacheStatsChanged FINAL)
    Q_PROPERTY(int transportCacheHits READ transportCacheHits NOTIFY transportCacheStatsChanged FINAL)
    Q_PROPERTY(int transportCacheMisses READ transportCacheMisses NOTIFY transportCacheStatsChanged FINAL)
    Q_PROPERTY(QString backendName READ backendName CONSTANT FINAL)

public:
    explicit CanvasPainterRunItem(QQuickItem *parent = nullptr);

    Q_INVOKABLE bool submitFrame(const QVariantList &commands, int revision,
                                 const QString &cacheKey = {});
    Q_INVOKABLE bool submitCachedFrame(const QString &cacheKey, int revision);
    Q_INVOKABLE bool hasCachedFrame(const QString &cacheKey) const;
    QCanvasPainterItemRenderer *createItemRenderer() const override;

    bool packetValid() const { return m_packetValid; }
    QString packetError() const { return m_packetError; }
    int acceptedRevision() const { return m_acceptedRevision; }
    int presentedRevision() const { return m_presentedRevision; }
    int batchCount() const { return m_batchCount; }
    int preparedCacheHits() const { return m_preparedCacheHits; }
    int preparedCacheMisses() const { return m_preparedCacheMisses; }
    int preparedCommandCount() const { return m_preparedCommandCount; }
    qreal prepareMilliseconds() const { return m_prepareMilliseconds; }
    int preparedCacheEntries() const { return m_preparedCacheEntries; }
    int preparedCacheCost() const { return m_preparedCacheCost; }
    int preparedCacheEvictions() const { return m_preparedCacheEvictions; }
    int largestPreparedFrameCost() const { return m_largestPreparedFrameCost; }
    int transportCacheHits() const { return m_transportCacheHits; }
    int transportCacheMisses() const { return m_transportCacheMisses; }
    QString backendName() const { return QStringLiteral("Qt Canvas Painter 6.11 prepared replay"); }
    const QVariantList &commands() const { return m_commands; }
    const QString &cacheKey() const { return m_cacheKey; }

Q_SIGNALS:
    void packetValidChanged();
    void packetErrorChanged();
    void acceptedRevisionChanged();
    void presentedRevisionChanged();
    void batchCountChanged();
    void preparedCacheStatsChanged();
    void transportCacheStatsChanged();

private:
    friend class CanvasPainterRunItemRenderer;
    void rejectPacket(const QString &error);
    void markPresented(int revision, int batches);
    void markPreparedStats(int hits, int misses, int commands, qreal milliseconds,
                           int entries, int cost, int evictions,
                           int largestFrameCost);

    QVariantList m_commands;
    QCache<QString, QVariantList> m_commandCache;
    QString m_cacheKey;
    bool m_packetValid = false;
    QString m_packetError;
    int m_acceptedRevision = 0;
    int m_presentedRevision = 0;
    int m_batchCount = 0;
    int m_preparedCacheHits = 0;
    int m_preparedCacheMisses = 0;
    int m_preparedCommandCount = 0;
    qreal m_prepareMilliseconds = 0.0;
    int m_preparedCacheEntries = 0;
    int m_preparedCacheCost = 0;
    int m_preparedCacheEvictions = 0;
    int m_largestPreparedFrameCost = 0;
    int m_transportCacheHits = 0;
    int m_transportCacheMisses = 0;
};