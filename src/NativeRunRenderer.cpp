#include "NativeRunRenderer.h"

#include <QMutexLocker>
#include <QPainterPath>
#include <QPainterPathStroker>
#include <QPointer>
#include <QPolygonF>
#include <QMetaObject>
#include <QFont>
#include <QFontMetricsF>
#include <QRegularExpression>
#include <QElapsedTimer>
#include <QCache>
#include <QCryptographicHash>
#include <QDataStream>
#include <QFile>
#include <QSGFlatColorMaterial>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGNode>
#include <QSGTransformNode>
#include <QThreadPool>
#include <QTransform>
#include <QVariantMap>

#include <cmath>
#include <algorithm>
#include <future>
#include <limits>
#include <thread>
#include <vector>

namespace {

constexpr int kMaximumBatches = 16384;
constexpr int kMaximumVerticesPerBatch = 196608;
constexpr qsizetype kMaximumOpaqueVertices = 393216;
constexpr qreal kMaximumTransformCoefficient = 1000000.0;

quint64 detectedTotalMemoryBytes()
{
#ifdef Q_OS_LINUX
    QFile file(QStringLiteral("/proc/meminfo"));
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        while (!file.atEnd()) {
            const QByteArray line = file.readLine();
            if (!line.startsWith("MemTotal:"))
                continue;
            const QList<QByteArray> fields = line.mid(sizeof("MemTotal:") - 1)
                .simplified().split(' ');
            bool ok = false;
            const quint64 totalKiB = fields.isEmpty()
                ? 0 : fields.first().toULongLong(&ok);
            if (ok && totalKiB <= std::numeric_limits<quint64>::max() / 1024)
                return totalKiB * 1024;
            break;
        }
    }
#endif
    return 0;
}

int adaptiveCacheCost(int baseCost)
{
    const quint64 totalBytes = detectedTotalMemoryBytes();
    if (totalBytes >= 8ULL * 1024 * 1024 * 1024)
        return baseCost * 2;
    if (totalBytes >= 3ULL * 1024 * 1024 * 1024)
        return baseCost + baseCost / 2;
    return baseCost;
}

struct DrawRecord {
    QPainterPath path;
    QColor color;
    QByteArray commandCacheKey;
    QTransform commandTransform;
    QVector<QPointF> cachedVertices;
    QByteArray cachedGeometryKey;
    bool commandCacheHit = false;
};

void appendRecord(QVector<DrawRecord> *records, QPainterPath path, const QColor &color,
                  const QByteArray &commandCacheKey = {},
                  const QTransform &commandTransform = {})
{
    if (path.isEmpty())
        return;
    DrawRecord record;
    record.path = std::move(path);
    record.color = color;
    record.commandCacheKey = commandCacheKey;
    record.commandTransform = commandTransform;
    records->append(std::move(record));
}

bool finitePoint(const QPointF &point)
{
    return std::isfinite(point.x()) && std::isfinite(point.y())
        && std::abs(point.x()) <= 1000000.0 && std::abs(point.y()) <= 1000000.0;
}

