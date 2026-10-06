#include "MetadataPanel.h"

#include <QHeaderView>
#include <QImage>
#include <QPushButton>
#include <QTableWidget>
#include <QVBoxLayout>
#include <QHBoxLayout>

MetadataPanel::MetadataPanel(QWidget *parent) : QWidget(parent) {
    m_table = new QTableWidget(0, 2, this);
    m_table->setHorizontalHeaderLabels({tr("Key"), tr("Value")});
    m_table->horizontalHeader()->setSectionResizeMode(0, QHeaderView::ResizeToContents);
    m_table->horizontalHeader()->setSectionResizeMode(1, QHeaderView::Stretch);
    m_table->verticalHeader()->setVisible(false);
    m_table->setSelectionBehavior(QAbstractItemView::SelectRows);

    auto *addButton = new QPushButton(tr("Add"), this);
    auto *removeButton = new QPushButton(tr("Remove"), this);
    connect(addButton, &QPushButton::clicked, this, &MetadataPanel::addRow);
    connect(removeButton, &QPushButton::clicked, this, &MetadataPanel::removeSelectedRows);

    auto *buttons = new QHBoxLayout;
    buttons->addWidget(addButton);
    buttons->addWidget(removeButton);
    buttons->addStretch();

    auto *layout = new QVBoxLayout(this);
    layout->addWidget(m_table);
    layout->addLayout(buttons);
}

void MetadataPanel::appendRow(const QString &key, const QString &value) {
    const int row = m_table->rowCount();
    m_table->insertRow(row);
    m_table->setItem(row, 0, new QTableWidgetItem(key));
    m_table->setItem(row, 1, new QTableWidgetItem(value));
}

void MetadataPanel::loadFrom(const QImage &image) {
    m_table->setRowCount(0);
    const auto keys = image.textKeys();
    for (const QString &key : keys) {
        if (!key.isEmpty())
            appendRow(key, image.text(key));
    }
}

QMap<QString, QString> MetadataPanel::values() const {
    QMap<QString, QString> result;
    for (int row = 0; row < m_table->rowCount(); ++row) {
        const QTableWidgetItem *keyItem = m_table->item(row, 0);
        const QTableWidgetItem *valueItem = m_table->item(row, 1);
        const QString key = keyItem ? keyItem->text().trimmed() : QString();
        if (key.isEmpty())
            continue;
        result.insert(key, valueItem ? valueItem->text() : QString());
    }
    return result;
}

void MetadataPanel::addRow() {
    appendRow(QString(), QString());
    m_table->editItem(m_table->item(m_table->rowCount() - 1, 0));
}

void MetadataPanel::removeSelectedRows() {
    const auto ranges = m_table->selectedRanges();
    QList<int> rows;
    for (const auto &range : ranges) {
        for (int r = range.topRow(); r <= range.bottomRow(); ++r)
            rows.append(r);
    }
    std::sort(rows.begin(), rows.end(), std::greater<int>());
    for (int r : rows)
        m_table->removeRow(r);
}
