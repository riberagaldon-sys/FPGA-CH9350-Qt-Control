#include "mainwindow.h"
#include "ui_mainwindow.h"

#include <QSerialPortInfo>
#include <QRegularExpression>
#include <QMessageBox>

#include <QPushButton>
#include <QLabel>
#include <QApplication>
#include <QWidget>

#include <QPlainTextEdit>
#include <QTextCursor>

#include <QSlider>
#include <QDial>
#include <QSignalBlocker>

#include <QTimer>

#include <QGraphicsScene>
#include <QGraphicsView>
#include <QGraphicsPathItem>
#include <QGraphicsRectItem>
#include <QGraphicsLineItem>
#include <QGraphicsTextItem>
#include <QGraphicsSimpleTextItem>

#include <QPainterPath>
#include <QPainter>
#include <QPen>
#include <QBrush>
#include <QFont>
#include <QColor>

#include <QMouseEvent>
#include <QEvent>
#include <QPaintEvent>
#include <QGroupBox>
#include <QFrame>

#include <QStringList>

#include <QtGlobal>


// ============================================================================
// 直流电机实时监视图
//
// 轮盘角度由FPGA上报的实测RPM驱动；右上角绿色灯直接镜像FPGA上报
// 的板载光电检测灯电平，包括电机停止后转盘停在槽内/槽外的状态。
// 该控件不使用Q_OBJECT，因此不需要额外运行moc。
// ============================================================================

class DcMotorMonitorWidget : public QWidget
{
public:
    explicit DcMotorMonitorWidget(QWidget *parent = nullptr)
        : QWidget(parent)
    {
        setAttribute(Qt::WA_TransparentForMouseEvents, true);
        setMinimumSize(150, 120);
    }

    void setWheelAngle(double angle)
    {
        wheelAngle = angle;
        update();
    }

    void setLedBrightness(double brightness)
    {
        ledBrightness = qBound(0.0, brightness, 1.0);
        update();
    }

protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter painter(this);
        painter.setRenderHint(QPainter::Antialiasing, true);

        painter.setPen(QPen(QColor(100, 100, 100), 1));
        painter.setBrush(QColor(28, 28, 28, 220));
        painter.drawRoundedRect(rect().adjusted(1, 1, -1, -1), 8, 8);

        const QPointF center(width() * 0.40, height() * 0.57);
        const double radius = qMin(width(), height()) * 0.34;

        painter.save();
        painter.translate(center);
        painter.rotate(wheelAngle);
        painter.setPen(QPen(QColor(220, 220, 220), 3));
        painter.setBrush(QColor(72, 72, 72));
        painter.drawEllipse(QPointF(0, 0), radius, radius);

        for (int i = 0; i < 4; ++i)
        {
            painter.drawLine(QPointF(0, 0), QPointF(0, -radius + 4));
            painter.rotate(90.0);
        }

        painter.setBrush(QColor(180, 180, 180));
        painter.drawEllipse(QPointF(0, 0), 5, 5);
        painter.restore();

        const int green = qRound(35 + 220 * ledBrightness);
        const int alpha = qRound(70 + 185 * ledBrightness);
        painter.setPen(QPen(QColor(80, 80, 80), 1));
        painter.setBrush(QColor(20, green, 35, alpha));
        painter.drawEllipse(QPointF(width() - 18, 17), 8, 8);

        painter.setPen(QColor(185, 185, 185));
        painter.setFont(QFont("Microsoft YaHei", 8));
        painter.drawText(QRect(3, 2, width() - 30, 18),
                         Qt::AlignCenter,
                         QStringLiteral("光电轮盘"));
    }

private:
    double wheelAngle = 0.0;
    double ledBrightness = 0.0;
};


// ============================================================================
// 步进电机 32 位/圈转盘监视图
//
// 5 位开关 S4..S0 组合成 0..31 共 32 个位置。
// 这里只做 Qt 可视化，不改变现有 STEP START/STOP/CW/CCW/SPEED 协议。
// ============================================================================

class StepperMonitorWidget : public QWidget
{
public:
    explicit StepperMonitorWidget(QWidget *parent = nullptr)
        : QWidget(parent)
    {
        setAttribute(Qt::WA_TransparentForMouseEvents, true);
        setMinimumSize(176, 138);
    }

    void setPosition(int value)
    {
        position = ((value % 32) + 32) % 32;
        update();
    }

protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter painter(this);
        painter.setRenderHint(QPainter::Antialiasing, true);

        painter.setPen(QPen(QColor(100, 100, 100), 1));
        painter.setBrush(QColor(28, 28, 28, 225));
        painter.drawRoundedRect(rect().adjusted(1, 1, -1, -1), 9, 9);

        painter.setPen(QColor(210, 210, 210));
        painter.setFont(QFont("Microsoft YaHei", 8));
        painter.drawText(QRect(4, 3, width() - 8, 18),
                         Qt::AlignCenter,
                         QStringLiteral("步进转盘  32位/圈"));

        const QPointF center(width() * 0.34, height() * 0.59);
        const double radius = qMin(width() * 0.54, height() * 0.72) * 0.43;

        painter.setPen(QPen(QColor(205, 205, 205), 2));
        painter.setBrush(QColor(65, 65, 65));
        painter.drawEllipse(center, radius, radius);

        // 32 个位置刻度，每 4 格加粗一次。
        painter.save();
        painter.translate(center);
        for (int i = 0; i < 32; ++i)
        {
            const bool major = (i % 4) == 0;
            painter.setPen(QPen(major ? QColor(235, 235, 235)
                                      : QColor(150, 150, 150),
                                major ? 2.0 : 1.0));
            painter.drawLine(QPointF(0, -radius + 2),
                             QPointF(0, -radius + (major ? 10 : 6)));
            painter.rotate(360.0 / 32.0);
        }
        painter.restore();

        // 当前 0..31 位置指针。
        painter.save();
        painter.translate(center);
        painter.rotate(position * (360.0 / 32.0));
        painter.setPen(QPen(QColor(0, 210, 255), 3));
        painter.drawLine(QPointF(0, 3), QPointF(0, -radius + 12));
        painter.restore();

        painter.setPen(QColor(230, 230, 230));
        painter.setFont(QFont("Microsoft YaHei", 9, QFont::Bold));
        painter.drawText(QRectF(center.x() - 22, center.y() - 10, 44, 20),
                         Qt::AlignCenter,
                         QString::number(position));

        // 5 位开关状态：S4 是最高位，S0 是最低位。
        const int switchX = qRound(width() * 0.63);
        const int switchW = qMax(42, width() - switchX - 8);
        const int topY = 28;
        const int cellH = qMax(18, (height() - topY - 8) / 5);

        painter.setFont(QFont("Microsoft YaHei", 7));
        for (int bit = 4; bit >= 0; --bit)
        {
            const int row = 4 - bit;
            const bool on = ((position >> bit) & 0x01) != 0;
            const QRect cell(switchX, topY + row * cellH, switchW, cellH - 2);

            painter.setPen(QPen(QColor(95, 95, 95), 1));
            painter.setBrush(on ? QColor(35, 190, 95) : QColor(52, 52, 52));
            painter.drawRoundedRect(cell, 4, 4);

            painter.setPen(on ? QColor(255, 255, 255) : QColor(190, 190, 190));
            painter.drawText(cell, Qt::AlignCenter,
                             QString("S%1  %2").arg(bit).arg(on ? 1 : 0));
        }
    }

private:
    int position = 0;
};


// ============================================================================
// 直流电机 PWM 死区边界提示
//
// 红色死区直接画在 QSlider 自己的 groove 上，保证与水平进度条完全重合。
// 这里不再画红色竖线，只在 20% 和 80% 位置画两个黄色向下箭头。
// valueChanged 中仍把实际值硬限制在 20..80。
// ============================================================================

class DcDeadZoneOverlay : public QWidget
{
public:
    explicit DcDeadZoneOverlay(QSlider *slider)
        : QWidget(slider), owner(slider)
    {
        setAttribute(Qt::WA_TransparentForMouseEvents, true);
        setAttribute(Qt::WA_NoSystemBackground, true);
        setAttribute(Qt::WA_TranslucentBackground, true);
        setGeometry(owner->rect());
        owner->installEventFilter(this);
        show();
        raise();
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (watched == owner &&
            (event->type() == QEvent::Resize || event->type() == QEvent::Show))
        {
            setGeometry(owner->rect());
            raise();
        }
        return QWidget::eventFilter(watched, event);
    }

    void paintEvent(QPaintEvent *) override
    {
        QPainter painter(this);
        painter.setRenderHint(QPainter::Antialiasing, true);

        // 红色死区的渐变是按整条 groove 的 0..100% 定位。
        // 因此箭头也直接按控件可见轨道的 20% / 80% 定位，
        // 不再扣除手柄半径，确保箭头尖端与红/灰边界视觉重合。
        const int left = 0;
        const int right = qMax(1, width() - 1);
        const int usable = right - left;

        const int x20 = left + qRound(usable * 0.20);
        const int x80 = left + qRound(usable * 0.80);

        // 箭头位于粗进度条上方，箭尖指向 20% / 80% 边界。
        const int grooveTop = height() / 2 - 6;
        const int tipY = qMax(9, grooveTop - 2);
        const int baseY = qMax(1, tipY - 8);

        auto drawArrow = [&](int x)
        {
            QPainterPath arrow;
            arrow.moveTo(x - 7, baseY);
            arrow.lineTo(x + 7, baseY);
            arrow.lineTo(x, tipY);
            arrow.closeSubpath();

            painter.fillPath(arrow, QColor(255, 193, 7));
            painter.setPen(QPen(QColor(255, 220, 70), 1));
            painter.drawPath(arrow);
        };

        drawArrow(x20);
        drawArrow(x80);
    }

private:
    QSlider *owner = nullptr;
};


// ============================================================================
// 键盘自动重复参数
// ============================================================================

static constexpr int KEY_REPEAT_DELAY_MS =
    450;

static constexpr int KEY_REPEAT_INTERVAL_MS =
    45;


