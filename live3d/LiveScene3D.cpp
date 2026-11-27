#include "LiveScene3D.h"

#include <QColor>
#include <QElapsedTimer>
#include <QPainterPath>
#include <QPolygonF>
#include <QTransform>
#include <QtGui/private/qtriangulator_p.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

namespace {

constexpr int kStride = 10 * sizeof(float);
constexpr double kTriangulationScale = 1024.0; // qTriangulate is fixed point

double num(const QVariant &value, double fallback = 0.0)
{
    bool ok = false;
    const double result = value.toDouble(&ok);
    return ok && std::isfinite(result) ? result : fallback;
}

// Accepts {x_in, y_in}, {x, r} or {x, y}.
QPointF readPoint(const QVariant &value)
{
    const QVariantMap map = value.toMap();
    if (map.contains(QStringLiteral("x_in")))
        return { num(map.value(QStringLiteral("x_in"))), num(map.value(QStringLiteral("y_in"))) };
    if (map.contains(QStringLiteral("r")))
        return { num(map.value(QStringLiteral("x"))), num(map.value(QStringLiteral("r"))) };
    return { num(map.value(QStringLiteral("x"))), num(map.value(QStringLiteral("y"))) };
}

QVector3D readVector(const QVariant &value)
{
    const QVariantMap map = value.toMap();
    return { float(num(map.value(QStringLiteral("x")))), float(num(map.value(QStringLiteral("y")))),
             float(num(map.value(QStringLiteral("z")))) };
}

QVector<QPointF> readLoop(const QVariant &value)
{
    QVector<QPointF> loop;
    const QVariantList list = value.toList();
    loop.reserve(list.size());
    for (const QVariant &point : list) {
        const QPointF p = readPoint(point);
        if (!loop.isEmpty() && std::hypot(p.x() - loop.last().x(), p.y() - loop.last().y()) < 1e-7)
            continue;
        loop.push_back(p);
    }
    if (loop.size() > 2 && std::hypot(loop.first().x() - loop.last().x(),
                                      loop.first().y() - loop.last().y()) < 1e-7)
        loop.pop_back();
    return loop;
}

double signedArea(const QVector<QPointF> &loop)
{
    double area = 0;
    for (int i = 0; i < loop.size(); ++i) {
        const QPointF &a = loop[i];
        const QPointF &b = loop[(i + 1) % loop.size()];
        area += a.x() * b.y() - b.x() * a.y();
    }
    return area * 0.5;
}

// Cap triangulation (outer + holes, even-odd) via Qt's private triangulator.
QVector<QPointF> triangulate(const QVector<QPointF> &outer, const QVector<QVector<QPointF>> &holes)
{
    QVector<QPointF> triangles;
    if (outer.size() < 3)
        return triangles;
    QPainterPath path;
    path.setFillRule(Qt::OddEvenFill);
    path.addPolygon(QPolygonF(outer));
    path.closeSubpath();
    for (const auto &hole : holes) {
        if (hole.size() < 3)
            continue;
        path.addPolygon(QPolygonF(hole));
        path.closeSubpath();
    }
    const QTriangleSet set = qTriangulate(path, QTransform::fromScale(kTriangulationScale, kTriangulationScale), 1, true);
    const int count = set.indices.size();
    triangles.reserve(count);
    const bool wide = set.indices.type() == QVertexIndexVector::UnsignedInt;
    const auto *i32 = static_cast<const quint32 *>(set.indices.data());
    const auto *i16 = static_cast<const quint16 *>(set.indices.data());
    for (int i = 0; i < count; ++i) {
        const int index = wide ? int(i32[i]) : int(i16[i]);
        triangles.push_back({ set.vertices[index * 2] / kTriangulationScale,
                              set.vertices[index * 2 + 1] / kTriangulationScale });
    }
    // Keep a consistent CCW winding for the +z cap.
    for (int t = 0; t + 2 < triangles.size(); t += 3) {
        const QPointF &a = triangles[t], &b = triangles[t + 1], &c = triangles[t + 2];
        if ((b.x() - a.x()) * (c.y() - a.y()) - (b.y() - a.y()) * (c.x() - a.x()) < 0)
            std::swap(triangles[t + 1], triangles[t + 2]);
    }
    return triangles;
}

struct Writer {
    QByteArray *buffer;
    float *cursor = nullptr;
    QVector3D minimum { std::numeric_limits<float>::max(), std::numeric_limits<float>::max(),
                        std::numeric_limits<float>::max() };
    QVector3D maximum { -std::numeric_limits<float>::max(), -std::numeric_limits<float>::max(),
                        -std::numeric_limits<float>::max() };
    int vertices = 0;

    void reserve(int count)
    {
        buffer->resize(qsizetype(count) * kStride);
        cursor = reinterpret_cast<float *>(buffer->data());
        vertices = 0;
    }
    void put(const QVector3D &p, const QVector3D &n, const QVector4D &c)
    {
        *cursor++ = p.x(); *cursor++ = p.y(); *cursor++ = p.z();
        *cursor++ = n.x(); *cursor++ = n.y(); *cursor++ = n.z();
        *cursor++ = c.x(); *cursor++ = c.y(); *cursor++ = c.z(); *cursor++ = c.w();
        minimum = QVector3D(qMin(minimum.x(), p.x()), qMin(minimum.y(), p.y()), qMin(minimum.z(), p.z()));
        maximum = QVector3D(qMax(maximum.x(), p.x()), qMax(maximum.y(), p.y()), qMax(maximum.z(), p.z()));
        ++vertices;
    }
    void finish()
    {
        buffer->resize(qsizetype(vertices) * kStride);
    }
};

QVector4D rgba(const QColor &color)
{
    return { float(color.redF()), float(color.greenF()), float(color.blueF()), float(color.alphaF()) };
}

void configure(QQuick3DGeometry *geometry, const QByteArray &buffer, int vertices,
               const QVector3D &minimum, const QVector3D &maximum)
{
    geometry->clear();
    geometry->setStride(kStride);
    geometry->setPrimitiveType(QQuick3DGeometry::PrimitiveType::Triangles);
    geometry->addAttribute(QQuick3DGeometry::Attribute::PositionSemantic, 0,
                           QQuick3DGeometry::Attribute::F32Type);
    geometry->addAttribute(QQuick3DGeometry::Attribute::NormalSemantic, 3 * sizeof(float),
                           QQuick3DGeometry::Attribute::F32Type);
    geometry->addAttribute(QQuick3DGeometry::Attribute::ColorSemantic, 6 * sizeof(float),
                           QQuick3DGeometry::Attribute::F32Type);
    geometry->setVertexData(buffer);
    if (vertices > 0)
        geometry->setBounds(minimum, maximum);
    geometry->update();
}

// Builds prism walls for one loop; outwardSign orients the wall normals.
template<typename Emit>
void emitWalls(const QVector<QPointF> &loop, bool hole, Emit sink)
{
    const double area = signedArea(loop);
    // Outer loops: outward normal is (dy, -dx) when CCW. Holes point inward.
    double sign = area >= 0 ? 1.0 : -1.0;
    if (hole)
        sign = -sign;
    for (int i = 0; i < loop.size(); ++i) {
        const QPointF &a = loop[i];
        const QPointF &b = loop[(i + 1) % loop.size()];
        const double dx = b.x() - a.x(), dy = b.y() - a.y();
        const double length = std::hypot(dx, dy);
        if (length < 1e-9)
            continue;
        sink(a, b, QPointF(sign * dy / length, -sign * dx / length));
    }
}

// SheetMetalFoldSolver.js port (finite-radius strip kinematics).
double sinc(double x)
{
    if (std::abs(x) < 1e-4) { const double x2 = x * x; return 1 - x2 / 6 + x2 * x2 / 120; }
    return std::sin(x) / x;
}
double cosc(double x)
{
    if (std::abs(x) < 1e-4) { const double x2 = x * x; return x / 2 - x * x2 / 24 + x * x2 * x2 / 720; }
    return (1 - std::cos(x)) / x;
}

} // namespace