QColor parseCanvasColor(const QVariant &value)
{
    const QString text = value.toString().trimmed();
    QColor color(text);
    if (color.isValid())
        return color;
    static const QRegularExpression rgbaPattern(
        QStringLiteral(R"(^rgba?\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)(?:\s*,\s*([0-9.]+))?\s*\)$)"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch match = rgbaPattern.match(text);
    if (!match.hasMatch())
        return {};
    const int red = std::clamp(qRound(match.captured(1).toDouble()), 0, 255);
    const int green = std::clamp(qRound(match.captured(2).toDouble()), 0, 255);
    const int blue = std::clamp(qRound(match.captured(3).toDouble()), 0, 255);
    const qreal alpha = match.captured(4).isEmpty()
        ? 1.0 : std::clamp(match.captured(4).toDouble(), 0.0, 1.0);
    return QColor(red, green, blue, qRound(alpha * 255.0));
}

bool buildSimplePathCommandCacheKey(const QVariantMap &command, bool stroke,
                                    QByteArray *key, QTransform *transform)
{
    if (!command.value(QStringLiteral("clipSubpaths")).toList().isEmpty()
        || command.value(QStringLiteral("composition")).toString()
               == QStringLiteral("destination-out")) {
        return false;
    }
    const QVariantList subpaths = command.value(QStringLiteral("subpaths")).toList();
    QPointF origin;
    QPointF direction;
    bool haveOrigin = false;
    bool haveDirection = false;
    for (const QVariant &subpathValue : subpaths) {
        const QVariantList points = subpathValue.toMap().value(QStringLiteral("points")).toList();
        if (points.size() < 4 || points.size() % 2 != 0)
            return false;
        for (qsizetype index = 0; index < points.size(); index += 2) {
            bool xOk = false;
            bool yOk = false;
            const QPointF point(points.at(index).toDouble(&xOk),
                                points.at(index + 1).toDouble(&yOk));
            if (!xOk || !yOk || !finitePoint(point))
                return false;
            if (!haveOrigin) {
                origin = point;
                haveOrigin = true;
            } else if (!haveDirection) {
                const QPointF candidate = point - origin;
                if (std::hypot(candidate.x(), candidate.y()) > 1.0e-7) {
                    direction = candidate;
                    haveDirection = true;
                }
            }
        }
    }
    if (!haveOrigin || !haveDirection)
        return false;

    const qreal length = std::hypot(direction.x(), direction.y());
    const qreal cosine = direction.x() / length;
    const qreal sine = direction.y() / length;
    *transform = QTransform(cosine, sine, -sine, cosine,
                            origin.x(), origin.y());
    bool inverseOk = false;
    const QTransform inverse = transform->inverted(&inverseOk);
    if (!inverseOk)
        return false;

    key->clear();
    QDataStream stream(key, QIODevice::WriteOnly);
    stream << quint8(stroke ? 1 : 0)
           << command.value(QStringLiteral("fillRule")).toString()
           << command.value(stroke ? QStringLiteral("strokeColor")
                                   : QStringLiteral("fillColor")).toString();
    if (stroke) {
        stream << command.value(QStringLiteral("lineWidth"), 1.0).toDouble()
               << command.value(QStringLiteral("lineCap")).toString()
               << command.value(QStringLiteral("dash")).toList();
    }
    stream << qint64(subpaths.size());
    for (const QVariant &subpathValue : subpaths) {
        const QVariantMap subpath = subpathValue.toMap();
        const QVariantList points = subpath.value(QStringLiteral("points")).toList();
        stream << subpath.value(QStringLiteral("closed")).toBool()
               << qint64(points.size());
        for (qsizetype index = 0; index < points.size(); index += 2) {
            const QPointF local = inverse.map(QPointF(
                points.at(index).toDouble(), points.at(index + 1).toDouble()));
            // Rotation introduces harmless floating-point noise. Quantize far
            // below a physical display pixel so rigid poses share one key
            // without collapsing genuinely deforming geometry.
            stream << qRound64(local.x() * 1000000.0)
                   << qRound64(local.y() * 1000000.0);
        }
    }
    return stream.status() == QDataStream::Ok;
}

struct ScanEdge {
    QPointF a;
    QPointF b;
    int windingDelta = 0;

    double xAt(double y) const
    {
        const double dy = b.y() - a.y();
        return a.x() + (y - a.y()) * (b.x() - a.x()) / dy;
    }
};

bool triangulatePath(const QPainterPath &path, QVector<QPointF> *triangles)
{
    QVector<ScanEdge> edges;
    QVector<double> levels;
    const QList<QPolygonF> contours = path.toSubpathPolygons();
    for (const QPolygonF &contour : contours) {
        if (contour.size() < 2)
            continue;
        for (qsizetype index = 0; index < contour.size(); ++index) {
            const QPointF &a = contour.at(index);
            const QPointF &b = contour.at((index + 1) % contour.size());
            if (!finitePoint(a) || !finitePoint(b))
                return false;
            if (std::abs(a.y() - b.y()) <= 1.0e-7)
                continue;
            edges.append({a, b, b.y() > a.y() ? 1 : -1});
            levels.append(a.y());
            levels.append(b.y());
        }
    }
    if (edges.isEmpty())
        return true;

    std::sort(levels.begin(), levels.end());
    levels.erase(std::unique(levels.begin(), levels.end(), [](double a, double b) {
        return std::abs(a - b) <= 1.0e-7;
    }), levels.end());

    struct Crossing {
        const ScanEdge *edge = nullptr;
        double middleX = 0.0;
    };
    QVector<Crossing> crossings;
    crossings.reserve(edges.size());
    const bool oddEven = path.fillRule() == Qt::OddEvenFill;
    for (qsizetype levelIndex = 0; levelIndex + 1 < levels.size(); ++levelIndex) {
        const double top = levels.at(levelIndex);
        const double bottom = levels.at(levelIndex + 1);
        if (bottom - top <= 1.0e-7)
            continue;
        const double middle = (top + bottom) * 0.5;
        crossings.clear();
        for (const ScanEdge &edge : edges) {
            const double minimum = std::min(edge.a.y(), edge.b.y());
            const double maximum = std::max(edge.a.y(), edge.b.y());
            if (middle > minimum && middle < maximum)
                crossings.append({&edge, edge.xAt(middle)});
        }
        std::sort(crossings.begin(), crossings.end(), [](const Crossing &a,
                                                          const Crossing &b) {
            return a.middleX < b.middleX;
        });

        const ScanEdge *left = nullptr;
        int winding = 0;
        bool inside = false;
        for (const Crossing &crossing : crossings) {
            const bool wasInside = inside;
            if (oddEven)
                inside = !inside;
            else {
                winding += crossing.edge->windingDelta;
                inside = winding != 0;
            }
            if (!wasInside && inside) {
                left = crossing.edge;
                continue;
            }
            if (!wasInside || inside || !left)
                continue;
            const ScanEdge *right = crossing.edge;
            const QPointF topLeft(left->xAt(top), top);
            const QPointF topRight(right->xAt(top), top);
            const QPointF bottomLeft(left->xAt(bottom), bottom);
            const QPointF bottomRight(right->xAt(bottom), bottom);
            if (topRight.x() > topLeft.x() + 1.0e-7
                || bottomRight.x() > bottomLeft.x() + 1.0e-7) {
                triangles->append(topLeft);
                triangles->append(bottomLeft);
                triangles->append(bottomRight);
                triangles->append(topLeft);
                triangles->append(bottomRight);
                triangles->append(topRight);
            }
            left = nullptr;
        }
    }
    return true;
}

bool appendPathSubpaths(const QVariantList &subpaths, QPainterPath *path,
                        QString *error, qsizetype commandIndex)
{
    for (const QVariant &subpathValue : subpaths) {
        const QVariantMap subpath = subpathValue.toMap();
        const QVariantList points = subpath.value(QStringLiteral("points")).toList();
        if (points.size() < 4 || points.size() % 2 != 0) {
            *error = QStringLiteral("Invalid native path at batch %1").arg(commandIndex);
            return false;
        }
        QPointF first;
        for (qsizetype index = 0; index < points.size(); index += 2) {
            bool xOk = false;
            bool yOk = false;
            const QPointF point(points.at(index).toDouble(&xOk),
                                points.at(index + 1).toDouble(&yOk));
            if (!xOk || !yOk || !finitePoint(point)) {
                *error = QStringLiteral("Invalid native path vertex at batch %1").arg(commandIndex);
                return false;
            }
            if (index == 0) {
                first = point;
                path->moveTo(point);
            } else {
                path->lineTo(point);
            }
        }
        if (subpath.value(QStringLiteral("closed")).toBool())
            path->closeSubpath();
    }
    return true;
}

QPainterPath pathFromCommand(const QVariantMap &command, const QString &key,
                             QString *error, qsizetype commandIndex)
{
    QPainterPath path;
    if (!appendPathSubpaths(command.value(key).toList(), &path, error, commandIndex))
        return {};
    path.setFillRule(command.value(QStringLiteral("fillRule")).toString()
                         == QStringLiteral("oddEven")
                     ? Qt::OddEvenFill : Qt::WindingFill);
    return path;
}

QPainterPath pathFromVariant(const QVariantList &subpaths, Qt::FillRule fillRule,
                             QString *error, qsizetype commandIndex)
{
    QPainterPath path;
    if (!appendPathSubpaths(subpaths, &path, error, commandIndex))
        return {};
    path.setFillRule(fillRule);
    return path;
}

void applyRecord(QVector<DrawRecord> *records, QPainterPath path,
                 const QColor &color, const QPainterPath &clip,
                 bool erase, const QByteArray &commandCacheKey = {},
                 const QTransform &commandTransform = {})
{
    if (!clip.isEmpty())
        path = path.intersected(clip);
    if (path.isEmpty())
        return;
    if (erase) {
        for (DrawRecord &record : *records) {
            record.path = record.path.subtracted(path);
            // Cached vertices describe the pre-erase path. Force this record
            // through normalized-path tessellation after any destructive
            // command so the submitted mesh matches the updated painter path.
            if (record.commandCacheHit) {
                record.cachedVertices.clear();
                record.cachedGeometryKey.clear();
                record.commandCacheHit = false;
            }
            record.commandCacheKey.clear();
            record.commandTransform.reset();
        }
    } else {
        appendRecord(records, std::move(path), color, commandCacheKey,
                     commandTransform);
    }
}

class RenderRootNode final : public QSGNode
{
public:
    int revision = std::numeric_limits<int>::min();
    QVector<QSGTransformNode *> transformNodes;
    QVector<QSGGeometryNode *> geometryNodes;
    QVector<QByteArray> geometryKeys;
    QVector<QColor> colors;
    QVector<QTransform> meshTransforms;
};

template<typename BatchType>
void updateGeometryNode(QSGGeometryNode *node, const BatchType &batch,
                        bool geometryChanged)
{
    const QVector<QPointF> &batchVertices = batch.vertexData();
    QSGGeometry *geometry = node->geometry();
    if (!geometry || geometry->vertexCount() != batchVertices.size()) {
        auto *replacement = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(),
                                             batchVertices.size());
        replacement->setDrawingMode(QSGGeometry::DrawTriangles);
        replacement->setVertexDataPattern(QSGGeometry::StreamPattern);
        node->setGeometry(replacement);
        geometry = replacement;
        geometryChanged = true;
    }
    if (geometryChanged) {
        auto *vertices = geometry->vertexDataAsPoint2D();
        for (qsizetype vertexIndex = 0; vertexIndex < batchVertices.size(); ++vertexIndex) {
            vertices[vertexIndex].set(float(batchVertices.at(vertexIndex).x()),
                                      float(batchVertices.at(vertexIndex).y()));
        }
        node->markDirty(QSGNode::DirtyGeometry);
    }

    auto *material = static_cast<QSGFlatColorMaterial *>(node->material());
    if (material->color() != batch.color) {
        material->setColor(batch.color);
        node->markDirty(QSGNode::DirtyMaterial);
    }
}

} // namespace