// ============================================================================
// 构造函数
// ============================================================================

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent),

    ui(new Ui::MainWindow),

    serial(new QSerialPort(this)),

    mouseScene(nullptr),

    mouseBodyItem(nullptr),

    mouseLeftItem(nullptr),

    mouseRightItem(nullptr),

    mouseWheelItem(nullptr),

    mouseMoveLine(nullptr),

    mouseMoveText(nullptr),

    mouseWheelText(nullptr),

    fpgaCursor(nullptr),

    fpgaCursorX(0.0),

    fpgaCursorY(0.0),

    previousFpgaLeftPressed(false),

    fpgaPressedWidget(nullptr),

    keyboardScene(nullptr),

    keyboardStatusText(nullptr),

    keyboardCapsText(nullptr),

    virtualKeyText(nullptr),

    capsLockOn(false),

    physicalShiftOn(false),

    virtualShiftOn(false),

    virtualPressedHid(-1),

    physicalKeyRepeatTimer(
        new QTimer(this)
        ),

    physicalRepeatHid(-1),

    virtualKeyRepeatTimer(
        new QTimer(this)
        ),

    virtualRepeatHid(-1),

    virtualCurrentKeyUsedVirtualShift(false),

    stepperRunning(false),

    stepperDirection(0),

    dcRunning(false),

    dcDirection(0),

    ec1LastDialValue(50),

    ec1Count(0),

    ec1PhysicalPressed(false),

    ec1IdleTimer(
        new QTimer(this)
        )
{
    ui->setupUi(this);


    // ============================================================
    // 标题
    // ============================================================

    setWindowTitle(
        "CH9350L FPGA PC Terminal"
        );


    // ============================================================
    // 波特率
    // ============================================================

    ui->comboBaud->clear();

    ui->comboBaud->addItem("9600");
    ui->comboBaud->addItem("19200");
    ui->comboBaud->addItem("38400");
    ui->comboBaud->addItem("57600");
    ui->comboBaud->addItem("115200");
    ui->comboBaud->addItem("300000");

    ui->comboBaud->setCurrentText(
        "115200"
        );


    // ============================================================
    // 鼠标状态初始值
    // ============================================================

    ui->labelLeft->setText(
        "左键：释放"
        );

    ui->labelRight->setText(
        "右键：释放"
        );

    ui->labelMiddle->setText(
        "中键：释放"
        );

    ui->labelMouseX->setText(
        "X：0"
        );

    ui->labelMouseY->setText(
        "Y：0"
        );

    ui->labelWheel->setText(
        "滚轮：0"
        );


    // ============================================================
    // 初始化
    // ============================================================

    initMouseGraphics();

    initKeyboardGraphics();

    initFpgaCursor();

    initBoardControlUi();


    // ============================================================
    // 虚拟键盘接收鼠标事件
    // ============================================================

    ui->graphicsKeyboard
        ->viewport()
        ->installEventFilter(this);

    ui->graphicsKeyboard
        ->setMouseTracking(true);


    // ============================================================
    // FPGA 实体键盘自动重复
    // ============================================================

    physicalKeyRepeatTimer->setSingleShot(
        false
        );


    connect(
        physicalKeyRepeatTimer,
        &QTimer::timeout,

        this,

        [this]()
        {
            if (physicalRepeatHid < 0)
            {
                stopPhysicalKeyRepeat();

                return;
            }


            if (
                !physicalPressedKeys.contains(
                    physicalRepeatHid
                    )
                )
            {
                stopPhysicalKeyRepeat();

                return;
            }


            if (!textInputHasFocus())
            {
                stopPhysicalKeyRepeat();

                return;
            }


            applyTextKey(
                physicalRepeatHid,
                physicalShiftOn
                );


            if (
                physicalKeyRepeatTimer
                    ->interval()
                !=
                KEY_REPEAT_INTERVAL_MS
                )
            {
                physicalKeyRepeatTimer
                    ->setInterval(
                        KEY_REPEAT_INTERVAL_MS
                        );
            }
        }
        );


    // ============================================================
    // 鼠标长按虚拟键盘自动重复
    // ============================================================

    virtualKeyRepeatTimer->setSingleShot(
        false
        );


    connect(
        virtualKeyRepeatTimer,
        &QTimer::timeout,

        this,

        [this]()
        {
            if (virtualRepeatHid < 0)
            {
                stopVirtualKeyRepeat();

                return;
            }


            bool shiftState =
                physicalShiftOn
                ||
                virtualCurrentKeyUsedVirtualShift;


            applyTextKey(
                virtualRepeatHid,
                shiftState
                );


            if (
                virtualKeyRepeatTimer
                    ->interval()
                !=
                KEY_REPEAT_INTERVAL_MS
                )
            {
                virtualKeyRepeatTimer
                    ->setInterval(
                        KEY_REPEAT_INTERVAL_MS
                        );
            }
        }
        );


    // ============================================================
    // 串口
    // ============================================================

    connect(
        ui->btnRefresh,
        &QPushButton::clicked,
        this,
        &MainWindow::refreshPorts
        );


    connect(
        ui->btnOpen,
        &QPushButton::clicked,
        this,
        &MainWindow::toggleSerial
        );


    connect(
        serial,
        &QSerialPort::readyRead,
        this,
        &MainWindow::readSerialData
        );

    connect(
        ui->btnSendTest,
        &QPushButton::clicked,
        this,
        [this]()
        {
            if (!serial->isOpen())
            {
                QMessageBox::warning(
                    this,
                    "提示",
                    "请先打开串口"
                    );

                return;
            }

            serial->write("TEST\r\n");

            ui->textReceive->appendPlainText(
                "PC TX: TEST"
                );
        }
        );

    refreshPorts();


    refreshPorts();
}


// ============================================================================
// 析构函数
// ============================================================================

MainWindow::~MainWindow()
{
    if (serial->isOpen())
    {
        serial->close();
    }


    delete ui;
}

void MainWindow::updateDcUi()
{

    QString dir;


    if(dcDirection > 0)
    {
        dir = "正转";
    }
    else if(dcDirection < 0)
    {
        dir = "反转";
    }
    else
    {
        dir = "停止";
    }


    QString state;


    if(dcInterlockActive)
    {
        state = "换向保护（停机3秒）";
    }
    else if(dcRunning)
    {
        state = "运行";
    }
    else
    {
        state = "停止";
    }


    ui->labelDcDirection->setText(
        QString("方向: %1    圈数: %2 + %3/4")
            .arg(dir)
            .arg(dcQuarterCount / 4)
            .arg(dcQuarterCount % 4)
        );


    ui->labelDcStatus->setText(
        QString("状态: %1    1/4计数: %2")
            .arg(state)
            .arg(dcQuarterCount)
        );


    ui->labelDcSpeed->setText(
        QString("PWM: %1%  [限20~80%]    实测: %2 RPM")
            .arg(dcPwm)
            .arg(dcMeasuredRpm)
        );

    if (dcMotorMonitor)
    {
        dcMotorMonitor->setLedBrightness(dcLedBrightness);
    }

}


// ============================================================================
// FPGA直流电机光电反馈解析
//
// FPGA格式：D Q=00000019 R=0120 P=050 L=1 I=0 S=1 D=1
// Q为十六进制累计1/4圈计数；R为实测RPM；L为板上DC_MOTOR_LED状态。
// ============================================================================

void MainWindow::parseDcLine(const QString &line)
{
    static const QRegularExpression pattern(
        QStringLiteral(
            "^D\\s+Q=([0-9A-Fa-f]{8})\\s+R=([0-9]{4})\\s+"
            "P=([0-9]{3})\\s+L=([01])\\s+I=([01])\\s+"
            "S=([01])\\s+D=([012])$"
            )
        );

    const QRegularExpressionMatch match = pattern.match(line);

    if (!match.hasMatch())
    {
        return;
    }

    bool countOk = false;
    bool rpmOk = false;
    bool pwmOk = false;

    const quint32 newQuarterCount =
        match.captured(1).toUInt(&countOk, 16);
    const int newRpm =
        match.captured(2).toInt(&rpmOk, 10);
    const int newPwm =
        match.captured(3).toInt(&pwmOk, 10);

    if (!countOk || !rpmOk || !pwmOk)
    {
        return;
    }

    dcQuarterCount = newQuarterCount;
    dcMeasuredRpm = newRpm;
    dcBoardLedOn = (match.captured(4) == "1");
    dcInterlockActive = (match.captured(5) == "1");
    dcRunning = (match.captured(6) == "1");

    const int appliedDirection = match.captured(7).toInt();
    dcDirection =
        (appliedDirection == 1) ? 1 :
            (appliedDirection == 2) ? -1 : 0;

    dcPwm = qBound(20, newPwm, 80);

    // FPGA返回值是最终实际设定值。阻断信号，避免回写一条新的PWM命令。
    {
        const QSignalBlocker blocker(ui->sliderDcSpeed);
        ui->sliderDcSpeed->setValue(dcPwm);
    }

    // 不做余辉、不根据计数猜测灯状态；L=1就亮，L=0就灭。
    // 因此电机停止时，Qt灯会保持与板上检测灯完全相同的最终状态。
    dcLedBrightness = dcBoardLedOn ? 1.0 : 0.0;

    updateDcUi();
}


// ============================================================================
// 直流电机轮盘与LED动画
// ============================================================================

void MainWindow::updateDcAnimation()
{
    // 定时器周期30 ms。RPM转为角速度：1 RPM = 6度/秒。
    const double directionSign = (dcDirection < 0) ? -1.0 : 1.0;

    if (dcRunning && !dcInterlockActive && dcMeasuredRpm > 0)
    {
        dcWheelAngle +=
            directionSign * static_cast<double>(dcMeasuredRpm) * 6.0 * 0.030;

        while (dcWheelAngle >= 360.0)
            dcWheelAngle -= 360.0;

        while (dcWheelAngle < 0.0)
            dcWheelAngle += 360.0;
    }

    // 绿色灯只显示FPGA最近一次上报的实际检测电平。这样在停止后
    // 不会被动画定时器自行熄灭，也不会因1/4计数变化而虚假点亮。
    dcLedBrightness = dcBoardLedOn ? 1.0 : 0.0;

    if (dcMotorMonitor)
    {
        dcMotorMonitor->setWheelAngle(dcWheelAngle);
        dcMotorMonitor->setLedBrightness(dcLedBrightness);
    }
}


// ============================================================================
// 初始化板载模块 Qt 控件
// ============================================================================