// ---------------------------------------------------------------------------

LiveProfileSolid::LiveProfileSolid(QQuick3DObject *parent)
    : QQuick3DGeometry(parent)
{
}

void LiveProfileSolid::clear()
{
    QQuick3DGeometry::clear();
    update();
    m_triangles = 0;
    emit rebuilt();
}

bool LiveProfileSolid::setProfile(const QVariantList &outerValue, const QVariantList &holesValue,
                                  const QVariantList &runsValue, const QString &colorName)
{
    const QVector<QPointF> outer = readLoop(outerValue);
    QVector<QVector<QPointF>> holes;
    for (const QVariant &hole : holesValue) {
        QVector<QPointF> loop = readLoop(hole);
        if (loop.size() >= 3)
            holes.push_back(loop);
    }
    QVector<QPair<double, double>> runs;
    for (const QVariant &run : runsValue) {
        const QVariantMap map = run.toMap();
        double z0 = num(map.value(QStringLiteral("z0")));
        double z1 = num(map.value(QStringLiteral("z1")));
        if (std::abs(z1 - z0) < 1e-6)
            continue;
        runs.push_back({ qMin(z0, z1), qMax(z0, z1) });
    }
    if (outer.size() < 3 || runs.isEmpty()) {
        clear();
        return false;
    }
    const QVector<QPointF> cap = triangulate(outer, holes);
    int wallEdges = outer.size();
    for (const auto &hole : holes)
        wallEdges += hole.size();
    const QVector4D face = rgba(QColor(colorName));
    const QVector4D side = rgba(QColor(colorName).darker(125));
    // Light seam: thin darker band at both ends of every run so adjacent
    // tooling segments read as separate pieces.
    const QVector4D seam = rgba(QColor(colorName).darker(175));
    constexpr float kSeamIn = 0.03f;

    QByteArray buffer;
    Writer w { &buffer };
    w.reserve(runs.size() * (cap.size() * 2 + wallEdges * 18));
    for (const auto &run : runs) {
        const float z0 = float(run.first), z1 = float(run.second);
        for (int t = 0; t + 2 < cap.size(); t += 3) {
            for (int k = 0; k < 3; ++k)
                w.put(QVector3D(cap[t + k].x(), cap[t + k].y(), z1), QVector3D(0, 0, 1), face);
            for (int k = 2; k >= 0; --k)
                w.put(QVector3D(cap[t + k].x(), cap[t + k].y(), z0), QVector3D(0, 0, -1), face);
        }
        const float band = qMin(kSeamIn, (z1 - z0) / 4);
        auto quad = [&](const QPointF &a, const QPointF &b, const QVector3D &normal,
                        float za, float zb, const QVector4D &color) {
            const QVector3D a0(a.x(), a.y(), za), a1(a.x(), a.y(), zb);
            const QVector3D b0(b.x(), b.y(), za), b1(b.x(), b.y(), zb);
            w.put(a0, normal, color); w.put(b0, normal, color); w.put(b1, normal, color);
            w.put(a0, normal, color); w.put(b1, normal, color); w.put(a1, normal, color);
        };
        auto wall = [&](const QPointF &a, const QPointF &b, const QPointF &n) {
            const QVector3D normal(n.x(), n.y(), 0);
            quad(a, b, normal, z0, z0 + band, seam);
            quad(a, b, normal, z0 + band, z1 - band, side);
            quad(a, b, normal, z1 - band, z1, seam);
        };
        emitWalls(outer, false, wall);
        for (const auto &hole : holes)
            emitWalls(hole, true, wall);
    }
    w.finish();
    configure(this, buffer, w.vertices, w.minimum, w.maximum);
    m_triangles = w.vertices / 3;
    emit rebuilt();
    return true;
}

// ---------------------------------------------------------------------------

bool LiveTriangleMesh::setMesh(const QVariantList &pointsValue, const QVariantList &trianglesValue,
                               bool mirrorZ, const QString &colorName)
{
    QVector<QVector3D> points;
    points.reserve(pointsValue.size());
    for (const QVariant &value : pointsValue) {
        const QVariantMap map = value.toMap();
        const double z = num(map.value(QStringLiteral("z")));
        points.push_back(QVector3D(float(num(map.value(QStringLiteral("x")))),
                                   float(num(map.value(QStringLiteral("r")))),
                                   float(mirrorZ ? -z : z)));
    }
    QVector<int> indices;
    for (const QVariant &value : trianglesValue) {
        const int index = value.toInt();
        if (index < 0 || index >= points.size()) {
            clear();
            update();
            return false;
        }
        indices.push_back(index);
    }
    indices.resize(indices.size() - indices.size() % 3);
    // Signed volume < 0 means the mapping inverted handedness: flip winding.
    double volume = 0;
    for (int t = 0; t + 2 < indices.size(); t += 3)
        volume += QVector3D::dotProduct(points[indices[t]],
                                        QVector3D::crossProduct(points[indices[t + 1]], points[indices[t + 2]]));
    const bool flip = volume < 0;
    const QVector4D color = rgba(QColor(colorName));
    QByteArray buffer;
    Writer w { &buffer };
    w.reserve(indices.size());
    for (int t = 0; t + 2 < indices.size(); t += 3) {
        const QVector3D &a = points[indices[t]];
        const QVector3D &b = points[indices[flip ? t + 2 : t + 1]];
        const QVector3D &c = points[indices[flip ? t + 1 : t + 2]];
        const QVector3D normal = QVector3D::crossProduct(b - a, c - a).normalized();
        w.put(a, normal, color); w.put(b, normal, color); w.put(c, normal, color);
    }
    w.finish();
    configure(this, buffer, w.vertices, w.minimum, w.maximum);
    return w.vertices > 0;
}

