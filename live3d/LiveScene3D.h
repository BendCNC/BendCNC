#pragma once

#include <QByteArray>
#include <QHash>
#include <QPointF>
#include <QQuaternion>
#include <QString>
#include <QVariant>
#include <QVector>
#include <QVector3D>
#include <QVector4D>
#include <QtQml/qqmlregistration.h>
#include <QtQuick3D/QQuick3DGeometry>

// LIVE 3D (Qt Quick 3D) geometry for the RUN view. All heavy work happens in
// C++: panel/tool profiles are triangulated once, and every animation frame
// only re-transforms the cached local vertices (part) or moves a Node (tools).
// Coordinates are the LIVE machine section frame in inches:
//   x = section horizontal (die centre at 0, backgauge on negative x)
//   y = section vertical (die seat at 0, punch above)
//   z = station depth along the bend line.
// Vertex layout: position(3f) normal(3f) color(4f), 40 bytes.

// Static extruded 2D profile: outer loop (+ holes) in (x, r) extruded over
// one or more depth runs. Used for table, holder, die, punch and finger.
class LiveProfileSolid : public QQuick3DGeometry
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int triangleCount READ triangleCount NOTIFY rebuilt)
public:
    explicit LiveProfileSolid(QQuick3DObject *parent = nullptr);

    // outer: [{x, r}] ; holes: [[{x, r}]] ; runs: [{z0, z1}] ; color: "#rrggbb"
    Q_INVOKABLE bool setProfile(const QVariantList &outer, const QVariantList &holes,
                                const QVariantList &runs, const QString &color);
    Q_INVOKABLE void clear();
    int triangleCount() const { return m_triangles; }

signals:
    void rebuilt();

private:
    int m_triangles = 0;
};

// Static indexed triangle mesh (e.g. exact STEP finger tessellation).
// points: [{x, r, z}] ; triangles: flat vertex indices. mirrorZ flips the
// width axis (right-hand finger). Winding is fixed outward automatically.
class LiveTriangleMesh : public QQuick3DGeometry
{
    Q_OBJECT
    QML_ELEMENT
public:
    explicit LiveTriangleMesh(QQuick3DObject *parent = nullptr) : QQuick3DGeometry(parent) {}
    Q_INVOKABLE bool setMesh(const QVariantList &points, const QVariantList &triangles,
                             bool mirrorZ, const QString &color);
};

// Sheet part: flat-pattern panels (local z in [-t, 0]) posed by the V5
// compiled transforms, plus finite-radius bend bands generated from the
// current joint angle (SheetMetalFoldSolver port).
class LivePartMesh : public QQuick3DGeometry
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int triangleCount READ triangleCount NOTIFY posed)
    Q_PROPERTY(double updateMs READ updateMs NOTIFY posed)
    Q_PROPERTY(bool hasTopology READ hasTopology NOTIFY topologyChanged)
    Q_PROPERTY(QString topologyKey READ topologyKey NOTIFY topologyChanged)
    // [{label, x, y, z, active}] hinge midpoints in display inches (Unfold badges).
    Q_PROPERTY(QVariantList bendAnchors READ bendAnchors NOTIFY posed)