void MainWindow::initBoardControlUi()
{
    // ========================================================================
    // 公共外观：步进电机、直流电机的 Horizontal Line / 横向控件加宽
    // ========================================================================

    auto findParentGroup = [](QWidget *widget) -> QGroupBox *
    {
        QWidget *p = widget;
        while (p)
        {
            if (QGroupBox *group = qobject_cast<QGroupBox *>(p))
            {
                return group;
            }
            p = p->parentWidget();
        }
        return nullptr;
    };

    auto widenHorizontalLines = [](QGroupBox *group)
    {
        if (!group)
        {
            return;
        }

        const QList<QFrame *> frames = group->findChildren<QFrame *>();
        for (QFrame *frame : frames)
        {
            if (frame->frameShape() != QFrame::HLine)
            {
                continue;
            }

            frame->setLineWidth(2);
            frame->setMidLineWidth(1);

            // 没有布局时直接向左右各扩一点；有布局时提高最小宽度。
            QWidget *parent = frame->parentWidget();
            if (parent && !parent->layout())
            {
                QRect g = frame->geometry();
                const int newLeft = qMax(8, g.left() - 20);
                const int newRight = qMin(parent->width() - 8, g.right() + 20);
                if (newRight > newLeft)
                {
                    frame->setGeometry(newLeft, g.y(), newRight - newLeft + 1,
                                       qMax(4, g.height()));
                }
            }
            else
            {
                frame->setMinimumWidth(qMax(frame->minimumWidth(), 220));
            }
        }
    };

    // 两条横向速度控件加长并明显加粗。
    ui->sliderStepperSpeed->setMinimumWidth(
        qMax(ui->sliderStepperSpeed->minimumWidth(), 230));
    ui->sliderDcSpeed->setMinimumWidth(
        qMax(ui->sliderDcSpeed->minimumWidth(), 230));

    ui->sliderStepperSpeed->setMinimumHeight(
        qMax(ui->sliderStepperSpeed->minimumHeight(), 30));
    ui->sliderDcSpeed->setMinimumHeight(
        qMax(ui->sliderDcSpeed->minimumHeight(), 30));

    // 步进电机速度条：10px 粗轨道 + 明显圆形手柄。
    const QString originalStepperSliderStyle =
        ui->sliderStepperSpeed->styleSheet();

    ui->sliderStepperSpeed->setStyleSheet(
        originalStepperSliderStyle +
        QStringLiteral(
            "QSlider::groove:horizontal {"
            "height:10px;"
            "border-radius:5px;"
            "background:#666666;"
            "}"
            "QSlider::sub-page:horizontal {"
            "height:10px;"
            "border-radius:5px;"
            "background:#1E9FE6;"
            "}"
            "QSlider::add-page:horizontal {"
            "height:10px;"
            "border-radius:5px;"
            "background:#666666;"
            "}"
            "QSlider::handle:horizontal {"
            "background:#D8D8D8;"
            "border:2px solid #4B4B4B;"
            "width:18px;"
            "height:18px;"
            "margin:-5px 0;"
            "border-radius:9px;"
            "}"
            )
        );

    QGroupBox *stepperGroup = findParentGroup(ui->sliderStepperSpeed);
    QGroupBox *dcGroup = findParentGroup(ui->sliderDcSpeed);
    widenHorizontalLines(stepperGroup);
    widenHorizontalLines(dcGroup);


    // ========================================================================
    // 步进电机
    // ========================================================================

    ui->sliderStepperSpeed->setRange(
        1,
        10
        );

    ui->sliderStepperSpeed->setValue(
        5
        );

    stepperRunning = false;
    stepperDirection = 0;
    stepperPosition = 0;
    stepperAnimationAccumulator = 0.0;

    // 在步进电机区域加入较大的 32 位/圈转盘。
    if (stepperGroup)
    {
        stepperMonitor = new StepperMonitorWidget(stepperGroup);

        const int monitorW = qMin(190, qMax(176, stepperGroup->width() / 2));
        const int monitorH = 145;
        const int monitorX = qMax(8, stepperGroup->width() - monitorW - 12);
        const int monitorY = qMax(45, stepperGroup->height() - monitorH - 10);

        stepperMonitor->setGeometry(monitorX, monitorY, monitorW, monitorH);
        stepperMonitor->setPosition(stepperPosition);
        stepperMonitor->show();
    }

    stepperAnimationTimer = new QTimer(this);
    stepperAnimationTimer->setInterval(30);

    connect(
        stepperAnimationTimer,
        &QTimer::timeout,
        this,
        &MainWindow::updateStepperAnimation
        );

    stepperAnimationTimer->start();

    updateStepperUi();


    connect(
        ui->btnStepperStart,
        &QPushButton::clicked,
        this,
        [this]()
        {
            if (stepperDirection == 0)
            {
                stepperDirection = 1;
            }

            stepperRunning = true;
            updateStepperUi();

            sendControlCommand(
                "STEP START"
                );
        }
        );


    connect(
        ui->btnStepperStop,
        &QPushButton::clicked,
        this,
        [this]()
        {
            stepperRunning = false;
            stepperDirection = 0;
            stepperAnimationAccumulator = 0.0;

            updateStepperUi();

            sendControlCommand(
                "STEP STOP"
                );
        }
        );


    connect(
        ui->btnStepperCW,
        &QPushButton::clicked,
        this,
        [this]()
        {
            stepperDirection = 1;
            updateStepperUi();

            sendControlCommand(
                "STEP CW"
                );
        }
        );


    connect(
        ui->btnStepperCCW,
        &QPushButton::clicked,
        this,
        [this]()
        {
            stepperDirection = -1;
            updateStepperUi();

            sendControlCommand(
                "STEP CCW"
                );
        }
        );


    connect(
        ui->sliderStepperSpeed,
        &QSlider::valueChanged,
        this,
        [this](int value)
        {
            updateStepperUi();

            sendControlCommand(
                QString(
                    "STEP SPEED %1"
                    )
                    .arg(value)
                );
        }
        );


    // ========================================================================
    // 直流电机
    // ========================================================================

    // 保留 0..100 的视觉比例用于显示红色死区，但是软件硬限制 20..80。
    ui->sliderDcSpeed->setRange(
        0,
        100
        );

    ui->sliderDcSpeed->setValue(
        70
        );

    dcPwm = 70;
    dcRunning = false;
    dcDirection = 0;

    // 0..20% 与 80..100% 的红色死区直接作为 groove 背景，
    // 不再额外叠一条红色矩形，因此会与水平进度条完全重合。
    // 同时显式定义 handle，保证直流电机拖动圆点始终可见。
    const QString originalDcSliderStyle = ui->sliderDcSpeed->styleSheet();
    ui->sliderDcSpeed->setStyleSheet(
        originalDcSliderStyle +
        QStringLiteral(
            "QSlider::groove:horizontal {"
            "height:12px;"
            "border-radius:6px;"
            "background:qlineargradient(x1:0,y1:0,x2:1,y2:0,"
            "stop:0 #B52B2B,"
            "stop:0.20 #B52B2B,"
            "stop:0.201 #676767,"
            "stop:0.799 #676767,"
            "stop:0.80 #B52B2B,"
            "stop:1 #B52B2B);"
            "}"
            "QSlider::sub-page:horizontal {"
            "background:transparent;"
            "}"
            "QSlider::add-page:horizontal {"
            "background:transparent;"
            "}"
            "QSlider::handle:horizontal {"
            "background:#E0E0E0;"
            "border:2px solid #4A4A4A;"
            "width:18px;"
            "height:18px;"
            "margin:-4px 0;"
            "border-radius:9px;"
            "}"
            )
        );

    // 覆盖层现在只画 20% / 80% 两个黄色箭头，不画任何红色竖线。
    new DcDeadZoneOverlay(ui->sliderDcSpeed);

    // 在原有直流电机 GroupBox 右下角进一步放大光电轮盘。
    dcMotorMonitor =
        new DcMotorMonitorWidget(
            ui->groupDcMotor
            );

    const int dcMonitorW = 185;
    const int dcMonitorH = 150;
    dcMotorMonitor->setGeometry(
        qMax(8, ui->groupDcMotor->width() - dcMonitorW - 10),
        qMax(42, ui->groupDcMotor->height() - dcMonitorH - 8),
        dcMonitorW,
        dcMonitorH
        );

    dcMotorMonitor->show();

    dcAnimationTimer = new QTimer(this);
    dcAnimationTimer->setInterval(30);

    connect(
        dcAnimationTimer,
        &QTimer::timeout,
        this,
        &MainWindow::updateDcAnimation
        );

    dcAnimationTimer->start();

    updateDcUi();


    connect(
        ui->btnDcStart,
        &QPushButton::clicked,
        this,
        [this]()
        {
            dcRunning = true;
            updateDcUi();

            sendControlCommand(
                "DC START"
                );
        }
        );


    connect(
        ui->btnDcStop,
        &QPushButton::clicked,
        this,
        [this]()
        {
            dcRunning = false;
            updateDcUi();

            sendControlCommand(
                "DC STOP"
                );
        }
        );


    connect(
        ui->btnDcForward,
        &QPushButton::clicked,
        this,
        [this]()
        {
            dcDirection = 1;
            updateDcUi();

            sendControlCommand(
                "DC FWD"
                );
        }
        );


    connect(
        ui->btnDcReverse,
        &QPushButton::clicked,
        this,
        [this]()
        {
            dcDirection = -1;
            updateDcUi();

            sendControlCommand(
                "DC REV"
                );
        }
        );


    connect(
        ui->sliderDcSpeed,
        &QSlider::valueChanged,
        this,
        [this](int value)
        {
            // 硬死区：拖到20%或80%后不能继续。黄色箭头仅作边界提示。
            const int boundedValue = qBound(20, value, 80);

            if (boundedValue != value)
            {
                const QSignalBlocker blocker(ui->sliderDcSpeed);
                ui->sliderDcSpeed->setValue(boundedValue);
            }

            if (dcPwm == boundedValue)
            {
                updateDcUi();
                return;
            }

            dcPwm = boundedValue;
            updateDcUi();

            sendControlCommand(
                QString("DC PWM %1")
                    .arg(boundedValue)
                );
        }
        );


    // ========================================================================
    // FPGA_EC1
    // ========================================================================

    ui->dialEc1->setRange(
        0,
        100
        );


    ui->dialEc1->setWrapping(
        true
        );


    ui->dialEc1->setValue(
        50
        );


    ec1LastDialValue =
        ui->dialEc1->value();


    ec1Count =
        0;


    ui->labelEc1Value->setText(
        "计数值：0"
        );


    ui->labelEc1Direction->setText(
        "方向：停止"
        );


    ui->labelEc1Key->setText(
        "按键：释放"
        );


    ui->labelEc1Status->setText(
        "状态：等待"
        );


    // ============================================================
    // EC1 停止旋转检测
    // ============================================================

    ec1IdleTimer->setSingleShot(
        true
        );


    ec1IdleTimer->setInterval(
        250
        );


    connect(
        ec1IdleTimer,
        &QTimer::timeout,

        this,

        [this]()
        {
            ui->labelEc1Direction
                ->setText(
                    "方向：停止"
                    );


            if (
                !ec1PhysicalPressed &&
                !ui->btnEc1Press
                     ->isDown()
                )
            {
                ui->labelEc1Status
                    ->setText(
                        "状态：等待"
                        );
            }
        }
        );


    // ============================================================
    // EC1 Dial 转动
    // ============================================================

    connect(
        ui->dialEc1,
        &QDial::valueChanged,

        this,

        [this](int newValue)
        {
            // Dial 范围 0~100，一共 101 个位置
            const int rangeSize =
                101;


            int delta =
                newValue
                -
                ec1LastDialValue;


            // ====================================================
            // 处理 wrapping
            //
            // 100 -> 0：
            // 应当认为 +1
            //
            // 0 -> 100：
            // 应当认为 -1
            // ====================================================

            if (delta > 50)
            {
                delta -=
                    rangeSize;
            }
            else if (delta < -50)
            {
                delta +=
                    rangeSize;
            }


            if (delta > 0)
            {
                ui->labelEc1Direction
                    ->setText(
                        "方向：顺时针"
                        );


                ui->labelEc1Status
                    ->setText(
                        "状态：旋转"
                        );


                ec1Count +=
                    delta;
            }
            else if (delta < 0)
            {
                ui->labelEc1Direction
                    ->setText(
                        "方向：逆时针"
                        );


                ui->labelEc1Status
                    ->setText(
                        "状态：旋转"
                        );


                ec1Count +=
                    delta;
            }


            ec1LastDialValue =
                newValue;


            updateEc1Ui();


            ec1IdleTimer->start();
        }
        );


    // ============================================================
    // EC1 按下
    // ============================================================

    connect(
        ui->btnEc1Press,
        &QPushButton::pressed,

        this,

        [this]()
        {
            ui->labelEc1Key
                ->setText(
                    "按键：按下"
                    );


            ui->labelEc1Status
                ->setText(
                    "状态：触发"
                    );
        }
        );


    // ============================================================
    // EC1 松开
    // ============================================================

    connect(
        ui->btnEc1Press,
        &QPushButton::released,

        this,

        [this]()
        {
            ui->labelEc1Key
                ->setText(
                    "按键：释放"
                    );


            ui->labelEc1Status
                ->setText(
                    "状态：等待"
                    );
        }
        );
}


// ============================================================================
// 更新步进电机显示
// ============================================================================

void MainWindow::updateStepperUi()
{
    ui->labelStepperSpeed
        ->setText(
            QString(
                "速度：%1    位置：%2/31"
                )
                .arg(
                    ui->sliderStepperSpeed
                        ->value()
                    )
                .arg(stepperPosition)
            );


    if (stepperDirection > 0)
    {
        ui->labelStepperDirection
            ->setText(
                "方向：正转"
                );
    }
    else if (stepperDirection < 0)
    {
        ui->labelStepperDirection
            ->setText(
                "方向：反转"
                );
    }
    else
    {
        ui->labelStepperDirection
            ->setText(
                "方向：停止"
                );
    }


    ui->labelStepperStatus
        ->setText(
            stepperRunning
                ?
                "状态：运行    5位开关=32位/圈"
                :
                "状态：停止    5位开关=32位/圈"
            );

    if (stepperMonitor)
    {
        stepperMonitor->setPosition(stepperPosition);
    }
}


// ============================================================================
// 步进电机 Qt 转盘动画
//
// 一圈固定 32 个位置；5位开关显示当前位置的二进制值。
// 当前 FPGA 协议没有绝对位置回传，所以这里仅根据已发送的运行/方向/速度
// 命令做界面动画，不参与电机控制。
// ============================================================================