struct NativeRunRenderer::TessellationCache
{
    struct CommandEntry {
        Batch batch;
        QPainterPath localPath;
    };

    TessellationCache()
        : paths(adaptiveCacheCost(2000000)),
          commands(adaptiveCacheCost(4000000))
    {
        const unsigned int hardwareThreads = std::max(1u, std::thread::hardware_concurrency());
        const int workerCount = int(std::min(8u, hardwareThreads > 2 ? hardwareThreads - 1 : 1u));
        tessellationPool.setMaxThreadCount(workerCount);
        tessellationPool.setExpiryTimeout(30000);
    }

    QCache<QByteArray, QVector<QPointF>> paths;
    // Rigidly transformed commands can bypass QPainterPath and stroke rebuilds,
    // not merely their final triangulation.
    QCache<QByteArray, CommandEntry> commands;
    QMutex mutex;
    QThreadPool tessellationPool;
};

NativeRunRenderer::NativeRunRenderer(QQuickItem *parent)
    : QQuickItem(parent), m_tessellationCache(std::make_shared<TessellationCache>())
{
    setFlag(ItemHasContents, true);
}

NativeRunRenderer::~NativeRunRenderer()
{
    if (m_tessellationCache)
        m_tessellationCache->tessellationPool.waitForDone();
}

int NativeRunRenderer::acceptedRevision() const
{
    return m_acceptedRevision;
}

int NativeRunRenderer::presentedRevision() const
{
    return m_presentedRevision;
}

bool NativeRunRenderer::packetValid() const
{
    return m_packetValid;
}

QString NativeRunRenderer::packetError() const
{
    return m_packetError;
}

int NativeRunRenderer::batchCount() const
{
    return m_batchCount;
}

int NativeRunRenderer::vertexCount() const
{
    return m_vertexCount;
}

int NativeRunRenderer::parseMilliseconds() const
{
    return m_parseMilliseconds;
}

int NativeRunRenderer::coalescedFrameCount() const
{
    return m_coalescedFrameCount;
}

int NativeRunRenderer::tessellationCacheHits() const
{
    return m_tessellationCacheHits;
}

int NativeRunRenderer::tessellationCacheMisses() const
{
    return m_tessellationCacheMisses;
}

int NativeRunRenderer::retainedTransformUpdates() const
{
    return m_retainedTransformUpdates;
}

int NativeRunRenderer::sceneGraphGeometryUpdates() const
{
    return m_sceneGraphGeometryUpdates;
}

int NativeRunRenderer::sceneGraphTransformUpdates() const
{
    return m_sceneGraphTransformUpdates;
}

QString NativeRunRenderer::presentedGeometryDigest() const
{
    return m_presentedGeometryDigest;
}

QObject *NativeRunRenderer::timingSink() const
{
    return m_timingSink;
}

void NativeRunRenderer::setTimingSink(QObject *timingSink)
{
    m_timingSink = timingSink;
}

QString NativeRunRenderer::backendName() const
{
    return QStringLiteral("qtquick-qsg-triangles");
}

void NativeRunRenderer::setPacketStatus(bool valid, const QString &error)
{
    if (m_packetValid != valid) {
        m_packetValid = valid;
        emit packetValidChanged();
    }
    if (m_packetError != error) {
        m_packetError = error;
        emit packetErrorChanged();
    }
}

bool NativeRunRenderer::rejectOpaqueOperation(const QString &error,
                                              QString *outputError)
{
    if (outputError)
        *outputError = error;
    setPacketStatus(false, error);
    return false;
}

void NativeRunRenderer::acceptPacket(const std::shared_ptr<const Packet> &packet,
                                     int parseMilliseconds)
{
    {
        QMutexLocker locker(&m_packetMutex);
        m_packet = packet;
    }
    m_parseMilliseconds = parseMilliseconds;
    m_batchCount = packet->batches.size();
    m_vertexCount = 0;
    for (const Batch &batch : packet->batches)
        m_vertexCount += batch.vertexData().size();
    m_tessellationCacheHits = packet->tessellationCacheHits;
    m_tessellationCacheMisses = packet->tessellationCacheMisses;
    m_retainedTransformUpdates = packet->retainedTransformUpdates;
    setPacketStatus(true, {});
    if (m_acceptedRevision != packet->revision) {
        m_acceptedRevision = packet->revision;
        emit acceptedRevisionChanged();
    }
    update();
}

