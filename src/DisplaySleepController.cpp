#include "DisplaySleepController.h"

#include <QCoreApplication>
#include <QEvent>
#include <QGuiApplication>
#include <QLoggingCategory>
#include <QScreen>

#include <qpa/qplatformscreen.h>

namespace {

bool isPointerPress(QEvent::Type type)
{
    return type == QEvent::MouseButtonPress
        || type == QEvent::TouchBegin
        || type == QEvent::TabletPress;
}

bool isPointerSequenceEvent(QEvent::Type type)
{
    return type == QEvent::MouseButtonPress
        || type == QEvent::MouseButtonRelease
        || type == QEvent::MouseButtonDblClick
        || type == QEvent::MouseMove
        || type == QEvent::TouchBegin
        || type == QEvent::TouchUpdate
        || type == QEvent::TouchEnd
        || type == QEvent::TouchCancel
        || type == QEvent::TabletPress
        || type == QEvent::TabletMove
        || type == QEvent::TabletRelease;
}

bool endsPointerSequence(QEvent::Type type)
{
    return type == QEvent::MouseButtonRelease
        || type == QEvent::TouchEnd
        || type == QEvent::TouchCancel
        || type == QEvent::TabletRelease;
}

} // namespace

DisplaySleepController::DisplaySleepController(QObject *parent)
    : QObject(parent)
{
    m_idleTimer.setSingleShot(true);
    connect(&m_idleTimer, &QTimer::timeout,
            this, &DisplaySleepController::sleepNow);
    qApp->installEventFilter(this);
}

bool DisplaySleepController::supported() const
{
#ifdef Q_OS_LINUX
    return QGuiApplication::platformName().startsWith(QStringLiteral("eglfs"));
#else
    return false;
#endif
}

int DisplaySleepController::normalizedTimeout(int minutes)
{
    switch (minutes) {
    case 5:
    case 10:
    case 30:
        return minutes;
    default:
        return 0;
    }
}

void DisplaySleepController::setTimeoutMinutes(int minutes)
{
    const int normalized = normalizedTimeout(minutes);
    if (m_timeoutMinutes == normalized)
        return;
    m_timeoutMinutes = normalized;
    emit timeoutMinutesChanged();
    if (m_timeoutMinutes == 0) {
        m_idleTimer.stop();
        wake();
    } else {
        resetIdleTimer();
    }
}

void DisplaySleepController::resetIdleTimer()
{
    if (m_timeoutMinutes <= 0 || m_sleeping)
        return;
    m_idleTimer.start(m_timeoutMinutes * 60 * 1000);
}

void DisplaySleepController::sleepNow()
{
    if (m_timeoutMinutes <= 0 || m_sleeping)
        return;
    if (!setDisplayPower(false))
        return;
    m_sleeping = true;
    emit sleepingChanged();
    qInfo().noquote() << "DISPLAY-SLEEP state=OFF timeoutMinutes="
                      << m_timeoutMinutes;
}

void DisplaySleepController::wake()
{
    if (!m_sleeping) {
        resetIdleTimer();
        return;
    }
    if (!setDisplayPower(true))
        return;
    m_sleeping = false;
    emit sleepingChanged();
    resetIdleTimer();
    qInfo().noquote() << "DISPLAY-SLEEP state=ON";
}

bool DisplaySleepController::setDisplayPower(bool on)
{
    if (!supported())
        return true;
    QScreen *screen = QGuiApplication::primaryScreen();
    QPlatformScreen *platformScreen = screen ? screen->handle() : nullptr;
    if (!platformScreen) {
        const QString message = QStringLiteral("No platform screen is available for HDMI power control.");
        qWarning().noquote() << "DISPLAY-SLEEP error=" + message;
        emit displayPowerError(message);
        return false;
    }
    platformScreen->setPowerState(on ? QPlatformScreen::PowerStateOn
                                     : QPlatformScreen::PowerStateOff);
    return true;
}

bool DisplaySleepController::isUserInputEvent(const QEvent *event) const
{
    switch (event->type()) {
    case QEvent::KeyPress:
    case QEvent::MouseButtonPress:
    case QEvent::Wheel:
    case QEvent::TouchBegin:
    case QEvent::TabletPress:
        return true;
    default:
        return false;
    }
}

bool DisplaySleepController::eventFilter(QObject *watched, QEvent *event)
{
    Q_UNUSED(watched)
    const QEvent::Type type = event->type();
    if (m_suppressPointerSequence && isPointerSequenceEvent(type)) {
        if (endsPointerSequence(type))
            m_suppressPointerSequence = false;
        return true;
    }
    if (!isUserInputEvent(event))
        return false;
    if (m_sleeping) {
        if (isPointerPress(type))
            m_suppressPointerSequence = true;
        wake();
        return true;
    }
    resetIdleTimer();
    return false;
}