void MainWindow::updateStepperAnimation()
{
    if (!stepperRunning || stepperDirection == 0)
    {
        return;
    }

    const int speed = qBound(1, ui->sliderStepperSpeed->value(), 10);

    // 速度1约2步/秒，速度10约15.5步/秒；每步对应1/32圈。
    const double stepsPerSecond = 0.5 + static_cast<double>(speed) * 1.5;
    stepperAnimationAccumulator += stepsPerSecond * 0.030;

    bool changed = false;
    while (stepperAnimationAccumulator >= 1.0)
    {
        stepperAnimationAccumulator -= 1.0;
        stepperPosition += (stepperDirection > 0) ? 1 : -1;
        stepperPosition = ((stepperPosition % 32) + 32) % 32;
        changed = true;
    }

    if (changed)
    {
        updateStepperUi();
    }
}


// ============================================================================
// 更新 EC1 显示
// ============================================================================

void MainWindow::updateEc1Ui()
{
    ui->labelEc1Value
        ->setText(
            QString(
                "计数值：%1"
                )
                .arg(
                    ec1Count
                    )
            );
}


// ============================================================================
// 判断文本框是否拥有焦点
// ============================================================================

bool MainWindow::textInputHasFocus() const
{
    QWidget *focusWidget =
        QApplication::focusWidget();


    if (!focusWidget)
    {
        return false;
    }


    if (
        focusWidget ==
        ui->editTextInput
        )
    {
        return true;
    }


    if (
        ui->editTextInput
            ->isAncestorOf(
                focusWidget
                )
        )
    {
        return true;
    }


    return false;
}


// ============================================================================
// 判断是否支持自动重复
// ============================================================================

bool MainWindow::isRepeatableTextKey(
    int hidCode
    ) const
{
    if (
        hidCode >= 0x04 &&
        hidCode <= 0x27
        )
    {
        return true;
    }


    switch (hidCode)
    {
    case 0x28: // Enter
    case 0x2A: // Backspace
    case 0x2B: // Tab
    case 0x2C: // Space

    case 0x2D:
    case 0x2E:
    case 0x2F:
    case 0x30:
    case 0x31:
    case 0x33:
    case 0x34:
    case 0x35:
    case 0x36:
    case 0x37:
    case 0x38:

    case 0x4A: // Home
    case 0x4C: // Delete
    case 0x4D: // End

    case 0x4F: // Right
    case 0x50: // Left
    case 0x51: // Down
    case 0x52: // Up

        return true;

    default:

        break;
    }


    return false;
}


// ============================================================================
// 执行一个文本按键
// ============================================================================

void MainWindow::applyTextKey(
    int hidCode,
    bool shiftPressed
    )
{
    QTextCursor cursor =
        ui->editTextInput
            ->textCursor();


    // Enter
    if (hidCode == 0x28)
    {
        cursor.insertBlock();
    }

    // Backspace
    else if (hidCode == 0x2A)
    {
        if (cursor.hasSelection())
        {
            cursor.removeSelectedText();
        }
        else
        {
            cursor.deletePreviousChar();
        }
    }

    // Tab
    else if (hidCode == 0x2B)
    {
        cursor.insertText(
            "\t"
            );
    }

    // Space
    else if (hidCode == 0x2C)
    {
        cursor.insertText(
            " "
            );
    }

    // Delete
    else if (hidCode == 0x4C)
    {
        if (cursor.hasSelection())
        {
            cursor.removeSelectedText();
        }
        else
        {
            cursor.deleteChar();
        }
    }

    // Left
    else if (hidCode == 0x50)
    {
        cursor.movePosition(
            QTextCursor::Left
            );
    }

    // Right
    else if (hidCode == 0x4F)
    {
        cursor.movePosition(
            QTextCursor::Right
            );
    }

    // Up
    else if (hidCode == 0x52)
    {
        cursor.movePosition(
            QTextCursor::Up
            );
    }

    // Down
    else if (hidCode == 0x51)
    {
        cursor.movePosition(
            QTextCursor::Down
            );
    }

    // Home
    else if (hidCode == 0x4A)
    {
        cursor.movePosition(
            QTextCursor::StartOfLine
            );
    }

    // End
    else if (hidCode == 0x4D)
    {
        cursor.movePosition(
            QTextCursor::EndOfLine
            );
    }

    else
    {
        bool printable =
            (
                hidCode >= 0x04 &&
                hidCode <= 0x27
                )
            ||
            hidCode == 0x2D
            ||
            hidCode == 0x2E
            ||
            hidCode == 0x2F
            ||
            hidCode == 0x30
            ||
            hidCode == 0x31
            ||
            hidCode == 0x33
            ||
            hidCode == 0x34
            ||
            hidCode == 0x35
            ||
            hidCode == 0x36
            ||
            hidCode == 0x37
            ||
            hidCode == 0x38;


        if (!printable)
        {
            return;
        }


        QString text =
            keyboardKeyText(
                hidCode,
                shiftPressed
                );


        cursor.insertText(
            text
            );
    }


    ui->editTextInput
        ->setTextCursor(
            cursor
            );


    ui->editTextInput
        ->ensureCursorVisible();
}


// ============================================================================
// 实体 FPGA 键盘输入
// ============================================================================

void MainWindow::inputFpgaKeyboardToText(
    const QVector<int> &keyCodes
    )
{
    if (!textInputHasFocus())
    {
        stopPhysicalKeyRepeat();

        return;
    }


    int newestRepeatKey =
        -1;


    for (
        int code :
        keyCodes
        )
    {
        bool newPress =
            !previousKeyboardKeys.contains(
                code
                );


        if (!newPress)
        {
            continue;
        }


        if (
            !isRepeatableTextKey(
                code
                )
            )
        {
            continue;
        }


        applyTextKey(
            code,
            physicalShiftOn
            );


        newestRepeatKey =
            code;
    }


    if (newestRepeatKey >= 0)
    {
        startPhysicalKeyRepeat(
            newestRepeatKey
            );
    }


    if (
        physicalRepeatHid >= 0 &&
        !physicalPressedKeys.contains(
            physicalRepeatHid
            )
        )
    {
        stopPhysicalKeyRepeat();
    }
}


// ============================================================================
// 虚拟键盘输入
// ============================================================================

void MainWindow::inputVirtualKeyToText(
    int hidCode,
    bool shiftPressed
    )
{
    if (
        !isRepeatableTextKey(
            hidCode
            )
        )
    {
        return;
    }


    applyTextKey(
        hidCode,
        shiftPressed
        );


    ui->editTextInput
        ->setFocus(
            Qt::OtherFocusReason
            );


    ui->editTextInput
        ->ensureCursorVisible();
}


// ============================================================================
// 实体键盘长按开始
// ============================================================================

void MainWindow::startPhysicalKeyRepeat(
    int hidCode
    )
{
    if (
        !isRepeatableTextKey(
            hidCode
            )
        )
    {
        return;
    }


    physicalRepeatHid =
        hidCode;


    physicalKeyRepeatTimer->stop();


    physicalKeyRepeatTimer
        ->setInterval(
            KEY_REPEAT_DELAY_MS
            );


    physicalKeyRepeatTimer->start();
}


// ============================================================================
// 实体键盘长按停止
// ============================================================================

void MainWindow::stopPhysicalKeyRepeat()
{
    physicalKeyRepeatTimer->stop();

    physicalRepeatHid =
        -1;
}


// ============================================================================
// 虚拟键盘长按开始
// ============================================================================

void MainWindow::startVirtualKeyRepeat(
    int hidCode,
    bool usedVirtualShift
    )
{
    if (
        !isRepeatableTextKey(
            hidCode
            )
        )
    {
        return;
    }


    virtualRepeatHid =
        hidCode;


    virtualCurrentKeyUsedVirtualShift =
        usedVirtualShift;


    virtualKeyRepeatTimer->stop();


    virtualKeyRepeatTimer
        ->setInterval(
            KEY_REPEAT_DELAY_MS
            );


    virtualKeyRepeatTimer->start();
}


// ============================================================================
// 虚拟键盘长按停止
// ============================================================================

void MainWindow::stopVirtualKeyRepeat()
{
    virtualKeyRepeatTimer->stop();

    virtualRepeatHid =
        -1;
}


// ============================================================================
// FPGA 蓝色光标初始化
// ============================================================================

void MainWindow::initFpgaCursor()
{
    fpgaCursor =
        new QLabel(
            ui->centralwidget
            );


    fpgaCursor->setFixedSize(
        20,
        20
        );


    fpgaCursor->setStyleSheet(
        "QLabel {"
        "background-color:#00E5FF;"
        "border:2px solid white;"
        "border-radius:10px;"
        "}"
        );


    fpgaCursor->setAttribute(
        Qt::WA_TransparentForMouseEvents,
        true
        );


    fpgaCursorX =
        ui->centralwidget->width()
        /
        2.0;


    fpgaCursorY =
        ui->centralwidget->height()
        /
        2.0;


    fpgaCursor->move(
        static_cast<int>(
            fpgaCursorX - 10.0
            ),

        static_cast<int>(
            fpgaCursorY - 10.0
            )
        );


    fpgaCursor->raise();

    fpgaCursor->show();
}


// ============================================================================
// FPGA 蓝色光标移动
// ============================================================================

void MainWindow::updateFpgaCursor(
    int dx,
    int dy
    )
{
    if (!fpgaCursor)
    {
        return;
    }


    const double sensitivity =
        3.0;


    fpgaCursorX +=
        static_cast<double>(dx)
        *
        sensitivity;


    fpgaCursorY +=
        static_cast<double>(dy)
        *
        sensitivity;


    double maxX =
        ui->centralwidget->width()
        -
        1.0;


    double maxY =
        ui->centralwidget->height()
        -
        1.0;


    if (maxX < 0.0)
    {
        maxX =
            0.0;
    }


    if (maxY < 0.0)
    {
        maxY =
            0.0;
    }


    fpgaCursorX =
        qBound(
            0.0,
            fpgaCursorX,
            maxX
            );


    fpgaCursorY =
        qBound(
            0.0,
            fpgaCursorY,
            maxY
            );


    fpgaCursor->move(
        static_cast<int>(
            fpgaCursorX - 10.0
            ),

        static_cast<int>(
            fpgaCursorY - 10.0
            )
        );


    fpgaCursor->raise();


    // ============================================================
    // FPGA 鼠标按住左键时，
    // 给当前按住的 Qt 控件发送 MouseMove。
    //
    // 这样就能真正拖动：
    //
    // sliderStepperSpeed
    // sliderDcSpeed
    // dialEc1
    // ============================================================

    if (
        previousFpgaLeftPressed &&
        fpgaPressedWidget
        )
    {
        sendFpgaMouseMoveToPressedWidget();
    }
}


// ============================================================================
// FPGA 鼠标按住时发送 MouseMove
// ============================================================================

void MainWindow::sendFpgaMouseMoveToPressedWidget()
{
    if (!fpgaPressedWidget)
    {
        return;
    }


    QPoint centralPoint(
        static_cast<int>(
            fpgaCursorX
            ),

        static_cast<int>(
            fpgaCursorY
            )
        );


    QPoint globalPoint =
        ui->centralwidget
            ->mapToGlobal(
                centralPoint
                );


    QPoint localPoint =
        fpgaPressedWidget
            ->mapFromGlobal(
                globalPoint
                );


    QMouseEvent moveEvent(
        QEvent::MouseMove,

        QPointF(
            localPoint
            ),

        QPointF(
            globalPoint
            ),

        Qt::NoButton,

        Qt::LeftButton,

        Qt::NoModifier
        );


    QApplication::sendEvent(
        fpgaPressedWidget,
        &moveEvent
        );


    if (fpgaCursor)
    {
        fpgaCursor->raise();
    }
}