bool NativeRunRenderer::installOpaqueTriangleBatches(
    const QVector<OpaqueTriangleBatchDefinition> &batches, QString *error)
{
    if (batches.isEmpty() || batches.size() > kMaximumBatches)
        return rejectOpaqueOperation(
            QStringLiteral("Invalid opaque triangle batch count"), error);

    QVector<InstalledOpaqueBatch> installed;
    installed.reserve(batches.size());
    qsizetype totalVertices = 0;
    for (qsizetype batchIndex = 0; batchIndex < batches.size(); ++batchIndex) {
        const OpaqueTriangleBatchDefinition &definition = batches.at(batchIndex);
        if (!definition.color.isValid() || definition.color.alpha() != 255) {
            return rejectOpaqueOperation(
                QStringLiteral("Opaque triangle batch %1 requires an opaque color")
                    .arg(batchIndex), error);
        }
        if (definition.vertices.size() < 3
            || definition.vertices.size() % 3 != 0
            || definition.vertices.size() > kMaximumVerticesPerBatch) {
            return rejectOpaqueOperation(
                QStringLiteral("Invalid opaque triangle data at batch %1")
                    .arg(batchIndex), error);
        }
        if (definition.vertices.size() > kMaximumOpaqueVertices - totalVertices) {
            return rejectOpaqueOperation(
                QStringLiteral("Opaque triangle installation exceeds the vertex budget"),
                error);
        }
        totalVertices += definition.vertices.size();
        for (const QPointF &point : definition.vertices) {
            if (!finitePoint(point)) {
                return rejectOpaqueOperation(
                    QStringLiteral("Invalid opaque triangle vertex at batch %1")
                        .arg(batchIndex), error);
            }
        }

        QByteArray geometryKey;
        QDataStream geometryStream(&geometryKey, QIODevice::WriteOnly);
        geometryStream << definition.vertices;
        if (geometryStream.status() != QDataStream::Ok) {
            return rejectOpaqueOperation(
                QStringLiteral("Failed to encode opaque triangle batch %1")
                    .arg(batchIndex), error);
        }
        InstalledOpaqueBatch batch;
        batch.vertices = std::make_shared<const QVector<QPointF>>(
            definition.vertices);
        batch.color = definition.color;
        batch.geometryKey = std::move(geometryKey);
        installed.append(std::move(batch));
    }

    m_installedOpaqueBatches = std::move(installed);
    m_opaqueTransforms.fill(QTransform(), m_installedOpaqueBatches.size());
    m_committedOpaqueTransforms = m_opaqueTransforms;
    m_opaqueTransformStageValid = true;
    setPacketStatus(true, {});
    if (error)
        error->clear();
    return true;
}

bool NativeRunRenderer::submitOpaqueTriangleFrame(
    const QVector<QTransform> &transforms, int revision, QString *error)
{
    if (m_installedOpaqueBatches.isEmpty())
        return rejectOpaqueOperation(
            QStringLiteral("No opaque triangle batches are installed"), error);
    if (revision <= 0 || revision <= m_acceptedRevision
        || revision <= m_pendingRevision) {
        return false;
    }
    if (transforms.size() != m_installedOpaqueBatches.size()) {
        return rejectOpaqueOperation(
            QStringLiteral("Opaque transform count does not match installed batches"),
            error);
    }
    for (qsizetype batchIndex = 0; batchIndex < transforms.size(); ++batchIndex) {
        const QTransform &transform = transforms.at(batchIndex);
        if (!transform.isAffine()
            || !std::isfinite(transform.m11())
            || !std::isfinite(transform.m12())
            || !std::isfinite(transform.m21())
            || !std::isfinite(transform.m22())
            || !std::isfinite(transform.dx())
            || !std::isfinite(transform.dy())
            || std::abs(transform.m11()) > kMaximumTransformCoefficient
            || std::abs(transform.m12()) > kMaximumTransformCoefficient
            || std::abs(transform.m21()) > kMaximumTransformCoefficient
            || std::abs(transform.m22()) > kMaximumTransformCoefficient
            || std::abs(transform.dx()) > kMaximumTransformCoefficient
            || std::abs(transform.dy()) > kMaximumTransformCoefficient) {
            return rejectOpaqueOperation(
                QStringLiteral("Invalid opaque transform at batch %1")
                    .arg(batchIndex), error);
        }
    }

    auto packet = std::make_shared<Packet>();
    packet->revision = revision;
    packet->retainedTransformUpdates = transforms.size();
    packet->batches.reserve(m_installedOpaqueBatches.size());
    for (qsizetype batchIndex = 0;
         batchIndex < m_installedOpaqueBatches.size(); ++batchIndex) {
        const InstalledOpaqueBatch &installed =
            m_installedOpaqueBatches.at(batchIndex);
        Batch batch;
        batch.retainedVertices = installed.vertices;
        batch.color = installed.color;
        batch.geometryKey = installed.geometryKey;
        batch.meshTransform = transforms.at(batchIndex);
        packet->batches.append(std::move(batch));
    }
    m_pendingCommands.clear();
    m_pendingRevision = 0;
    m_opaqueTransforms = transforms;
    m_committedOpaqueTransforms = transforms;
    m_opaqueTransformStageValid = true;
    acceptPacket(packet, 0);
    if (error)
        error->clear();
    return true;
}

bool NativeRunRenderer::beginOpaqueBatchInstall(int expectedBatchCount)
{
    cancelOpaqueBatchInstall();
    if (expectedBatchCount <= 0 || expectedBatchCount > kMaximumBatches)
        return rejectOpaqueOperation(
            QStringLiteral("Invalid expected opaque batch count"));
    m_expectedOpaqueBatchCount = expectedBatchCount;
    m_opaqueInstallActive = true;
    return true;
}

