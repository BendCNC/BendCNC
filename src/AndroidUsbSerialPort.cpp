#include "AndroidUsbSerialPort.h"

#include <QCoreApplication>
#include <QHash>
#include <QJniEnvironment>
#include <QJniObject>
#include <QMetaObject>
#include <QMutex>
#include <QPointer>

namespace {

constexpr const char *JavaClass = "com/bendcnc/UsbSerial";

QMutex registryMutex;
QHash<int, QPointer<AndroidUsbSerialPort>> &registry()
{
    static QHash<int, QPointer<AndroidUsbSerialPort>> ports;
    return ports;
}

void JNICALL nativeData(JNIEnv *env, jclass, jint handle, jbyteArray array)
{
    const jsize size = env->GetArrayLength(array);
    QByteArray data(size, Qt::Uninitialized);
    env->GetByteArrayRegion(array, 0, size, reinterpret_cast<jbyte *>(data.data()));
    AndroidUsbSerialPort::deliverData(handle, data);
}

void JNICALL nativeError(JNIEnv *env, jclass, jint handle, jstring message)
{
    const char *chars = env->GetStringUTFChars(message, nullptr);
    const QString text = QString::fromUtf8(chars);
    env->ReleaseStringUTFChars(message, chars);
    AndroidUsbSerialPort::deliverError(handle, text);
}

void ensureNativesRegistered()
{
    static bool registered = false;
    if (registered)
        return;
    QJniEnvironment env;
    const JNINativeMethod methods[] = {
        {"nativeData", "(I[B)V", reinterpret_cast<void *>(nativeData)},
        {"nativeError", "(ILjava/lang/String;)V", reinterpret_cast<void *>(nativeError)},
    };
    registered = env.registerNativeMethods(JavaClass, methods, 2);
}

QJniObject context()
{
    return QJniObject(QNativeInterface::QAndroidApplication::context());
}

}

AndroidUsbSerialPort::AndroidUsbSerialPort(QObject *parent)
    : QObject(parent)
{
}

AndroidUsbSerialPort::~AndroidUsbSerialPort()
{
    close();
}

QList<AndroidUsbSerialPort::DeviceInfo> AndroidUsbSerialPort::devices()
{
    QList<DeviceInfo> result;
    const QJniObject array = QJniObject::callStaticObjectMethod(
        JavaClass, "list", "(Landroid/content/Context;)[Ljava/lang/String;",
        context().object());
    if (!array.isValid())
        return result;
    QJniEnvironment env;
    const auto jarray = static_cast<jobjectArray>(array.object());
    const jsize count = env->GetArrayLength(jarray);
    for (jsize i = 0; i < count; ++i) {
        const QJniObject item(env->GetObjectArrayElement(jarray, i));
        const QStringList fields = item.toString().split(QLatin1Char('|'));
        if (fields.size() < 5)
            continue;
        DeviceInfo info;
        info.name = fields.at(0);
        info.vendorId = static_cast<quint16>(fields.at(1).toUInt());
        info.productId = static_cast<quint16>(fields.at(2).toUInt());
        info.serialNumber = fields.at(3);
        info.product = fields.at(4);
        result.push_back(info);
    }
    return result;
}

bool AndroidUsbSerialPort::open(QIODevice::OpenMode)
{
    if (isOpen())
        return true;
    ensureNativesRegistered();
    const jint handle = QJniObject::callStaticMethod<jint>(
        JavaClass, "open", "(Landroid/content/Context;Ljava/lang/String;I)I",
        context().object(), QJniObject::fromString(m_portName).object<jstring>(),
        static_cast<jint>(m_baud));
    if (handle <= 0) {
        m_errorString = handle == -2 ? QStringLiteral("USB permission requested; accept it on the tablet")
            : handle == -1 ? QStringLiteral("USB device absent")
                           : QStringLiteral("USB open failed");
        return false;
    }
    m_errorString.clear();
    m_buffer.clear();
    m_handle = handle;
    QMutexLocker lock(&registryMutex);
    registry().insert(handle, this);
    return true;
}

void AndroidUsbSerialPort::close()
{
    if (!isOpen())
        return;
    const int handle = m_handle;
    {
        QMutexLocker lock(&registryMutex);
        registry().remove(handle);
    }
    m_handle = 0;
    QJniObject::callStaticMethod<void>(JavaClass, "close", "(I)V", static_cast<jint>(handle));
    m_buffer.clear();
}

qint64 AndroidUsbSerialPort::write(const QByteArray &data)
{
    if (!isOpen())
        return -1;
    QJniEnvironment env;
    jbyteArray array = env->NewByteArray(data.size());
    env->SetByteArrayRegion(array, 0, data.size(), reinterpret_cast<const jbyte *>(data.constData()));
    const jint written = QJniObject::callStaticMethod<jint>(
        JavaClass, "write", "(I[B)I", static_cast<jint>(m_handle), array);
    env->DeleteLocalRef(array);
    if (written < 0) {
        m_errorString = QStringLiteral("USB write failed");
        return -1;
    }
    QMetaObject::invokeMethod(this, [this, written]() { emit bytesWritten(written); },
                              Qt::QueuedConnection);
    return written;
}

QByteArray AndroidUsbSerialPort::readAll()
{
    QByteArray out;
    out.swap(m_buffer);
    return out;
}

void AndroidUsbSerialPort::deliverData(int handle, const QByteArray &data)
{
    QPointer<AndroidUsbSerialPort> port;
    {
        QMutexLocker lock(&registryMutex);
        port = registry().value(handle);
    }
    if (!port)
        return;
    QMetaObject::invokeMethod(port, [port, handle, data]() {
        if (!port || port->m_handle != handle)
            return;
        port->m_buffer.append(data);
        emit port->readyRead();
    }, Qt::QueuedConnection);
}

void AndroidUsbSerialPort::deliverError(int handle, const QString &message)
{
    QPointer<AndroidUsbSerialPort> port;
    {
        QMutexLocker lock(&registryMutex);
        port = registry().value(handle);
    }
    if (!port)
        return;
    QMetaObject::invokeMethod(port, [port, handle, message]() {
        if (!port || port->m_handle != handle)
            return;
        port->m_errorString = message;
        emit port->errorOccurred(QSerialPort::ResourceError);
    }, Qt::QueuedConnection);
}
