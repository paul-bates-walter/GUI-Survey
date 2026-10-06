#pragma once

#include <QColor>
#include <QImage>
#include <QPoint>
#include <QWidget>

// CanvasWidget owns the editable raster and renders it 1:1.
// Drawing modes match spec.md: circle, rectangle, path.
class CanvasWidget : public QWidget {
    Q_OBJECT
public:
    enum class Mode { Circle, Rectangle, Path };

    explicit CanvasWidget(QWidget *parent = nullptr);

    void newImage(const QSize &size, const QColor &fill = Qt::white);
    bool loadImage(const QString &path);
    // Writes a PNG whose only tEXt metadata is the provided key/value map.
    bool saveImage(const QString &path, const QMap<QString, QString> &metadata);

    const QImage &image() const { return m_image; }

    void setMode(Mode mode);
    Mode mode() const { return m_mode; }

    void setPenColor(const QColor &color) { m_penColor = color; }
    QColor penColor() const { return m_penColor; }

    void setPenRadius(int radius) { m_penRadius = qMax(1, radius); }
    int penRadius() const { return m_penRadius; }

    bool isModified() const { return m_modified; }
    void clearModified();

signals:
    void modifiedChanged(bool modified);

protected:
    void paintEvent(QPaintEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;

private:
    QPoint clampToImage(const QPoint &pt) const;
    void paintShape(QPainter &painter, const QPoint &a, const QPoint &b) const;
    void adoptImage(QImage image);
    void markModified();

    QImage m_image;
    Mode m_mode = Mode::Path;
    QColor m_penColor = Qt::black;
    int m_penRadius = 4;
    bool m_modified = false;

    // Two-click state for circle/rectangle.
    bool m_havePending = false;
    QPoint m_startPoint;
    QPoint m_cursorPoint;

    // Freehand state for path mode.
    bool m_drawing = false;
    QPoint m_lastPoint;
};