// ============================================================================
// 找 FPGA 光标下面控件
// ============================================================================

QWidget *MainWindow::findWidgetUnderFpgaCursor()
{
    if (!fpgaCursor)
    {
        return nullptr;
    }


    QPoint centralPoint(
        static_cast<int>(
            fpgaCursorX
            ),

        static_cast<int>(
            fpgaCursorY
            )
        );


    QPoint globalPoint =
        ui->centralwidget
            ->mapToGlobal(
                centralPoint
                );


    fpgaCursor->hide();


    QWidget *target =
        QApplication::widgetAt(
            globalPoint
            );


    fpgaCursor->show();

    fpgaCursor->raise();


    if (!target)
    {
        return nullptr;
    }


    QWidget *check =
        target;


    bool belongsToThisWindow =
        false;


    while (check)
    {
        if (
            check == this ||
            check == ui->centralwidget
            )
        {
            belongsToThisWindow =
                true;

            break;
        }


        check =
            check->parentWidget();
    }


    if (!belongsToThisWindow)
    {
        return nullptr;
    }


    if (!target->isEnabled())
    {
        return nullptr;
    }


    return target;
}


// ============================================================================
// FPGA 鼠标按钮
// ============================================================================

void MainWindow::handleFpgaMouseButton(
    int button
    )
{
    bool leftPressed =
        (
            button &
            0x01
            )
        !=
        0;


    // ========================================================================
    // 左键按下沿
    // ========================================================================

    if (
        leftPressed &&
        !previousFpgaLeftPressed
        )
    {
        QWidget *target =
            findWidgetUnderFpgaCursor();


        fpgaPressedWidget =
            target;


        if (fpgaCursor)
        {
            fpgaCursor->setStyleSheet(
                "QLabel {"
                "background-color:#FF9800;"
                "border:2px solid white;"
                "border-radius:10px;"
                "}"
                );


            fpgaCursor->raise();
        }


        if (target)
        {
            QPoint centralPoint(
                static_cast<int>(
                    fpgaCursorX
                    ),

                static_cast<int>(
                    fpgaCursorY
                    )
                );


            QPoint globalPoint =
                ui->centralwidget
                    ->mapToGlobal(
                        centralPoint
                        );


            QPoint localPoint =
                target
                    ->mapFromGlobal(
                        globalPoint
                        );


            // ====================================================
            // 文本输入框
            // ====================================================

            if (
                target ==
                    ui->editTextInput
                ||
                target ==
                    ui->editTextInput
                        ->viewport()
                )
            {
                ui->editTextInput
                    ->setFocus(
                        Qt::MouseFocusReason
                        );
            }
            else
            {
                QWidget *focusTarget =
                    target;


                while (
                    focusTarget &&
                    focusTarget != this &&
                    focusTarget
                            ->focusPolicy()
                        ==
                        Qt::NoFocus
                    )
                {
                    focusTarget =
                        focusTarget
                            ->parentWidget();
                }


                if (
                    focusTarget &&
                    focusTarget != this
                    )
                {
                    focusTarget
                        ->setFocus(
                            Qt::MouseFocusReason
                            );
                }
            }


            QMouseEvent pressEvent(
                QEvent::MouseButtonPress,

                QPointF(
                    localPoint
                    ),

                QPointF(
                    globalPoint
                    ),

                Qt::LeftButton,

                Qt::LeftButton,

                Qt::NoModifier
                );


            QApplication::sendEvent(
                target,
                &pressEvent
                );
        }
    }


    // ========================================================================
    // 左键释放沿
    // ========================================================================

    if (
        !leftPressed &&
        previousFpgaLeftPressed
        )
    {
        if (fpgaCursor)
        {
            fpgaCursor->setStyleSheet(
                "QLabel {"
                "background-color:#00E5FF;"
                "border:2px solid white;"
                "border-radius:10px;"
                "}"
                );


            fpgaCursor->raise();
        }


        if (fpgaPressedWidget)
        {
            QPoint centralPoint(
                static_cast<int>(
                    fpgaCursorX
                    ),

                static_cast<int>(
                    fpgaCursorY
                    )
                );


            QPoint globalPoint =
                ui->centralwidget
                    ->mapToGlobal(
                        centralPoint
                        );


            QPoint localPoint =
                fpgaPressedWidget
                    ->mapFromGlobal(
                        globalPoint
                        );


            QMouseEvent releaseEvent(
                QEvent::MouseButtonRelease,

                QPointF(
                    localPoint
                    ),

                QPointF(
                    globalPoint
                    ),

                Qt::LeftButton,

                Qt::NoButton,

                Qt::NoModifier
                );


            QApplication::sendEvent(
                fpgaPressedWidget,
                &releaseEvent
                );


            fpgaPressedWidget =
                nullptr;
        }
    }


    previousFpgaLeftPressed =
        leftPressed;
}


// ============================================================================
// 刷新串口
// ============================================================================

void MainWindow::refreshPorts()
{
    QString oldPort =
        ui->comboPort
            ->currentText();


    ui->comboPort->clear();


    const QList<QSerialPortInfo> ports =
        QSerialPortInfo::availablePorts();


    for (
        const QSerialPortInfo &info :
        ports
        )
    {
        ui->comboPort
            ->addItem(
                info.portName()
                );
    }


    int oldIndex =
        ui->comboPort
            ->findText(
                oldPort
                );


    if (oldIndex >= 0)
    {
        ui->comboPort
            ->setCurrentIndex(
                oldIndex
                );
    }


    int com9Index =
        ui->comboPort
            ->findText(
                "COM9"
                );


    if (com9Index >= 0)
    {
        ui->comboPort
            ->setCurrentIndex(
                com9Index
                );
    }
}


// ============================================================================
// 打开 / 关闭串口
// ============================================================================

void MainWindow::toggleSerial()
{
    if (serial->isOpen())
    {
        serial->close();


        stopPhysicalKeyRepeat();

        stopVirtualKeyRepeat();


        ui->btnOpen
            ->setText(
                "打开串口"
                );


        ui->comboPort
            ->setEnabled(
                true
                );


        ui->comboBaud
            ->setEnabled(
                true
                );


        ui->btnRefresh
            ->setEnabled(
                true
                );


        ui->textReceive
            ->appendPlainText(
                "串口已关闭"
                );


        return;
    }


    if (
        ui->comboPort
            ->currentText()
            .isEmpty()
        )
    {
        QMessageBox::warning(
            this,
            "串口错误",
            "没有找到可用串口。"
            );


        return;
    }


    serial->setPortName(
        ui->comboPort
            ->currentText()
        );


    bool baudOk =
        false;


    qint32 baud =
        ui->comboBaud
            ->currentText()
            .toInt(
                &baudOk
                );


    if (!baudOk)
    {
        baud =
            115200;
    }


    serial->setBaudRate(
        baud
        );


    serial->setDataBits(
        QSerialPort::Data8
        );


    serial->setParity(
        QSerialPort::NoParity
        );


    serial->setStopBits(
        QSerialPort::OneStop
        );


    serial->setFlowControl(
        QSerialPort::NoFlowControl
        );


    // 当前仍然是 FPGA -> PC 接收阶段
    if (
        !serial->open(
            QIODevice::ReadWrite
            )
        )
    {
        QMessageBox::critical(
            this,
            "串口打开失败",

            QString(
                "无法打开 %1\n\n%2"
                )
                .arg(
                    ui->comboPort
                        ->currentText()
                    )
                .arg(
                    serial->errorString()
                    )
            );


        return;
    }


    serial->clear();

    rxBuffer.clear();


    ui->btnOpen
        ->setText(
            "关闭串口"
            );


    ui->comboPort
        ->setEnabled(
            false
            );


    ui->comboBaud
        ->setEnabled(
            false
            );


    ui->btnRefresh
        ->setEnabled(
            false
            );


    ui->textReceive
        ->appendPlainText(
            QString(
                "串口打开成功：%1  %2  8N1"
                )
                .arg(
                    ui->comboPort
                        ->currentText()
                    )
                .arg(
                    baud
                    )
            );
}

// ============================================================================
// Qt -> FPGA 控制命令
// ============================================================================

void MainWindow::sendControlCommand(
    const QString &command
    )
{
    if (!serial->isOpen())
    {
        QMessageBox::warning(
            this,
            "提示",
            "请先打开串口"
            );

        return;
    }


    QByteArray data =
        command.toLatin1();


    data.append(
        "\r\n"
        );


    serial->write(
        data
        );


    ui->textReceive->appendPlainText(
        "PC CMD: " + command
        );
}

// ============================================================================
// 串口读取
// ============================================================================

void MainWindow::readSerialData()
{
    rxBuffer.append(
        serial->readAll()
        );


    while (true)
    {
        int newlineIndex =
            rxBuffer.indexOf(
                '\n'
                );


        if (newlineIndex < 0)
        {
            break;
        }


        QByteArray lineData =
            rxBuffer.left(
                newlineIndex
                );


        rxBuffer.remove(
            0,
            newlineIndex + 1
            );


        lineData =
            lineData.trimmed();


        if (
            lineData.isEmpty()
            )
        {
            continue;
        }


        QString line =
            QString::fromLatin1(
                lineData
                );


        if (
            line.startsWith(
                "K "
                )
            )
        {
            ui->textReceive
                ->appendPlainText(
                    "[HEX] " + line
                    );
        }
        else if (
            !line.startsWith(
                "D "
                )
            )
        {
            ui->textReceive
                ->appendPlainText(
                    line
                    );
        }


        parseMouseLine(
            line
            );


        parseKeyboardLine(
            line
            );


        parseEc1Line(
            line
            );


        parseDcLine(
            line
            );
    }
}


// ============================================================================
// Physical FPGA_EC1 parser
//
// FPGA line:
//   E C=+00001 D=+ K=0
//   E C=-00001 D=- K=0
//   E C=+00000 D=0 K=1
//
// C: signed accumulated count
// D: + clockwise, - counter-clockwise, 0 stopped/key event
// K: 1 pressed, 0 released
// ============================================================================

void MainWindow::parseEc1Line(
    const QString &line
    )
{
    static const QRegularExpression ec1Regex(
        R"(^E C=([+-]\d{5}) D=([+\-0]) K=([01])$)"
        );


    const QRegularExpressionMatch match =
        ec1Regex.match(
            line
            );


    if (!match.hasMatch())
    {
        return;
    }


    bool countOk = false;

    const int physicalCount =
        match.captured(1)
            .toInt(
                &countOk
                );


    if (!countOk)
    {
        return;
    }


    const QString directionToken =
        match.captured(2);

    ec1PhysicalPressed =
        (match.captured(3) == "1");

    ec1Count =
        physicalCount;


    // Convert an unbounded signed hardware count into the visual 0..100 dial.
    const int dialValue =
        ((ec1Count % 101) + 101) % 101;


    // Do not feed a physical update back into the existing virtual-dial slot.
    {
        const QSignalBlocker dialBlocker(
            ui->dialEc1
            );

        ui->dialEc1->setValue(
            dialValue
            );
    }


    ec1LastDialValue =
        dialValue;


    // Mirror the physical push switch on the Qt button without emitting the
    // existing virtual-button signals.
    {
        const QSignalBlocker buttonBlocker(
            ui->btnEc1Press
            );

        ui->btnEc1Press->setDown(
            ec1PhysicalPressed
            );
    }


    if (directionToken == "+")
    {
        ui->labelEc1Direction
            ->setText(
                "方向：顺时针"
                );

        ui->labelEc1Status
            ->setText(
                "状态：旋转"
                );

        ec1IdleTimer->start();
    }
    else if (directionToken == "-")
    {
        ui->labelEc1Direction
            ->setText(
                "方向：逆时针"
                );

        ui->labelEc1Status
            ->setText(
                "状态：旋转"
                );

        ec1IdleTimer->start();
    }
    else
    {
        ec1IdleTimer->stop();

        ui->labelEc1Direction
            ->setText(
                "方向：停止"
                );

        ui->labelEc1Status
            ->setText(
                ec1PhysicalPressed
                    ? "状态：触发"
                    : "状态：等待"
                );
    }


    ui->labelEc1Key
        ->setText(
            ec1PhysicalPressed
                ? "按键：按下"
                : "按键：释放"
            );


    updateEc1Ui();
}