public:
    explicit LivePartMesh(QQuick3DObject *parent = nullptr);

    // panels: [{id, outerLoop:[{x_in,y_in}], holeLoops:[[...]], thickness}]
    // edges:  [{parentPanelId, childPanelId, hingeStart, hingeEnd,
    //           childSideSign, insideRadius_in, thickness_in, kFactor}]
    Q_INVOKABLE bool setTopology(const QString &key, const QVariantList &panels,
                                 const QVariantList &edges);
    // transforms: {panelId: {m:[16]}} ; angles: {childPanelId: radians}
    // frame: {origin, horizontal, vertical, viewAxis} ; panelStates:
    // {panelId: "completed"|"current"|"future"} (optional)
    Q_INVOKABLE bool setPose(const QVariantMap &transforms, const QVariantMap &angles,
                             const QVariantMap &frame, double centerX, double centerR,
                             const QVariantMap &panelStates);
    Q_INVOKABLE void clear();
    // Sequence change animation (Unfold-like): capture the last pose of the
    // finished bend; the next setPose computes the rigid delta to the new
    // bend's display frame. transitionAt(t in [0,1]) returns {position,
    // rotation} for the part node that morphs old placement -> new.
    Q_PROPERTY(double transitionClearX MEMBER m_transitionClearX)
    Q_INVOKABLE void captureTransitionStart();
    // Pure +x slide of the finished pose to the park point (t 0..1).
    Q_INVOKABLE QVariantMap exitAt(double t) const;
    // Call after the first setPose of the next bend.
    Q_INVOKABLE void resolveTransition();
    Q_INVOKABLE QVariantMap transitionAt(double t) const;
    // Station (z) extent of the posed part edge facing the backgauge:
    // vertices within `tolerance` of the part's minimum x. {found, z0, z1}
    // With gaugeX (part-local x of the finger face) the span is the widest z
    // run of material at that x that no other material crosses beyond it
    // (a longer flange protruding past the gauge would bury the finger).
    Q_INVOKABLE QVariantMap gaugeContactSpan(double tolerance) const;
    Q_INVOKABLE QVariantMap gaugeContactSpanAt(double tolerance, double gaugeX) const;
    // Upward lift (inches) so the posed part rests on, not inside, the die
    // section profile (die treated as a height field from below).
    Q_INVOKABLE QVariantMap lastContactDebug() const { return { { QStringLiteral("top0"), m_lastTopAtZero }, { QStringLiteral("low0"), m_lastLowAtZero }, { QStringLiteral("dx"), m_lastShiftX }, { QStringLiteral("tilt"), m_lastTilt }, { QStringLiteral("anchorGap"), m_lastAnchorGap } }; }
    mutable double m_lastTopAtZero = 0, m_lastLowAtZero = 0, m_lastShiftX = 0, m_lastTilt = 0, m_lastAnchorGap = 0;
    Q_INVOKABLE double dieClearanceLift(const QVariantList &dieOuter, const QVariantList &dieRuns, double shiftX = 0, double tiltDeg = 0, bool useCache = false) const;
    // Convert the die profile once per tooling change; seatLift() then avoids
    // re-marshalling the JS arrays on every animation frame.
    Q_INVOKABLE void setDieProfile(const QVariantList &dieOuter, const QVariantList &dieRuns)
    {
        m_dieOuter = dieOuter;
        m_dieRuns = dieRuns;
        m_dieCacheValid = false;
        m_cacheShoulderValid = false;
        m_seatLiftCache.clear();
    }
    // Exact memo: the lift depends only on the posed mesh bytes, the die and
    // shiftX, so repeated poses (SIM loops, holds, replays) skip the scan.
    Q_INVOKABLE double seatLift(double shiftX) const
    {
        const size_t key = qHash(m_buffer) ^ (qHash(shiftX) * size_t(0x9e3779b97f4a7c15ULL));
        const auto it = m_seatLiftCache.constFind(key);
        if (it != m_seatLiftCache.constEnd())
            return it.value();
        const double lift = dieClearanceLift(m_dieOuter, m_dieRuns, shiftX, 0, true);
        if (m_seatLiftCache.size() >= 2048)
            m_seatLiftCache.clear();
        m_seatLiftCache.insert(key, lift);
        return lift;
    }

    int triangleCount() const { return m_triangleCount; }
    double updateMs() const { return m_updateMs; }
    bool hasTopology() const { return !m_panels.isEmpty(); }
    QString topologyKey() const { return m_topologyKey; }
    QVariantList bendAnchors() const { return m_bendAnchors; }

signals:
    void posed();
    void topologyChanged();

private:
    struct LocalVertex { QVector3D p; QVector3D n; quint8 face; }; // 0 top, 1 bottom, 2 wall
    struct Panel { QString id; double thickness = 0; QVector<LocalVertex> vertices; };
    struct Edge {
        QString parentId, childId, label, direction;
        int sequence = 0;
        QVector3D start, end;
        double side = 1, radius = 0, thickness = 0, k = 0.44;
        // Developed (neutral) strip length at the full fold: constant while
        // forming; only the curvature changes with the instantaneous angle.
        double developed = 0;
        double neutralLength(double angle) const
        {
            return developed > 1e-9 ? developed : std::abs(angle) * (radius + k * thickness);
        }
    };

    QString m_topologyKey;
    QVector<Panel> m_panels;
    QVector<Edge> m_edges;
    QByteArray m_buffer;
    QVariantList m_bendAnchors;
    QVariantList m_dieOuter;
    QVariantList m_dieRuns;
    mutable bool m_dieCacheValid = false;
    mutable QHash<size_t, double> m_seatLiftCache;
    mutable bool m_cacheShoulderValid = false;
    mutable QVector<QPair<double, double>> m_cacheRuns;
    mutable QVector<QPointF> m_cacheDie;
    mutable QVector<QPointF> m_cacheShoulder;
    mutable double m_cacheDieMid = 0;
    QQuaternion m_refRotation;
    QVector3D m_refOrigin, m_center;
    QQuaternion m_fromRotation, m_transRotation;
    QVector3D m_fromOrigin, m_transCenterFrom, m_transCenter;
    float m_transRadius = 0, m_radius = 0;
    double m_transitionClearX = 0;
    QVector3D m_exitCenter;
    float m_parkX = 0;
    QString m_refPanelId;
    bool m_refMirrored = false, m_fromMirrored = false, m_frameMirrored = false;
public:
    Q_INVOKABLE QString transitionDebug() const;
private:
    bool m_transitionArmed = false;
    int m_triangleCount = 0;
    double m_updateMs = 0;
};
