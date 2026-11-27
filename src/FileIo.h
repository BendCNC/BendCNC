#pragma once

#include <QObject>
#include <QString>
#include <QUrl>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QSaveFile>
#include <QTextStream>
#include <QCoreApplication>
#include <QStandardPaths>
#include <QVariantList>
#include <QCryptographicHash>
#include <QMessageAuthenticationCode>
#include <QtEndian>

// FileIo
// Narrow C++ file-IO surface for the pure-QML BendCNC app. Pure-QML
// XMLHttpRequest can read file:// URLs and overwrite pre-existing files, but it
// cannot create new files and hangs on a synchronous GET of a missing file.
// This class provides the IO backend expected by core/storage/EntityStorage.js:
//
//   read(url)        -> string ("" if missing/unreadable; JS treats "" as absent)
//   write(url, text) -> bool   (atomic create-or-overwrite via QSaveFile)
//   append(url, text) -> bool  (append without rereading whole file)
//   exists(url)      -> bool    (no hang on missing)
//   copy(srcUrl, dstUrl) -> bool
//
// Exposed to QML as the `fileIo` context property (see main.cpp). Accepts either
// file:// URLs or plain absolute paths; relative paths are resolved against CWD.
class FileIo : public QObject
{
    Q_OBJECT
public:
    explicit FileIo(QObject *parent = nullptr) : QObject(parent) {}

    // Compressed .bend container: "BCZ1" + 4-byte big-endian length + zlib stream
    // (exactly qCompress output after the magic). Plain JSON text is still read.
    static QByteArray compressedMagic() { return QByteArrayLiteral("BCZ1"); }

    // Protected catalog (.bct, same scheme as sequence-planner tools/protect_catalog.py):
    // "BCTE1\n" | nonce(16) | HMAC-SHA256 tag(32) | body, body = zlib stream XOR
    // SHA-256(key|nonce|uint32be(block)). Deters casual copying of tooling DXFs only.
    static QByteArray unprotectCatalog(const QByteArray &raw)
    {
        static const QByteArray magic = QByteArrayLiteral("BCTE1\n");
        if (raw.size() < magic.size() + 48 || !raw.startsWith(magic))
            return QByteArray();
        const QByteArray key = QCryptographicHash::hash(
            QStringLiteral("BendCNC tooling catalog v1 \u00b7 7f3c91e2a4d84b0c").toUtf8(),
            QCryptographicHash::Sha256);
        const QByteArray nonce = raw.mid(6, 16), tag = raw.mid(22, 32), body = raw.mid(54);
        if (QMessageAuthenticationCode::hash(nonce + body, key, QCryptographicHash::Sha256) != tag)
            return QByteArray();
        QByteArray plain(body.size(), Qt::Uninitialized);
        for (qsizetype i = 0, block = 0; i < body.size(); i += 32, ++block) {
            QByteArray counter(4, Qt::Uninitialized);
            qToBigEndian(quint32(block), counter.data());
            const QByteArray ks = QCryptographicHash::hash(key + nonce + counter, QCryptographicHash::Sha256);
            for (qsizetype j = 0; j < 32 && i + j < body.size(); ++j)
                plain[i + j] = char(body[i + j] ^ ks[j]);
        }
        // qUncompress expects a 4-byte big-endian size hint before the zlib stream.
        QByteArray sized(4, Qt::Uninitialized);
        qToBigEndian(quint32(qMin<qsizetype>(plain.size() * 16, 64 * 1024 * 1024)), sized.data());
        return qUncompress(sized + plain);
    }

    Q_INVOKABLE QString read(const QString &url) const
    {
        const QString path = toLocalPath(url);
        QFile f(path);
        if (!f.exists()) {
            QFile p(path + QStringLiteral(".bct"));
            if (!p.open(QIODevice::ReadOnly))
                return QString();
            // Same newline handling as the QIODevice::Text read below.
            return QString::fromUtf8(unprotectCatalog(p.readAll()).replace("\r\n", "\n"));
        }
        if (!f.open(QIODevice::ReadOnly))
            return QString();
        if (f.peek(4) == compressedMagic()) {
            const QByteArray raw = f.readAll();
            f.close();
            const QByteArray data = qUncompress(raw.mid(4));
            return data.isEmpty() ? QString() : QString::fromUtf8(data);
        }
        f.close();
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
            return QString();
        const QString content = QString::fromUtf8(f.readAll());
        f.close();
        return content;
    }

    Q_INVOKABLE bool isCompressed(const QString &url) const
    {
        QFile f(toLocalPath(url));
        return f.open(QIODevice::ReadOnly) && f.peek(4) == compressedMagic();
    }