bool NativeRunRenderer::appendOpaqueBatch(int primitive,
                                          const QVariantList &xyVertices,
                                          const QColor &color)
{
    if (!m_opaqueInstallActive)
        return rejectOpaqueOperation(
            QStringLiteral("Opaque batch installation is not active"));
    if (!m_opaqueInstallError.isEmpty())
        return false;
    if (primitive != OpaqueTriangles) {
        m_opaqueInstallError = QStringLiteral("Unsupported opaque primitive");
        return rejectOpaqueOperation(m_opaqueInstallError);
    }
    if (m_stagedOpaqueBatches.size() >= m_expectedOpaqueBatchCount) {
        m_opaqueInstallError = QStringLiteral("Too many opaque batches appended");
        return rejectOpaqueOperation(m_opaqueInstallError);
    }
    if (!color.isValid() || color.alpha() != 255) {
        m_opaqueInstallError = QStringLiteral("Opaque triangle batch requires an opaque color");
        return rejectOpaqueOperation(m_opaqueInstallError);
    }
    if (xyVertices.size() < 6 || xyVertices.size() % 6 != 0
        || xyVertices.size() / 2 > kMaximumVerticesPerBatch) {
        m_opaqueInstallError = QStringLiteral("Invalid opaque triangle coordinate data");
        return rejectOpaqueOperation(m_opaqueInstallError);
    }
    const qsizetype vertexCount = xyVertices.size() / 2;
    if (vertexCount > kMaximumOpaqueVertices - m_stagedOpaqueVertexCount) {
        m_opaqueInstallError = QStringLiteral(
            "Opaque triangle installation exceeds the vertex budget");
        return rejectOpaqueOperation(m_opaqueInstallError);
    }

    OpaqueTriangleBatchDefinition definition;
    definition.color = color;
    definition.vertices.reserve(xyVertices.size() / 2);
    for (qsizetype index = 0; index < xyVertices.size(); index += 2) {
        bool xOk = false;
        bool yOk = false;
        const QPointF point(xyVertices.at(index).toDouble(&xOk),
                            xyVertices.at(index + 1).toDouble(&yOk));
        if (!xOk || !yOk || !finitePoint(point)) {
            m_opaqueInstallError = QStringLiteral("Invalid opaque triangle coordinate");
            return rejectOpaqueOperation(m_opaqueInstallError);
        }
        definition.vertices.append(point);
    }
    m_stagedOpaqueBatches.append(std::move(definition));
    m_stagedOpaqueVertexCount += vertexCount;
    return true;
}

bool NativeRunRenderer::commitOpaqueBatchInstall()
{
    if (!m_opaqueInstallActive)
        return rejectOpaqueOperation(
            QStringLiteral("Opaque batch installation is not active"));
    if (!m_opaqueInstallError.isEmpty())
        return false;
    if (m_stagedOpaqueBatches.size() != m_expectedOpaqueBatchCount)
        return rejectOpaqueOperation(
            QStringLiteral("Opaque batch count does not match installation"));
    const QVector<OpaqueTriangleBatchDefinition> batches = m_stagedOpaqueBatches;
    cancelOpaqueBatchInstall();
    return installOpaqueTriangleBatches(batches);
}

void NativeRunRenderer::cancelOpaqueBatchInstall()
{
    m_stagedOpaqueBatches.clear();
    m_stagedOpaqueVertexCount = 0;
    m_expectedOpaqueBatchCount = 0;
    m_opaqueInstallActive = false;
    m_opaqueInstallError.clear();
}

bool NativeRunRenderer::setOpaqueBatchTransform(int batchIndex,
                                                qreal m11, qreal m12,
                                                qreal m21, qreal m22,
                                                qreal dx, qreal dy)
{
    if (!m_opaqueTransformStageValid)
        return rejectOpaqueOperation(
            QStringLiteral("Opaque transform staging is invalid"));
    const QTransform transform(m11, m12, m21, m22, dx, dy);
    if (batchIndex < 0 || batchIndex >= m_opaqueTransforms.size()
        || !transform.isAffine()
        || !std::isfinite(m11) || !std::isfinite(m12)
        || !std::isfinite(m21) || !std::isfinite(m22)
        || !std::isfinite(dx) || !std::isfinite(dy)
        || std::abs(m11) > kMaximumTransformCoefficient
        || std::abs(m12) > kMaximumTransformCoefficient
        || std::abs(m21) > kMaximumTransformCoefficient
        || std::abs(m22) > kMaximumTransformCoefficient
        || std::abs(dx) > kMaximumTransformCoefficient
        || std::abs(dy) > kMaximumTransformCoefficient) {
        m_opaqueTransforms = m_committedOpaqueTransforms;
        m_opaqueTransformStageValid = false;
        return rejectOpaqueOperation(QStringLiteral("Invalid opaque batch transform"));
    }
    m_opaqueTransforms[batchIndex] = transform;
    return true;
}

bool NativeRunRenderer::submitSharedOpaqueTransform(qreal m11, qreal m12,
                                                    qreal m21, qreal m22,
                                                    qreal dx, qreal dy,
                                                    int revision)
{
    if (m_installedOpaqueBatches.isEmpty())
        return rejectOpaqueOperation(
            QStringLiteral("No opaque triangle batches are installed"));
    const QTransform transform(m11, m12, m21, m22, dx, dy);
    if (!transform.isAffine()
        || !std::isfinite(m11) || !std::isfinite(m12)
        || !std::isfinite(m21) || !std::isfinite(m22)
        || !std::isfinite(dx) || !std::isfinite(dy)
        || std::abs(m11) > kMaximumTransformCoefficient
        || std::abs(m12) > kMaximumTransformCoefficient
        || std::abs(m21) > kMaximumTransformCoefficient
        || std::abs(m22) > kMaximumTransformCoefficient
        || std::abs(dx) > kMaximumTransformCoefficient
        || std::abs(dy) > kMaximumTransformCoefficient) {
        m_opaqueTransforms = m_committedOpaqueTransforms;
        m_opaqueTransformStageValid = true;
        return rejectOpaqueOperation(QStringLiteral("Invalid shared opaque transform"));
    }
    QVector<QTransform> transforms(m_installedOpaqueBatches.size(), transform);
    return submitOpaqueTriangleFrame(transforms, revision);
}

bool NativeRunRenderer::submitOpaqueRevision(int revision)
{
    if (!m_opaqueTransformStageValid) {
        m_opaqueTransforms = m_committedOpaqueTransforms;
        m_opaqueTransformStageValid = true;
        return rejectOpaqueOperation(
            QStringLiteral("Opaque transform staging was invalid; transforms were rolled back"));
    }
    return submitOpaqueTriangleFrame(m_opaqueTransforms, revision);
}

