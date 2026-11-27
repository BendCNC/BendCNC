#include "RunFrameTiming.h"

#include <QMutex>
#include <QMutexLocker>
#include <QTest>

namespace {

QMutex messageMutex;
QStringList capturedMessages;
QtMessageHandler previousMessageHandler = nullptr;

void captureMessage(QtMsgType type, const QMessageLogContext &context,
                    const QString &message)
{
    {
        QMutexLocker locker(&messageMutex);
        capturedMessages.append(message);
    }
    if (previousMessageHandler)
        previousMessageHandler(type, context, message);
}

QString timingWindowMessage()
{
    QMutexLocker locker(&messageMutex);
    for (auto iterator = capturedMessages.crbegin();
         iterator != capturedMessages.crend(); ++iterator) {
        if (iterator->contains(QStringLiteral("RUN-TIMING window")))
            return *iterator;
    }
    return {};
}

} // namespace

class RunFrameTimingTest final : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        previousMessageHandler = qInstallMessageHandler(captureMessage);
    }

    void cleanupTestCase()
    {
        qInstallMessageHandler(previousMessageHandler);
        previousMessageHandler = nullptr;
    }

    void recordsAtomicBackgaugeReadoutSample()
    {
        {
            QMutexLocker locker(&messageMutex);
            capturedMessages.clear();
        }

        // Leave ample scheduler headroom: on a loaded Windows CI host even a
        // nominal qWait(2) can resume after the collection window and make
        // otherwise valid synthetic samples look stale.
        RunFrameTiming timing(true, 1000);
        const qreal first = timing.timingTimestampNanoseconds();
        QTest::qWait(2);
        const qreal second = timing.timingTimestampNanoseconds();
        QVERIFY(first >= 0.0);
        QVERIFY(second > first);

        timing.finishBackgaugeFingerReadoutSample(
            0.0, 1000000.0, 3000000.0, 6000000.0);
        const qreal boundary = timing.timingTimestampNanoseconds();
        timing.finishBackgaugeFingerReadoutSample(
            boundary, boundary - 1.0, boundary, boundary);

        QTRY_VERIFY_WITH_TIMEOUT(!timingWindowMessage().isEmpty(), 2000);
        const QString message = timingWindowMessage();
        QVERIFY(message.contains(QStringLiteral(
            "backgaugeReadoutSetupCount=1")));
        QVERIFY(message.contains(QStringLiteral(
            "backgaugeReadoutStrokeTextCallCount=1")));
        QVERIFY(message.contains(QStringLiteral(
            "backgaugeReadoutFillTextCallCount=1")));
        QVERIFY(message.contains(QStringLiteral(
            "backgaugeReadoutMeasuredTotalCount=1")));
        QVERIFY(message.contains(QStringLiteral(
            "backgaugeReadoutInvalidSamples=1")));
        QVERIFY(message.contains(QStringLiteral(
            "backgaugeReadoutSetupP50Ms=1.000")));
        QVERIFY(message.contains(QStringLiteral(
            "backgaugeReadoutStrokeTextCallP50Ms=2.000")));
        QVERIFY(message.contains(QStringLiteral(
            "nativePunchShadowPresented=0")));
        QVERIFY(message.contains(QStringLiteral("liveCycleHit=0")));
        QVERIFY(message.contains(QStringLiteral("liveFreshV5Build=0")));
        QVERIFY(message.contains(QStringLiteral("v5PanelSetupCount=0")));
        QVERIFY(message.contains(QStringLiteral("v5ResolveBoundsCount=0")));
        QVERIFY(message.contains(QStringLiteral("v5ToolingBoundsHit=0")));
        QVERIFY(message.contains(QStringLiteral("v5ToolingBuildCount=0")));
    }

    void recordsLiveV5StageCountersAndDurations()
    {
        {
            QMutexLocker locker(&messageMutex);
            capturedMessages.clear();
        }

        RunFrameTiming timing(true, 1000);
        timing.recordCount(QStringLiteral("live-cycle-hit"));
        timing.recordCount(QStringLiteral("live-cycle-hit"));
        timing.recordCount(QStringLiteral("live-fresh-v5-build"));
        timing.recordCount(QStringLiteral("v5-projected-artifact-miss"));
        timing.recordCount(QStringLiteral("v5-tooling-bounds-hit"));
        timing.recordCount(QStringLiteral("v5-tooling-bounds-miss"));
        timing.recordStageNanoseconds(
            QStringLiteral("v5-panel-setup"), 1250000);
        timing.recordStageNanoseconds(
            QStringLiteral("v5-panel-alignment"), 750000);
        timing.recordStageNanoseconds(
            QStringLiteral("v5-resolve-bounds"), 3750000);
        timing.recordStageNanoseconds(
            QStringLiteral("v5-tooling-key"), 250000);
        timing.recordStageNanoseconds(
            QStringLiteral("v5-tooling-build"), 2250000);

        QTRY_VERIFY_WITH_TIMEOUT(!timingWindowMessage().isEmpty(), 2000);
        const QString message = timingWindowMessage();
        QVERIFY(message.contains(QStringLiteral("liveCycleHit=2")));
        QVERIFY(message.contains(QStringLiteral("liveFreshV5Build=1")));
        QVERIFY(message.contains(QStringLiteral("v5ProjectedArtifactMiss=1")));
        QVERIFY(message.contains(QStringLiteral("v5ToolingBoundsHit=1")));
        QVERIFY(message.contains(QStringLiteral("v5ToolingBoundsMiss=1")));
        QVERIFY(message.contains(QStringLiteral("v5PanelSetupCount=1")));
        QVERIFY(message.contains(QStringLiteral("v5PanelSetupP50Ms=1.250")));
        QVERIFY(message.contains(QStringLiteral("v5PanelSetupTotalMs=1.250")));
        QVERIFY(message.contains(QStringLiteral("v5PanelAlignmentP50Ms=0.750")));
        QVERIFY(message.contains(QStringLiteral("v5ResolveBoundsCount=1")));
        QVERIFY(message.contains(QStringLiteral("v5ResolveBoundsP50Ms=3.750")));
        QVERIFY(message.contains(QStringLiteral("v5ResolveBoundsTotalMs=3.750")));
        QVERIFY(message.contains(QStringLiteral("v5ToolingKeyP50Ms=0.250")));
        QVERIFY(message.contains(QStringLiteral("v5ToolingBuildP50Ms=2.250")));
    }

    void preservesEventIntervalsAcrossWindowBoundaries()
    {
        {
            QMutexLocker locker(&messageMutex);
            capturedMessages.clear();
        }

        RunFrameTiming timing(true, 1000);
        timing.recordEvent(QStringLiteral("canvas-painted"));
        QTRY_VERIFY_WITH_TIMEOUT(!timingWindowMessage().isEmpty(), 2000);
        {
            QMutexLocker locker(&messageMutex);
            capturedMessages.clear();
        }

        timing.recordEvent(QStringLiteral("canvas-painted"));
        QTRY_VERIFY_WITH_TIMEOUT(!timingWindowMessage().isEmpty(), 2000);
        const QString message = timingWindowMessage();
        QVERIFY(message.contains(QStringLiteral("canvasPainted=1")));
        QVERIFY(message.contains(QStringLiteral("canvasIntervalCount=1")));
    }

    void disabledTimingReturnsSentinel()
    {
        RunFrameTiming timing(false);
        QCOMPARE(timing.timingTimestampNanoseconds(), -1.0);
        timing.finishBackgaugeFingerReadoutSample(0.0, 1.0, 2.0, 3.0);
    }
};

QTEST_GUILESS_MAIN(RunFrameTimingTest)

#include "tst_RunFrameTiming.moc"