// ---------------------------------------------------------------------------

LivePartMesh::LivePartMesh(QQuick3DObject *parent)
    : QQuick3DGeometry(parent)
{
}

void LivePartMesh::clear()
{
    m_panels.clear();
    m_edges.clear();
    m_topologyKey.clear();
    QQuick3DGeometry::clear();
    update();
    m_triangleCount = 0;
    emit topologyChanged();
    emit posed();
}

bool LivePartMesh::setTopology(const QString &key, const QVariantList &panels, const QVariantList &edges)
{
    m_panels.clear();
    m_edges.clear();
    for (const QVariant &value : panels) {
        const QVariantMap map = value.toMap();
        const QVector<QPointF> outer = readLoop(map.value(QStringLiteral("outerLoop")));
        if (outer.size() < 3)
            continue;
        QVector<QVector<QPointF>> holes;
        for (const QVariant &hole : map.value(QStringLiteral("holeLoops")).toList()) {
            QVector<QPointF> loop = readLoop(hole);
            if (loop.size() >= 3)
                holes.push_back(loop);
        }
        Panel panel;
        panel.id = map.value(QStringLiteral("id")).toString();
        panel.thickness = qMax(0.0, num(map.value(QStringLiteral("thickness")), 0.036));
        const float bottom = float(-panel.thickness);
        const QVector<QPointF> cap = triangulate(outer, holes);
        for (int t = 0; t + 2 < cap.size(); t += 3) {
            for (int k = 0; k < 3; ++k)
                panel.vertices.push_back({ QVector3D(cap[t + k].x(), cap[t + k].y(), 0), QVector3D(0, 0, 1), 0 });
            for (int k = 2; k >= 0; --k)
                panel.vertices.push_back({ QVector3D(cap[t + k].x(), cap[t + k].y(), bottom), QVector3D(0, 0, -1), 1 });
        }
        auto wall = [&](const QPointF &a, const QPointF &b, const QPointF &n) {
            const QVector3D normal(n.x(), n.y(), 0);
            const QVector3D a0(a.x(), a.y(), bottom), a1(a.x(), a.y(), 0);
            const QVector3D b0(b.x(), b.y(), bottom), b1(b.x(), b.y(), 0);
            for (const QVector3D &p : { a0, b0, b1, a0, b1, a1 })
                panel.vertices.push_back({ p, normal, 2 });
        };
        emitWalls(outer, false, wall);
        for (const auto &hole : holes)
            emitWalls(hole, true, wall);
        m_panels.push_back(panel);
    }
    for (const QVariant &value : edges) {
        const QVariantMap map = value.toMap();
        Edge edge;
        edge.parentId = map.value(QStringLiteral("parentPanelId")).toString();
        edge.childId = map.value(QStringLiteral("childPanelId")).toString();
        const int sequence = int(num(map.value(QStringLiteral("sequenceHint")), 0));
        edge.sequence = sequence;
        edge.direction = map.value(QStringLiteral("direction")).toString();
        edge.label = sequence > 0 ? QStringLiteral("B%1").arg(sequence)
                                  : map.value(QStringLiteral("bendId")).toString();
        const QPointF s = readPoint(map.value(QStringLiteral("hingeStart")));
        const QPointF e = readPoint(map.value(QStringLiteral("hingeEnd")));
        edge.start = QVector3D(s.x(), s.y(), 0);
        edge.end = QVector3D(e.x(), e.y(), 0);
        edge.side = num(map.value(QStringLiteral("childSideSign")), 1) < 0 ? -1 : 1;
        edge.radius = qMax(0.0, num(map.value(QStringLiteral("insideRadius_in"))));
        edge.thickness = qMax(0.0, num(map.value(QStringLiteral("thickness_in"))));
        edge.k = qBound(0.0, num(map.value(QStringLiteral("kFactor")), 0.44), 1.0);
        {
            double fold = num(map.value(QStringLiteral("foldAngleDegrees")), -1);
            if (!(fold >= 0))
                fold = 180 - num(map.value(QStringLiteral("bendAngleDegrees")), 180);
            fold = qBound(0.0, fold, 180.0);
            edge.developed = qDegreesToRadians(fold) * (edge.radius + edge.k * edge.thickness);
        }
        if ((edge.end - edge.start).length() > 1e-9)
            m_edges.push_back(edge);
    }
    m_topologyKey = m_panels.isEmpty() ? QString() : key;
    emit topologyChanged();
    return !m_panels.isEmpty();
}

QVariantMap LivePartMesh::gaugeContactSpan(double tolerance) const
{
    QVariantMap result { { QStringLiteral("found"), false } };
    const int count = int(m_buffer.size() / kStride);
    if (count <= 0)
        return result;
    const float *v = reinterpret_cast<const float *>(m_buffer.constData());
    const int step = kStride / int(sizeof(float));
    float minX = std::numeric_limits<float>::max();
    for (int i = 0; i < count; ++i)
        minX = qMin(minX, v[i * step]);
    float z0 = std::numeric_limits<float>::max(), z1 = -z0;
    for (int i = 0; i < count; ++i) {
        if (v[i * step] > minX + float(tolerance))
            continue;
        z0 = qMin(z0, v[i * step + 2]);
        z1 = qMax(z1, v[i * step + 2]);
    }
    result.insert(QStringLiteral("found"), z1 >= z0);
    result.insert(QStringLiteral("z0"), double(z0));
    result.insert(QStringLiteral("z1"), double(z1));
    return result;
}

namespace {
// z extent of the triangle part inside lo <= x <= hi (false if empty).
bool slabZRange(const QVector3D tri[3], double lo, double hi, double &z0, double &z1)
{
    QVector<QVector3D> poly { tri[0], tri[1], tri[2] };
    auto clip = [&poly](double bound, bool keepBelow) {
        QVector<QVector3D> out;
        for (int i = 0; i < poly.size(); ++i) {
            const QVector3D a = poly[i], b = poly[(i + 1) % poly.size()];
            const bool ina = keepBelow ? a.x() <= bound : a.x() >= bound;
            const bool inb = keepBelow ? b.x() <= bound : b.x() >= bound;
            if (ina)
                out.push_back(a);
            if (ina != inb) {
                const float t = float((bound - a.x()) / (b.x() - a.x()));
                out.push_back(a + (b - a) * t);
            }
        }
        poly = out;
    };
    clip(hi, true);
    if (poly.isEmpty())
        return false;
    if (std::isfinite(lo))
        clip(lo, false);
    if (poly.isEmpty())
        return false;
    z0 = z1 = poly[0].z();
    for (const QVector3D &p : poly) {
        z0 = qMin(z0, double(p.z()));
        z1 = qMax(z1, double(p.z()));
    }
    return true;
}

QVector<QPair<double, double>> mergeRuns(QVector<QPair<double, double>> runs)
{
    std::sort(runs.begin(), runs.end());
    QVector<QPair<double, double>> merged;
    for (const auto &r : runs) {
        if (!merged.isEmpty() && r.first <= merged.last().second + 1e-4)
            merged.last().second = qMax(merged.last().second, r.second);
        else
            merged.push_back(r);
    }
    return merged;
}
}

