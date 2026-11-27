#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>
#include <QTimer>

#include <deque>

// Persists an unfiltered, bounded history of the press serial conversation.
// Calls which record an event only append to memory; filesystem work happens
// from the periodic flush timer or during destruction.
class PressTelemetryRecorder final : public QObject
{
    Q_OBJECT

public:
    static constexpr qsizetype MaximumLogBytes = 4 * 1024 * 1024;
    static constexpr int RetainedRotations = 3;
    static constexpr qsizetype MaximumQueuedBytes = 4 * 1024 * 1024;

    explicit PressTelemetryRecorder(const QString &storageRoot = QString(),
                                    QObject *parent = nullptr);
    ~PressTelemetryRecorder() override;

    QString logPath() const { return m_logPath; }
    void recordRawFrame(const QString &direction, const QByteArray &frame);
    void recordError(const QString &category, const QString &message);
    void flush();

private:
    void enqueue(const QByteArray &line);
    void ensureStorageDirectory();
    bool rotateIfNeeded(qsizetype pendingLineBytes);
    void rotate();

    QString m_logPath;
    QTimer m_flushTimer;
    std::deque<QByteArray> m_pendingLines;
    qsizetype m_pendingBytes = 0;
    quint64 m_droppedEvents = 0;
};