    // Atomic write in the compressed container (see read()).
    Q_INVOKABLE bool writeCompressed(const QString &url, const QString &text) const
    {
        const QString path = toLocalPath(url);
        QDir().mkpath(QFileInfo(path).absolutePath());
        const QByteArray bytes = compressedMagic() + qCompress(text.toUtf8(), 6);
        QSaveFile f(path);
        if (!f.open(QIODevice::WriteOnly) || f.write(bytes) != bytes.size()) {
            f.cancelWriting();
            return false;
        }
        return f.commit();
    }

    Q_INVOKABLE bool write(const QString &url, const QString &text) const
    {
        const QString path = toLocalPath(url);
        const QFileInfo info(path);
        QDir().mkpath(info.absolutePath());

        // Atomic write: QSaveFile writes to a temp file then renames on commit,
        // so a crash mid-write never corrupts the target.
        QSaveFile f(path);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
            return writeDirect(path, text);
        const QByteArray bytes = text.toUtf8();
        if (f.write(bytes) != bytes.size()) {
            f.cancelWriting();
            return writeDirect(path, text);
        }
        if (f.commit())
            return true;
        return writeDirect(path, text);
    }

    Q_INVOKABLE bool append(const QString &url, const QString &text) const
    {
        const QString path = toLocalPath(url);
        const QFileInfo info(path);
        QDir().mkpath(info.absolutePath());

        QFile f(path);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
            return appendDirect(path, text);
        const QByteArray bytes = text.toUtf8();
        const qint64 written = f.write(bytes);
        f.close();
        if (written == bytes.size())
            return true;
        return appendDirect(path, text);
    }

    Q_INVOKABLE bool exists(const QString &url) const
    {
        const QString path = toLocalPath(url);
        return QFile::exists(path) || QFile::exists(path + QStringLiteral(".bct"));
    }

    Q_INVOKABLE bool copy(const QString &srcUrl, const QString &dstUrl) const
    {
        const QString src = toLocalPath(srcUrl);
        const QString dst = toLocalPath(dstUrl);
        if (!QFile::exists(src))
            return false;
        QDir().mkpath(QFileInfo(dst).absolutePath());
        QFile::remove(dst); // QFile::copy refuses to overwrite
        return QFile::copy(src, dst);
    }

    // Absolute directory of the running executable. QML uses this to build
    // launch-directory-independent asset/log paths so tooling DXFs and the run
    // debug log resolve regardless of the process working directory.
    Q_INVOKABLE QString appDir() const
    {
        return assetBaseDir();
    }

