#pragma once

#include <QObject>
#include <QTimer>

class QEvent;

class DisplaySleepController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int timeoutMinutes READ timeoutMinutes WRITE setTimeoutMinutes NOTIFY timeoutMinutesChanged)
    Q_PROPERTY(bool sleeping READ sleeping NOTIFY sleepingChanged)
    Q_PROPERTY(bool supported READ supported CONSTANT)

public:
    explicit DisplaySleepController(QObject *parent = nullptr);

    int timeoutMinutes() const { return m_timeoutMinutes; }
    bool sleeping() const { return m_sleeping; }
    bool supported() const;

    Q_INVOKABLE void setTimeoutMinutes(int minutes);
    Q_INVOKABLE void resetIdleTimer();
    Q_INVOKABLE void wake();
    Q_INVOKABLE void sleepNow();

signals:
    void timeoutMinutesChanged();
    void sleepingChanged();
    void displayPowerError(const QString &message);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    static int normalizedTimeout(int minutes);
    bool setDisplayPower(bool on);
    bool isUserInputEvent(const QEvent *event) const;

    QTimer m_idleTimer;
    int m_timeoutMinutes = 0;
    bool m_sleeping = false;
    bool m_suppressPointerSequence = false;
};