std::shared_ptr<const NativeRunRenderer::Packet> NativeRunRenderer::parsePacket(
    const QVariantList &commands, int revision, QString *error,
    const std::shared_ptr<TessellationCache> &cache)
{
    auto packet = std::make_shared<Packet>();
    packet->revision = revision;
    if (commands.size() > kMaximumBatches) {
        *error = QStringLiteral("Too many native render batches");
        return {};
    }

    QVector<DrawRecord> records;
    records.reserve(commands.size() * 2);
    for (qsizetype commandIndex = 0; commandIndex < commands.size(); ++commandIndex) {
        const QVariantMap command = commands.at(commandIndex).toMap();
        const QString primitive = command.value(QStringLiteral("type")).toString();
        if (primitive == QStringLiteral("text")) {
            const QString text = command.value(QStringLiteral("text")).toString();
            if (text.isEmpty())
                continue;
            bool xOk = false;
            bool yOk = false;
            const qreal x = command.value(QStringLiteral("x")).toDouble(&xOk);
            const qreal y = command.value(QStringLiteral("y")).toDouble(&yOk);
            if (!xOk || !yOk || !finitePoint(QPointF(x, y))) {
                *error = QStringLiteral("Invalid native text position at batch %1")
                             .arg(commandIndex);
                return {};
            }
            const qreal pixelSize = std::clamp(
                command.value(QStringLiteral("pixelSize"), 10.0).toDouble(),
                1.0, 256.0);
            QFont font;
            font.setPixelSize(qRound(pixelSize));
            font.setBold(command.value(QStringLiteral("bold")).toBool());
            QFontMetricsF metrics(font);
            qreal originX = x;
            const qreal width = metrics.horizontalAdvance(text);
            const QString alignment = command.value(QStringLiteral("align")).toString();
            if (alignment == QStringLiteral("center"))
                originX -= width * 0.5;
            else if (alignment == QStringLiteral("right")
                     || alignment == QStringLiteral("end"))
                originX -= width;
            qreal baselineY = y;
            const QString baseline = command.value(QStringLiteral("baseline")).toString();
            if (baseline == QStringLiteral("top"))
                baselineY += metrics.ascent();
            else if (baseline == QStringLiteral("middle"))
                baselineY += (metrics.ascent() - metrics.descent()) * 0.5;

            QPainterPath textPath;
            textPath.addText(QPointF(originX, baselineY), font, text);
            const QPainterPath clip;
            const QColor strokeColor = parseCanvasColor(
                command.value(QStringLiteral("strokeColor")));
            const qreal strokeWidth = command.value(QStringLiteral("strokeWidth"), 0.0).toDouble();
            if (strokeColor.isValid() && strokeWidth > 0.0) {
                QPainterPathStroker stroker;
                stroker.setWidth(strokeWidth * 2.0);
                stroker.setJoinStyle(Qt::RoundJoin);
                appendRecord(&records, stroker.createStroke(textPath), strokeColor);
            }
            const QColor fillColor = parseCanvasColor(
                command.value(QStringLiteral("color")));
            if (!fillColor.isValid()) {
                *error = QStringLiteral("Invalid native text color at batch %1")
                             .arg(commandIndex);
                return {};
            }
            appendRecord(&records, std::move(textPath), fillColor);
            continue;
        }
        if (primitive == QStringLiteral("triangles")) {
            const QColor color = parseCanvasColor(
                command.value(QStringLiteral("color")));
            if (!color.isValid()) {
                *error = QStringLiteral("Invalid native color at batch %1").arg(commandIndex);
                return {};
            }
            const QVariantList rawVertices = command.value(QStringLiteral("vertices")).toList();
            if (rawVertices.size() < 6 || rawVertices.size() % 6 != 0
                || rawVertices.size() / 2 > kMaximumVerticesPerBatch) {
                *error = QStringLiteral("Invalid native triangle data at batch %1").arg(commandIndex);
                return {};
            }
            Batch batch;
            batch.color = color;
            batch.vertices.reserve(rawVertices.size() / 2);
            qreal minimumX = std::numeric_limits<qreal>::max();
            qreal minimumY = std::numeric_limits<qreal>::max();
            for (qsizetype valueIndex = 0; valueIndex < rawVertices.size(); valueIndex += 2) {
                bool xOk = false;
                bool yOk = false;
                const QPointF point(rawVertices.at(valueIndex).toDouble(&xOk),
                                    rawVertices.at(valueIndex + 1).toDouble(&yOk));
                if (!xOk || !yOk || !finitePoint(point)) {
                    *error = QStringLiteral("Invalid native vertex at batch %1").arg(commandIndex);
                    return {};
                }
                batch.vertices.append(point);
                minimumX = std::min(minimumX, point.x());
                minimumY = std::min(minimumY, point.y());
            }
            batch.meshTransform = QTransform::fromTranslate(minimumX, minimumY);
            QDataStream geometryStream(&batch.geometryKey, QIODevice::WriteOnly);
            for (QPointF &point : batch.vertices) {
                point -= QPointF(minimumX, minimumY);
                geometryStream << point;
            }
            packet->batches.append(std::move(batch));
            continue;
        }
        if (primitive != QStringLiteral("path")) {
            *error = QStringLiteral("Unsupported native primitive at batch %1").arg(commandIndex);
            return {};
        }
        const QColor fillColor = parseCanvasColor(
            command.value(QStringLiteral("fillColor")));
        const QColor strokeColor = parseCanvasColor(
            command.value(QStringLiteral("strokeColor")));
        const bool simpleSingleRecord = fillColor.isValid() != strokeColor.isValid();
        QByteArray commandCacheKey;
        QTransform commandTransform;
        const bool commandCacheable = simpleSingleRecord
            && buildSimplePathCommandCacheKey(command, strokeColor.isValid(),
                                              &commandCacheKey, &commandTransform);
        if (commandCacheable) {
            QMutexLocker locker(&cache->mutex);
            if (const TessellationCache::CommandEntry *cachedCommand =
                    cache->commands.object(commandCacheKey)) {
                DrawRecord record;
                // A later destination-out command operates on retained paths,
                // not tessellated vertices. Retain the normalized painter path
                // with the mesh so a warm packet can preserve destructive
                // composition without rebuilding the source path or stroke.
                record.path = commandTransform.map(cachedCommand->localPath);
                record.color = cachedCommand->batch.color;
                record.commandCacheKey = commandCacheKey;
                record.commandTransform = commandTransform;
                record.cachedVertices = cachedCommand->batch.vertices;
                record.cachedGeometryKey = cachedCommand->batch.geometryKey;
                record.commandCacheHit = true;
                records.append(std::move(record));
                ++packet->tessellationCacheHits;
                ++packet->retainedTransformUpdates;
                continue;
            }
        }
        QPainterPath path = pathFromCommand(command, QStringLiteral("subpaths"),
                                            error, commandIndex);
        if (!error->isEmpty())
            return {};
        QPainterPath clip;
        const QVariantList clipSubpaths = command.value(QStringLiteral("clipSubpaths")).toList();
        if (!clipSubpaths.isEmpty()) {
            clip = pathFromVariant(
                clipSubpaths,
                command.value(QStringLiteral("clipFillRule")).toString()
                        == QStringLiteral("oddEven")
                    ? Qt::OddEvenFill : Qt::WindingFill,
                error, commandIndex);
            if (!error->isEmpty())
                return {};
        }
        const bool erase = command.value(QStringLiteral("composition")).toString()
            == QStringLiteral("destination-out");
        if (fillColor.isValid())
            applyRecord(&records, path, fillColor, clip, erase,
                        commandCacheable ? commandCacheKey : QByteArray(),
                        commandTransform);

        const double strokeWidth = command.value(QStringLiteral("lineWidth"), 1.0).toDouble();
        if (strokeColor.isValid() && strokeWidth > 0.0 && !erase) {
            QPainterPathStroker stroker;
            stroker.setWidth(strokeWidth);
            stroker.setJoinStyle(Qt::RoundJoin);
            stroker.setCapStyle(command.value(QStringLiteral("lineCap")).toString()
                                    == QStringLiteral("round")
                                ? Qt::RoundCap : Qt::FlatCap);
            QVector<qreal> dashPattern;
            for (const QVariant &dash : command.value(QStringLiteral("dash")).toList()) {
                const qreal value = dash.toReal();
                if (value > 0.0)
                    dashPattern.append(value / strokeWidth);
            }
            if (!dashPattern.isEmpty())
                stroker.setDashPattern(dashPattern);
            applyRecord(&records, stroker.createStroke(path), strokeColor, clip, erase,
                        commandCacheable ? commandCacheKey : QByteArray(),
                        commandTransform);
        }
    }

    struct PendingBatch {
        Batch batch;
        qsizetype recordIndex = 0;
        bool needsTessellation = false;
        QByteArray commandCacheKey;
        QTransform commandTransform;
    };
    QVector<PendingBatch> pendingBatches;
    QVector<qsizetype> missIndexes;
    pendingBatches.reserve(records.size());
    missIndexes.reserve(records.size());
    for (qsizetype recordIndex = 0; recordIndex < records.size(); ++recordIndex) {
        const DrawRecord &record = records.at(recordIndex);
        PendingBatch pending;
        pending.recordIndex = recordIndex;
        pending.batch.color = record.color;
        pending.commandCacheKey = record.commandCacheKey;
        pending.commandTransform = record.commandTransform;
        if (record.commandCacheHit && !record.cachedVertices.isEmpty()) {
            pending.batch.vertices = record.cachedVertices;
            pending.batch.geometryKey = record.cachedGeometryKey;
            pending.batch.meshTransform = record.commandTransform;
            pendingBatches.append(std::move(pending));
            continue;
        }
        QPainterPath normalizedPath;
        if (!record.commandCacheKey.isEmpty()) {
            bool inverseOk = false;
            const QTransform inverse = record.commandTransform.inverted(&inverseOk);
            if (!inverseOk) {
                *error = QStringLiteral("Invalid native rigid transform at record %1")
                             .arg(static_cast<qlonglong>(recordIndex));
                return {};
            }
            normalizedPath = inverse.map(record.path);
            pending.batch.meshTransform = record.commandTransform;
        } else {
            const QPointF offset = record.path.boundingRect().topLeft();
            normalizedPath = QTransform::fromTranslate(-offset.x(), -offset.y())
                                 .map(record.path);
            pending.batch.meshTransform = QTransform::fromTranslate(
                offset.x(), offset.y());
        }
        QDataStream geometryStream(&pending.batch.geometryKey, QIODevice::WriteOnly);
        geometryStream << normalizedPath;
        {
            QMutexLocker locker(&cache->mutex);
            if (const QVector<QPointF> *cachedVertices = cache->paths.object(
                    pending.batch.geometryKey)) {
                pending.batch.vertices = *cachedVertices;
                ++packet->tessellationCacheHits;
            }
        }
        if (pending.batch.vertices.isEmpty()) {
            ++packet->tessellationCacheMisses;
            pending.needsTessellation = true;
        }
        if (!pending.needsTessellation && !pending.batch.meshTransform.isIdentity())
            ++packet->retainedTransformUpdates;
        records[recordIndex].path = std::move(normalizedPath);
        pendingBatches.append(std::move(pending));
        if (pendingBatches.constLast().needsTessellation)
            missIndexes.append(pendingBatches.size() - 1);
    }

    const qsizetype workerCount = std::min<qsizetype>(
        missIndexes.size(), cache->tessellationPool.maxThreadCount());
    std::vector<std::future<qsizetype>> tessellationWorkers;
    tessellationWorkers.reserve(size_t(workerCount));
    for (qsizetype worker = 0; worker < workerCount; ++worker) {
        auto completion = std::make_shared<std::promise<qsizetype>>();
        tessellationWorkers.push_back(completion->get_future());
        cache->tessellationPool.start(
            [worker, workerCount, &missIndexes, &pendingBatches, &records, completion] {
                qsizetype failedRecord = -1;
                for (qsizetype cursor = worker; cursor < missIndexes.size();
                     cursor += workerCount) {
                    PendingBatch &pending = pendingBatches[missIndexes.at(cursor)];
                    if (!triangulatePath(records.at(pending.recordIndex).path,
                                         &pending.batch.vertices)) {
                        failedRecord = pending.recordIndex;
                        break;
                    }
                }
                completion->set_value(failedRecord);
            });
    }
    for (std::future<qsizetype> &worker : tessellationWorkers) {
        const qsizetype failedRecord = worker.get();
        if (failedRecord >= 0) {
            *error = QStringLiteral("Native path tessellation failed at record %1")
                         .arg(static_cast<qlonglong>(failedRecord));
            return {};
        }
    }

    packet->batches.reserve(packet->batches.size() + pendingBatches.size());
    for (PendingBatch &pending : pendingBatches) {
        if (pending.needsTessellation) {
            QMutexLocker locker(&cache->mutex);
            if (!cache->paths.contains(pending.batch.geometryKey)) {
                cache->paths.insert(
                    pending.batch.geometryKey,
                    new QVector<QPointF>(pending.batch.vertices),
                    int(std::min<qsizetype>(pending.batch.vertices.size(),
                                           std::numeric_limits<int>::max())));
            }
        }
        if (!pending.commandCacheKey.isEmpty()) {
            QMutexLocker locker(&cache->mutex);
            if (!cache->commands.contains(pending.commandCacheKey)) {
                auto *cachedCommand = new TessellationCache::CommandEntry;
                cachedCommand->batch = pending.batch;
                cachedCommand->batch.meshTransform.reset();
                cachedCommand->localPath = records.at(pending.recordIndex).path;
                cache->commands.insert(
                    pending.commandCacheKey,
                    cachedCommand,
                    int(std::min<qsizetype>(pending.batch.vertices.size(),
                                           std::numeric_limits<int>::max())));
            }
        }
        if (!pending.batch.vertices.isEmpty())
            packet->batches.append(std::move(pending.batch));
    }
    return packet;
}

