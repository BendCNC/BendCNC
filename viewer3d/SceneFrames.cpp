#include "SceneFrames.h"

#include <QDir>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStandardPaths>
#include <algorithm>
#include <cmath>
#include <cstring>

namespace {
constexpr int kGroups = 6;

// unfold: X feed (+X = backgauge side), Y along the bed, Z ram (up).
// Quick3D: Y up, camera on +Z looks at the operator side of the press.
QVector3D toView(const float *p) { return QVector3D(-p[1], p[2], -p[0]); }

struct Block { quint32 vertexCount; quint32 indexCount; const float *positions; const quint32 *indices; };

QVector<Block> blocksAt(const uchar *data)
{
    QVector<Block> blocks;
    for (int g = 0; g < kGroups; ++g) {
        Block b;
        std::memcpy(&b.vertexCount, data, 4);
        std::memcpy(&b.indexCount, data + 4, 4);
        b.positions = reinterpret_cast<const float *>(data + 8);
        b.indices = reinterpret_cast<const quint32 *>(data + 8 + b.vertexCount * 12);
        data += 8 + b.vertexCount * 12 + b.indexCount * 4;
        blocks.append(b);
    }
    return blocks;
}
}

MeshGeometry::MeshGeometry(QQuick3DObject *parent)
    : QQuick3DGeometry(parent)
{
    setPrimitiveType(PrimitiveType::Triangles);
    setStride(24);
    addAttribute(Attribute::PositionSemantic, 0, Attribute::F32Type);
    addAttribute(Attribute::NormalSemantic, 12, Attribute::F32Type);
}

void MeshGeometry::setMesh(const float *positions, quint32 vertexCount, const quint32 *indices,
                           quint32 indexCount, const float *nextPositions, float t)
{
    m_buffer.resize(qsizetype(indexCount) * 24);
    float *out = reinterpret_cast<float *>(m_buffer.data());
    QVector3D lo(1e9f, 1e9f, 1e9f), hi(-1e9f, -1e9f, -1e9f);
    auto vertex = [&](quint32 i) {
        if (i >= vertexCount)
            return QVector3D();
        QVector3D v = toView(positions + i * 3);
        if (nextPositions)
            v += (toView(nextPositions + i * 3) - v) * t;
        return v;
    };
    for (quint32 k = 0; k + 2 < indexCount; k += 3) {
        const QVector3D a = vertex(indices[k]), b = vertex(indices[k + 1]), c = vertex(indices[k + 2]);
        const QVector3D n = QVector3D::crossProduct(b - a, c - a).normalized();
        for (const QVector3D &v : {a, b, c}) {
            *out++ = v.x(); *out++ = v.y(); *out++ = v.z();
            *out++ = n.x(); *out++ = n.y(); *out++ = n.z();
            lo = QVector3D(std::min(lo.x(), v.x()), std::min(lo.y(), v.y()), std::min(lo.z(), v.z()));
            hi = QVector3D(std::max(hi.x(), v.x()), std::max(hi.y(), v.y()), std::max(hi.z(), v.z()));
        }
    }
    setVertexData(m_buffer);
    if (indexCount)
        setBounds(lo, hi);
    update();
}

SceneFrames::SceneFrames(QObject *parent)
    : QObject(parent)
{
    for (int g = 0; g < kGroups; ++g)
        m_geometries.append(new MeshGeometry());
}

QList<QObject *> SceneFrames::geometries() const
{
    QList<QObject *> list;
    for (MeshGeometry *g : m_geometries)
        list.append(g);
    return list;
}

QString SceneFrames::defaultPlanPath()
{
    const QDir dir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
                   + QStringLiteral("/BendCNC/BendCNC/unfold-plans"));
    const QFileInfoList plans = dir.entryInfoList({QStringLiteral("*.plan.json")}, QDir::Files, QDir::Time);
    return plans.isEmpty() ? QString() : plans.first().absoluteFilePath();
}

bool SceneFrames::ensureExport(const QString &dir)
{
    // The exporter owns the cache: it reuses frames only when the hash key
    // (model, plan, catalog, options, engine/playback/exporter) still matches.
    QProcess node;
    node.setProcessChannelMode(QProcess::MergedChannels);
    node.start(QStringLiteral("node"), {QStringLiteral(BENDCNC_EXPORTER), QStringLiteral("--plan"), m_planPath,
                                        QStringLiteral("--out"), dir});
    if (!node.waitForFinished(180000) || node.exitCode() != 0) {
        m_status = QStringLiteral("Exportación falló: ") + QString::fromUtf8(node.readAll().right(300));
        return false;
    }
    return true;
}

