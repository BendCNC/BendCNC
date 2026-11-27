#include "DisplaySleepController.h"

#include <QCoreApplication>
#include <QEvent>
#include <QtTest>

class InputReceiver final : public QObject
{
public:
    int received = 0;

protected:
    bool event(QEvent *event) override
    {
        if (event->type() == QEvent::MouseButtonPress
                || event->type() == QEvent::MouseButtonRelease)
            ++received;
        return QObject::event(event);
    }
};

class DisplaySleepControllerTest final : public QObject
{
    Q_OBJECT

private slots:
    void acceptsOnlySupportedTimeouts()
    {
        DisplaySleepController controller;
        controller.setTimeoutMinutes(5);
        QCOMPARE(controller.timeoutMinutes(), 5);
        controller.setTimeoutMinutes(10);
        QCOMPARE(controller.timeoutMinutes(), 10);
        controller.setTimeoutMinutes(30);
        QCOMPARE(controller.timeoutMinutes(), 30);
        controller.setTimeoutMinutes(7);
        QCOMPARE(controller.timeoutMinutes(), 0);
    }

    void firstPointerSequenceOnlyWakesDisplay()
    {
        DisplaySleepController controller;
        InputReceiver receiver;
        controller.setTimeoutMinutes(5);
        controller.sleepNow();
        QVERIFY(controller.sleeping());

        QEvent firstPress(QEvent::MouseButtonPress);
        QCoreApplication::sendEvent(&receiver, &firstPress);
        QVERIFY(!controller.sleeping());
        QCOMPARE(receiver.received, 0);

        QEvent firstRelease(QEvent::MouseButtonRelease);
        QCoreApplication::sendEvent(&receiver, &firstRelease);
        QCOMPARE(receiver.received, 0);

        QEvent secondPress(QEvent::MouseButtonPress);
        QCoreApplication::sendEvent(&receiver, &secondPress);
        QCOMPARE(receiver.received, 1);
    }

    void disablingTimeoutWakesDisplay()
    {
        DisplaySleepController controller;
        controller.setTimeoutMinutes(5);
        controller.sleepNow();
        QVERIFY(controller.sleeping());
        controller.setTimeoutMinutes(0);
        QVERIFY(!controller.sleeping());
    }
};

QTEST_MAIN(DisplaySleepControllerTest)
#include "tst_DisplaySleepController.moc"
