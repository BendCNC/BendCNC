#include "CanvasPainterRunRenderer.h"

#include <QtCanvasPainter/QCanvasPainter>
#include <QtCanvasPainter/QCanvasPath>
#include <QCache>
#include <QColor>
#include <QElapsedTimer>
#include <QFont>
#include <QMetaObject>
#include <QPainterPath>
#include <QPainterPathStroker>
#include <QPolygonF>
#include <QRegularExpression>
#include <QVariantMap>

#include <algorithm>
#include <cmath>
#include <limits>
#include <variant>

namespace {

constexpr int kMaximumCommands = 16384;
constexpr qreal kMaximumCoordinate = 1000000.0;
constexpr int kPreparedCacheMaximumCost = 32 * 1024 * 1024;
constexpr int kTransportCacheMaximumCost = 32768;

struct PreparedPathCommand
{
    QCanvasPath fillPath;
    QCanvasPath strokePath;
    QColor fillColor;
    QColor strokeColor;
    QCanvasPainter::CompositeOperation composition =
        QCanvasPainter::CompositeOperation::SourceOver;
    bool hasFill = false;
    bool hasStroke = false;
};

struct PreparedTextCommand
{
    QString text;
    QFont font;
    QColor fillColor;
    QColor outlineColor;
    QCanvasPainter::TextAlign align = QCanvasPainter::TextAlign::Left;
    QCanvasPainter::TextBaseline baseline = QCanvasPainter::TextBaseline::Alphabetic;
    float x = 0.0f;
    float y = 0.0f;
    float outlineOffset = 0.0f;
    bool hasOutline = false;
};

using PreparedCommand = std::variant<PreparedPathCommand, PreparedTextCommand>;

struct PreparedFrame
{
    QVector<PreparedCommand> commands;
    int cacheCost = 1;
};

QColor canvasColor(const QVariant &value)
{
    const QString text = value.toString().trimmed();
    QColor color(text);
    if (color.isValid())
        return color;
    static const QRegularExpression rgbaPattern(
        QStringLiteral(R"(^rgba?\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)(?:\s*,\s*([0-9.]+))?\s*\)$)"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch match = rgbaPattern.match(text);
    if (!match.hasMatch())
        return {};
    const int red = std::clamp(qRound(match.captured(1).toDouble()), 0, 255);
    const int green = std::clamp(qRound(match.captured(2).toDouble()), 0, 255);
    const int blue = std::clamp(qRound(match.captured(3).toDouble()), 0, 255);
    const qreal alpha = match.captured(4).isEmpty()
        ? 1.0 : std::clamp(match.captured(4).toDouble(), 0.0, 1.0);
    return QColor(red, green, blue, qRound(alpha * 255.0));
}

bool finiteCoordinate(double value)
{
    return std::isfinite(value) && std::abs(value) <= kMaximumCoordinate;
}

QPainterPath painterPath(const QVariantList &subpaths, const QString &fillRule,
                         bool *valid)
{
    QPainterPath path;
    path.setFillRule(fillRule == QStringLiteral("oddEven")
                         ? Qt::OddEvenFill : Qt::WindingFill);
    *valid = true;
    for (const QVariant &subpathValue : subpaths) {
        const QVariantMap subpath = subpathValue.toMap();
        const QVariantList points = subpath.value(QStringLiteral("points")).toList();
        if (points.size() < 2 || points.size() % 2 != 0) {
            *valid = false;
            return {};
        }
        bool xOk = false;
        bool yOk = false;
        const double firstX = points.at(0).toDouble(&xOk);
        const double firstY = points.at(1).toDouble(&yOk);
        if (!xOk || !yOk || !finiteCoordinate(firstX) || !finiteCoordinate(firstY)) {
            *valid = false;
            return {};
        }
        path.moveTo(firstX, firstY);
        for (qsizetype index = 2; index < points.size(); index += 2) {
            const double x = points.at(index).toDouble(&xOk);
            const double y = points.at(index + 1).toDouble(&yOk);
            if (!xOk || !yOk || !finiteCoordinate(x) || !finiteCoordinate(y)) {
                *valid = false;
                return {};
            }
            path.lineTo(x, y);
        }
        if (subpath.value(QStringLiteral("closed")).toBool())
            path.closeSubpath();
    }
    return path;
}

QPainterPath clippedPath(QPainterPath path, const QVariantMap &command, bool *valid)
{
    const QVariantList clips = command.value(QStringLiteral("clipSubpaths")).toList();
    if (clips.isEmpty())
        return path;
    QPainterPath clip = painterPath(clips,
        command.value(QStringLiteral("clipFillRule"), QStringLiteral("winding")).toString(),
        valid);
    if (!*valid)
        return {};
    return path.intersected(clip);
}

qreal signedPolygonArea(const QPolygonF &polygon)
{
    qreal area = 0.0;
    for (qsizetype index = 0; index < polygon.size(); ++index) {
        const QPointF &current = polygon.at(index);
        const QPointF &next = polygon.at((index + 1) % polygon.size());
        area += current.x() * next.y() - next.x() * current.y();
    }
    return area * 0.5;
}

QPointF interiorPolygonPoint(const QPolygonF &polygon)
{
    const QRectF bounds = polygon.boundingRect();
    for (int pass = 0; pass < 5; ++pass) {
        const qreal y = bounds.top() + bounds.height() * (0.5 + 0.08 * pass);
        QVector<qreal> intersections;
        for (qsizetype index = 0; index < polygon.size(); ++index) {
            const QPointF &a = polygon.at(index);
            const QPointF &b = polygon.at((index + 1) % polygon.size());
            if ((a.y() <= y && b.y() > y) || (b.y() <= y && a.y() > y))
                intersections.append(a.x() + (y - a.y()) * (b.x() - a.x())
                                     / (b.y() - a.y()));
        }
        std::sort(intersections.begin(), intersections.end());
        for (qsizetype index = 0; index + 1 < intersections.size(); index += 2) {
            const QPointF candidate((intersections.at(index) + intersections.at(index + 1)) * 0.5, y);
            if (polygon.containsPoint(candidate, Qt::OddEvenFill))
                return candidate;
        }
    }
    return bounds.center();
}

QCanvasPath windingPath(const QPainterPath &path)
{
    QCanvasPath canvasPath;
    const QList<QPolygonF> polygons = path.toSubpathPolygons();
    for (qsizetype polygonIndex = 0; polygonIndex < polygons.size(); ++polygonIndex) {
        const QPolygonF &polygon = polygons.at(polygonIndex);
        if (polygon.size() < 3)
            continue;
        const QPointF sample = interiorPolygonPoint(polygon);
        int nestingDepth = 0;
        qsizetype nearestContainer = -1;
        qreal nearestArea = std::numeric_limits<qreal>::max();
        for (qsizetype otherIndex = 0; otherIndex < polygons.size(); ++otherIndex) {
            if (otherIndex == polygonIndex)
                continue;
            const QPolygonF &other = polygons.at(otherIndex);
            const qreal otherArea = std::abs(signedPolygonArea(other));
            if (otherArea <= std::abs(signedPolygonArea(polygon))
                    || !other.containsPoint(sample, Qt::OddEvenFill))
                continue;
            ++nestingDepth;
            if (otherArea < nearestArea) {
                nearestArea = otherArea;
                nearestContainer = otherIndex;
            }
        }
        const bool hole = path.fillRule() == Qt::OddEvenFill
            ? nestingDepth % 2 == 1
            : nearestContainer >= 0
                && signedPolygonArea(polygon)
                    * signedPolygonArea(polygons.at(nearestContainer)) < 0.0;
        if (hole)
            canvasPath.beginHoleSubPath();
        else
            canvasPath.beginSolidSubPath();
        canvasPath.moveTo(polygon.constFirst());
        for (qsizetype index = 1; index < polygon.size(); ++index)
            canvasPath.lineTo(polygon.at(index));
        canvasPath.closePath();
    }
    return canvasPath;
}

QCanvasPainter::CompositeOperation compositeOperation(const QVariantMap &command)
{
    return command.value(QStringLiteral("composition")).toString()
            == QStringLiteral("destination-out")
        ? QCanvasPainter::CompositeOperation::DestinationOut
        : QCanvasPainter::CompositeOperation::SourceOver;
}

QCanvasPainter::TextAlign textAlign(const QString &value)
{
    if (value == QStringLiteral("center"))
        return QCanvasPainter::TextAlign::Center;
    if (value == QStringLiteral("right"))
        return QCanvasPainter::TextAlign::Right;
    if (value == QStringLiteral("end"))
        return QCanvasPainter::TextAlign::End;
    if (value == QStringLiteral("start"))
        return QCanvasPainter::TextAlign::Start;
    return QCanvasPainter::TextAlign::Left;
}

QCanvasPainter::TextBaseline textBaseline(const QString &value)
{
    if (value == QStringLiteral("top"))
        return QCanvasPainter::TextBaseline::Top;
    if (value == QStringLiteral("hanging"))
        return QCanvasPainter::TextBaseline::Hanging;
    if (value == QStringLiteral("middle"))
        return QCanvasPainter::TextBaseline::Middle;
    if (value == QStringLiteral("bottom"))
        return QCanvasPainter::TextBaseline::Bottom;
    return QCanvasPainter::TextBaseline::Alphabetic;
}

bool preparePath(const QVariantMap &command, PreparedPathCommand *prepared,
                 int *cacheCost)
{
    bool valid = false;
    QPainterPath path = painterPath(command.value(QStringLiteral("subpaths")).toList(),
                                    command.value(QStringLiteral("fillRule")).toString(),
                                    &valid);
    if (!valid)
        return false;

    const QColor fill = canvasColor(command.value(QStringLiteral("fillColor")));
    const QColor stroke = canvasColor(command.value(QStringLiteral("strokeColor")));
    prepared->composition = compositeOperation(command);
    if (fill.isValid()) {
        path = clippedPath(path, command, &valid);
        if (!valid)
            return false;
        prepared->fillColor = fill;
        prepared->fillPath = windingPath(path);
        prepared->hasFill = true;
    }
    if (stroke.isValid()) {
        QPainterPathStroker stroker;
        stroker.setWidth(std::max(0.01, command.value(QStringLiteral("lineWidth"), 1.0).toDouble()));
        const QString cap = command.value(QStringLiteral("lineCap")).toString();
        stroker.setCapStyle(cap == QStringLiteral("round") ? Qt::RoundCap
            : cap == QStringLiteral("square") ? Qt::SquareCap : Qt::FlatCap);
        const QVariantList dashValues = command.value(QStringLiteral("dash")).toList();
        if (!dashValues.isEmpty()) {
            QVector<qreal> dashPattern;
            dashPattern.reserve(dashValues.size());
            for (const QVariant &value : dashValues)
                dashPattern.append(std::max(0.01, value.toDouble()));
            stroker.setDashPattern(dashPattern);
        }
        QPainterPath strokePath = clippedPath(stroker.createStroke(path), command, &valid);
        if (!valid)
            return false;
        prepared->strokeColor = stroke;
        prepared->strokePath = windingPath(strokePath);
        prepared->hasStroke = true;
    }
    const QVariantList subpaths = command.value(QStringLiteral("subpaths")).toList();
    const QVariantList clips = command.value(QStringLiteral("clipSubpaths")).toList();
    for (const QVariant &value : subpaths)
        *cacheCost += value.toMap().value(QStringLiteral("points")).toList().size();
    for (const QVariant &value : clips)
        *cacheCost += value.toMap().value(QStringLiteral("points")).toList().size();
    return fill.isValid() || stroke.isValid();
}

bool prepareText(const QVariantMap &command, PreparedTextCommand *prepared,
                 int *cacheCost)
{
    const QColor fill = canvasColor(command.value(QStringLiteral("color")));
    if (!fill.isValid())
        return false;
    prepared->font = QFont(QStringLiteral("sans-serif"));
    prepared->font.setPixelSize(std::max(1, qRound(command.value(QStringLiteral("pixelSize"), 10.0).toDouble())));
    prepared->font.setBold(command.value(QStringLiteral("bold")).toBool());
    prepared->align = textAlign(command.value(QStringLiteral("align")).toString());
    prepared->baseline = textBaseline(command.value(QStringLiteral("baseline")).toString());
    prepared->text = command.value(QStringLiteral("text")).toString();
    prepared->x = command.value(QStringLiteral("x")).toFloat();
    prepared->y = command.value(QStringLiteral("y")).toFloat();
    prepared->fillColor = fill;
    const QColor outline = canvasColor(command.value(QStringLiteral("strokeColor")));
    const float outlineWidth = command.value(QStringLiteral("strokeWidth")).toFloat();
    if (outline.isValid() && outlineWidth > 0.0f) {
        prepared->outlineColor = outline;
        prepared->outlineOffset = std::max(0.5f, outlineWidth * 0.7f);
        prepared->hasOutline = true;
    }
    *cacheCost += int(std::max<qsizetype>(1, prepared->text.size()));
    return true;
}

std::shared_ptr<const PreparedFrame> prepareFrame(const QVariantList &commands)
{
    auto frame = std::make_shared<PreparedFrame>();
    frame->commands.reserve(commands.size());
    frame->cacheCost = commands.size() * 8;
    for (const QVariant &value : commands) {
        const QVariantMap command = value.toMap();
        if (command.value(QStringLiteral("type")).toString() == QStringLiteral("path")) {
            PreparedPathCommand path;
            if (preparePath(command, &path, &frame->cacheCost))
                frame->commands.append(std::move(path));
        } else {
            PreparedTextCommand text;
            if (prepareText(command, &text, &frame->cacheCost))
                frame->commands.append(std::move(text));
        }
    }
    qsizetype byteCost = sizeof(PreparedFrame)
        + frame->commands.capacity() * qsizetype(sizeof(PreparedCommand));
    for (const PreparedCommand &command : std::as_const(frame->commands)) {
        if (const auto *path = std::get_if<PreparedPathCommand>(&command)) {
            byteCost += path->fillPath.commandsSize()
                + path->fillPath.commandsDataSize() * qsizetype(sizeof(float));
            byteCost += path->strokePath.commandsSize()
                + path->strokePath.commandsDataSize() * qsizetype(sizeof(float));
        } else {
            const auto &text = std::get<PreparedTextCommand>(command);
            byteCost += text.text.size() * qsizetype(sizeof(QChar));
        }
    }
    frame->cacheCost = int(std::clamp<qsizetype>(byteCost, 1,
                                                 kPreparedCacheMaximumCost));
    return frame;
}

void replayPreparedCommand(QCanvasPainter *painter, const PreparedCommand &command)
{
    if (const auto *path = std::get_if<PreparedPathCommand>(&command)) {
        painter->setGlobalCompositeOperation(path->composition);
        if (path->hasFill) {
            painter->setFillStyle(path->fillColor);
            painter->fill(path->fillPath);
        }
        if (path->hasStroke) {
            painter->setFillStyle(path->strokeColor);
            painter->fill(path->strokePath);
        }
        return;
    }
    const auto &text = std::get<PreparedTextCommand>(command);
    painter->setFont(text.font);
    painter->setTextAlign(text.align);
    painter->setTextBaseline(text.baseline);
    painter->setGlobalCompositeOperation(QCanvasPainter::CompositeOperation::SourceOver);
    if (text.hasOutline) {
        painter->setFillStyle(text.outlineColor);
        static const QPointF directions[] = {
            {-1, -1}, {0, -1}, {1, -1}, {-1, 0},
            {1, 0}, {-1, 1}, {0, 1}, {1, 1}
        };
        for (const QPointF &direction : directions)
            painter->fillText(text.text,
                text.x + float(direction.x()) * text.outlineOffset,
                text.y + float(direction.y()) * text.outlineOffset);
    }
    painter->setFillStyle(text.fillColor);
    painter->fillText(text.text, text.x, text.y);
}

} // namespace

class CanvasPainterRunItemRenderer::Private
{
public:
    QCache<QString, std::shared_ptr<const PreparedFrame>> cache{kPreparedCacheMaximumCost};
    std::shared_ptr<const PreparedFrame> frame;
    int cacheHits = 0;
    int cacheMisses = 0;
    int cacheEvictions = 0;
    int largestFrameCost = 0;
    qreal prepareMilliseconds = 0.0;
};

CanvasPainterRunItemRenderer::CanvasPainterRunItemRenderer()
    : d(std::make_unique<Private>())
{
}

CanvasPainterRunItemRenderer::~CanvasPainterRunItemRenderer() = default;

CanvasPainterRunItem::CanvasPainterRunItem(QQuickItem *parent)
    : QCanvasPainterItem(parent)
{
    m_commandCache.setMaxCost(kTransportCacheMaximumCost);
    setFillColor(Qt::transparent);
    setAlphaBlending(true);
    setSampleCount(4);
}

bool CanvasPainterRunItem::submitFrame(const QVariantList &commands, int revision,
                                       const QString &cacheKey)
{
    if (revision <= m_acceptedRevision) {
        rejectPacket(QStringLiteral("revision must increase"));
        return false;
    }
    if (commands.isEmpty() || commands.size() > kMaximumCommands) {
        rejectPacket(QStringLiteral("command count is outside the accepted range"));
        return false;
    }
    int expectedOrder = 0;
    for (const QVariant &value : commands) {
        const QVariantMap command = value.toMap();
        const QString type = command.value(QStringLiteral("type")).toString();
        if ((type != QStringLiteral("path") && type != QStringLiteral("text"))
            || command.value(QStringLiteral("order"), -1).toInt() != expectedOrder++) {
            rejectPacket(QStringLiteral("ordered stream contains an invalid command"));
            return false;
        }
    }
    m_commands = commands;
    m_cacheKey = cacheKey;
    if (!cacheKey.isEmpty()) {
        m_commandCache.insert(cacheKey, new QVariantList(commands),
                              int(std::max<qsizetype>(1, commands.size())));
    }
    m_acceptedRevision = revision;
    m_packetValid = true;
    m_packetError.clear();
    Q_EMIT packetValidChanged();
    Q_EMIT packetErrorChanged();
    Q_EMIT acceptedRevisionChanged();
    update();
    return true;
}

bool CanvasPainterRunItem::submitCachedFrame(const QString &cacheKey, int revision)
{
    if (revision <= m_acceptedRevision) {
        rejectPacket(QStringLiteral("revision must increase"));
        return false;
    }
    if (cacheKey.isEmpty()) {
        rejectPacket(QStringLiteral("cache key must not be empty"));
        return false;
    }
    const QVariantList *commands = m_commandCache.object(cacheKey);
    if (!commands) {
        ++m_transportCacheMisses;
        Q_EMIT transportCacheStatsChanged();
        rejectPacket(QStringLiteral("command cache key is unavailable"));
        return false;
    }
    ++m_transportCacheHits;
    Q_EMIT transportCacheStatsChanged();
    m_commands = *commands;
    m_cacheKey = cacheKey;
    m_acceptedRevision = revision;
    m_packetValid = true;
    m_packetError.clear();
    Q_EMIT packetValidChanged();
    Q_EMIT packetErrorChanged();
    Q_EMIT acceptedRevisionChanged();
    update();
    return true;
}

bool CanvasPainterRunItem::hasCachedFrame(const QString &cacheKey) const
{
    return !cacheKey.isEmpty() && m_commandCache.contains(cacheKey);
}

QCanvasPainterItemRenderer *CanvasPainterRunItem::createItemRenderer() const
{
    return new CanvasPainterRunItemRenderer;
}

void CanvasPainterRunItem::rejectPacket(const QString &error)
{
    m_packetValid = false;
    m_packetError = error;
    Q_EMIT packetValidChanged();
    Q_EMIT packetErrorChanged();
}

void CanvasPainterRunItem::markPresented(int revision, int batches)
{
    if (revision < m_presentedRevision)
        return;
    if (m_batchCount != batches) {
        m_batchCount = batches;
        Q_EMIT batchCountChanged();
    }
    if (m_presentedRevision != revision) {
        m_presentedRevision = revision;
        Q_EMIT presentedRevisionChanged();
    }
}

void CanvasPainterRunItem::markPreparedStats(int hits, int misses, int commands,
                                             qreal milliseconds, int entries,
                                             int cost, int evictions,
                                             int largestFrameCost)
{
    if (m_preparedCacheHits == hits && m_preparedCacheMisses == misses
        && m_preparedCommandCount == commands
        && qFuzzyCompare(m_prepareMilliseconds + 1.0, milliseconds + 1.0)
        && m_preparedCacheEntries == entries && m_preparedCacheCost == cost
        && m_preparedCacheEvictions == evictions
        && m_largestPreparedFrameCost == largestFrameCost) {
        return;
    }
    m_preparedCacheHits = hits;
    m_preparedCacheMisses = misses;
    m_preparedCommandCount = commands;
    m_prepareMilliseconds = milliseconds;
    m_preparedCacheEntries = entries;
    m_preparedCacheCost = cost;
    m_preparedCacheEvictions = evictions;
    m_largestPreparedFrameCost = largestFrameCost;
    Q_EMIT preparedCacheStatsChanged();
}

void CanvasPainterRunItemRenderer::synchronizeData(QCanvasPainterItem *item)
{
    auto *runItem = static_cast<CanvasPainterRunItem *>(item);
    m_item = runItem;
    if (runItem->acceptedRevision() <= m_revision)
        return;
    const QVariantList commands = runItem->commands();
    const QString cacheKey = runItem->cacheKey();
    QElapsedTimer timer;
    timer.start();
    if (!cacheKey.isEmpty()) {
        if (const auto *cached = d->cache.object(cacheKey)) {
            d->frame = *cached;
            ++d->cacheHits;
            d->prepareMilliseconds = 0.0;
        } else {
            d->frame = prepareFrame(commands);
            ++d->cacheMisses;
            d->prepareMilliseconds = qreal(timer.nsecsElapsed()) / 1000000.0;
            d->largestFrameCost = std::max(d->largestFrameCost,
                                           d->frame->cacheCost);
            const int previousEntries = d->cache.size();
            d->cache.insert(cacheKey,
                            new std::shared_ptr<const PreparedFrame>(d->frame),
                            d->frame->cacheCost);
            d->cacheEvictions += int(std::max<qsizetype>(
                0, previousEntries + 1 - d->cache.size()));
        }
    } else {
        d->frame = prepareFrame(commands);
        ++d->cacheMisses;
        d->prepareMilliseconds = qreal(timer.nsecsElapsed()) / 1000000.0;
    }
    m_revision = runItem->acceptedRevision();
    const QPointer<CanvasPainterRunItem> itemPointer = m_item;
    const int hits = d->cacheHits;
    const int misses = d->cacheMisses;
    const int preparedCommands = d->frame ? d->frame->commands.size() : 0;
    const qreal milliseconds = d->prepareMilliseconds;
    const int cacheEntries = d->cache.size();
    const int cacheCost = d->cache.totalCost();
    const int cacheEvictions = d->cacheEvictions;
    const int largestFrameCost = d->largestFrameCost;
    QMetaObject::invokeMethod(itemPointer,
        [itemPointer, hits, misses, preparedCommands, milliseconds, cacheEntries,
         cacheCost, cacheEvictions, largestFrameCost] {
            if (itemPointer)
                itemPointer->markPreparedStats(hits, misses, preparedCommands,
                                               milliseconds, cacheEntries,
                                               cacheCost, cacheEvictions,
                                               largestFrameCost);
        }, Qt::QueuedConnection);
}

void CanvasPainterRunItemRenderer::paint(QCanvasPainter *painter)
{
    painter->reset();
    painter->setAntialias(1.0f);
    painter->setTextAntialias(1.0f);
    painter->setRenderHint(QCanvasPainter::RenderHint::HighQualityStroking);
    int rendered = 0;
    if (d->frame) {
        for (const PreparedCommand &command : std::as_const(d->frame->commands)) {
            replayPreparedCommand(painter, command);
            ++rendered;
        }
    }
    const QPointer<CanvasPainterRunItem> item = m_item;
    const int revision = m_revision;
    QMetaObject::invokeMethod(item, [item, revision, rendered] {
        if (item)
            item->markPresented(revision, rendered);
    }, Qt::QueuedConnection);
}