QVariantMap LivePartMesh::gaugeContactSpanAt(double tolerance, double gaugeX) const
{
    const int count = int(m_buffer.size() / kStride);
    if (count < 3 || !std::isfinite(gaugeX))
        return gaugeContactSpan(tolerance);
    const float *v = reinterpret_cast<const float *>(m_buffer.constData());
    const int step = kStride / int(sizeof(float));
    QVector<QPair<double, double>> contact, blocked;
    for (int i = 0; i + 2 < count; i += 3) {
        QVector3D tri[3];
        for (int k = 0; k < 3; ++k) {
            const float *p = v + (i + k) * step;
            tri[k] = QVector3D(p[0], p[1], p[2]);
        }
        double z0, z1;
        if (slabZRange(tri, gaugeX - tolerance, gaugeX + tolerance, z0, z1))
            contact.push_back({ z0, z1 });
        if (slabZRange(tri, -std::numeric_limits<double>::infinity(), gaugeX - tolerance, z0, z1))
            blocked.push_back({ z0, z1 });
    }
    contact = mergeRuns(contact);
    blocked = mergeRuns(blocked);
    // Free contact = contact runs minus blocked runs; keep the widest.
    // All free runs are also returned (z order) so separate corner tabs can
    // each carry a finger.
    double best0 = 0, best1 = -1;
    QVariantList spans;
    auto addFree = [&](double a, double b) {
        if (b - a <= 1e-4)
            return;
        spans.push_back(QVariantMap { { QStringLiteral("z0"), a }, { QStringLiteral("z1"), b } });
        if (b - a > best1 - best0) { best0 = a; best1 = b; }
    };
    for (const auto &c : contact) {
        double start = c.first;
        for (const auto &b : blocked) {
            if (b.second <= start || b.first >= c.second)
                continue;
            addFree(start, b.first);
            start = qMax(start, b.second);
        }
        addFree(start, c.second);
    }
    if (best1 <= best0)
        return gaugeContactSpan(tolerance);
    return { { QStringLiteral("found"), true }, { QStringLiteral("z0"), best0 }, { QStringLiteral("z1"), best1 },
             { QStringLiteral("spans"), spans },
             { QStringLiteral("blocked"), !blocked.isEmpty() }, { QStringLiteral("exact"), true } };
}

