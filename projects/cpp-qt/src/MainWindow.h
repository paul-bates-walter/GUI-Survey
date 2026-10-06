#pragma once

#include <QMainWindow>
#include <QString>

class CanvasWidget;
class MetadataPanel;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget *parent = nullptr);

protected:
    void closeEvent(QCloseEvent *event) override;

private slots:
    void newFile();
    void openFile();
    bool saveFile();
    bool saveFileAs();
    void chooseColor();

private:
    void buildUi();
    void updateTitle();
    bool maybeSave();
    bool writeTo(const QString &path);

    CanvasWidget *m_canvas = nullptr;
    MetadataPanel *m_metadata = nullptr;
    QString m_currentPath;
};
