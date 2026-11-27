#pragma once

#include <QFile>
#include <QObject>
#include <QVector>
#include <QVector3D>
#include <QtQml/qqmlregistration.h>
#include <QtQuick3D/QQuick3DGeometry>

// Flat-shaded triangle soup (position + normal), rebuilt for every frame.
class MeshGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit MeshGeometry(QQuick3DObject *parent = nullptr);
    void setMesh(const float *positions, quint32 vertexCount, const quint32 *indices, quint32 indexCount,
                 const float *nextPositions, float t);
private:
    QByteArray m_buffer;
};

// Loads frames exported by tools/export_unfold_scene.mjs and exposes one
// geometry per body group (part, punch, die, riser, table, finger).
class SceneFrames : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString planPath READ planPath WRITE setPlanPath NOTIFY loaded)
    Q_PROPERTY(QString status READ status NOTIFY loaded)
    Q_PROPERTY(double durationSeconds READ durationSeconds NOTIFY loaded)
    Q_PROPERTY(int stageCount READ stageCount NOTIFY loaded)
    Q_PROPERTY(double time READ time WRITE setTime NOTIFY timeChanged)
    Q_PROPERTY(QString stageText READ stageText NOTIFY timeChanged)
    Q_PROPERTY(QString phaseText READ phaseText NOTIFY timeChanged)
    Q_PROPERTY(double updateMs READ updateMs NOTIFY timeChanged)
    Q_PROPERTY(int triangleCount READ triangleCount NOTIFY timeChanged)
    Q_PROPERTY(QList<QObject *> geometries READ geometries CONSTANT)
public:
    explicit SceneFrames(QObject *parent = nullptr);

    QString planPath() const { return m_planPath; }
    void setPlanPath(const QString &path);
    QString status() const { return m_status; }
    double durationSeconds() const { return m_duration; }
    int stageCount() const { return m_stageCount; }
    double time() const { return m_time; }
    void setTime(double seconds);
    QString stageText() const { return m_stageText; }
    QString phaseText() const { return m_phaseText; }
    double updateMs() const { return m_updateMs; }
    int triangleCount() const { return m_triangles; }
    QList<QObject *> geometries() const;

    Q_INVOKABLE double stageStartTime(int stage) const;
    static QString defaultPlanPath();

signals:
    void loaded();
    void timeChanged();

private:
    // segment: timeline segment (stage + phase); topology: per-group signature.
    // Frames are interpolated only inside one segment with equal topology.
    struct Frame { qint64 offset; double time; int stage; QString bend; bool partial; QString phase;
                   int segment; QStringList topology; };
    bool ensureExport(const QString &dir);
    void applyFrame();

    QString m_planPath;
    QString m_status = QStringLiteral("Sin plan");
    QFile m_bin;
    const uchar *m_data = nullptr;
    QVector<Frame> m_frames;
    QVector<MeshGeometry *> m_geometries;
    double m_duration = 0;
    int m_stageCount = 0;
    double m_time = 0;
    QString m_stageText;
    QString m_phaseText;
    double m_updateMs = 0;
    int m_triangles = 0;
};
