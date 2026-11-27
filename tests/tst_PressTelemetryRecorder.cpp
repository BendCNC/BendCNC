#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QtTest>

#include "PressTelemetryRecorder.h"

class PressTelemetryRecorderTests final : public QObject
{
    Q_OBJECT

private slots:
    void persistsRawFramesAndErrors()
    {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        PressTelemetryRecorder recorder(directory.path());
        recorder.recordRawFrame(QStringLiteral("RX"),
                                QByteArrayLiteral("[TH_CTRL]|\x01\x02"));
        recorder.recordRawFrame(QStringLiteral("TX"), QByteArrayLiteral("<TH:HB>\n"));
        recorder.recordError(QStringLiteral("TRANSPORT"), QStringLiteral("SHORT_WRITE"));
        recorder.flush();

        QFile file(recorder.logPath());
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QList<QByteArray> lines = file.readAll().split('\n');
        QVERIFY(lines.size() >= 4);
        const QJsonObject rx = QJsonDocument::fromJson(lines.at(0)).object();
        QCOMPARE(rx.value(QStringLiteral("event")).toString(), QStringLiteral("RX"));
        QCOMPARE(QByteArray::fromBase64(rx.value(QStringLiteral("frameBase64")).toString().toLatin1()),
                 QByteArrayLiteral("[TH_CTRL]|\x01\x02"));
        const QJsonObject error = QJsonDocument::fromJson(lines.at(2)).object();
        QCOMPARE(error.value(QStringLiteral("event")).toString(), QStringLiteral("ERROR"));
        QCOMPARE(error.value(QStringLiteral("category")).toString(), QStringLiteral("TRANSPORT"));
    }

    void persistsThs1FramesByteExactlyAcrossMultipleRows()
    {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        PressTelemetryRecorder recorder(directory.path());
        const QByteArray payload = QByteArrayLiteral(
            "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
            "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100");
        QCOMPARE(payload.size(), 128);
        const QByteArray ths1 = QByteArrayLiteral("[THS1 ") + payload + QByteArrayLiteral("]\r\n");
        QCOMPARE(ths1.size(), 137);

        recorder.recordRawFrame(QStringLiteral("RX"), ths1);
        recorder.recordRawFrame(QStringLiteral("RX"), ths1);
        recorder.flush();

        QFile file(recorder.logPath());
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QList<QByteArray> lines = file.readAll().split('\n');
        QCOMPARE(lines.size(), 3);
        for (int index = 0; index < 2; ++index) {
            const QJsonObject row = QJsonDocument::fromJson(lines.at(index)).object();
            QCOMPARE(row.value(QStringLiteral("event")).toString(), QStringLiteral("RX"));
            QCOMPARE(QByteArray::fromBase64(
                         row.value(QStringLiteral("frameBase64")).toString().toLatin1()),
                     ths1);
        }
    }

    void writesBoundedOverflowMarkerAfterStorageRecovers()
    {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QString blockedRoot = directory.filePath(QStringLiteral("blocked-root"));
        QFile blocker(blockedRoot);
        QVERIFY(blocker.open(QIODevice::WriteOnly));
        blocker.close();

        PressTelemetryRecorder recorder(blockedRoot);
        const QByteArray oversizedFrame(PressTelemetryRecorder::MaximumQueuedBytes, 'x');
        recorder.recordRawFrame(QStringLiteral("RX"), oversizedFrame);
        recorder.flush();
        QVERIFY(!QFile::exists(recorder.logPath()));

        QVERIFY(QFile::remove(blockedRoot));
        recorder.flush();

        QFile file(recorder.logPath());
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QJsonObject row = QJsonDocument::fromJson(file.readLine()).object();
        QCOMPARE(row.value(QStringLiteral("event")).toString(), QStringLiteral("DROPPED"));
        QCOMPARE(row.value(QStringLiteral("category")).toString(),
                 QStringLiteral("BUFFER_OVERFLOW"));
        QCOMPARE(row.value(QStringLiteral("message")).toString(), QStringLiteral("1"));
    }

    void rotatesBoundedHistory()
    {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        PressTelemetryRecorder recorder(directory.path());
        const QByteArray frame(4096, 'x');
        for (int batch = 0; batch < 3; ++batch) {
            for (int index = 0; index < 450; ++index)
                recorder.recordRawFrame(QStringLiteral("RX"), frame);
            recorder.flush();
        }

        QVERIFY(QFile::exists(recorder.logPath()));
        QVERIFY(QFile::exists(recorder.logPath() + QStringLiteral(".1")));
        QVERIFY(QFileInfo(recorder.logPath()).size()
                <= PressTelemetryRecorder::MaximumLogBytes + 6000);
        QVERIFY(!QFile::exists(recorder.logPath() + QStringLiteral(".4")));
    }
};

QTEST_MAIN(PressTelemetryRecorderTests)
#include "tst_PressTelemetryRecorder.moc"