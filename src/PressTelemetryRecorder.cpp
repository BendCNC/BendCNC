#include "PressTelemetryRecorder.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

namespace
{
QString telemetryRoot(const QString &requestedRoot)
{
    if (!requestedRoot.isEmpty())
        return requestedRoot;
    const QByteArray overrideRoot = qgetenv("BENDCNC_QT_HOME");
    if (!overrideRoot.isEmpty())
        return QString::fromLocal8Bit(overrideRoot);
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

QByteArray eventLine(const QString &event, const QByteArray &frame,
                     const QString &category, const QString &message)
{
    QJsonObject object;
    object.insert(QStringLiteral("timestampUtc"),
                  QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    object.insert(QStringLiteral("event"), event);
    if (!frame.isEmpty())
        object.insert(QStringLiteral("frameBase64"),
                      QString::fromLatin1(frame.toBase64()));
    if (!category.isEmpty())
        object.insert(QStringLiteral("category"), category);
    if (!message.isEmpty())
        object.insert(QStringLiteral("message"), message);
    return QJsonDocument(object).toJson(QJsonDocument::Compact) + '\n';
}
}

PressTelemetryRecorder::PressTelemetryRecorder(const QString &storageRoot, QObject *parent)
    : QObject(parent)
{
    const QString root = telemetryRoot(storageRoot);
    m_logPath = QDir(root).filePath(QStringLiteral("telemetry/press-telemetry.ndjson"));
    ensureStorageDirectory();
    m_flushTimer.setInterval(500);
    connect(&m_flushTimer, &QTimer::timeout, this, &PressTelemetryRecorder::flush);
    m_flushTimer.start();
}

PressTelemetryRecorder::~PressTelemetryRecorder()
{
    m_flushTimer.stop();
    flush();
}

void PressTelemetryRecorder::recordRawFrame(const QString &direction, const QByteArray &frame)
{
    enqueue(eventLine(direction, frame, QString(), QString()));
}

void PressTelemetryRecorder::recordError(const QString &category, const QString &message)
{
    enqueue(eventLine(QStringLiteral("ERROR"), QByteArray(), category, message));
}

void PressTelemetryRecorder::enqueue(const QByteArray &line)
{
    // This method is intentionally I/O-free: it runs in the serial signal path.
    if (line.size() > MaximumQueuedBytes || m_pendingBytes + line.size() > MaximumQueuedBytes) {
        ++m_droppedEvents;
        return;
    }
    m_pendingBytes += line.size();
    m_pendingLines.push_back(line);
}

void PressTelemetryRecorder::ensureStorageDirectory()
{
    QDir().mkpath(QFileInfo(m_logPath).absolutePath());
}

bool PressTelemetryRecorder::rotateIfNeeded(qsizetype pendingLineBytes)
{
    const QFileInfo info(m_logPath);
    if (!info.exists() || info.size() == 0 || info.size() + pendingLineBytes <= MaximumLogBytes)
        return true;
    rotate();
    return !QFileInfo::exists(m_logPath) || QFileInfo(m_logPath).size() == 0;
}

void PressTelemetryRecorder::rotate()
{
    for (int index = RetainedRotations; index >= 1; --index) {
        const QString source = index == 1 ? m_logPath
            : m_logPath + QLatin1Char('.') + QString::number(index - 1);
        const QString destination = m_logPath + QLatin1Char('.') + QString::number(index);
        if (QFile::exists(source)) {
            QFile::remove(destination);
            QFile::rename(source, destination);
        }
    }
}

void PressTelemetryRecorder::flush()
{
    if (m_droppedEvents != 0) {
        const QByteArray dropped = eventLine(QStringLiteral("DROPPED"), QByteArray(),
                                             QStringLiteral("BUFFER_OVERFLOW"),
                                             QString::number(m_droppedEvents));
        if (m_pendingBytes + dropped.size() <= MaximumQueuedBytes) {
            m_pendingBytes += dropped.size();
            m_pendingLines.push_front(dropped);
            m_droppedEvents = 0;
        }
    }
    if (m_pendingLines.empty())
        return;

    ensureStorageDirectory();
    QFile output(m_logPath);
    if (!output.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
        return;
    while (!m_pendingLines.empty()) {
        const QByteArray &line = m_pendingLines.front();
        if (output.size() > 0 && output.size() + line.size() > MaximumLogBytes) {
            output.close();
            rotate();
            if (!output.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
                break;
        }
        if (output.write(line) != line.size())
            break;
        m_pendingBytes -= line.size();
        m_pendingLines.pop_front();
    }
    output.flush();
}