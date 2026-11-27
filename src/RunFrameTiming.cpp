#include "RunFrameTiming.h"

#include <QDebug>
#include <QMutexLocker>
#include <QQuickWindow>
#include <QTimer>

#include <algorithm>
#include <chrono>
#include <cmath>

namespace {

qreal percentileMilliseconds(QVector<qint64> samples, qreal percentile)
{
    if (samples.isEmpty())
        return -1.0;
    std::sort(samples.begin(), samples.end());
    const qreal position = percentile * qreal(samples.size() - 1);
    const qsizetype lower = qsizetype(std::floor(position));
    const qsizetype upper = qsizetype(std::ceil(position));
    const qreal fraction = position - qreal(lower);
    const qreal nanoseconds = qreal(samples.at(lower))
        + (qreal(samples.at(upper)) - qreal(samples.at(lower))) * fraction;
    return nanoseconds / 1000000.0;
}

QString formattedMetric(qreal value)
{
    return value < 0.0 ? QStringLiteral("-1")
                       : QString::number(value, 'f', 3);
}

qreal totalMilliseconds(const QVector<qint64> &samples)
{
    qint64 totalNanoseconds = 0;
    for (const qint64 sample : samples)
        totalNanoseconds += sample;
    return qreal(totalNanoseconds) / 1000000.0;
}

} // namespace

RunFrameTiming::RunFrameTiming(bool enabled, int windowMilliseconds, QObject *parent)
    : QObject(parent)
    , m_enabled(enabled)
    , m_windowMilliseconds(std::max(250, windowMilliseconds))
    , m_clockOriginNs(monotonicNanoseconds())
    , m_windowStartedNs(m_clockOriginNs)
{
    if (!m_enabled)
        return;
    m_publishTimer = new QTimer(this);
    m_publishTimer->setInterval(m_windowMilliseconds);
    m_publishTimer->setTimerType(Qt::PreciseTimer);
    connect(m_publishTimer, &QTimer::timeout, this, &RunFrameTiming::publishWindow);
    m_publishTimer->start();
}

bool RunFrameTiming::enabled() const
{
    return m_enabled;
}

void RunFrameTiming::attachWindow(QQuickWindow *window)
{
    if (!m_enabled || !window || m_window == window)
        return;
    m_window = window;
    connect(window, &QQuickWindow::afterFrameEnd, this, [this] {
        recordEventAt(QStringLiteral("after-frame-end"), monotonicNanoseconds());
    }, Qt::DirectConnection);
    connect(window, &QQuickWindow::frameSwapped, this, [this] {
        recordEventAt(QStringLiteral("frame-swapped"), monotonicNanoseconds());
    }, Qt::DirectConnection);
    qInfo().noquote() << "RUN-TIMING enabled"
                      << "windowMs=" + QString::number(m_windowMilliseconds)
                      << "clock=steady_clock"
                      << "presentation=queued-not-scanout";
}

void RunFrameTiming::beginStage(const QString &name)
{
    if (!m_enabled || name.isEmpty())
        return;
    QMutexLocker locker(&m_mutex);
    m_stageStarts.insert(name, monotonicNanoseconds());
}

void RunFrameTiming::endStage(const QString &name)
{
    if (!m_enabled || name.isEmpty())
        return;
    const qint64 now = monotonicNanoseconds();
    QMutexLocker locker(&m_mutex);
    const auto iterator = m_stageStarts.find(name);
    if (iterator == m_stageStarts.end())
        return;
    m_stageDurations[name].append(std::max<qint64>(0, now - iterator.value()));
    m_stageStarts.erase(iterator);
}

void RunFrameTiming::recordEvent(const QString &name)
{
    if (m_enabled && !name.isEmpty())
        recordEventAt(name, monotonicNanoseconds());
}

void RunFrameTiming::recordCount(const QString &name)
{
    if (!m_enabled || name.isEmpty())
        return;
    QMutexLocker locker(&m_mutex);
    ++m_counts[name];
}