NativeRunRenderer::ParseResult NativeRunRenderer::parseTimedPacket(
    const QVariantList &commands, int revision,
    const std::shared_ptr<TessellationCache> &cache)
{
    QElapsedTimer timer;
    timer.start();
    ParseResult result;
    result.packet = parsePacket(commands, revision, &result.error, cache);
    result.parseMilliseconds = int(timer.elapsed());
    return result;
}

bool NativeRunRenderer::submitFrame(const QVariantList &commands, int revision)
{
    if (revision <= 0 || revision <= m_acceptedRevision
        || revision <= m_pendingRevision)
        return false;
    if (m_parseRunning && m_pendingRevision > 0 && revision > m_pendingRevision)
        ++m_coalescedFrameCount;
    m_pendingCommands = commands;
    m_pendingRevision = revision;
    startPendingParse();
    return true;
}

void NativeRunRenderer::startPendingParse()
{
    if (m_parseRunning || m_pendingRevision <= 0)
        return;
    m_parseRunning = true;
    const QVariantList commands = m_pendingCommands;
    const int revision = m_pendingRevision;
    const std::shared_ptr<TessellationCache> cache = m_tessellationCache;
    QPointer<NativeRunRenderer> guard(this);
    QThreadPool::globalInstance()->start([guard, commands, revision, cache] {
        const ParseResult result = NativeRunRenderer::parseTimedPacket(
            commands, revision, cache);
        if (!guard)
            return;
        QMetaObject::invokeMethod(guard, [guard, revision, result] {
            if (guard)
                guard->finishParse(revision, result);
        }, Qt::QueuedConnection);
    });
}

