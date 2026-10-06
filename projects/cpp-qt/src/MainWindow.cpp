#include "MainWindow.h"

#include "CanvasWidget.h"
#include "MetadataPanel.h"

#include <QActionGroup>
#include <QCloseEvent>
#include <QColorDialog>
#include <QComboBox>
#include <QDockWidget>
#include <QFileDialog>
#include <QFileInfo>
#include <QLabel>
#include <QMenuBar>
#include <QMessageBox>
#include <QScrollArea>
#include <QSpinBox>
#include <QToolBar>

MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent) {
    m_canvas = new CanvasWidget(this);
    m_metadata = new MetadataPanel(this);
    buildUi();
    connect(m_canvas, &CanvasWidget::modifiedChanged, this, &MainWindow::updateTitle);
    updateTitle();
}

void MainWindow::buildUi() {
    auto *scroll = new QScrollArea(this);
    scroll->setWidget(m_canvas);
    scroll->setAlignment(Qt::AlignCenter);
    setCentralWidget(scroll);

    // --- File menu ---
    QMenu *fileMenu = menuBar()->addMenu(tr("&File"));
    // Note: the addAction(text, shortcut, receiver, slot) overload requires
    // Qt 6.3+. This project targets the 6.2 LTS floor, so wire actions explicitly.
    auto *newAction = fileMenu->addAction(tr("&New"), this, &MainWindow::newFile);
    newAction->setShortcut(QKeySequence::New);
    auto *openAction = fileMenu->addAction(tr("&Open..."), this, &MainWindow::openFile);
    openAction->setShortcut(QKeySequence::Open);
    auto *saveAction = fileMenu->addAction(tr("&Save"), this, [this] { saveFile(); });
    saveAction->setShortcut(QKeySequence::Save);
    auto *saveAsAction = fileMenu->addAction(tr("Save &As..."), this, [this] { saveFileAs(); });
    saveAsAction->setShortcut(QKeySequence::SaveAs);
    fileMenu->addSeparator();
    auto *quitAction = fileMenu->addAction(tr("&Quit"), this, &QWidget::close);
    quitAction->setShortcut(QKeySequence::Quit);

    // --- Tool bar: mode + pen settings ---
    QToolBar *tools = addToolBar(tr("Tools"));
    tools->setMovable(false);

    tools->addWidget(new QLabel(tr("Mode: "), tools));
    auto *modeBox = new QComboBox(tools);
    modeBox->addItem(tr("Path"), int(CanvasWidget::Mode::Path));
    modeBox->addItem(tr("Circle"), int(CanvasWidget::Mode::Circle));
    modeBox->addItem(tr("Rectangle"), int(CanvasWidget::Mode::Rectangle));
    connect(modeBox, &QComboBox::currentIndexChanged, this, [this, modeBox](int) {
        m_canvas->setMode(CanvasWidget::Mode(modeBox->currentData().toInt()));
    });
    tools->addWidget(modeBox);

    tools->addSeparator();
    auto *colorAction = tools->addAction(tr("Pen Color"));
    connect(colorAction, &QAction::triggered, this, &MainWindow::chooseColor);

    tools->addWidget(new QLabel(tr("  Radius: "), tools));
    auto *radiusBox = new QSpinBox(tools);
    radiusBox->setRange(1, 200);
    radiusBox->setValue(m_canvas->penRadius());
    connect(radiusBox, &QSpinBox::valueChanged, this, [this](int v) { m_canvas->setPenRadius(v); });
    tools->addWidget(radiusBox);

    // --- Metadata dock ---
    auto *dock = new QDockWidget(tr("PNG Text Metadata"), this);
    dock->setWidget(m_metadata);
    dock->setAllowedAreas(Qt::RightDockWidgetArea | Qt::LeftDockWidgetArea);
    addDockWidget(Qt::RightDockWidgetArea, dock);

    resize(1100, 720);
}

void MainWindow::updateTitle() {
    const QString name = m_currentPath.isEmpty() ? tr("Untitled")
                                                 : QFileInfo(m_currentPath).fileName();
    const QString marker = m_canvas->isModified() ? QStringLiteral("*") : QString();
    setWindowTitle(tr("%1%2 — PNG Editor (Qt)").arg(name, marker));
}

void MainWindow::newFile() {
    if (!maybeSave())
        return;
    m_canvas->newImage(QSize(800, 600));
    m_metadata->loadFrom(m_canvas->image());
    m_currentPath.clear();
    updateTitle();
}

void MainWindow::openFile() {
    if (!maybeSave())
        return;
    const QString path = QFileDialog::getOpenFileName(
        this, tr("Open PNG"), QString(), tr("PNG Images (*.png)"));
    if (path.isEmpty())
        return;
    if (!m_canvas->loadImage(path)) {
        QMessageBox::warning(this, tr("Open Failed"), tr("Could not load %1").arg(path));
        return;
    }
    m_metadata->loadFrom(m_canvas->image());
    m_currentPath = path;
    updateTitle();
}

bool MainWindow::writeTo(const QString &path) {
    if (!m_canvas->saveImage(path, m_metadata->values())) {
        QMessageBox::warning(this, tr("Save Failed"), tr("Could not save %1").arg(path));
        return false;
    }
    m_currentPath = path;
    updateTitle();
    return true;
}

bool MainWindow::saveFile() {
    if (m_currentPath.isEmpty())
        return saveFileAs();
    return writeTo(m_currentPath);
}

bool MainWindow::saveFileAs() {
    QString path = QFileDialog::getSaveFileName(
        this, tr("Save PNG"), m_currentPath.isEmpty() ? QStringLiteral("untitled.png") : m_currentPath,
        tr("PNG Images (*.png)"));
    if (path.isEmpty())
        return false;
    if (!path.endsWith(".png", Qt::CaseInsensitive))
        path += ".png";
    return writeTo(path);
}

void MainWindow::chooseColor() {
    const QColor color = QColorDialog::getColor(m_canvas->penColor(), this, tr("Pen Color"));
    if (color.isValid())
        m_canvas->setPenColor(color);
}

bool MainWindow::maybeSave() {
    if (!m_canvas->isModified())
        return true;
    const auto choice = QMessageBox::warning(
        this, tr("Unsaved Changes"),
        tr("The image has unsaved changes. Save them?"),
        QMessageBox::Save | QMessageBox::Discard | QMessageBox::Cancel);
    if (choice == QMessageBox::Save)
        return saveFile();
    return choice == QMessageBox::Discard;
}

void MainWindow::closeEvent(QCloseEvent *event) {
    if (maybeSave())
        event->accept();
    else
        event->ignore();
}