double LivePartMesh::dieClearanceLift(const QVariantList &dieOuter, const QVariantList &dieRuns, double shiftX, double tiltDeg, bool useCache) const
{
    // Die-derived data is constant between tooling changes: reuse it per frame.
    if (useCache && !m_dieCacheValid) {
        m_cacheRuns.clear();
        for (const QVariant &value : dieRuns) {
            const QVariantMap run = value.toMap();
            m_cacheRuns.push_back({ num(run.value(QStringLiteral("z0"))), num(run.value(QStringLiteral("z1"))) });
        }
        m_cacheDie = readLoop(dieOuter);
        m_dieCacheValid = true;
    }
    // Only material above an installed die segment can rest on it.
    QVector<QPair<double, double>> runsLocal;
    if (!useCache) {
        for (const QVariant &value : dieRuns) {
            const QVariantMap run = value.toMap();
            runsLocal.push_back({ num(run.value(QStringLiteral("z0"))), num(run.value(QStringLiteral("z1"))) });
        }
    }
    const QVector<QPair<double, double>> &runs = useCache ? m_cacheRuns : runsLocal;
    auto overDie = [&](float z) {
        if (runs.isEmpty())
            return true;
        for (const auto &run : runs)
            if (z >= run.first && z <= run.second)
                return true;
        return false;
    };
    const QVector<QPointF> dieLocal = useCache ? QVector<QPointF>() : readLoop(dieOuter);
    const QVector<QPointF> &die = useCache ? m_cacheDie : dieLocal;
    const int count = int(m_buffer.size() / kStride);
    if (die.size() < 3 || count < 3)
        return 0;
    const float *v = reinterpret_cast<const float *>(m_buffer.constData());
    const int step = kStride / int(sizeof(float));
    // Evaluate the part as displayed: rotated by tiltDeg about z.
    QVector<float> rotated;
    if (tiltDeg != 0) {
        const float c = float(std::cos(qDegreesToRadians(tiltDeg))), s = float(std::sin(qDegreesToRadians(tiltDeg)));
        rotated.resize(count * step);
        for (int i = 0; i < count; ++i) {
            const float *p = v + i * step;
            float *q = rotated.data() + i * step;
            q[0] = c * p[0] - s * p[1];
            q[1] = s * p[0] + c * p[1];
            q[2] = p[2];
        }
        v = rotated.constData();
    }
    float minX = std::numeric_limits<float>::max(), maxX = -minX;
    for (int i = 0; i < count; ++i) {
        minX = qMin(minX, v[i * step]);
        maxX = qMax(maxX, v[i * step]);
    }
    double zoneMid = 0;
    {
        double lo = std::numeric_limits<double>::max(), hi = -lo;
        for (const QPointF &p : die) { lo = qMin(lo, p.x()); hi = qMax(hi, p.x()); }
        zoneMid = (lo + hi) * 0.5;
    }
    const double zoneX0 = zoneMid - 1.1, zoneX1 = zoneMid + 1.1;
    // Lowest part point per 0.005 in column (triangle edges sampled per bin).
    const double bin = 0.005;
    const int bins = qBound(1, int(std::ceil((maxX - minX) / bin)) + 1, 20000);
    QVector<double> low(bins, std::numeric_limits<double>::max());
    QVector<double> high(bins, -std::numeric_limits<double>::max());
    auto addLine = [&](double xa, double ya, double xb, double yb) {
        const double x0 = qMax(qMin(xa, xb), zoneX0), x1 = qMin(qMax(xa, xb), zoneX1);
        if (x1 < x0)
            return;
        const int i0 = qBound(0, int((x0 - minX) / bin), bins - 1);
        const int i1 = qBound(0, int((x1 - minX) / bin), bins - 1);
        for (int i = i0; i <= i1; ++i) {
            const double x = qBound(x0, minX + (i + 0.5) * bin, x1);
            const double y = std::abs(xb - xa) < 1e-9 ? qMin(ya, yb)
                : ya + (yb - ya) * (x - xa) / (xb - xa);
            low[i] = qMin(low[i], y);
            high[i] = qMax(high[i], y);
        }
    };
    for (int t = 0; t + 2 < count; t += 3) {
        // Every line added below lies inside the triangle's x hull and is
        // clipped to the forming zone, so triangles fully outside it add
        // nothing: skip them (exact; most of the part is outside the zone).
        {
            const float x0 = v[t * step], x1 = v[(t + 1) * step], x2 = v[(t + 2) * step];
            if (qMax(x0, qMax(x1, x2)) < zoneX0 || qMin(x0, qMin(x1, x2)) > zoneX1)
                continue;
        }
        // Triangle clipped by each die segment's end planes: the cut edges are
        // part of the clipped polygon and can be its lowest point over the die.
        for (const auto &run : runs) {
            for (const double plane : { run.first, run.second }) {
                double px[2], py[2];
                int hits = 0;
                for (int k = 0; k < 3 && hits < 2; ++k) {
                    const float *a = v + (t + k) * step, *b = v + (t + (k + 1) % 3) * step;
                    const double da = a[2] - plane, db = b[2] - plane;
                    if ((da < 0) == (db < 0) || std::abs(db - da) < 1e-12)
                        continue;
                    const double f = da / (da - db);
                    px[hits] = a[0] + (b[0] - a[0]) * f;
                    py[hits] = a[1] + (b[1] - a[1]) * f;
                    ++hits;
                }
                if (hits == 2)
                    addLine(px[0], py[0], px[1], py[1]);
            }
        }
        for (int k = 0; k < 3; ++k) {
            const float *a = v + (t + k) * step, *b = v + (t + (k + 1) % 3) * step;
            // Clip the edge to each die z-run analytically (a flange beside
            // the die must not seat on it) and to the forming zone in x.
            if (qMax(a[0], b[0]) < zoneX0 || qMin(a[0], b[0]) > zoneX1)
                continue;
            auto addSpan = [&](double f0, double f1) {
                const double xa = a[0] + (b[0] - a[0]) * f0, xb = a[0] + (b[0] - a[0]) * f1;
                const double ya = a[1] + (b[1] - a[1]) * f0, yb = a[1] + (b[1] - a[1]) * f1;
                const double x0 = qMax(qMin(xa, xb), zoneX0), x1 = qMin(qMax(xa, xb), zoneX1);
                if (x1 < x0)
                    return;
                const int i0 = qBound(0, int((x0 - minX) / bin), bins - 1);
                const int i1 = qBound(0, int((x1 - minX) / bin), bins - 1);
                for (int i = i0; i <= i1; ++i) {
                    const double x = qBound(x0, minX + (i + 0.5) * bin, x1);
                    const double y = std::abs(xb - xa) < 1e-9 ? qMin(ya, yb)
                        : ya + (yb - ya) * (x - xa) / (xb - xa);
                    low[i] = qMin(low[i], y);
                    high[i] = qMax(high[i], y);
                }
            };
            if (runs.isEmpty()) {
                addSpan(0, 1);
                continue;
            }
            const double dz = b[2] - a[2];
            for (const auto &run : runs) {
                double f0 = 0, f1 = 1;
                if (std::abs(dz) < 1e-9) {
                    if (a[2] < run.first || a[2] > run.second)
                        continue;
                } else {
                    const double g0 = (run.first - a[2]) / dz, g1 = (run.second - a[2]) / dz;
                    f0 = qMax(0.0, qMin(g0, g1));
                    f1 = qMin(1.0, qMax(g0, g1));
                }
                if (f1 >= f0)
                    addSpan(f0, f1);
            }
        }
    }
    auto partMinY = [&](double x) {
        return low[qBound(0, int((x - minX) / bin), bins - 1)];
    };
    // Signed: positive lifts a sinking part, negative lowers a floating one
    // so the lowest contact sits exactly on the die.
    QVector<QPointF> diePtsLocal;
    double dieMid = 0;
    if (!(useCache && m_cacheShoulderValid)) {
        double dieMinX = std::numeric_limits<double>::max(), dieMaxX = -dieMinX;
        for (int i = 0; i < die.size(); ++i) {
            const QPointF a = die[i], b = die[(i + 1) % die.size()];
            dieMinX = qMin(dieMinX, a.x());
            dieMaxX = qMax(dieMaxX, a.x());
            const int n = qMax(1, int(std::ceil(QLineF(a, b).length() / 0.01)));
            for (int s = 0; s <= n; ++s)
                diePtsLocal.push_back(a + (b - a) * (double(s) / n));
        }
        dieMid = (dieMinX + dieMaxX) * 0.5;
        // Seat only on the forming zone (shoulders/V mouth), not the die body:
        // a long flange swinging past the die must not lift the bend off the V.
        double dieTop = -std::numeric_limits<double>::max();
        for (const QPointF &d : diePtsLocal)
            dieTop = qMax(dieTop, d.y());
        diePtsLocal.erase(std::remove_if(diePtsLocal.begin(), diePtsLocal.end(),
                                         [&](const QPointF &d) { return d.y() < dieTop - 0.3 || std::abs(d.x() - dieMid) > 0.5; }),
                          diePtsLocal.end());
        if (useCache) {
            m_cacheShoulder = diePtsLocal;
            m_cacheDieMid = dieMid;
            m_cacheShoulderValid = true;
        }
    }
    if (useCache)
        dieMid = m_cacheDieMid;
    const QVector<QPointF> &diePts = useCache ? m_cacheShoulder : diePtsLocal;
    const double none = -std::numeric_limits<double>::max();
    // Required lift against the left (side<0) / right (side>0) shoulder with
    // the part shifted by dx.
    auto sideLift = [&](double dx, int side) {
        double best = none;
        for (const QPointF &d : diePts) {
            if (side * (d.x() - dieMid) < 0)
                continue;
            const double px = d.x() - dx;
            if (px < minX || px > maxX)
                continue;
            const double y = partMinY(px);
            if (y < std::numeric_limits<double>::max())
                best = qMax(best, d.y() - y);
        }
        return best;
    };
    // The caller places the active bend line under the punch (shiftX).
    // No tilt/balancing: the formed bend is centred on its hinge line; a
    // shoulder gap comes from minor tooling-sketch asymmetry.
    const double dx = shiftX;
    m_lastShiftX = dx;
    const double liftL = sideLift(dx, -1), liftR = sideLift(dx, 1);
    const double lift = qMax(liftL, liftR);
    m_lastTilt = tiltDeg;
    m_lastTopAtZero = high[qBound(0, int((-dx - minX) / bin), bins - 1)];
    m_lastLowAtZero = low[qBound(0, int((-dx - minX) / bin), bins - 1)];
    // Physical contact: the sheet always rests on the die (it is what forms
    // the bend), so apply the full signed correction.
    // Always lower a floating part onto the die; only lift for shallow seating
    // error. A deep overlap is another panel colliding with the die (a real
    // pose collision) and must not raise the bend off the V.
    return lift > none / 2 ? lift : 0.0;
}