void RunFrameTiming::recordStageNanoseconds(const QString &name, qint64 nanoseconds)
{
    if (!m_enabled || name.isEmpty() || nanoseconds < 0)
        return;
    QMutexLocker locker(&m_mutex);
    m_stageDurations[name].append(nanoseconds);
}

void RunFrameTiming::recordStageMilliseconds(const QString &name, qreal milliseconds)
{
    if (!std::isfinite(milliseconds) || milliseconds < 0.0)
        return;
    recordStageNanoseconds(name, qRound64(milliseconds * 1000000.0));
}

qreal RunFrameTiming::timingTimestampNanoseconds() const noexcept
{
    if (!m_enabled)
        return -1.0;
    return qreal(monotonicNanoseconds() - m_clockOriginNs);
}

void RunFrameTiming::finishBackgaugeFingerReadoutSample(
    qreal startedNs, qreal setupEndedNs, qreal strokeEndedNs,
    qreal fillEndedNs)
{
    if (!m_enabled)
        return;
    const bool valid = std::isfinite(startedNs)
        && std::isfinite(setupEndedNs)
        && std::isfinite(strokeEndedNs)
        && std::isfinite(fillEndedNs)
        && startedNs >= 0.0
        && setupEndedNs >= startedNs
        && strokeEndedNs >= setupEndedNs
        && fillEndedNs >= strokeEndedNs;

    QMutexLocker locker(&m_mutex);
    if (!valid) {
        ++m_backgaugeReadoutInvalidSamples;
        return;
    }

    const qint64 started = qRound64(startedNs);
    const qint64 setupEnded = qRound64(setupEndedNs);
    const qint64 strokeEnded = qRound64(strokeEndedNs);
    const qint64 fillEnded = qRound64(fillEndedNs);
    m_backgaugeReadoutSetupDurations.append(setupEnded - started);
    m_backgaugeReadoutStrokeTextCallDurations.append(strokeEnded - setupEnded);
    m_backgaugeReadoutFillTextCallDurations.append(fillEnded - strokeEnded);
    m_backgaugeReadoutMeasuredTotalDurations.append(fillEnded - started);
}