// ============================================================================
// FPGA 鼠标解析
//
// M B=01 X=+003 Y=-002 W=+001
// ============================================================================

void MainWindow::parseMouseLine(
    const QString &line
    )
{
    static const QRegularExpression mouseRegex(
        R"(^M B=([0-9A-Fa-f]{2}) X=([+-]\d{3}) Y=([+-]\d{3}) W=([+-]\d{3})$)"
        );


    QRegularExpressionMatch match =
        mouseRegex.match(
            line
            );


    if (!match.hasMatch())
    {
        return;
    }


    bool buttonOk =
        false;

    bool xOk =
        false;

    bool yOk =
        false;

    bool wheelOk =
        false;


    int button =
        match
            .captured(1)
            .toInt(
                &buttonOk,
                16
                );


    int dx =
        match
            .captured(2)
            .toInt(
                &xOk
                );


    int dy =
        match
            .captured(3)
            .toInt(
                &yOk
                );


    int wheel =
        match
            .captured(4)
            .toInt(
                &wheelOk
                );


    if (
        !buttonOk ||
        !xOk ||
        !yOk ||
        !wheelOk
        )
    {
        return;
    }


    updateMouseButtonDisplay(
        button
        );


    ui->labelMouseX
        ->setText(
            QString(
                "X：%1"
                )
                .arg(
                    dx
                    )
            );


    ui->labelMouseY
        ->setText(
            QString(
                "Y：%1"
                )
                .arg(
                    dy
                    )
            );


    ui->labelWheel
        ->setText(
            QString(
                "滚轮：%1"
                )
                .arg(
                    wheel
                    )
            );


    updateMouseGraphics(
        button,
        dx,
        dy,
        wheel
        );


    updateFpgaCursor(
        dx,
        dy
        );


    handleFpgaMouseButton(
        button
        );
}


// ============================================================================
// 鼠标文字状态
// ============================================================================

void MainWindow::updateMouseButtonDisplay(
    int button
    )
{
    bool leftPressed =
        (
            button &
            0x01
            )
        !=
        0;


    bool rightPressed =
        (
            button &
            0x02
            )
        !=
        0;


    bool middlePressed =
        (
            button &
            0x04
            )
        !=
        0;


    ui->labelLeft
        ->setText(
            leftPressed
                ?
                "左键：按下"
                :
                "左键：释放"
            );


    ui->labelLeft
        ->setStyleSheet(
            leftPressed
                ?
                "QLabel {"
                "background:#00AEEF;"
                "color:white;"
                "font-weight:bold;"
                "border-radius:5px;"
                "padding:5px;"
                "}"
                :
                "QLabel {"
                "background:transparent;"
                "color:palette(text);"
                "padding:5px;"
                "}"
            );


    ui->labelRight
        ->setText(
            rightPressed
                ?
                "右键：按下"
                :
                "右键：释放"
            );


    ui->labelRight
        ->setStyleSheet(
            rightPressed
                ?
                "QLabel {"
                "background:#00AEEF;"
                "color:white;"
                "font-weight:bold;"
                "border-radius:5px;"
                "padding:5px;"
                "}"
                :
                "QLabel {"
                "background:transparent;"
                "color:palette(text);"
                "padding:5px;"
                "}"
            );


    ui->labelMiddle
        ->setText(
            middlePressed
                ?
                "中键：按下"
                :
                "中键：释放"
            );


    ui->labelMiddle
        ->setStyleSheet(
            middlePressed
                ?
                "QLabel {"
                "background:#FFC107;"
                "color:black;"
                "font-weight:bold;"
                "border-radius:5px;"
                "padding:5px;"
                "}"
                :
                "QLabel {"
                "background:transparent;"
                "color:palette(text);"
                "padding:5px;"
                "}"
            );
}


// ============================================================================
// 初始化鼠标实时图形
// ============================================================================

void MainWindow::initMouseGraphics()
{
    mouseScene =
        new QGraphicsScene(
            this
            );


    mouseScene->setSceneRect(
        0,
        0,
        280,
        220
        );


    ui->graphicsMouse
        ->setScene(
            mouseScene
            );


    ui->graphicsMouse
        ->setRenderHint(
            QPainter::Antialiasing,
            true
            );


    ui->graphicsMouse
        ->setHorizontalScrollBarPolicy(
            Qt::ScrollBarAlwaysOff
            );


    ui->graphicsMouse
        ->setVerticalScrollBarPolicy(
            Qt::ScrollBarAlwaysOff
            );


    ui->graphicsMouse
        ->setStyleSheet(
            "QGraphicsView {"
            "background:#202124;"
            "border:1px solid #505050;"
            "border-radius:8px;"
            "}"
            );


    QPainterPath body;


    body.moveTo(
        140,
        15
        );


    body.cubicTo(
        85,
        15,
        55,
        40,
        55,
        100
        );


    body.cubicTo(
        55,
        165,
        85,
        195,
        140,
        195
        );


    body.cubicTo(
        195,
        195,
        225,
        165,
        225,
        100
        );


    body.cubicTo(
        225,
        40,
        195,
        15,
        140,
        15
        );


    body.closeSubpath();


    mouseBodyItem =
        mouseScene->addPath(
            body,

            QPen(
                QColor("#B0B0B0"),
                3
                ),

            QBrush(
                QColor("#303236")
                )
            );


    mouseLeftItem =
        mouseScene->addRect(
            70,
            32,
            63,
            58,

            QPen(
                QColor("#707070"),
                1
                ),

            QBrush(
                QColor("#424448")
                )
            );


    mouseRightItem =
        mouseScene->addRect(
            147,
            32,
            63,
            58,

            QPen(
                QColor("#707070"),
                1
                ),

            QBrush(
                QColor("#424448")
                )
            );


    mouseWheelItem =
        mouseScene->addRect(
            132,
            38,
            16,
            45,

            QPen(
                QColor("#A0A0A0"),
                2
                ),

            QBrush(
                QColor("#666666")
                )
            );


    mouseScene->addLine(
        140,
        18,
        140,
        92,

        QPen(
            QColor("#808080"),
            2
            )
        );


    mouseMoveLine =
        mouseScene->addLine(
            140,
            135,
            140,
            135,

            QPen(
                QColor("#40C4FF"),
                4
                )
            );


    mouseMoveText =
        mouseScene->addText(
            "DX:0   DY:0"
            );


    mouseMoveText
        ->setDefaultTextColor(
            QColor("#FFFFFF")
            );


    mouseMoveText
        ->setPos(
            88,
            198
            );


    mouseWheelText =
        mouseScene->addText(
            "Wheel: 0"
            );


    mouseWheelText
        ->setDefaultTextColor(
            QColor("#C0C0C0")
            );


    mouseWheelText
        ->setPos(
            108,
            92
            );
}


// ============================================================================
// 更新鼠标图形
// ============================================================================

void MainWindow::updateMouseGraphics(
    int button,
    int dx,
    int dy,
    int wheel
    )
{
    bool leftPressed =
        (
            button &
            0x01
            )
        !=
        0;


    bool rightPressed =
        (
            button &
            0x02
            )
        !=
        0;


    bool middlePressed =
        (
            button &
            0x04
            )
        !=
        0;


    mouseLeftItem
        ->setBrush(
            QBrush(
                leftPressed
                    ?
                    QColor("#00AEEF")
                    :
                    QColor("#424448")
                )
            );


    mouseRightItem
        ->setBrush(
            QBrush(
                rightPressed
                    ?
                    QColor("#00AEEF")
                    :
                    QColor("#424448")
                )
            );


    mouseWheelItem
        ->setBrush(
            QBrush(
                middlePressed
                    ?
                    QColor("#FFC107")
                    :
                    QColor("#666666")
                )
            );


    int moveX =
        qBound(
            -35,
            dx * 3,
            35
            );


    int moveY =
        qBound(
            -35,
            dy * 3,
            35
            );


    mouseMoveLine
        ->setLine(
            140,
            135,

            140 + moveX,
            135 + moveY
            );


    mouseMoveText
        ->setPlainText(
            QString(
                "DX:%1   DY:%2"
                )
                .arg(
                    dx
                    )
                .arg(
                    dy
                    )
            );


    if (wheel > 0)
    {
        mouseWheelText
            ->setPlainText(
                QString(
                    "Wheel: +%1 ↑"
                    )
                    .arg(
                        wheel
                        )
                );


        mouseWheelText
            ->setDefaultTextColor(
                QColor("#40C4FF")
                );
    }
    else if (wheel < 0)
    {
        mouseWheelText
            ->setPlainText(
                QString(
                    "Wheel: %1 ↓"
                    )
                    .arg(
                        wheel
                        )
                );


        mouseWheelText
            ->setDefaultTextColor(
                QColor("#FFB74D")
                );
    }
    else
    {
        mouseWheelText
            ->setPlainText(
                "Wheel: 0"
                );


        mouseWheelText
            ->setDefaultTextColor(
                QColor("#C0C0C0")
                );
    }
}


// ============================================================================
// FPGA 键盘帧解析
//
// K 00 00 04 00 00 00 00 00
// ============================================================================

void MainWindow::parseKeyboardLine(
    const QString &line
    )
{
    QStringList parts =
        line.split(
            ' ',
            Qt::SkipEmptyParts
            );


    if (
        parts.size()
        !=
        9
        )
    {
        return;
    }


    if (
        parts[0]
        !=
        "K"
        )
    {
        return;
    }


    int values[8];


    for (
        int i = 0;
        i < 8;
        ++i
        )
    {
        bool ok =
            false;


        values[i] =
            parts[i + 1]
                .toInt(
                    &ok,
                    16
                    );


        if (!ok)
        {
            return;
        }
    }


    int modifier =
        values[0];


    QVector<int> keyCodes;


    for (
        int i = 2;
        i < 8;
        ++i
        )
    {
        if (
            values[i]
            !=
            0
            )
        {
            keyCodes.append(
                values[i]
                );
        }
    }


    updateKeyboardGraphics(
        modifier,
        keyCodes
        );
}


// ============================================================================
// 初始化虚拟键盘
// ============================================================================