    // Stable writable storage shared by DataStore reads and AppState writes.
    // Bundled qrc JSON remains the factory-default fallback; user edits belong
    // under the platform app-data directory so they survive upgrades/restarts.
    Q_INVOKABLE QString storageFilePath(const QString &fileName) const
    {
        QString root = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
        if (root.isEmpty())
            root = QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("data"));
        const QString currentDir = QDir(root).filePath(QStringLiteral("current"));
        QDir().mkpath(currentDir);
        const QString safeFileName = QFileInfo(fileName).fileName();
        return QDir(currentDir).filePath(safeFileName);
    }

    Q_INVOKABLE QString importDirectory() const
    {
        QString path = qEnvironmentVariable("BENDCNC_IMPORT_DIR");
        if (path.isEmpty()) {
            QString root = qEnvironmentVariable("BENDCNC_QT_HOME");
            if (root.isEmpty())
                root = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
            path = QDir(root).filePath(QStringLiteral("imports"));
        }
        QDir().mkpath(path);
        return QDir::cleanPath(path);
    }

    Q_INVOKABLE QString parentDirectory(const QString &path) const
    {
        QDir directory(toLocalPath(path));
        directory.cdUp();
        return directory.absolutePath();
    }

    Q_INVOKABLE QVariantList directoryEntries(const QString &path) const
    {
        QVariantList entries;
        QDir directory(toLocalPath(path));
        if (!directory.exists())
            return entries;
        const QFileInfoList infos = directory.entryInfoList(
            QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot | QDir::Readable,
            QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);
        for (const QFileInfo &info : infos) {
            const bool directoryEntry = info.isDir();
            const QString suffix = info.suffix().toLower();
            if (!directoryEntry && suffix != QStringLiteral("bend")
                    && suffix != QStringLiteral("bcbend")
                    && suffix != QStringLiteral("json"))
                continue;
            QVariantMap entry;
            entry.insert(QStringLiteral("name"), info.fileName());
            entry.insert(QStringLiteral("path"), info.absoluteFilePath());
            entry.insert(QStringLiteral("directory"), directoryEntry);
            entry.insert(QStringLiteral("size"), directoryEntry ? 0 : info.size());
            entry.insert(QStringLiteral("modified"), info.lastModified().toMSecsSinceEpoch());
            if (directoryEntry) {
                const QStringList filters{QStringLiteral("*.bend"), QStringLiteral("*.bcbend"), QStringLiteral("*.json")};
                entry.insert(QStringLiteral("count"), QDir(info.absoluteFilePath()).entryList(filters, QDir::Files).size());
            }
            entries.append(entry);
        }
        return entries;
    }

    // Folder/file organisation for the CAD import picker. Names are single path
    // components only (no separators, no ".."), so callers cannot escape `parent`.
    static bool safeEntryName(const QString &name)
    {
        const QString n = name.trimmed();
        return !n.isEmpty() && n != QStringLiteral(".") && n != QStringLiteral("..")
            && !n.contains(QLatin1Char('/')) && !n.contains(QLatin1Char('\\'))
            && !n.contains(QLatin1Char(':')) && n.size() <= 80;
    }

    Q_INVOKABLE bool makeDirectory(const QString &parent, const QString &name) const
    {
        if (!safeEntryName(name))
            return false;
        QDir directory(toLocalPath(parent));
        return directory.exists() && directory.mkdir(name.trimmed());
    }

    // Moves a file or folder into targetDirectory (same file system); never overwrites.
    Q_INVOKABLE bool moveEntry(const QString &sourcePath, const QString &targetDirectory) const
    {
        const QFileInfo source(toLocalPath(sourcePath));
        const QDir target(toLocalPath(targetDirectory));
        if (!source.exists() || !target.exists())
            return false;
        const QString destination = target.filePath(source.fileName());
        if (QFileInfo::exists(destination))
            return false;
        if (source.isDir() && QDir::cleanPath(target.absolutePath() + QLatin1Char('/'))
                .startsWith(QDir::cleanPath(source.absoluteFilePath()) + QLatin1Char('/')))
            return false;
        return QDir().rename(source.absoluteFilePath(), destination);
    }

    Q_INVOKABLE bool renameEntry(const QString &sourcePath, const QString &newName) const
    {
        if (!safeEntryName(newName))
            return false;
        const QFileInfo source(toLocalPath(sourcePath));
        const QString destination = source.dir().filePath(newName.trimmed());
        if (!source.exists() || QFileInfo::exists(destination))
            return false;
        return QDir().rename(source.absoluteFilePath(), destination);
    }

    // Deletes one CAD file (.bend/.bcbend/.json) or an EMPTY folder. Never recursive.
    Q_INVOKABLE bool deleteEntry(const QString &path) const
    {
        const QFileInfo info(toLocalPath(path));
        if (!info.exists())
            return false;
        if (info.isDir())
            return QDir().rmdir(info.absoluteFilePath());
        const QString suffix = info.suffix().toLower();
        if (suffix != QStringLiteral("bend") && suffix != QStringLiteral("bcbend")
                && suffix != QStringLiteral("json"))
            return false;
        return QFile::remove(info.absoluteFilePath());
    }

    Q_INVOKABLE QString localFileUrl(const QString &path) const
    {
        return QUrl::fromLocalFile(toLocalPath(path)).toString();
    }

private:
    // On Android the packaged assets (DXF tooling, bcbends) live inside the APK
    // under assets:/ (see android/README.md); elsewhere next to the executable.
    static QString assetBaseDir()
    {
#ifdef Q_OS_ANDROID
        return QStringLiteral("assets:");
#else
        return QCoreApplication::applicationDirPath();
#endif
    }

    static bool writeDirect(const QString &path, const QString &text)
    {
        QFile directFile(path);
        if (!directFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
            return false;
        const QByteArray bytes = text.toUtf8();
        const qint64 written = directFile.write(bytes);
        directFile.close();
        return written == bytes.size();
    }

    static bool appendDirect(const QString &path, const QString &text)
    {
        QFile directFile(path);
        if (!directFile.open(QIODevice::ReadWrite | QIODevice::Text))
            return false;
        if (!directFile.seek(directFile.size())) {
            directFile.close();
            return false;
        }
        const QByteArray bytes = text.toUtf8();
        const qint64 written = directFile.write(bytes);
        directFile.close();
        return written == bytes.size();
    }

    static QString toLocalPath(const QString &url)
    {
        if (url.startsWith(QStringLiteral("file:")))
            return QUrl(url).toLocalFile();
        if (QFile::exists(url))
            return QDir::cleanPath(url);
        const QFileInfo info(url);
        if (info.isRelative()) {
            const QString base = assetBaseDir();
            if (!base.isEmpty()) {
                const QString candidate = QDir::cleanPath(base + QLatin1Char('/') + url);
                if (QFile::exists(candidate))
                    return candidate;
            }
        }
        return url;
    }
};
