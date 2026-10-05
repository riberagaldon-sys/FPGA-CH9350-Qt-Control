#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>
#include <QSerialPort>
#include <QByteArray>
#include <QHash>
#include <QSet>
#include <QVector>
#include <QString>
#include <QtGlobal>

class QGraphicsScene;
class QGraphicsPathItem;
class QGraphicsRectItem;
class QGraphicsLineItem;
class QGraphicsTextItem;
class QGraphicsSimpleTextItem;

class QLabel;
class QWidget;
class QEvent;
class QTimer;
class DcMotorMonitorWidget;
class StepperMonitorWidget;

QT_BEGIN_NAMESPACE
namespace Ui {
class MainWindow;
}
QT_END_NAMESPACE


class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:

    // ===== DC Motor 状态 =====
    bool dcRunning = false;

    int dcDirection = 0;

    int dcPwm = 70;

    // FPGA光电反馈：每个有效脉冲代表转盘转过1/4圈。
    quint32 dcQuarterCount = 0;
    int dcMeasuredRpm = 0;
    bool dcBoardLedOn = false;
    bool dcInterlockActive = false;

    // Qt动画只负责显示，不参与电机控制。
    double dcWheelAngle = 0.0;
    double dcLedBrightness = 0.0;
    DcMotorMonitorWidget *dcMotorMonitor = nullptr;
    QTimer *dcAnimationTimer = nullptr;


    // ===== DC Motor UI刷新 =====
    void updateDcUi();

    void parseDcLine(
        const QString &line
        );

    void updateDcAnimation();

    Ui::MainWindow *ui;

    // ============================================================
    // 串口
    // ============================================================

    QSerialPort *serial;
    QByteArray rxBuffer;


    // ============================================================
    // 鼠标实时图形
    // ============================================================

    QGraphicsScene *mouseScene;

    QGraphicsPathItem *mouseBodyItem;

    QGraphicsRectItem *mouseLeftItem;
    QGraphicsRectItem *mouseRightItem;
    QGraphicsRectItem *mouseWheelItem;

    QGraphicsLineItem *mouseMoveLine;

    QGraphicsTextItem *mouseMoveText;
    QGraphicsTextItem *mouseWheelText;


    // ============================================================
    // FPGA 全窗口虚拟鼠标
    // ============================================================

    QLabel *fpgaCursor;

    double fpgaCursorX;
    double fpgaCursorY;

    bool previousFpgaLeftPressed;

    QWidget *fpgaPressedWidget;


    // ============================================================
    // 虚拟键盘
    // ============================================================

    struct KeyboardKeyVisual
    {
        QGraphicsRectItem *rect = nullptr;

        QGraphicsSimpleTextItem *text = nullptr;

        QString normalText;
        QString shiftText;
    };

    QGraphicsScene *keyboardScene;

    QHash<int, KeyboardKeyVisual> keyboardKeys;

    QGraphicsSimpleTextItem *keyboardStatusText;
    QGraphicsSimpleTextItem *keyboardCapsText;
    QGraphicsSimpleTextItem *virtualKeyText;


    // ============================================================
    // 实体 FPGA USB 键盘状态
    // ============================================================

    QSet<int> previousKeyboardKeys;
    QSet<int> physicalPressedKeys;

    bool capsLockOn;
    bool physicalShiftOn;
    bool virtualShiftOn;

    int virtualPressedHid;


    // ============================================================
    // 实体 FPGA 键盘长按
    // ============================================================

    QTimer *physicalKeyRepeatTimer;

    int physicalRepeatHid;


    // ============================================================
    // 鼠标长按虚拟键盘
    // ============================================================

    QTimer *virtualKeyRepeatTimer;

    int virtualRepeatHid;

    bool virtualCurrentKeyUsedVirtualShift;


    // ============================================================
    // 步进电机 Qt 状态
    //
    // direction:
    //  1 = 正转
    // -1 = 反转
    //  0 = 停止
    // ============================================================

    bool stepperRunning;

    int stepperDirection;

    // 5位开关组成 0~31 共32个位置，一圈32位精度。
    int stepperPosition = 0;
    double stepperAnimationAccumulator = 0.0;
    StepperMonitorWidget *stepperMonitor = nullptr;
    QTimer *stepperAnimationTimer = nullptr;


    // ============================================================
    // FPGA_EC1 Qt 状态
    // ============================================================

    int ec1LastDialValue;

    int ec1Count;

    bool ec1PhysicalPressed;

    QTimer *ec1IdleTimer;


private:

    // ============================================================
    // 串口
    // ============================================================

    void refreshPorts();

    void toggleSerial();

    void readSerialData();

    void sendControlCommand(
        const QString &command
        );


    // ============================================================
    // FPGA 鼠标
    // ============================================================

    void parseMouseLine(
        const QString &line
        );

    void updateMouseButtonDisplay(
        int button
        );

    void initMouseGraphics();

    void updateMouseGraphics(
        int button,
        int dx,
        int dy,
        int wheel
        );


    // ============================================================
    // FPGA 全窗口鼠标
    // ============================================================

    void initFpgaCursor();

    void updateFpgaCursor(
        int dx,
        int dy
        );

    QWidget *findWidgetUnderFpgaCursor();

    void handleFpgaMouseButton(
        int button
        );

    void sendFpgaMouseMoveToPressedWidget();


    // ============================================================
    // FPGA / 虚拟键盘
    // ============================================================

    void parseKeyboardLine(
        const QString &line
        );

    void initKeyboardGraphics();

    void updateKeyboardGraphics(
        int modifier,
        const QVector<int> &keyCodes
        );

    void refreshKeyboardLabels(
        bool shiftPressed
        );

    void refreshKeyboardColors();

    QString keyboardKeyText(
        int hidCode,
        bool shiftPressed
        ) const;


    // ============================================================
    // Physical FPGA_EC1
    // ============================================================

    void parseEc1Line(
        const QString &line
        );


    // ============================================================
    // 文本输入
    // ============================================================

    bool textInputHasFocus() const;

    bool isRepeatableTextKey(
        int hidCode
        ) const;

    void applyTextKey(
        int hidCode,
        bool shiftPressed
        );

    void inputFpgaKeyboardToText(
        const QVector<int> &keyCodes
        );

    void inputVirtualKeyToText(
        int hidCode,
        bool shiftPressed
        );


    // ============================================================
    // 键盘长按
    // ============================================================

    void startPhysicalKeyRepeat(
        int hidCode
        );

    void stopPhysicalKeyRepeat();

    void startVirtualKeyRepeat(
        int hidCode,
        bool usedVirtualShift
        );

    void stopVirtualKeyRepeat();


    // ============================================================
    // 板载模块 Qt 控制
    // ============================================================

    void initBoardControlUi();

    void updateStepperUi();
    void updateStepperAnimation();

    void updateEc1Ui();
};

#endif // MAINWINDOW_H
