#include "CanvasWidget.h"

#include <QMouseEvent>
#include <QPainter>
#include <QPen>

#include <cmath>

CanvasWidget::CanvasWidget(QWidget *parent) : QWidget(parent) {
    setMouseTracking(true);
    setFocusPolicy(Qt::StrongFocus);
    newImage(QSize(800, 600));
}

void CanvasWidget::adoptImage(QImage image) {
    m_image = std::move(image);
    m_havePending = false;
    m_drawing = false;
    setFixedSize(m_image.size());
    update();
}

void CanvasWidget::newImage(const QSize &size, const QColor &fill) {
    QImage image(size, QImage::Format_ARGB32);
    image.fill(fill);
    adoptImage(std::move(image));
    clearModified();
}

bool CanvasWidget::loadImage(const QString &path) {
    QImage loaded;
    if (!loaded.load(path))
        return false;

    // Preserve text metadata across the format conversion.
    QImage converted = loaded.convertToFormat(QImage::Format_ARGB32);
    const auto keys = loaded.textKeys();
    for (const QString &key : keys) {
        if (!key.isEmpty())
            converted.setText(key, loaded.text(key));
    }
    adoptImage(std::move(converted));
    clearModified();
    return true;
}

bool CanvasWidget::saveImage(const QString &path, const QMap<QString, QString> &metadata) {
    // Rebuild a clean image so removed keys do not survive as stale tEXt chunks.
    QImage out(m_image.size(), m_image.format());
    {
        QPainter painter(&out);
        painter.drawImage(0, 0, m_image);
    }
    for (auto it = metadata.constBegin(); it != metadata.constEnd(); ++it) {
        if (!it.key().isEmpty())
            out.setText(it.key(), it.value());
    }
    if (!out.save(path, "PNG"))
        return false;
    clearModified();
    return true;
}

void CanvasWidget::setMode(Mode mode) {
    m_mode = mode;
    m_havePending = false;
    m_drawing = false;
    update();
}

void CanvasWidget::clearModified() {
    if (m_modified) {
        m_modified = false;
        emit modifiedChanged(false);
    }
}

void CanvasWidget::markModified() {
    if (!m_modified) {
        m_modified = true;
        emit modifiedChanged(true);
    }
}

QPoint CanvasWidget::clampToImage(const QPoint &pt) const {
    return QPoint(qBound(0, pt.x(), m_image.width() - 1),
                  qBound(0, pt.y(), m_image.height() - 1));
}

void CanvasWidget::paintShape(QPainter &painter, const QPoint &a, const QPoint &b) const {
    QPen pen(m_penColor, m_penRadius, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
    painter.setPen(pen);
    painter.setBrush(Qt::NoBrush);
    if (m_mode == Mode::Circle) {
        const double r = std::hypot(double(b.x() - a.x()), double(b.y() - a.y()));
        painter.drawEllipse(QPointF(a), r, r);
    } else { // Rectangle
        painter.drawRect(QRect(a, b).normalized());
    }
}

void CanvasWidget::paintEvent(QPaintEvent *) {
    QPainter painter(this);
    painter.drawImage(0, 0, m_image);
    if (m_havePending) {
        painter.setRenderHint(QPainter::Antialiasing, true);
        paintShape(painter, m_startPoint, m_cursorPoint);
    }
}

void CanvasWidget::mousePressEvent(QMouseEvent *event) {
    if (event->button() != Qt::LeftButton)
        return;
    const QPoint pt = clampToImage(event->pos());

    if (m_mode == Mode::Path) {
        m_drawing = true;
        m_lastPoint = pt;
        QPainter painter(&m_image);
        painter.setRenderHint(QPainter::Antialiasing, true);
        painter.setPen(Qt::NoPen);
        painter.setBrush(m_penColor);
        painter.drawEllipse(pt, m_penRadius, m_penRadius); // initial dab
        markModified();
        update();
        return;
    }

    if (!m_havePending) {
        m_havePending = true;
        m_startPoint = pt;
        m_cursorPoint = pt;
    } else {
        QPainter painter(&m_image);
        painter.setRenderHint(QPainter::Antialiasing, true);
        paintShape(painter, m_startPoint, pt);
        m_havePending = false;
        markModified();
    }
    update();
}

void CanvasWidget::mouseMoveEvent(QMouseEvent *event) {
    const QPoint pt = clampToImage(event->pos());

    if (m_mode == Mode::Path && m_drawing) {
        QPainter painter(&m_image);
        painter.setRenderHint(QPainter::Antialiasing, true);
        QPen pen(m_penColor, m_penRadius * 2, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
        painter.setPen(pen);
        painter.drawLine(m_lastPoint, pt);
        m_lastPoint = pt;
        markModified();
        update();
    } else if (m_havePending) {
        m_cursorPoint = pt;
        update();
    }
}

void CanvasWidget::mouseReleaseEvent(QMouseEvent *event) {
    if (event->button() == Qt::LeftButton && m_mode == Mode::Path)
        m_drawing = false;
}