void NativeRunRenderer::finishParse(int revision, const ParseResult &result)
{
    m_parseRunning = false;
    if (m_timingSink) {
        QMetaObject::invokeMethod(m_timingSink, "recordStageMilliseconds",
                                  Qt::QueuedConnection,
                                  Q_ARG(QString, QStringLiteral("native-parse")),
                                  Q_ARG(qreal, qreal(result.parseMilliseconds)));
    }
    const bool newerFramePending = revision != m_pendingRevision;
    if (revision == m_pendingRevision)
        m_pendingCommands.clear();
    if (revision <= m_acceptedRevision) {
        if (newerFramePending)
            startPendingParse();
        return;
    }
    m_parseMilliseconds = result.parseMilliseconds;
    const std::shared_ptr<const Packet> &parsed = result.packet;
    const QString &error = result.error;
    if (!parsed && newerFramePending) {
        startPendingParse();
        return;
    }
    setPacketStatus(bool(parsed), error);
    if (!parsed)
        return;
    acceptPacket(parsed, result.parseMilliseconds);
    if (newerFramePending)
        startPendingParse();
}

void NativeRunRenderer::finishPresentation(int revision, int geometryUpdates,
                                           int transformUpdates,
                                           const QString &geometryDigest)
{
    if (revision <= m_presentedRevision)
        return;
    m_sceneGraphGeometryUpdates = geometryUpdates;
    m_sceneGraphTransformUpdates = transformUpdates;
    m_presentedGeometryDigest = geometryDigest;
    m_presentedRevision = revision;
    emit presentedRevisionChanged();
}

QSGNode *NativeRunRenderer::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    QElapsedTimer updateTimer;
    updateTimer.start();
    std::shared_ptr<const Packet> packet;
    {
        QMutexLocker locker(&m_packetMutex);
        packet = m_packet;
    }

    auto *root = static_cast<RenderRootNode *>(oldNode);
    if (!root)
        root = new RenderRootNode;
    if (!packet || root->revision == packet->revision)
        return root;

    while (root->geometryNodes.size() < packet->batches.size()) {
        auto *transform = new QSGTransformNode;
        auto *node = new QSGGeometryNode;
        auto *material = new QSGFlatColorMaterial;
        node->setFlag(QSGNode::OwnsGeometry, true);
        node->setFlag(QSGNode::OwnsMaterial, true);
        node->setMaterial(material);
        transform->appendChildNode(node);
        root->appendChildNode(transform);
        root->transformNodes.append(transform);
        root->geometryNodes.append(node);
        root->geometryKeys.append(QByteArray());
        root->colors.append(QColor());
        root->meshTransforms.append(QTransform());
    }
    while (root->geometryNodes.size() > packet->batches.size()) {
        root->geometryNodes.removeLast();
        QSGTransformNode *transform = root->transformNodes.takeLast();
        root->removeChildNode(transform);
        delete transform;
        root->geometryKeys.removeLast();
        root->colors.removeLast();
        root->meshTransforms.removeLast();
    }
    int geometryUpdates = 0;
    int transformUpdates = 0;
    for (qsizetype batchIndex = 0; batchIndex < packet->batches.size(); ++batchIndex) {
        const Batch &batch = packet->batches.at(batchIndex);
        const bool geometryChanged = root->geometryKeys.at(batchIndex)
            != batch.geometryKey;
        const bool colorChanged = root->colors.at(batchIndex) != batch.color;
        if (geometryChanged || colorChanged) {
            updateGeometryNode(root->geometryNodes.at(batchIndex), batch, geometryChanged);
            if (geometryChanged)
                ++geometryUpdates;
        }
        if (root->meshTransforms.at(batchIndex) != batch.meshTransform) {
            const QMatrix4x4 matrix(batch.meshTransform);
            root->transformNodes.at(batchIndex)->setMatrix(matrix);
            ++transformUpdates;
        }
        root->geometryKeys[batchIndex] = batch.geometryKey;
        root->colors[batchIndex] = batch.color;
        root->meshTransforms[batchIndex] = batch.meshTransform;
    }
    QByteArray geometryDigest;
    QDataStream digestStream(&geometryDigest, QIODevice::WriteOnly);
    for (const Batch &batch : packet->batches)
        digestStream << batch.geometryKey << batch.color;
    const QString presentedGeometryDigest = QString::fromLatin1(
        QCryptographicHash::hash(geometryDigest, QCryptographicHash::Sha256).toHex());
    root->revision = packet->revision;
    const int presentedRevision = packet->revision;
    QMetaObject::invokeMethod(this, [this, presentedRevision, geometryUpdates,
                                     transformUpdates, presentedGeometryDigest] {
        finishPresentation(presentedRevision, geometryUpdates, transformUpdates,
                           presentedGeometryDigest);
    }, Qt::QueuedConnection);
    if (m_timingSink) {
        const qint64 updateNanoseconds = updateTimer.nsecsElapsed();
        QMetaObject::invokeMethod(m_timingSink, "recordStageNanoseconds",
                                  Qt::QueuedConnection,
                                  Q_ARG(QString, QStringLiteral("native-update-paint-node")),
                                  Q_ARG(qint64, updateNanoseconds));
    }
    return root;
}