void LivePartMesh::captureTransitionStart()
{
    m_fromRotation = m_refRotation;
    m_fromOrigin = m_refOrigin;
    m_fromMirrored = m_refMirrored;
    m_transRotation = QQuaternion();
    m_transCenterFrom = m_transCenter = m_center;
    m_exitCenter = m_center;
    // Park in front of the tooling, clear by the part radius + 1 in.
    m_parkX = qMax(m_center.x(), float(m_transitionClearX)) + m_radius + 1.0f;
    m_transRadius = m_radius;
    m_transitionArmed = true;
}

static double smooth01(double x) { x = qBound(0.0, x, 1.0); return x * x * (3 - 2 * x); }

QString LivePartMesh::transitionDebug() const
{
    // Root panel origin/x-axis: end of exit vs start of entry (should match).
    const QVariantMap p0 = transitionAt(0);
    const QVector3D pos = p0.value(QStringLiteral("position")).value<QVector3D>();
    const QQuaternion r = p0.value(QStringLiteral("rotation")).value<QQuaternion>();
    const QVector3D exitDx(m_parkX - m_exitCenter.x(), 0, 0);
    const QVector3D oldO = m_fromOrigin + exitDx, newO = r.rotatedVector(m_refOrigin) + pos;
    const QVector3D oldX = m_fromRotation.rotatedVector(QVector3D(1, 0, 0));
    const QVector3D newX = (r * m_refRotation).rotatedVector(QVector3D(1, 0, 0));
    return QStringLiteral("ref=%1 mirroredFrom=%2 mirroredTo=%3 originGap=%4 axisDot=%5")
        .arg(m_refPanelId).arg(m_fromMirrored).arg(m_refMirrored)
        .arg((oldO - newO).length(), 0, 'f', 3).arg(QVector3D::dotProduct(oldX, newX), 0, 'f', 3);
}

QVariantMap LivePartMesh::exitAt(double t) const
{
    const float dx = (m_parkX - m_exitCenter.x()) * float(smooth01(t));
    return { { QStringLiteral("position"), QVariant::fromValue(QVector3D(dx, 0, 0)) },
             { QStringLiteral("rotation"), QVariant::fromValue(QQuaternion()) } };
}

void LivePartMesh::resolveTransition()
{
    if (!m_transitionArmed)
        return;
    m_transitionArmed = false;
    m_transRotation = (m_fromRotation * m_refRotation.inverted()).normalized();
    m_transCenter = m_center;
    m_transCenterFrom = m_transRotation.rotatedVector(m_center - m_refOrigin) + m_fromOrigin;
    m_transRadius = qMax(m_transRadius, m_radius);
}

QVariantMap LivePartMesh::transitionAt(double t) const
{
    // After exitAt(): new pose, starting parked with the old orientation;
    // reorient while parked (0..0.55), then slide in along -x (0.55..1).
    const double q = qBound(0.0, t, 1.0);
    const double turn = smooth01(q / 0.55), in = smooth01((q - 0.55) / 0.45);
    // Start exactly where exitAt(1) left the part: the mapped centre shifted
    // by the same exit offset (centres of old/new mesh differ in x).
    const QVector3D parkFrom = m_transCenterFrom + QVector3D(m_parkX - m_exitCenter.x(), 0, 0);
    QVector3D parkTo = m_transCenter;
    parkTo.setX(qMax(parkFrom.x(), m_parkX));
    QVector3D c;
    if (q < 0.55)
        c = parkFrom + (parkTo - parkFrom) * float(turn);
    else
        c = parkTo + (m_transCenter - parkTo) * float(in);
    const QQuaternion r = QQuaternion::slerp(m_transRotation, QQuaternion(), float(turn));
    return { { QStringLiteral("position"), QVariant::fromValue(c - r.rotatedVector(m_transCenter)) },
             { QStringLiteral("rotation"), QVariant::fromValue(r) } };
}