void SceneFrames::setPlanPath(const QString &path)
{
    m_planPath = path.isEmpty() ? defaultPlanPath() : path;
    m_frames.clear();
    m_data = nullptr;
    m_bin.close();
    if (!QFileInfo::exists(m_planPath)) {
        m_status = QStringLiteral("Plan no encontrado");
        emit loaded();
        return;
    }
    const QString dir = m_planPath + QStringLiteral(".scene3d");
    if (ensureExport(dir)) {
        QFile metaFile(dir + QStringLiteral("/frames.json"));
        metaFile.open(QIODevice::ReadOnly);
        const QJsonObject meta = QJsonDocument::fromJson(metaFile.readAll()).object();
        m_duration = meta.value(QStringLiteral("durationSeconds")).toDouble();
        m_stageCount = meta.value(QStringLiteral("stages")).toInt();
        for (const QJsonValue &v : meta.value(QStringLiteral("frames")).toArray()) {
            const QJsonObject f = v.toObject();
            m_frames.append({qint64(f.value(QStringLiteral("offset")).toDouble()), f.value(QStringLiteral("time")).toDouble(),
                             f.value(QStringLiteral("stage")).toInt(), f.value(QStringLiteral("bend")).toString(),
                             f.value(QStringLiteral("partial")).toBool(), f.value(QStringLiteral("phase")).toString(),
                             f.value(QStringLiteral("segment")).toInt(-1),
                             f.value(QStringLiteral("topology")).toVariant().toStringList()});
        }
        m_bin.setFileName(dir + QStringLiteral("/frames.bin"));
        if (m_bin.open(QIODevice::ReadOnly))
            m_data = m_bin.map(0, m_bin.size());
        m_status = m_data && !m_frames.isEmpty()
                ? QStringLiteral("%1 cuadros · %2 pasos · %3").arg(m_frames.size()).arg(m_stageCount)
                      .arg(meta.value(QStringLiteral("engine")).toString(QStringLiteral("engine unknown")))
                : QStringLiteral("No se pudo leer la escena");
    }
    emit loaded();
    m_time = -1;
    setTime(0);
}

double SceneFrames::stageStartTime(int stage) const
{
    for (const Frame &f : m_frames)
        if (f.stage == stage)
            return f.time;
    return 0;
}

void SceneFrames::setTime(double seconds)
{
    seconds = std::clamp(seconds, 0.0, m_duration);
    if (seconds == m_time || !m_data || m_frames.isEmpty())
        return;
    m_time = seconds;
    applyFrame();
    emit timeChanged();
}

void SceneFrames::applyFrame()
{
    QElapsedTimer timer;
    timer.start();
    // Last frame whose time <= m_time; boundary frames repeat the same time.
    const auto it = std::upper_bound(m_frames.cbegin(), m_frames.cend(), m_time,
                                     [](double t, const Frame &f) { return t < f.time; });
    const int i = std::max(0, int(it - m_frames.cbegin()) - 1);
    const int j = std::min(int(m_frames.size()) - 1, i + 1);
    const double span = m_frames[j].time - m_frames[i].time;
    const float t = span > 1e-9 ? float((m_time - m_frames[i].time) / span) : 0.0f;
    const QVector<Block> a = blocksAt(m_data + m_frames[i].offset), b = blocksAt(m_data + m_frames[j].offset);
    m_triangles = 0;
    for (int g = 0; g < kGroups; ++g) {
        // Equal counts are not enough: the vertices must be the same bodies and
        // triangles (topology signature) within one stage/phase segment.
        const Frame &fi = m_frames[i], &fj = m_frames[j];
        const bool same = j != i && fi.segment >= 0 && fi.segment == fj.segment
                && g < fi.topology.size() && g < fj.topology.size() && fi.topology[g] == fj.topology[g]
                && a[g].vertexCount == b[g].vertexCount && a[g].indexCount == b[g].indexCount;
        m_geometries[g]->setMesh(a[g].positions, a[g].vertexCount, a[g].indices, a[g].indexCount,
                                 same ? b[g].positions : nullptr, t);
        m_triangles += int(a[g].indexCount / 3);
    }
    const Frame &f = m_frames[i];
    m_stageText = QStringLiteral("Paso %1/%2 · %3%4").arg(f.stage + 1).arg(m_stageCount).arg(f.bend,
                  f.partial ? QStringLiteral(" (parcial)") : QString());
    m_phaseText = f.phase;
    m_updateMs = timer.nsecsElapsed() / 1e6;
}
