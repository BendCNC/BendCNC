#pragma once

#include <QObject>
#include <QHash>
#include <QMutex>
#include <QString>
#include <QVector>
#include <QPointer>

class QQuickWindow;
class QTimer;

class RunFrameTiming final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled CONSTANT)

public:
    explicit RunFrameTiming(bool enabled, int windowMilliseconds = 1000,
                            QObject *parent = nullptr);

    bool enabled() const;
    void attachWindow(QQuickWindow *window);

    Q_INVOKABLE void beginStage(const QString &name);
    Q_INVOKABLE void endStage(const QString &name);
    Q_INVOKABLE void recordEvent(const QString &name);
    Q_INVOKABLE void recordCount(const QString &name);
    Q_INVOKABLE void recordStageNanoseconds(const QString &name, qint64 nanoseconds);
    Q_INVOKABLE void recordStageMilliseconds(const QString &name, qreal milliseconds);
    Q_INVOKABLE qreal timingTimestampNanoseconds() const noexcept;
    Q_INVOKABLE void finishBackgaugeFingerReadoutSample(
        qreal startedNs, qreal setupEndedNs, qreal strokeEndedNs,
        qreal fillEndedNs);

private:
    struct EventSeries {
        int count = 0;
        qint64 lastTimestampNs = 0;
        QVector<qint64> intervalsNs;
    };

    static qint64 monotonicNanoseconds();
    static QString metricSummary(const QVector<qint64> &samples,
                                 const QString &prefix);
    static QString stageMetricSummary(const QVector<qint64> &samples,
                                      const QString &prefix);
    void recordEventAt(const QString &name, qint64 timestampNs);
    void publishWindow();

    const bool m_enabled;
    const int m_windowMilliseconds;
    const qint64 m_clockOriginNs;
    qint64 m_windowStartedNs = 0;
    QTimer *m_publishTimer = nullptr;
    QPointer<QQuickWindow> m_window;
    QMutex m_mutex;
    QHash<QString, qint64> m_stageStarts;
    QHash<QString, QVector<qint64>> m_stageDurations;
    QHash<QString, EventSeries> m_events;
    QHash<QString, int> m_counts;
    QVector<qint64> m_backgaugeReadoutSetupDurations;
    QVector<qint64> m_backgaugeReadoutStrokeTextCallDurations;
    QVector<qint64> m_backgaugeReadoutFillTextCallDurations;
    QVector<qint64> m_backgaugeReadoutMeasuredTotalDurations;
    int m_backgaugeReadoutInvalidSamples = 0;
};