bool LivePartMesh::setPose(const QVariantMap &transforms, const QVariantMap &angles,
                           const QVariantMap &frame, double centerX, double centerR,
                           const QVariantMap &panelStates)
{
    if (m_panels.isEmpty())
        return false;
    QElapsedTimer timer;
    timer.start();
    const QVector3D origin = readVector(frame.value(QStringLiteral("origin")));
    const QVector3D h = readVector(frame.value(QStringLiteral("horizontal")));
    const QVector3D v = readVector(frame.value(QStringLiteral("vertical")));
    QVector3D a = readVector(frame.value(QStringLiteral("viewAxis")));
    if (h.lengthSquared() < 1e-12 || v.lengthSquared() < 1e-12 || a.lengthSquared() < 1e-12)
        return false;
    // Mirrored placements (2D section convention) would render a
    // chirally-flipped solid; keep the 3D display frame right-handed so the
    // part is the same physical solid in every bend.
    m_frameMirrored = QVector3D::dotProduct(QVector3D::crossProduct(h, v), a) < 0;
    if (m_frameMirrored)
        a = -a;
    const QVector3D shift(float(centerX), float(centerR), 0);
    auto toDisplay = [&](const QVector3D &world) {
        const QVector3D rel = world - origin;
        return shift + QVector3D(QVector3D::dotProduct(rel, h), QVector3D::dotProduct(rel, v),
                                 QVector3D::dotProduct(rel, a));
    };
    auto dirToDisplay = [&](const QVector3D &world) {
        return QVector3D(QVector3D::dotProduct(world, h), QVector3D::dotProduct(world, v),
                         QVector3D::dotProduct(world, a));
    };
    struct Matrix { double m[12]; bool ok = false; };
    // Each panel matrix is requested several times per pose (edges + panels):
    // unpack the QVariant list once per id.
    QHash<QString, Matrix> matrixCache;
    auto readMatrix = [&](const QString &id) {
        const auto cached = matrixCache.constFind(id);
        if (cached != matrixCache.constEnd())
            return cached.value();
        Matrix matrix;
        const QVariantList list = transforms.value(id).toMap().value(QStringLiteral("m")).toList();
        if (list.size() >= 12) {
            for (int i = 0; i < 12; ++i)
                matrix.m[i] = num(list[i]);
            matrix.ok = true;
        }
        matrixCache.insert(id, matrix);
        return matrix;
    };
    auto apply = [](const Matrix &m, const QVector3D &p) {
        return QVector3D(float(m.m[0] * p.x() + m.m[1] * p.y() + m.m[2] * p.z() + m.m[3]),
                         float(m.m[4] * p.x() + m.m[5] * p.y() + m.m[6] * p.z() + m.m[7]),
                         float(m.m[8] * p.x() + m.m[9] * p.y() + m.m[10] * p.z() + m.m[11]));
    };
    auto applyVector = [](const Matrix &m, const QVector3D &p) {
        return QVector3D(float(m.m[0] * p.x() + m.m[1] * p.y() + m.m[2] * p.z()),
                         float(m.m[4] * p.x() + m.m[5] * p.y() + m.m[6] * p.z()),
                         float(m.m[8] * p.x() + m.m[9] * p.y() + m.m[10] * p.z()));
    };

    // Unfold viewer palette: panels cycle a steel-blue palette, bend bands
    // are teal (bright for the active bend).
    static const QVector4D panelPalette[] = {
        // Mid-tone steel: light enough to read on the dark scene, dark enough
        // that lighting/edges keep holes, slots and flanges distinguishable.
        rgba(QColor(0x7d97a8)), rgba(QColor(0x6c889b)), rgba(QColor(0x8aa1b0)),
        rgba(QColor(0x7892a3)), rgba(QColor(0x648194)), rgba(QColor(0x839cab)),
        rgba(QColor(0x7390a1)) };
    const QVector4D bandColor = rgba(QColor(0x3f9488));
    const QVector4D activeBandColor = rgba(QColor(0x52d6b4));
    const QVector4D bandWallColor = rgba(QColor(0x3f9488).darker(130));

    // Band sampling: one segment per 10 degrees of fold, minimum two.
    struct BandPlan { const Edge *edge; Matrix parent; double theta; int samples; };
    QVector<BandPlan> bands;
    int vertexCount = 0;
    for (const Panel &panel : m_panels)
        vertexCount += panel.vertices.size();
    for (const Edge &edge : m_edges) {
        const double angle = num(angles.value(edge.childId));
        // Unformed (future) bends still show their flat-pattern bend zone,
        // as in the unfold viewer, so upcoming operations stay visible.
        const bool flat = std::abs(angle) < 1e-6;
        if (flat ? edge.developed <= 1e-9 : edge.radius + edge.k * edge.thickness <= 1e-9)
            continue;
        const Matrix parent = readMatrix(edge.parentId);
        if (!parent.ok)
            continue;
        const int samples = flat ? 1 : qMax(2, int(std::ceil(std::abs(angle) / (10.0 * 3.14159265358979323846 / 180.0))));
        bands.push_back({ &edge, parent, angle, samples });
        vertexCount += samples * 24; // two surfaces + two end walls, 6 vertices per quad
    }

    Writer w { &m_buffer };
    w.reserve(vertexCount);
    for (int panelIndex = 0; panelIndex < m_panels.size(); ++panelIndex) {
        const Panel &panel = m_panels[panelIndex];
        const Matrix matrix = readMatrix(panel.id);
        if (!matrix.ok)
            continue;
        const QVector4D face = panelPalette[panelIndex % 7];
        const QVector4D wall = face * 0.78f + QVector4D(0, 0, 0, 0.22f);
        // The flat panels meet at the hinge centreline; the radius band owns
        // the neutral strip [-L/2, +L/2] around it. Trim each panel's hinge
        // side back to the strip edge (as unfold does) so flanges do not
        // overlap the band and cross each other at the bend.
        struct Trim { QVector3D start, transverse, axis; float half, span, sign; };
        QVector<Trim> trims;
        for (const Edge &edge : m_edges) {
            const bool asChild = edge.childId == panel.id;
            if (!asChild && edge.parentId != panel.id)
                continue;
            const double angle = num(angles.value(edge.childId));
            if (std::abs(angle) < 1e-6 && edge.developed <= 1e-9)
                continue;
            const double half = edge.neutralLength(angle) / 2;
            if (half <= 1e-9)
                continue;
            const QVector3D axis = (edge.end - edge.start).normalized() * float(edge.side);
            trims.push_back({ edge.start, QVector3D(-axis.y(), axis.x(), 0), axis, float(half),
                              QVector3D::dotProduct(edge.end - edge.start, axis),
                              asChild ? 1.0f : -1.0f });
        }
        for (const LocalVertex &vertex : panel.vertices) {
            QVector3D local = vertex.p;
            for (const Trim &trim : trims) {
                const QVector3D d = local - trim.start;
                const float a = QVector3D::dotProduct(d, trim.axis);
                if (a < qMin(0.0f, trim.span) - 1e-4f || a > qMax(0.0f, trim.span) + 1e-4f)
                    continue;
                const float s = QVector3D::dotProduct(d, trim.transverse) * trim.sign;
                if (s > -1e-4f && s < trim.half)
                    local += trim.transverse * (trim.sign * (trim.half - s));
            }
            const QVector3D p = toDisplay(apply(matrix, local));
            const QVector3D n = dirToDisplay(applyVector(matrix, vertex.n));
            w.put(p, n, vertex.face == 2 ? wall : face);
        }
    }
    m_bendAnchors.clear();
    for (const Edge &edge : m_edges) {
        const Matrix parent = readMatrix(edge.parentId);
        if (!parent.ok)
            continue;
        const QVector3D mid = toDisplay(apply(parent, (edge.start + edge.end) * 0.5f));
        const QVector3D s = toDisplay(apply(parent, edge.start));
        const QVector3D e = toDisplay(apply(parent, edge.end));
        // Real curve centre: neutral-surface midpoint of the band at the
        // current angle (same geometry as the drawn band). The flat hinge
        // midpoint sits at the band's start, not at its apex.
        QVector3D curve = mid;
        double bandTop = -std::numeric_limits<double>::max();
        {
            const QVector3D axis = (edge.end - edge.start).normalized() * float(edge.side);
            const QVector3D transverse(-axis.y(), axis.x(), 0);
            const double theta = num(angles.value(edge.childId)) * edge.side;
            const double neutralLength = std::abs(theta) > 1e-6 ? edge.neutralLength(theta) : 0.0;
            if (neutralLength > 1e-9) {
                const double neutralZ = theta > 0 ? -edge.k * edge.thickness : -(1 - edge.k) * edge.thickness;
                const double half = theta * 0.5, arc = neutralLength * 0.5;
                const double b = arc * sinc(half);
                const double n = neutralZ + arc * cosc(half);
                const QVector3D local = (edge.start + edge.end) * 0.5f
                    - transverse * float(neutralLength / 2) + transverse * float(b)
                    + QVector3D(0, 0, float(n));
                curve = toDisplay(apply(parent, local));
                // Band faces (z=0 and z=-t) at the apex: punch contacts the higher one.
                for (const double zFlat : { 0.0, -edge.thickness }) {
                    const double fb = b - (zFlat - neutralZ) * std::sin(half);
                    const double fn = neutralZ + arc * cosc(half) + (zFlat - neutralZ) * std::cos(half);
                    const QVector3D face = toDisplay(apply(parent, (edge.start + edge.end) * 0.5f
                        - transverse * float(neutralLength / 2) + transverse * float(fb)
                        + QVector3D(0, 0, float(fn))));
                    bandTop = qMax(bandTop, double(face.y()));
                }
            }
        }
        if (bandTop == -std::numeric_limits<double>::max()) {
            for (const double zFlat : { 0.0, -edge.thickness })
                bandTop = qMax(bandTop, double(toDisplay(apply(parent,
                    (edge.start + edge.end) * 0.5f + QVector3D(0, 0, float(zFlat)))).y()));
        }
        m_bendAnchors.push_back(QVariantMap {
            { QStringLiteral("cx"), curve.x() }, { QStringLiteral("cy"), curve.y() },
            { QStringLiteral("bandTop"), bandTop },
            { QStringLiteral("label"), edge.label },
            { QStringLiteral("childId"), edge.childId },
            { QStringLiteral("sequence"), edge.sequence },
            { QStringLiteral("direction"), edge.direction },
            { QStringLiteral("sx"), s.x() }, { QStringLiteral("sy"), s.y() }, { QStringLiteral("sz"), s.z() },
            { QStringLiteral("ex"), e.x() }, { QStringLiteral("ey"), e.y() }, { QStringLiteral("ez"), e.z() },
            { QStringLiteral("x"), mid.x() }, { QStringLiteral("y"), mid.y() },
            { QStringLiteral("z"), mid.z() },
            { QStringLiteral("active"),
              panelStates.value(edge.childId).toString() == QLatin1String("current") } });
    }
    for (const BandPlan &band : bands) {
        const Edge &e = *band.edge;
        const QVector3D directed = (e.end - e.start).normalized();
        const QVector3D axis = directed * float(e.side);
        const QVector3D transverse(-axis.y(), axis.x(), 0);
        const QVector3D normal(0, 0, 1);
        const double theta = band.theta * e.side;
        const double neutralLength = e.neutralLength(theta);
        const double neutralZ = theta > 0 ? -e.k * e.thickness : -(1 - e.k) * e.thickness;
        const QVector3D bendOrigin = e.start - transverse * float(neutralLength / 2);
        const double span = QVector3D::dotProduct(e.end - e.start, axis);
        auto bandPoint = [&](double axial, double fraction, double zFlat) {
            const double angle = theta * fraction;
            const double arc = neutralLength * fraction;
            const double b = arc * sinc(angle) - (zFlat - neutralZ) * std::sin(angle);
            const double n = neutralZ + arc * cosc(angle) + (zFlat - neutralZ) * std::cos(angle);
            return bendOrigin + axis * float(axial) + transverse * float(b) + normal * float(n);
        };
        auto world = [&](const QVector3D &local) { return toDisplay(apply(band.parent, local)); };
        auto tri = [&](const QVector3D &p0, const QVector3D &p1, const QVector3D &p2, const QVector4D &color) {
            const QVector3D n = QVector3D::crossProduct(p1 - p0, p2 - p0).normalized();
            w.put(p0, n, color); w.put(p1, n, color); w.put(p2, n, color);
        };
        const double t = e.thickness;
        const QVector4D surfaceColor =
            panelStates.value(e.childId).toString() == QLatin1String("current")
            ? activeBandColor : bandColor;
        for (int i = 0; i < band.samples; ++i) {
            const double f0 = double(i) / band.samples, f1 = double(i + 1) / band.samples;
            for (int surface = 0; surface < 2; ++surface) {
                const double z = surface == 0 ? 0.0 : -t;
                const QVector4D &color = surfaceColor;
                const QVector3D p00 = world(bandPoint(0, f0, z)), p01 = world(bandPoint(span, f0, z));
                const QVector3D p10 = world(bandPoint(0, f1, z)), p11 = world(bandPoint(span, f1, z));
                tri(p00, p10, p11, color);
                tri(p00, p11, p01, color);
            }
        }
        // End caps (radius-zone side walls) at both hinge ends, as fans.
        for (int end = 0; end < 2; ++end) {
            const double axial = end == 0 ? 0.0 : span;
            for (int i = 0; i < band.samples; ++i) {
                const double f0 = double(i) / band.samples, f1 = double(i + 1) / band.samples;
                const QVector3D a0 = world(bandPoint(axial, f0, 0)), a1 = world(bandPoint(axial, f1, 0));
                const QVector3D b0 = world(bandPoint(axial, f0, -t)), b1 = world(bandPoint(axial, f1, -t));
                tri(a0, a1, b1, bandWallColor);
                tri(a0, b1, b0, bandWallColor);
            }
        }
    }
    w.finish();
    configure(this, m_buffer, w.vertices, w.minimum, w.maximum);
    m_center = (w.minimum + w.maximum) * 0.5f;
    // Reference (root) panel display frame for sequence transitions.
    // Keep the same physical panel while a transition is armed: panel order
    // can change when the next bend's topology is loaded.
    if (!m_panels.isEmpty()) {
        Matrix ref = readMatrix(m_refPanelId);
        if (!m_transitionArmed || !ref.ok) {
            m_refPanelId = m_panels.first().id;
            ref = readMatrix(m_refPanelId);
        }
        if (ref.ok) {
            m_refOrigin = toDisplay(apply(ref, QVector3D()));
            const QVector3D ax = dirToDisplay(applyVector(ref, QVector3D(1, 0, 0))).normalized();
            const QVector3D ay = dirToDisplay(applyVector(ref, QVector3D(0, 1, 0))).normalized();
            const QVector3D az = dirToDisplay(applyVector(ref, QVector3D(0, 0, 1))).normalized();
            m_refMirrored = QVector3D::dotProduct(QVector3D::crossProduct(ax, ay), az) < 0;
            // Proper rotation even if the display frame is mirrored.
            m_refRotation = QQuaternion::fromAxes(ax, ay, QVector3D::crossProduct(ax, ay)).normalized();
        }
    }
    m_radius = (w.maximum - w.minimum).length() * 0.5f;
    m_triangleCount = w.vertices / 3;
    m_updateMs = timer.nsecsElapsed() / 1.0e6;
    emit posed();
    return true;
}