void MainWindow::initKeyboardGraphics()
{
    keyboardScene =
        new QGraphicsScene(
            this
            );


    keyboardScene->setSceneRect(
        0,
        0,
        1000,
        365
        );


    ui->graphicsKeyboard
        ->setScene(
            keyboardScene
            );


    ui->graphicsKeyboard
        ->setRenderHint(
            QPainter::Antialiasing,
            true
            );


    ui->graphicsKeyboard
        ->setHorizontalScrollBarPolicy(
            Qt::ScrollBarAlwaysOff
            );


    ui->graphicsKeyboard
        ->setVerticalScrollBarPolicy(
            Qt::ScrollBarAlwaysOff
            );


    ui->graphicsKeyboard
        ->setAlignment(
            Qt::AlignCenter
            );


    ui->graphicsKeyboard
        ->setStyleSheet(
            "QGraphicsView {"
            "background:#202124;"
            "border:1px solid #505050;"
            "border-radius:8px;"
            "}"
            );


    auto addKey =
        [this](
            int hid,
            const QString &normalText,
            const QString &shiftText,
            qreal x,
            qreal y,
            qreal w,
            qreal h
            )
    {
        KeyboardKeyVisual key;


        key.rect =
            keyboardScene->addRect(
                x,
                y,
                w,
                h,

                QPen(
                    QColor("#777777"),
                    1.2
                    ),

                QBrush(
                    QColor("#3A3B3F")
                    )
                );


        key.normalText =
            normalText;


        key.shiftText =
            shiftText;


        QFont font;

        font.setPointSize(
            9
            );


        key.text =
            keyboardScene->addSimpleText(
                normalText,
                font
                );


        key.text->setBrush(
            QBrush(
                QColor("#FFFFFF")
                )
            );


        QRectF textRect =
            key.text->boundingRect();


        key.text->setPos(
            x +
                (
                    w -
                    textRect.width()
                    )
                    /
                    2.0,

            y +
                (
                    h -
                    textRect.height()
                    )
                    /
                    2.0
            );


        key.rect->setZValue(
            1
            );


        key.text->setZValue(
            2
            );


        keyboardKeys.insert(
            hid,
            key
            );
    };


    const qreal H =
        40;


    qreal x =
        0;


    qreal y =
        8;


    // ============================================================
    // Esc / F1~F12
    // ============================================================

    addKey(
        0x29,
        "Esc",
        "",
        10,
        y,
        48,
        34
        );


    x =
        85;


    for (
        int i = 0;
        i < 12;
        ++i
        )
    {
        addKey(
            0x3A + i,

            QString(
                "F%1"
                )
                .arg(
                    i + 1
                    ),

            "",

            x,
            y,
            48,
            34
            );


        x +=
            52;


        if (
            i == 3 ||
            i == 7
            )
        {
            x +=
                12;
        }
    }


    addKey(
        0x46,
        "PrtSc",
        "",
        790,
        y,
        58,
        34
        );


    addKey(
        0x47,
        "ScrLk",
        "",
        852,
        y,
        58,
        34
        );


    addKey(
        0x48,
        "Pause",
        "",
        914,
        y,
        58,
        34
        );


    // ============================================================
    // 数字排
    // ============================================================

    y =
        52;


    x =
        10;


    addKey(0x35, "`", "~", x, y, 48, H); x += 52;

    addKey(0x1E, "1", "!", x, y, 48, H); x += 52;
    addKey(0x1F, "2", "@", x, y, 48, H); x += 52;
    addKey(0x20, "3", "#", x, y, 48, H); x += 52;
    addKey(0x21, "4", "$", x, y, 48, H); x += 52;
    addKey(0x22, "5", "%", x, y, 48, H); x += 52;
    addKey(0x23, "6", "^", x, y, 48, H); x += 52;
    addKey(0x24, "7", "&", x, y, 48, H); x += 52;
    addKey(0x25, "8", "*", x, y, 48, H); x += 52;
    addKey(0x26, "9", "(", x, y, 48, H); x += 52;
    addKey(0x27, "0", ")", x, y, 48, H); x += 52;

    addKey(0x2D, "-", "_", x, y, 48, H); x += 52;

    addKey(0x2E, "=", "+", x, y, 48, H); x += 52;


    addKey(
        0x2A,
        "Backspace",
        "",
        x,
        y,
        104,
        H
        );


    addKey(
        0x49,
        "Ins",
        "",
        800,
        y,
        58,
        H
        );


    addKey(
        0x4A,
        "Home",
        "",
        862,
        y,
        58,
        H
        );


    addKey(
        0x4B,
        "PgUp",
        "",
        924,
        y,
        58,
        H
        );


    // ============================================================
    // QWERTY
    // ============================================================

    y =
        96;


    x =
        10;


    addKey(
        0x2B,
        "Tab",
        "",
        x,
        y,
        72,
        H
        );


    x +=
        76;


    addKey(0x14, "q", "Q", x, y, 48, H); x += 52;
    addKey(0x1A, "w", "W", x, y, 48, H); x += 52;
    addKey(0x08, "e", "E", x, y, 48, H); x += 52;
    addKey(0x15, "r", "R", x, y, 48, H); x += 52;
    addKey(0x17, "t", "T", x, y, 48, H); x += 52;
    addKey(0x1C, "y", "Y", x, y, 48, H); x += 52;
    addKey(0x18, "u", "U", x, y, 48, H); x += 52;
    addKey(0x0C, "i", "I", x, y, 48, H); x += 52;
    addKey(0x12, "o", "O", x, y, 48, H); x += 52;
    addKey(0x13, "p", "P", x, y, 48, H); x += 52;

    addKey(0x2F, "[", "{", x, y, 48, H); x += 52;
    addKey(0x30, "]", "}", x, y, 48, H); x += 52;


    addKey(
        0x31,
        "\\",
        "|",
        x,
        y,
        64,
        H
        );


    addKey(
        0x4C,
        "Del",
        "",
        800,
        y,
        58,
        H
        );


    addKey(
        0x4D,
        "End",
        "",
        862,
        y,
        58,
        H
        );


    addKey(
        0x4E,
        "PgDn",
        "",
        924,
        y,
        58,
        H
        );


    // ============================================================
    // ASDF
    // ============================================================

    y =
        140;


    x =
        10;


    addKey(
        0x39,
        "Caps",
        "",
        x,
        y,
        86,
        H
        );


    x +=
        90;


    addKey(0x04, "a", "A", x, y, 48, H); x += 52;
    addKey(0x16, "s", "S", x, y, 48, H); x += 52;
    addKey(0x07, "d", "D", x, y, 48, H); x += 52;
    addKey(0x09, "f", "F", x, y, 48, H); x += 52;
    addKey(0x0A, "g", "G", x, y, 48, H); x += 52;
    addKey(0x0B, "h", "H", x, y, 48, H); x += 52;
    addKey(0x0D, "j", "J", x, y, 48, H); x += 52;
    addKey(0x0E, "k", "K", x, y, 48, H); x += 52;
    addKey(0x0F, "l", "L", x, y, 48, H); x += 52;

    addKey(0x33, ";", ":", x, y, 48, H); x += 52;
    addKey(0x34, "'", "\"", x, y, 48, H); x += 52;


    addKey(
        0x28,
        "Enter",
        "",
        x,
        y,
        110,
        H
        );


    // ============================================================
    // ZXCV
    // ============================================================

    y =
        184;


    x =
        10;


    addKey(
        0xE1,
        "LShift",
        "",
        x,
        y,
        112,
        H
        );


    x +=
        116;


    addKey(0x1D, "z", "Z", x, y, 48, H); x += 52;
    addKey(0x1B, "x", "X", x, y, 48, H); x += 52;
    addKey(0x06, "c", "C", x, y, 48, H); x += 52;
    addKey(0x19, "v", "V", x, y, 48, H); x += 52;
    addKey(0x05, "b", "B", x, y, 48, H); x += 52;
    addKey(0x11, "n", "N", x, y, 48, H); x += 52;
    addKey(0x10, "m", "M", x, y, 48, H); x += 52;

    addKey(0x36, ",", "<", x, y, 48, H); x += 52;
    addKey(0x37, ".", ">", x, y, 48, H); x += 52;
    addKey(0x38, "/", "?", x, y, 48, H); x += 52;


    addKey(
        0xE5,
        "RShift",
        "",
        x,
        y,
        126,
        H
        );


    addKey(
        0x52,
        "↑",
        "",
        862,
        y,
        58,
        H
        );


    // ============================================================
    // 最底排
    // ============================================================

    y =
        228;


    x =
        10;


    addKey(0xE0, "LCtrl", "", x, y, 60, H); x += 64;

    addKey(0xE3, "LWin", "", x, y, 60, H); x += 64;

    addKey(0xE2, "LAlt", "", x, y, 60, H); x += 64;


    addKey(
        0x2C,
        "Space",
        "",
        x,
        y,
        278,
        H
        );


    x +=
        282;


    addKey(0xE6, "RAlt", "", x, y, 60, H); x += 64;

    addKey(0xE7, "RWin", "", x, y, 60, H); x += 64;

    addKey(0x65, "Menu", "", x, y, 60, H); x += 64;

    addKey(0xE4, "RCtrl", "", x, y, 60, H);


    addKey(
        0x50,
        "←",
        "",
        800,
        y,
        58,
        H
        );


    addKey(
        0x51,
        "↓",
        "",
        862,
        y,
        58,
        H
        );


    addKey(
        0x4F,
        "→",
        "",
        924,
        y,
        58,
        H
        );


    // ============================================================
    // 实体按键状态
    // ============================================================

    QFont statusFont;

    statusFont.setPointSize(
        10
        );

    statusFont.setBold(
        true
        );


    keyboardStatusText =
        keyboardScene->addSimpleText(
            "实体按键：无",
            statusFont
            );


    keyboardStatusText->setBrush(
        QBrush(
            QColor("#FFFFFF")
            )
        );


    keyboardStatusText->setPos(
        12,
        285
        );


    // ============================================================
    // Caps / Shift
    // ============================================================

    QFont stateFont;

    stateFont.setPointSize(
        9
        );


    keyboardCapsText =
        keyboardScene->addSimpleText(
            "CapsLock：OFF    Shift：OFF",
            stateFont
            );


    keyboardCapsText->setBrush(
        QBrush(
            QColor("#BFC3C7")
            )
        );


    keyboardCapsText->setPos(
        12,
        313
        );


    // ============================================================
    // 虚拟点击
    // ============================================================

    QFont virtualFont;

    virtualFont.setPointSize(
        10
        );

    virtualFont.setBold(
        true
        );


    virtualKeyText =
        keyboardScene->addSimpleText(
            "虚拟点击：无",
            virtualFont
            );


    virtualKeyText->setBrush(
        QBrush(
            QColor("#40C4FF")
            )
        );


    virtualKeyText->setPos(
        430,
        313
        );


    ui->graphicsKeyboard
        ->fitInView(
            keyboardScene->sceneRect(),
            Qt::KeepAspectRatio
            );
}


// ============================================================================
// 更新键帽文字
// ============================================================================

void MainWindow::refreshKeyboardLabels(
    bool shiftPressed
    )
{
    for (
        auto it =
        keyboardKeys.begin();

        it !=
        keyboardKeys.end();

        ++it
        )
    {
        int hid =
            it.key();


        KeyboardKeyVisual &key =
            it.value();


        bool useShift =
            shiftPressed;


        if (
            hid >= 0x04 &&
            hid <= 0x1D
            )
        {
            useShift =
                shiftPressed
                ^
                capsLockOn;
        }


        QString text =
            key.normalText;


        if (
            useShift &&
            !key.shiftText.isEmpty()
            )
        {
            text =
                key.shiftText;
        }


        key.text->setText(
            text
            );


        QRectF keyRect =
            key.rect->rect();


        QRectF textRect =
            key.text->boundingRect();


        key.text->setPos(
            keyRect.x()
                +
                (
                    keyRect.width()
                    -
                    textRect.width()
                    )
                    /
                    2.0,

            keyRect.y()
                +
                (
                    keyRect.height()
                    -
                    textRect.height()
                    )
                    /
                    2.0
            );
    }
}


// ============================================================================
// HID -> 键名/字符
// ============================================================================

QString MainWindow::keyboardKeyText(
    int hidCode,
    bool shiftPressed
    ) const
{
    if (
        !keyboardKeys.contains(
            hidCode
            )
        )
    {
        QString hex =
            QString(
                "%1"
                )
                .arg(
                    hidCode,
                    2,
                    16,
                    QChar('0')
                    )
                .toUpper();


        return
            "0x" + hex;
    }


    KeyboardKeyVisual key =
        keyboardKeys.value(
            hidCode
            );


    bool useShift =
        shiftPressed;


    if (
        hidCode >= 0x04 &&
        hidCode <= 0x1D
        )
    {
        useShift =
            shiftPressed
            ^
            capsLockOn;
    }


    if (
        useShift &&
        !key.shiftText.isEmpty()
        )
    {
        return
            key.shiftText;
    }


    return
        key.normalText;
}