qint64 RunFrameTiming::monotonicNanoseconds()
{
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

QString RunFrameTiming::metricSummary(const QVector<qint64> &samples,
                                      const QString &prefix)
{
    if (samples.isEmpty())
        return prefix + "Count=0 " + prefix + "P50Ms=-1 "
            + prefix + "P95Ms=-1 " + prefix + "P99Ms=-1";
    return prefix + "Count=" + QString::number(samples.size())
        + " " + prefix + "P50Ms="
        + formattedMetric(percentileMilliseconds(samples, 0.50))
        + " " + prefix + "P95Ms="
        + formattedMetric(percentileMilliseconds(samples, 0.95))
        + " " + prefix + "P99Ms="
        + formattedMetric(percentileMilliseconds(samples, 0.99));
}

    QString RunFrameTiming::stageMetricSummary(const QVector<qint64> &samples,
                           const QString &prefix)
    {
        return metricSummary(samples, prefix)
        + " " + prefix + "TotalMs="
        + QString::number(totalMilliseconds(samples), 'f', 3);
    }

void RunFrameTiming::recordEventAt(const QString &name, qint64 timestampNs)
{
    QMutexLocker locker(&m_mutex);
    EventSeries &series = m_events[name];
    ++series.count;
    if (series.lastTimestampNs > 0 && timestampNs >= series.lastTimestampNs)
        series.intervalsNs.append(timestampNs - series.lastTimestampNs);
    series.lastTimestampNs = timestampNs;
}

void RunFrameTiming::publishWindow()
{
    if (!m_enabled)
        return;
    QHash<QString, QVector<qint64>> stages;
    QHash<QString, EventSeries> events;
    QHash<QString, int> counts;
    QVector<qint64> backgaugeReadoutSetupDurations;
    QVector<qint64> backgaugeReadoutStrokeTextCallDurations;
    QVector<qint64> backgaugeReadoutFillTextCallDurations;
    QVector<qint64> backgaugeReadoutMeasuredTotalDurations;
    int backgaugeReadoutInvalidSamples = 0;
    qint64 elapsedNs = 0;
    {
        QMutexLocker locker(&m_mutex);
        const qint64 now = monotonicNanoseconds();
        elapsedNs = std::max<qint64>(1, now - m_windowStartedNs);
        m_windowStartedNs = now;
        stages.swap(m_stageDurations);
        events = m_events;
        counts.swap(m_counts);
        backgaugeReadoutSetupDurations.swap(
            m_backgaugeReadoutSetupDurations);
        backgaugeReadoutStrokeTextCallDurations.swap(
            m_backgaugeReadoutStrokeTextCallDurations);
        backgaugeReadoutFillTextCallDurations.swap(
            m_backgaugeReadoutFillTextCallDurations);
        backgaugeReadoutMeasuredTotalDurations.swap(
            m_backgaugeReadoutMeasuredTotalDurations);
        backgaugeReadoutInvalidSamples = m_backgaugeReadoutInvalidSamples;
        m_backgaugeReadoutInvalidSamples = 0;
        for (auto iterator = m_events.begin(); iterator != m_events.end(); ++iterator) {
            iterator->count = 0;
            iterator->intervalsNs.clear();
        }
    }

    const qreal elapsedSeconds = qreal(elapsedNs) / 1000000000.0;
    const EventSeries swapped = events.value(QStringLiteral("frame-swapped"));
    const EventSeries submitted = events.value(QStringLiteral("after-frame-end"));
    const EventSeries canvasPainted = events.value(QStringLiteral("canvas-painted"));
    const qreal queuedFps = elapsedSeconds > 0.0
        ? qreal(swapped.count) / elapsedSeconds : 0.0;

    qInfo().noquote()
        << "RUN-TIMING window"
        << "windowMs=" + QString::number(qRound64(elapsedSeconds * 1000.0))
        << "queuedFps=" + QString::number(queuedFps, 'f', 3)
        << "frameSwapped=" + QString::number(swapped.count)
        << metricSummary(swapped.intervalsNs, QStringLiteral("swapInterval"))
        << "afterFrameEnd=" + QString::number(submitted.count)
        << metricSummary(submitted.intervalsNs, QStringLiteral("submitInterval"))
        << "canvasPainted=" + QString::number(canvasPainted.count)
        << metricSummary(canvasPainted.intervalsNs, QStringLiteral("canvasInterval"))
        << metricSummary(stages.value(QStringLiteral("frame-build")),
                         QStringLiteral("frameBuild"))
        << metricSummary(stages.value(QStringLiteral("canvas-paint")),
                         QStringLiteral("canvasPaint"))
        << metricSummary(stages.value(QStringLiteral("canvas-static-paint")),
                         QStringLiteral("canvasStaticPaint"))
        << metricSummary(backgaugeReadoutSetupDurations,
                         QStringLiteral("backgaugeReadoutSetup"))
        << metricSummary(backgaugeReadoutStrokeTextCallDurations,
                         QStringLiteral("backgaugeReadoutStrokeTextCall"))
        << metricSummary(backgaugeReadoutFillTextCallDurations,
                         QStringLiteral("backgaugeReadoutFillTextCall"))
        << metricSummary(backgaugeReadoutMeasuredTotalDurations,
                         QStringLiteral("backgaugeReadoutMeasuredTotal"))
        << "backgaugeReadoutInvalidSamples="
            + QString::number(backgaugeReadoutInvalidSamples)
        << metricSummary(stages.value(QStringLiteral("native-parse")),
                         QStringLiteral("nativeParse"))
        << metricSummary(stages.value(QStringLiteral("native-update-paint-node")),
                         QStringLiteral("nativeUpdate"))
        << "canvasBackpressure="
            + QString::number(events.value(QStringLiteral("canvas-backpressure")).count)
        << "nativeBackpressure="
            + QString::number(events.value(QStringLiteral("native-backpressure")).count)
        << "nativeRevisionInstalled="
            + QString::number(events.value(QStringLiteral("native-revision-installed")).count)
        << "nativePunchShadowPresented="
            + QString::number(events.value(
                QStringLiteral("native-punch-shadow-presented")).count)
        << "liveCycleHit="
            + QString::number(counts.value(QStringLiteral("live-cycle-hit")))
        << "liveImmediateHit="
            + QString::number(counts.value(QStringLiteral("live-immediate-hit")))
        << "liveFreshV5Build="
            + QString::number(counts.value(QStringLiteral("live-fresh-v5-build")))
        << "v5CompiledPoseHit="
            + QString::number(counts.value(QStringLiteral("v5-compiled-pose-hit")))
        << "v5CompiledPoseMiss="
            + QString::number(counts.value(QStringLiteral("v5-compiled-pose-miss")))
        << "v5TopologyCacheHit="
            + QString::number(counts.value(QStringLiteral("v5-topology-cache-hit")))
        << "v5TopologyCacheMiss="
            + QString::number(counts.value(QStringLiteral("v5-topology-cache-miss")))
        << "v5StaticDescriptorCacheHit="
            + QString::number(counts.value(QStringLiteral("v5-static-descriptor-cache-hit")))
        << "v5StaticDescriptorCacheMiss="
            + QString::number(counts.value(QStringLiteral("v5-static-descriptor-cache-miss")))
        << "v5ProjectedArtifactHit="
            + QString::number(counts.value(QStringLiteral("v5-projected-artifact-hit")))
        << "v5ProjectedArtifactMiss="
            + QString::number(counts.value(QStringLiteral("v5-projected-artifact-miss")))
        << "v5ToolingBoundsHit="
            + QString::number(counts.value(QStringLiteral("v5-tooling-bounds-hit")))
        << "v5ToolingBoundsMiss="
            + QString::number(counts.value(QStringLiteral("v5-tooling-bounds-miss")))
        << stageMetricSummary(stages.value(QStringLiteral("v5-panel-setup")),
                      QStringLiteral("v5PanelSetup"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-panel-descriptors")),
                      QStringLiteral("v5PanelDescriptors"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-panel-angles")),
                      QStringLiteral("v5PanelAngles"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-panel-section-frame")),
                      QStringLiteral("v5PanelSectionFrame"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-panel-alignment")),
                      QStringLiteral("v5PanelAlignment"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-compile-pose")),
                      QStringLiteral("v5CompilePose"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-prepare-render-geometry")),
                      QStringLiteral("v5PrepareRenderGeometry"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-pose-panels")),
                      QStringLiteral("v5PosePanels"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-project-panels")),
                      QStringLiteral("v5ProjectPanels"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-panel-project")),
                  QStringLiteral("v5PanelProject"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-panel-assembly")),
                  QStringLiteral("v5PanelAssembly"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-internal-edges")),
                      QStringLiteral("v5InternalEdges"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-frame-panels")),
                      QStringLiteral("v5FramePanels"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-frame-geometry")),
                      QStringLiteral("v5FrameGeometry"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-frame-collision")),
                      QStringLiteral("v5FrameCollision"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-frame-position")),
                      QStringLiteral("v5FramePosition"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-resolve-bounds")),
                      QStringLiteral("v5ResolveBounds"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-bounds-geometry")),
                  QStringLiteral("v5BoundsGeometry"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-bounds-tooling")),
                  QStringLiteral("v5BoundsTooling"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-tooling-key")),
                  QStringLiteral("v5ToolingKey"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-tooling-build")),
                  QStringLiteral("v5ToolingBuild"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-bounds-finalize")),
                  QStringLiteral("v5BoundsFinalize"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-frame-fillets")),
                      QStringLiteral("v5FrameFillets"))
        << stageMetricSummary(stages.value(QStringLiteral("v5-frame-parity")),
                      QStringLiteral("v5FrameParity"));
}