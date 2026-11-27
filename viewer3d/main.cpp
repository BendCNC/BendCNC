// unfold3d_viewer: Qt Quick 3D playback of an unfold plan, for comparison with
// the 2D RunExecutionCanvas. Options:
//   --plan=<file.plan.json>   (default: newest plan in the unfold-plans cache)
//   --capture=<png> [--capture-time=<s>]   render one frame and exit
//   --bench=<s>               play at 1x for <s> seconds, print FPS and exit
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QtQuick3D/qquick3d.h>

int main(int argc, char *argv[])
{
    QSurfaceFormat::setDefaultFormat(QQuick3D::idealSurfaceFormat());
    QGuiApplication app(argc, argv);
    QVariantMap props{{QStringLiteral("planPath"), QString()}, {QStringLiteral("capturePath"), QString()},
                      {QStringLiteral("captureTime"), 0.0}, {QStringLiteral("benchSeconds"), 0.0}};
    for (const QString &arg : app.arguments()) {
        const auto value = [&](const char *key) { return arg.mid(int(qstrlen(key))); };
        if (arg.startsWith(QLatin1String("--plan=")))
            props[QStringLiteral("planPath")] = value("--plan=");
        else if (arg.startsWith(QLatin1String("--capture=")))
            props[QStringLiteral("capturePath")] = value("--capture=");
        else if (arg.startsWith(QLatin1String("--capture-time=")))
            props[QStringLiteral("captureTime")] = value("--capture-time=").toDouble();
        else if (arg.startsWith(QLatin1String("--bench=")))
            props[QStringLiteral("benchSeconds")] = value("--bench=").toDouble();
    }
    QQmlApplicationEngine engine;
    engine.setInitialProperties(props);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Unfold3DViewer", "Main");
    return app.exec();
}
