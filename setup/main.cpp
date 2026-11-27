#include "SetupBackend.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName(QStringLiteral("BendCNC"));
    SetupBackend backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("setup"), &backend);
    engine.load(QUrl(QStringLiteral("qrc:/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return 1;

    // BENDCNC_SETUP_SHOTS=<dir>: render every step to PNG and exit (UI review).
    const QString shots = qEnvironmentVariable("BENDCNC_SETUP_SHOTS");
    if (!shots.isEmpty()) {
        auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        for (int s = 0; s <= 6; ++s) {
            QTimer::singleShot(400 + s * 400, win, [win, s, shots] {
                win->setProperty("step", s);
                QMetaObject::invokeMethod(win, "shotFocus");
                QTimer::singleShot(250, win, [win, s, shots] {
                    win->grabWindow().save(QStringLiteral("%1/step%2.png").arg(shots).arg(s));
                    if (s == 6)
                        QCoreApplication::quit();
                });
            });
        }
    }
    return app.exec();
}