// ============================================================================
// 刷新键盘颜色
// ============================================================================

void MainWindow::refreshKeyboardColors()
{
    for (
        auto it =
        keyboardKeys.begin();

        it !=
        keyboardKeys.end();

        ++it
        )
    {
        int hid =
            it.key();


        bool physicalPressed =
            physicalPressedKeys.contains(
                hid
                );


        bool virtualPressed =
            (
                virtualPressedHid
                ==
                hid
                );


        bool virtualShift =
            virtualShiftOn
            &&
            (
                hid == 0xE1 ||
                hid == 0xE5
                );


        bool pressed =
            physicalPressed
            ||
            virtualPressed
            ||
            virtualShift;


        if (pressed)
        {
            QColor color =
                virtualShift
                    ?
                    QColor("#FFC107")
                    :
                    QColor("#00AEEF");


            it.value()
                .rect
                ->setBrush(
                    QBrush(
                        color
                        )
                    );


            it.value()
                .rect
                ->setPen(
                    QPen(
                        QColor("#7FDBFF"),
                        2
                        )
                    );
        }
        else
        {
            it.value()
            .rect
                ->setBrush(
                    QBrush(
                        QColor("#3A3B3F")
                        )
                    );


            it.value()
                .rect
                ->setPen(
                    QPen(
                        QColor("#777777"),
                        1.2
                        )
                    );
        }
    }


    if (
        capsLockOn &&
        keyboardKeys.contains(
            0x39
            ) &&
        !physicalPressedKeys.contains(
            0x39
            ) &&
        virtualPressedHid
            !=
            0x39
        )
    {
        keyboardKeys[
            0x39
        ]
            .rect
            ->setPen(
                QPen(
                    QColor("#FFC107"),
                    2.5
                    )
                );
    }
}


// ============================================================================
// 实体 FPGA 键盘状态
// ============================================================================

void MainWindow::updateKeyboardGraphics(
    int modifier,
    const QVector<int> &keyCodes
    )
{
    QSet<int> currentPressed;


    for (
        int bit = 0;
        bit < 8;
        ++bit
        )
    {
        if (
            modifier &
            (
                1 << bit
                )
            )
        {
            currentPressed.insert(
                0xE0 + bit
                );
        }
    }


    for (
        int code :
        keyCodes
        )
    {
        if (code != 0)
        {
            currentPressed.insert(
                code
                );
        }
    }


    // ============================================================
    // CapsLock 按下沿
    // ============================================================

    if (
        currentPressed.contains(
            0x39
            ) &&
        !previousKeyboardKeys.contains(
            0x39
            )
        )
    {
        capsLockOn =
            !capsLockOn;
    }


    physicalShiftOn =
        (
            modifier &
            0x02
            )
        ||
        (
            modifier &
            0x20
            );


    physicalPressedKeys =
        currentPressed;


    bool effectiveShift =
        physicalShiftOn
        ||
        virtualShiftOn;


    refreshKeyboardLabels(
        effectiveShift
        );


    refreshKeyboardColors();


    QStringList names;

    QStringList hexCodes;

    QStringList decCodes;


    const int modifierCodes[8] =
        {
            0xE0,
            0xE1,
            0xE2,
            0xE3,

            0xE4,
            0xE5,
            0xE6,
            0xE7
        };


    for (
        int i = 0;
        i < 8;
        ++i
        )
    {
        int code =
            modifierCodes[i];


        if (
            currentPressed.contains(
                code
                )
            )
        {
            names.append(
                keyboardKeyText(
                    code,
                    effectiveShift
                    )
                );


            QString hex =
                QString(
                    "%1"
                    )
                    .arg(
                        code,
                        2,
                        16,
                        QChar('0')
                        )
                    .toUpper();


            hexCodes.append(
                "0x" + hex
                );


            decCodes.append(
                QString::number(
                    code
                    )
                );
        }
    }


    for (
        int code :
        keyCodes
        )
    {
        if (code == 0)
        {
            continue;
        }


        names.append(
            keyboardKeyText(
                code,
                effectiveShift
                )
            );


        QString hex =
            QString(
                "%1"
                )
                .arg(
                    code,
                    2,
                    16,
                    QChar('0')
                    )
                .toUpper();


        hexCodes.append(
            "0x" + hex
            );


        decCodes.append(
            QString::number(
                code
                )
            );
    }


    if (
        names.isEmpty()
        )
    {
        keyboardStatusText
            ->setText(
                "实体按键：无"
                );
    }
    else
    {
        keyboardStatusText
            ->setText(
                QString(
                    "实体按键：%1    HID：%2    DEC：%3"
                    )
                    .arg(
                        names.join(
                            " + "
                            )
                        )
                    .arg(
                        hexCodes.join(
                            " + "
                            )
                        )
                    .arg(
                        decCodes.join(
                            " + "
                            )
                        )
                );
    }


    keyboardCapsText
        ->setText(
            QString(
                "CapsLock：%1    Shift：%2"
                )
                .arg(
                    capsLockOn
                        ?
                        "ON"
                        :
                        "OFF"
                    )
                .arg(
                    effectiveShift
                        ?
                        "ON"
                        :
                        "OFF"
                    )
            );


    // ============================================================
    // 输入文字
    //
    // 必须在 previousKeyboardKeys 更新之前
    // ============================================================

    inputFpgaKeyboardToText(
        keyCodes
        );


    if (
        physicalRepeatHid >= 0 &&
        !currentPressed.contains(
            physicalRepeatHid
            )
        )
    {
        stopPhysicalKeyRepeat();
    }


    previousKeyboardKeys =
        currentPressed;
}


// ============================================================================
// 虚拟键盘鼠标事件
//
// Windows 鼠标、FPGA 蓝色鼠标都会进入这里。
// ============================================================================

bool MainWindow::eventFilter(
    QObject *watched,
    QEvent *event
    )
{
    if (
        watched ==
        ui->graphicsKeyboard
            ->viewport()
        )
    {
        // ====================================================================
        // 左键按下
        // ====================================================================

        if (
            event->type()
            ==
            QEvent::MouseButtonPress
            )
        {
            QMouseEvent *mouseEvent =
                static_cast<QMouseEvent *>(
                    event
                    );


            if (
                mouseEvent->button()
                !=
                Qt::LeftButton
                )
            {
                return
                    QMainWindow::eventFilter(
                        watched,
                        event
                        );
            }


            QPointF scenePos =
                ui->graphicsKeyboard
                    ->mapToScene(
                        mouseEvent
                            ->position()
                            .toPoint()
                        );


            int clickedHid =
                -1;


            for (
                auto it =
                keyboardKeys.begin();

                it !=
                keyboardKeys.end();

                ++it
                )
            {
                if (
                    it.value()
                        .rect
                        ->sceneBoundingRect()
                        .contains(
                            scenePos
                            )
                    )
                {
                    clickedHid =
                        it.key();


                    break;
                }
            }


            if (clickedHid < 0)
            {
                return
                    true;
            }


            // ================================================================
            // Shift
            // ================================================================

            if (
                clickedHid == 0xE1 ||
                clickedHid == 0xE5
                )
            {
                stopVirtualKeyRepeat();


                virtualCurrentKeyUsedVirtualShift =
                    false;


                virtualShiftOn =
                    !virtualShiftOn;


                virtualPressedHid =
                    -1;


                refreshKeyboardLabels(
                    physicalShiftOn
                    ||
                    virtualShiftOn
                    );


                refreshKeyboardColors();


                virtualKeyText
                    ->setText(
                        virtualShiftOn
                            ?
                            "虚拟点击：Shift ON"
                            :
                            "虚拟点击：Shift OFF"
                        );


                keyboardCapsText
                    ->setText(
                        QString(
                            "CapsLock：%1    Shift：%2"
                            )
                            .arg(
                                capsLockOn
                                    ?
                                    "ON"
                                    :
                                    "OFF"
                                )
                            .arg(
                                (
                                    physicalShiftOn
                                    ||
                                    virtualShiftOn
                                    )
                                    ?
                                    "ON"
                                    :
                                    "OFF"
                                )
                        );


                return
                    true;
            }


            // ================================================================
            // CapsLock
            // ================================================================

            if (
                clickedHid ==
                0x39
                )
            {
                stopVirtualKeyRepeat();


                virtualCurrentKeyUsedVirtualShift =
                    false;


                capsLockOn =
                    !capsLockOn;


                virtualPressedHid =
                    clickedHid;


                refreshKeyboardLabels(
                    physicalShiftOn
                    ||
                    virtualShiftOn
                    );


                refreshKeyboardColors();


                virtualKeyText
                    ->setText(
                        capsLockOn
                            ?
                            "虚拟点击：CapsLock ON"
                            :
                            "虚拟点击：CapsLock OFF"
                        );


                keyboardCapsText
                    ->setText(
                        QString(
                            "CapsLock：%1    Shift：%2"
                            )
                            .arg(
                                capsLockOn
                                    ?
                                    "ON"
                                    :
                                    "OFF"
                                )
                            .arg(
                                (
                                    physicalShiftOn
                                    ||
                                    virtualShiftOn
                                    )
                                    ?
                                    "ON"
                                    :
                                    "OFF"
                                )
                        );


                return
                    true;
            }


            // ================================================================
            // 普通虚拟按键
            // ================================================================

            bool usedVirtualShift =
                virtualShiftOn;


            bool effectiveShift =
                physicalShiftOn
                ||
                usedVirtualShift;


            QString keyName =
                keyboardKeyText(
                    clickedHid,
                    effectiveShift
                    );


            QString hex =
                QString(
                    "%1"
                    )
                    .arg(
                        clickedHid,
                        2,
                        16,
                        QChar('0')
                        )
                    .toUpper();


            virtualKeyText
                ->setText(
                    QString(
                        "虚拟点击：%1    HID：0x%2    DEC：%3"
                        )
                        .arg(
                            keyName
                            )
                        .arg(
                            hex
                            )
                        .arg(
                            clickedHid
                            )
                    );


            virtualPressedHid =
                clickedHid;


            virtualCurrentKeyUsedVirtualShift =
                usedVirtualShift;


            refreshKeyboardColors();


            // 第一次立即输入
            inputVirtualKeyToText(
                clickedHid,
                effectiveShift
                );


            // 开始长按
            startVirtualKeyRepeat(
                clickedHid,
                usedVirtualShift
                );


            return
                true;
        }


        // ====================================================================
        // 左键释放
        // ====================================================================

        if (
            event->type()
            ==
            QEvent::MouseButtonRelease
            )
        {
            bool consumeVirtualShift =
                virtualCurrentKeyUsedVirtualShift;


            stopVirtualKeyRepeat();


            virtualPressedHid =
                -1;


            virtualCurrentKeyUsedVirtualShift =
                false;


            if (consumeVirtualShift)
            {
                virtualShiftOn =
                    false;
            }


            refreshKeyboardLabels(
                physicalShiftOn
                ||
                virtualShiftOn
                );


            refreshKeyboardColors();


            keyboardCapsText
                ->setText(
                    QString(
                        "CapsLock：%1    Shift：%2"
                        )
                        .arg(
                            capsLockOn
                                ?
                                "ON"
                                :
                                "OFF"
                            )
                        .arg(
                            (
                                physicalShiftOn
                                ||
                                virtualShiftOn
                                )
                                ?
                                "ON"
                                :
                                "OFF"
                            )
                    );


            return
                true;
        }
    }


    return
        QMainWindow::eventFilter(
            watched,
            event
            );
}
