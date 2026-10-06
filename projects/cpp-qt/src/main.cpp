#include "MainWindow.h"

#include <QApplication>

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("PNG Editor (Qt)"));
    QApplication::setOrganizationName(QStringLiteral("Desktop GUI Survey"));

    MainWindow window;
    window.show();
    return app.exec();
}
