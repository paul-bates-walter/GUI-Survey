#pragma once

#include <QMap>
#include <QString>
#include <QWidget>

class QImage;
class QTableWidget;

// Editable key/value view of a PNG's tEXt metadata.
class MetadataPanel : public QWidget {
    Q_OBJECT
public:
    explicit MetadataPanel(QWidget *parent = nullptr);

    void loadFrom(const QImage &image);
    QMap<QString, QString> values() const;

private slots:
    void addRow();
    void removeSelectedRows();

private:
    void appendRow(const QString &key, const QString &value);

    QTableWidget *m_table = nullptr;
};
